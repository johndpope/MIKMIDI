//
//  MIKAppDelegate.m
//  MIDI Testbed
//
//  Created by Andrew Madsen on 3/7/13.
//  Copyright (c) 2013 Mixed In Key. All rights reserved.
//

#import "MIKAppDelegate.h"
#import "MIKMIDI.h"
#import <mach/mach.h>
#import <mach/mach_time.h>



@interface MIKAppDelegate ()

@property (nonatomic, strong) MIKMIDIDeviceManager *midiDeviceManager;
@property (nonatomic, strong) NSMapTable *connectionTokensForSources;

@end

@implementation MIKAppDelegate

- (id)init
{
    self = [super init];
    if (self) {
        self.connectionTokensForSources = [NSMapTable strongToStrongObjectsMapTable];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	self.midiDeviceManager = [MIKMIDIDeviceManager sharedDeviceManager];
	[self.midiDeviceManager addObserver:self forKeyPath:@"availableDevices" options:NSKeyValueObservingOptionInitial context:NULL];
	[self.midiDeviceManager addObserver:self forKeyPath:@"virtualSources" options:NSKeyValueObservingOptionInitial context:NULL];
	[self.midiDeviceManager addObserver:self forKeyPath:@"virtualDestinations" options:NSKeyValueObservingOptionInitial context:NULL];
    
    
    [self createClock];
    [self playMusic];
}


-(void)createClock{
    
    OSStatus err = CAClockNew(0, &mtcClockRef);
 
    if (err != noErr) {
        NSLog(@"\t\terror %d at CAClockNew()", (int)err);
    }
    else {
        CAClockTimebase timebase = kCAClockTimebase_HostTime;
        UInt32 size = 0;
        size = sizeof(timebase);
        err = CAClockSetProperty(mtcClockRef, kCAClockProperty_InternalTimebase, size, &timebase);
        if (err)
            NSLog(@"Error setting clock timebase");
        
        UInt32 tSyncMode = kCAClockSyncMode_Internal;
        size = sizeof(tSyncMode);
        err = CAClockSetProperty(mtcClockRef, kCAClockProperty_SyncMode, size, &tSyncMode);
        err = CAClockAddListener(mtcClockRef, clockListenerProc, (__bridge void *)(self));
        if (err != noErr)
            NSLog(@"\t\terr %d adding listener in %s", (int)err, __func__);
        else {
            err = CAClockArm(mtcClockRef);
            if (err != noErr)
                NSLog(@"\t\ter %d arming clock in %s", (int)err, __func__);

        }
    }
     CAClockStart(mtcClockRef);
}
-(void)playMusic{

   __block MIDIObjectRef endpointRef;
    //Clavinova
	NSMutableSet *devicelessDestinations = [NSMutableSet setWithArray:self.midiDeviceManager.virtualDestinations];
    [devicelessDestinations enumerateObjectsUsingBlock:^(MIKMIDIDestinationEndpoint *ep, BOOL *stop) {
        NSLog(@"endpoint:%u name:%@",  (unsigned int)ep.objectRef,ep.name);
        if ([ep.name isEqualToString:@"Clavinova"]) { //IAC Bus 1
            endpointRef = ep.objectRef;
        }
    }];
    for(int i =0; i<10; i++){
        [NSThread sleepForTimeInterval:.1]; // simulate a lag
        NSString *midiFilePath = [[NSBundle mainBundle] pathForResource:@"1" ofType:@"mid"];
        NSURL * midiFileURL = [NSURL fileURLWithPath:midiFilePath];
        
        MusicPlayer musicPlayer;
        MusicSequence musicSequence;
        NewMusicPlayer(&musicPlayer);
        
        if (NewMusicSequence(&musicSequence) != noErr)
        {
            [NSException raise:@"play" format:@"Can't create MusicSequence"];
        }
        
        if(MusicSequenceFileLoad(musicSequence, (__bridge CFURLRef)midiFileURL, 0, 0 != noErr))
        {
            [NSException raise:@"play" format:@"Can't load MusicSequence"];
        }
        
        MusicPlayerSetSequence(musicPlayer, musicSequence);
       
        MusicSequenceSetMIDIEndpoint(musicSequence,endpointRef);
        OSStatus err = CAClockSetProperty(mtcClockRef, kCAClockProperty_SyncSource, sizeof(endpointRef), endpointRef);
        MusicPlayerPreroll(musicPlayer);
        MusicPlayerStart(musicPlayer);
    }

    
        // Set the endpoint of the sequence to be our virtual endpoint
     //   MusicSequenceSetMIDIEndpoint(sequence, virtualEndpoint);
    
}
    

- (void)applicationWillTerminate:(NSNotification *)notification
{
	[self.midiDeviceManager removeObserver:self forKeyPath:@"availableDevices"];
	[self.midiDeviceManager removeObserver:self forKeyPath:@"virtualSources"];
	[self.midiDeviceManager removeObserver:self forKeyPath:@"virtualDestinations"];
}

#pragma mark - Connections

- (void)connectToSource:(MIKMIDISourceEndpoint *)source
{
	NSError *error = nil;
	id connectionToken = [self.midiDeviceManager connectInput:source error:&error eventHandler:^(MIKMIDISourceEndpoint *source, NSArray *commands) {
		for (MIKMIDIChannelVoiceCommand *command in commands) { [self handleMIDICommand:command]; }
	}];
	if (!connectionToken) {
		NSLog(@"Unable to connect to input: %@", error);
		return;
	}
	[self.connectionTokensForSources setObject:connectionToken forKey:source];
}

- (void)disconnectFromSource:(MIKMIDISourceEndpoint *)source
{
	if (!source) return;
	id token = [self.connectionTokensForSources objectForKey:source];
	if (!token) return;
	[self.midiDeviceManager disconnectInput:source forConnectionToken:token];
}

- (void)connectToDevice:(MIKMIDIDevice *)device
{
	if (!device) return;
	NSArray *sources = [device.entities valueForKeyPath:@"@unionOfArrays.sources"];
	if (![sources count]) return;
    for (MIKMIDISourceEndpoint *source in sources) {
        [self connectToSource:source];
    }
}

- (void)disconnectFromDevice:(MIKMIDIDevice *)device
{
	if (!device) return;
	NSArray *sources = [device.entities valueForKeyPath:@"@unionOfArrays.sources"];
	for (MIKMIDISourceEndpoint *source in sources) {
		[self disconnectFromSource:source];
	}
}

- (void)handleMIDICommand:(MIKMIDICommand *)command
{
	NSMutableString *textFieldString = self.textView.textStorage.mutableString;
	[textFieldString appendFormat:@"Received: %@\n", command];
    [self.textView scrollToEndOfDocument:self];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	NSLog(@"%@'s %@ changed to: %@", object, keyPath, [object valueForKeyPath:keyPath]);
}

#pragma mark - Devices

+ (NSSet *)keyPathsForValuesAffectingAvailableDevices
{
	return [NSSet setWithObject:@"midiDeviceManager.availableDevices"];
}

- (NSArray *)availableDevices
{
	NSArray *regularDevices = [self.midiDeviceManager availableDevices];
	NSMutableArray *result = [regularDevices mutableCopy];
	
	NSMutableSet *endpointsInDevices = [NSMutableSet set];
	for (MIKMIDIDevice *device in regularDevices) {
		NSSet *sources = [NSSet setWithArray:[device.entities valueForKeyPath:@"@distinctUnionOfArrays.sources"]];
		NSSet *destinations = [NSSet setWithArray:[device.entities valueForKeyPath:@"@distinctUnionOfArrays.destinations"]];
		[endpointsInDevices unionSet:sources];
		[endpointsInDevices unionSet:destinations];
	}
	
	NSMutableSet *devicelessSources = [NSMutableSet setWithArray:self.midiDeviceManager.virtualSources];
	NSMutableSet *devicelessDestinations = [NSMutableSet setWithArray:self.midiDeviceManager.virtualDestinations];
	[devicelessSources minusSet:endpointsInDevices];
	[devicelessDestinations minusSet:endpointsInDevices];
	
	// Now we need to try to associate each source with its corresponding destination on the same device
	NSMapTable *destinationToSourceMap = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory];
	NSMapTable *deviceNamesBySource = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory];
	NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
	for (MIKMIDIEndpoint *source in devicelessSources) {
		NSMutableArray *sourceNameComponents = [[source.name componentsSeparatedByCharactersInSet:whitespace] mutableCopy];
		[sourceNameComponents removeLastObject];
		for (MIKMIDIEndpoint *destination in devicelessDestinations) {
			NSMutableArray *destinationNameComponents = [[destination.name componentsSeparatedByCharactersInSet:whitespace] mutableCopy];
			[destinationNameComponents removeLastObject];
			
			if ([sourceNameComponents isEqualToArray:destinationNameComponents]) {
				// Source and destination match
				[destinationToSourceMap setObject:destination forKey:source];

				NSString *deviceName = [sourceNameComponents componentsJoinedByString:@" "];
				[deviceNamesBySource setObject:deviceName forKey:source];
				break;
			}
		}
	}
	
	for (MIKMIDIEndpoint *source in destinationToSourceMap) {
		MIKMIDIEndpoint *destination = [destinationToSourceMap objectForKey:source];
		[devicelessSources removeObject:source];
		[devicelessDestinations removeObject:destination];
		
		MIKMIDIDevice *device = [MIKMIDIDevice deviceWithVirtualEndpoints:@[source, destination]];
		device.name = [deviceNamesBySource objectForKey:source];
	 	if (device) [result addObject:device];
	}
	for (MIKMIDIEndpoint *endpoint in devicelessSources) {
		MIKMIDIDevice *device = [MIKMIDIDevice deviceWithVirtualEndpoints:@[endpoint]];
	 	if (device) [result addObject:device];
	}
	for (MIKMIDIEndpoint *endpoint in devicelessSources) {
		MIKMIDIDevice *device = [MIKMIDIDevice deviceWithVirtualEndpoints:@[endpoint]];
	 	if (device) [result addObject:device];
	}
	
	return result;
}

- (void)setDevice:(MIKMIDIDevice *)device
{
	if (device != _device) {
		[self disconnectFromDevice:_device];
		_device = device;
		[self connectToDevice:_device];
	}
}

- (void)setSource:(MIKMIDISourceEndpoint *)source
{
	if (source != _source) {
		[self disconnectFromSource:_source];
		_source = source;
		[self connectToSource:_source];
	}
}

#pragma mark - Command Execution

- (IBAction)clearOutput:(id)sender 
{
    [self.textView setString:@""];
}

- (IBAction)sendSysex:(id)sender
{
    NSComboBox *comboBox = self.commandComboBox;
    NSString *commandString = [[comboBox stringValue] stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (!commandString || commandString.length == 0) {
        return;
    }
    
    struct MIDIPacket packet;
    packet.timeStamp = mach_absolute_time();
    packet.length = commandString.length / 2;
    
    char byte_chars[3] = {'\0','\0','\0'};
    for (int i = 0; i < packet.length; i++) {
        byte_chars[0] = [commandString characterAtIndex:i*2];
        byte_chars[1] = [commandString characterAtIndex:i*2+1];
        packet.data[i] = strtol(byte_chars, NULL, 16);;
    }

    MIKMIDICommand *command = [MIKMIDICommand commandWithMIDIPacket:&packet];
	NSLog(@"Sending idenity request command: %@", command);
	
	NSArray *destinations = [self.device.entities valueForKeyPath:@"@unionOfArrays.destinations"];
	if (![destinations count]) return;
	for (MIKMIDIDestinationEndpoint *destination in destinations) {
        NSError *error = nil;
        if (![self.midiDeviceManager sendCommands:@[command] toEndpoint:destination error:&error]) {
            NSLog(@"Unable to send command %@ to endpoint %@: %@", command, destination, error);
        }
    }
}

@synthesize availableCommands = _availableCommands;
- (NSArray *)availableCommands 
{
    if (_availableCommands == nil) {
        MIKMIDISystemExclusiveCommand *identityRequest = [MIKMIDISystemExclusiveCommand identityRequestCommand];
        NSString *identityRequestString = [NSString stringWithFormat:@"%@", identityRequest.data];
        identityRequestString = [identityRequestString substringWithRange:NSMakeRange(1, identityRequestString.length-2)];
        _availableCommands = @[
                               @{@"name": @"Identity Request",
                                 @"value": identityRequestString}
                               ];
    }
    return _availableCommands;
}

- (IBAction)commandTextFieldDidSelect:(id)sender 
{
    NSComboBox *comboBox = (NSComboBox *)sender;
    NSString *selectedValue = [comboBox objectValueOfSelectedItem];
    NSArray *availableCommands = [self availableCommands];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:[NSString stringWithFormat:@"name=\"%@\"", selectedValue]];
    NSDictionary *selectedObject = [[availableCommands filteredArrayUsingPredicate:predicate] firstObject];
    if (selectedObject) {
        [comboBox setStringValue:selectedObject[@"value"]];
    }
    [self sendSysex:sender];
}

    
    
    void clockListenerProc(void *userData, CAClockMessage msg, const void *param) {

        NSLog(@"%s",__func__);
        switch (msg) {
            case kCAClockMessage_StartTimeSet:
                NSLog(@"\t\tclock start time set");
                break;
                
            case kCAClockMessage_Started:
                NSLog(@"\t\tclock started");
                break;
                
            case kCAClockMessage_Stopped:
                NSLog(@"\t\tclock stopped");
                break;
                
            case kCAClockMessage_Armed:
                NSLog(@"\t\tclock armed");
                break;
                
            case kCAClockMessage_Disarmed:
                NSLog(@"\t\tclock disarmed");
                break;
                
            case kCAClockMessage_PropertyChanged:
                NSLog(@"\t\tclock property changed");
                break;
                
            case kCAClockMessage_WrongSMPTEFormat:
                NSLog(@"\t\tclock wrong SMPTE format");
                break;
        }

    }

@end
