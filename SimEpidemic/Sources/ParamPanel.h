//
//  ParamPanel.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/06.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CommonTypes.h"

NS_ASSUME_NONNULL_BEGIN
@class Document;

@interface ParamPanel : NSWindowController <NSWindowDelegate> {
	IBOutlet NSTextField *infecDgt, *infecDstDgt;
	IBOutlet NSTextField
		*mobDistMinDgt, *mobDistMaxDgt, *mobDistModeDgt,
		*incubMinDgt, *incubMaxDgt, *incubModeDgt,
		*fatalMinDgt, *fatalMaxDgt, *fatalModeDgt,
		*recovMinDgt, *recovMaxDgt, *recovModeDgt,
		*immunMinDgt, *immunMaxDgt, *immunModeDgt;
	IBOutlet NSSlider *infecSld, *infecDstSld;
	IBOutlet NSTextField *initPopDgt, *worldSizeDgt, *stepsPerDayDgt, *meshDgt, *nInfecDgt;
	IBOutlet NSStepper *initPopStp, *worldSizeStp, *stepsPerDayStp, *meshStp, *nInfecStp;
	IBOutlet NSTextField *qnsRtDgt, *qnsDlDgt, *qdsRtDgt, *qdsDlDgt,
		*dstSTDgt, *dstOBDgt, *mobFrDgt;
	IBOutlet NSSlider *qnsRtSld, *qnsDlSld, *qdsRtSld, *qdsDlSld,
		*dstSTSld, *dstOBSld, *mobFrSld;
	IBOutlet NSButton *revertUDBtn, *revertFDBtn, *clearUDBtn,
		*saveAsUDBtn, *makeInitBtn;
}
- (instancetype)initWithDoc:(Document *)dc;
- (void)adjustControls;
- (IBAction)changeStepsPerDay:(id)sender;
- (void)setParamsWithPointer:(Params *)paramsP;
- (IBAction)reset:(id)sender;
- (IBAction)resetToFactoryDefaults:(id)sender;
- (IBAction)saveAsUserDefaults:(id)sender;
- (IBAction)clearUserDefaults:(id)sender;
- (IBAction)makeItInitialParameters:(id)sender;
- (IBAction)saveDocument:(id)sender;
- (IBAction)loadDocument:(id)sender;
@end

NS_ASSUME_NONNULL_END
