//
//  MyView.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/05.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef enum {
	ColNormal, ColAntiVax, ColVaxVariant
} ColorType;

@class Document, World;

@interface MyView : NSView {
	IBOutlet NSButton *magDownBtn;
	NSBitmapImageRep *imgRep;
	BOOL liveResizeEnded;
	NSMutableDictionary *attr;
	NSInteger worldSize;
	CGFloat fontSize;
	NSSize frameSize;
}
@property __weak World * __nullable world;
@property CGFloat scale;
@property NSPoint offset;
@property BOOL showGatherings;
@property ColorType colorType;
- (void)enableMagDownButton;
@end

@interface LegendView: NSView {
	NSTextField *label, *digits;
	NSColor *color;
}
- (void)setColor:(NSColor *)col;
- (void)setName:(NSString *)nm;
- (void)setIntegerValue:(NSInteger)value;
@end

@interface FillView : NSView
@end

NS_ASSUME_NONNULL_END
