//
//  MIKMIDIUtilities.m
//  MIDI Testbed
//
//  Created by Andrew Madsen on 3/7/13.
//  Copyright (c) 2013 Mixed In Key. All rights reserved.
//

#import "MIKMIDIUtilities.h"

#if !__has_feature(objc_arc)
#error MIKMIDIUtilities.m must be compiled with ARC. Either turn on ARC for the project or set the -fobjc-arc flag for MIKMIDIUtilities.m in the Build Phases for this target
#endif

NSString *MIKStringPropertyFromMIDIObject(MIDIObjectRef object, CFStringRef propertyID, NSError *__autoreleasing*error)
{
	error = error ? error : &(NSError *__autoreleasing){ nil };
	CFStringRef result;
	OSStatus err = MIDIObjectGetStringProperty(object, propertyID, &result);
	
	if (err) {
		*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		return nil;
	}
	
	NSCharacterSet *controlCharacters = [NSCharacterSet controlCharacterSet];	
	return [(__bridge NSString *)result stringByTrimmingCharactersInSet:controlCharacters];
}

BOOL MIKSetStringPropertyOnMIDIObject(MIDIObjectRef object, CFStringRef propertyID, NSString *string, NSError *__autoreleasing*error)
{
	error = error ? error : &(NSError *__autoreleasing){ nil };
	OSStatus err = MIDIObjectSetStringProperty(object, propertyID, (__bridge CFStringRef)string);
	
	if (err) {
		*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		return NO;
	}
	return YES;
}

SInt32 MIKIntegerPropertyFromMIDIObject(MIDIObjectRef object, CFStringRef propertyID, NSError *__autoreleasing*error)
{
	error = error ? error : &(NSError *__autoreleasing){ nil };
	SInt32 result;
	OSStatus err = MIDIObjectGetIntegerProperty(object, propertyID, &result);
	if (err) {
		*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		return INT32_MIN;
	}
	return (SInt32)result;
}

BOOL MIKSetIntegerPropertyFromMIDIObject(MIDIObjectRef object, CFStringRef propertyID, SInt32 integerValue, NSError *__autoreleasing*error)
{
	error = error ? error : &(NSError *__autoreleasing){ nil };
	OSStatus err = MIDIObjectSetIntegerProperty(object, propertyID, integerValue);
	if (err) {
		*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		return NO;
	}
	return YES;
}

MIDIObjectType MIKMIDIObjectTypeOfObject(MIDIObjectRef object, NSError *__autoreleasing*error)
{
	error = error ? error : &(NSError *__autoreleasing){ nil };
	MIDIUniqueID uniqueID = MIKIntegerPropertyFromMIDIObject(object, kMIDIPropertyUniqueID, error);
	if (*error) return -2;
	
	MIDIObjectRef resultObject;
	MIDIObjectType objectType;
	OSStatus err = MIDIObjectFindByUniqueID(uniqueID, &resultObject, &objectType);
	if (err) {
		*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		return -2;
	}

	if (resultObject != object) {
		*error = [NSError errorWithDomain:@"MIKMIDIErrorDomain" code:-1 userInfo:nil];
		return -2;
	}

	return objectType;
}

NSString *MIKMIDIMappingAttributeStringForInteractionType(MIKMIDIResponderType type)
{
	NSDictionary *map = @{@(MIKMIDIResponderTypePressReleaseButton) : @"Key",
						  @(MIKMIDIResponderTypePressButton) : @"Tap",
						  @(MIKMIDIResponderTypeAbsoluteSliderOrKnob) : @"KnobSlider",
						  @(MIKMIDIResponderTypeRelativeKnob) : @"JogWheel",
						  @(MIKMIDIResponderTypeTurntableKnob) : @"TurnTable",
						  @(MIKMIDIResponderTypeRelativeAbsoluteKnob) : @"RelativeAbsoluteKnob"};
	return [map objectForKey:@(type)];
}

MIKMIDIResponderType MIKMIDIMappingInteractionTypeForAttributeString(NSString *string)
{
	NSDictionary *map = @{@"Key" : @(MIKMIDIResponderTypePressReleaseButton),
						  @"Tap" : @(MIKMIDIResponderTypePressButton),
						  @"KnobSlider" : @(MIKMIDIResponderTypeAbsoluteSliderOrKnob),
						  @"JogWheel" : @(MIKMIDIResponderTypeRelativeKnob),
						  @"TurnTable" : @(MIKMIDIResponderTypeTurntableKnob),
						  @"RelativeAbsoluteKnob" : @(MIKMIDIResponderTypeRelativeAbsoluteKnob)};
	return [[map objectForKey:string] integerValue];
}

NSInteger _MIKMIDIStandardLengthOfMessageForCommandType(MIKMIDICommandType commandType)
{
	// Result includes status/command type byte
	switch (commandType) {
		case MIKMIDICommandTypeNoteOff:
		case MIKMIDICommandTypeNoteOn:
		case MIKMIDICommandTypePolyphonicKeyPressure:
		case MIKMIDICommandTypeControlChange:
		case MIKMIDICommandTypePitchWheelChange:
		case MIKMIDICommandTypeSystemSongPositionPointer:
			return 3;
			break;
		case MIKMIDICommandTypeProgramChange:
		case MIKMIDICommandTypeChannelPressure:
		case MIKMIDICommandTypeSystemTimecodeQuarterFrame:
		case MIKMIDICommandTypeSystemSongSelect:
			return 2;
			break;
		case MIKMIDICommandTypeSystemTuneRequest:
		case MIKMIDICommandTypeSystemTimingClock:
		case MIKMIDICommandTypeSystemStartSequence:
		case MIKMIDICommandTypeSystemContinueSequence:
		case MIKMIDICommandTypeSystemStopSequence:
		case MIKMIDICommandTypeSystemKeepAlive:
			return 1;
			break;
		case MIKMIDICommandTypeSystemMessage:
		case MIKMIDICommandTypeSystemExclusive:
			return -1; // No standard length
			break;
		default:
			return NSIntegerMin;
			break;
	}
}

NSInteger MIKMIDIStandardLengthOfMessageForCommandType(MIKMIDICommandType commandType)
{
	NSInteger result = _MIKMIDIStandardLengthOfMessageForCommandType(commandType);
	if (result == NSIntegerMin) result = _MIKMIDIStandardLengthOfMessageForCommandType(commandType | 0x0F); // Mask out channel nibble
	return result;
}