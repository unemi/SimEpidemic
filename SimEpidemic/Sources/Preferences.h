//
//  Preferences.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/08/31.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface Preferences : NSWindowController {
	IBOutlet NSStepper *animeStepper;
	IBOutlet NSTextField *animeStepTxt;
	IBOutlet NSColorWell
		*bgColWell, *hospitalColWell, *cemeteryColWell, *textColWell,
		*susColWell, *asyColWell, *symColWell, *recColWell, *dieColWell;
	IBOutlet NSSlider *warpOpacitySld, *panelsAlphaSld;
	IBOutlet NSTextField *warpOpacityDgt, *panelsAlphaDgt;
	IBOutlet NSButton *childWinCBox;
}
@end

NS_ASSUME_NONNULL_END
