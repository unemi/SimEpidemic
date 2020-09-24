//
//  MyView.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/05.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@class Document;

@interface MyView : NSView {
	IBOutlet Document *doc;
	IBOutlet NSButton *magDownBtn;
	NSBitmapImageRep *imgRep;
	NSMutableDictionary *attr;
	NSInteger worldSize;
	CGFloat fontSize;
	NSSize frameSize;
}
@property CGFloat scale;
@property NSPoint offset;
@property BOOL showGatherings;
@end

@interface LegendView: NSView {
	NSTextField *label, *digits;
	NSColor *color;
}
- (void)setColor:(NSColor *)col;
- (void)setName:(NSString *)nm;
- (void)setIntegerValue:(NSInteger)value;
@end

NS_ASSUME_NONNULL_END
