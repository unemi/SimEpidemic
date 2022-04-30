//
//  PopDist.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2021/03/25.
//  Copyright © 2021 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class Document;
@interface PopDist : NSWindowController <NSWindowDelegate> {
	IBOutlet NSTextField *nPointsDgt, *edgeDgt, *centerDgt, *intExpDgt, *gammaDgt;
	IBOutlet NSSlider *edgeSld, *centerSld, *intExpSld, *gammaSld;
	IBOutlet NSButton *pasteBtn, *saveBtn;
	IBOutlet NSImageView *imgView;
}
@property NSImage *image;
@end

NS_ASSUME_NONNULL_END
