//
//  MIKMIDITrackView.m
//  MIDI Files Testbed
//
//  Created by Andrew Madsen on 5/23/14.
//  Copyright (c) 2014 Mixed In Key. All rights reserved.
//

#import "MIKMIDISequenceView.h"
#import "MIKMIDISequence.h"
#import "MIKMIDITrack.h"
#import "MIKMIDIEvent.h"
#import "MIKMIDINoteEvent.h"

#define NUM_KEYS 49

#define KEY_WIDTH 50
#define CELL_LENGTH 25
#define HEADER_HEIGHT 62

#define MAX_LENGTH 32
#define DEFAULT_LENGTH 32
#define DEFAULT_RESOLUTION 16

@interface DividerView : NSView
@end
@implementation DividerView

- (void)drawRect:(NSRect)dirtyRect {
    // set any NSColor for filling, say white:
    [[NSColor colorWithCalibratedRed:.3f green:.3f blue:.3f alpha:1.0f] setFill];
    NSRectFill(dirtyRect);
    [super drawRect:dirtyRect];
}

@end


@interface MIKMIDISequenceView ()

@property (nonatomic) BOOL dragInProgress;

@end

@implementation MIKMIDISequenceView

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self registerForDraggedTypes:@[NSFilenamesPboardType]];
        //        [self setHasVerticalScroller:YES];
        //        [self setVerticalScrollElasticity:NSScrollElasticityNone];
        [self drawDividers];
        
    }
    return self;
}
/*
 * Drawing some dividers
 */
- (void)drawDividers
{
    CGFloat ppt = [self pixelsPerTick];
    CGFloat noteHeight = [self pixelsPerNote];
    
    float currentX = KEY_WIDTH - 1;
    for (int i = 4; i < MAX_LENGTH; i+=4) {
        currentX += ( (int)ppt);
        DividerView *dv = [[DividerView alloc] initWithFrame:NSMakeRect(currentX, 0, (int)ppt, self.frame.size.height - HEADER_HEIGHT)];
        [dv setAlphaValue:0.5f];
        [self addSubview:dv];
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    if (self.dragInProgress) {
        [[NSColor lightGrayColor] set];
        NSRectFill([self bounds]);
    }
    
    CGFloat ppt = [self pixelsPerTick];
    CGFloat noteHeight = [self pixelsPerNote];
    NSInteger index=0;
    for (MIKMIDITrack *track in self.sequence.tracks) {
        
        for (MIKMIDINoteEvent *note in [track events]) {
            if (note.eventType != kMusicEventType_MIDINoteMessage) continue;
            
            NSColor *noteColor = [self.sequence.tracks count] <= 2 ? [self colorForNote:note] : [self colorForTrackAtIndex:index];
            
            [[NSColor blackColor] setStroke];
            [noteColor setFill];
            
            CGFloat yPosition = NSMinY([self bounds]) + note.note * [self pixelsPerNote];
            NSRect noteRect = NSMakeRect(NSMinX([self bounds]) + note.musicTimeStamp * ppt, yPosition, note.duration * ppt, 5);
            
            NSBezierPath *path = [NSBezierPath bezierPathWithRect:noteRect];
            [path fill];
            [path stroke];
        }
        index++;
    }
    
    
    [super drawRect:dirtyRect];
}

#pragma mark - NSDraggingDestination

- (NSArray *)MIDIFilesFromPasteboard:(NSPasteboard *)pb
{
    if (![[pb types] containsObject:NSFilenamesPboardType]) return NSDragOperationNone;
    
    NSArray *files = [pb propertyListForType:NSFilenamesPboardType];
    files = [files filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *file, NSDictionary *bindings) {
        return [[file pathExtension] isEqualToString:@"mid"] || [[file pathExtension] isEqualToString:@"midi"];
    }]];
    return files;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    NSArray *files = [self MIDIFilesFromPasteboard:[sender draggingPasteboard]];
    self.dragInProgress = [files count] != 0;
    return [files count] ? NSDragOperationCopy : NSDragOperationNone;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender
{
    self.dragInProgress = NO;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSArray *files = [self MIDIFilesFromPasteboard:[sender draggingPasteboard]];
    if (![files count]) return NO;
    
    if ([self.delegate respondsToSelector:@selector(midiSequenceView:receivedDroppedMIDIFiles:)]) {
        [self.delegate midiSequenceView:self receivedDroppedMIDIFiles:files];
    }
    
    return YES;
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender
{
    self.dragInProgress = NO;
}

#pragma mark - Private

- (NSColor *)colorForNote:(MIKMIDINoteEvent *)note
{
    NSArray	*colors = @[[NSColor redColor], [NSColor orangeColor], [NSColor yellowColor], [NSColor greenColor], [NSColor blueColor], [NSColor purpleColor]];
    NSGradient *gradient = [[NSGradient alloc] initWithColors:colors];
    CGFloat notePosition = (CGFloat)(note.note % 12) / 12.0;
    return [gradient interpolatedColorAtLocation:notePosition];
}

- (NSColor *)colorForTrackAtIndex:(NSInteger)index
{
    NSArray	*colors = @[[NSColor redColor], [NSColor orangeColor], [NSColor yellowColor], [NSColor greenColor], [NSColor blueColor], [NSColor purpleColor]];
    NSGradient *gradient = [[NSGradient alloc] initWithColors:colors];
    return [gradient interpolatedColorAtLocation:index / (float)[self.sequence.tracks count]];
}

- (CGFloat)pixelsPerTick
{
    double maxLength = [[self.sequence valueForKeyPath:@"tracks.@max.length"] doubleValue];
    NSLog(@"max::%f",maxLength);
    CGFloat w =  NSWidth([self bounds]) / maxLength;
    return w;
}

- (CGFloat)pixelsPerNote
{
    CGFloat h =  NSHeight([self bounds]) / 127.0 ;
    return h;
    
}

#pragma mark - Properties

- (void)setSequence:(MIKMIDISequence *)sequence
{
    if (sequence != _sequence) {
        _sequence = sequence;
        [self setNeedsDisplay:YES];
    }
}

- (void)setDragInProgress:(BOOL)dragInProgress
{
    if (dragInProgress != _dragInProgress) {
        _dragInProgress = dragInProgress;
        [self setNeedsDisplay:YES];
    }
}

@end
