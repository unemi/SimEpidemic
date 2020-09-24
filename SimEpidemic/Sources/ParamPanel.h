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

@interface ParamPanel : NSWindowController
	<NSWindowDelegate, NSTabViewDelegate> {
	IBOutlet NSView *worldPView, *movePView, *pathoPView, *measPView, *testPView;
	IBOutlet NSTabView *tabView;
	IBOutlet NSTextField *massDgt, *fricDgt, *avoidDgt;
	IBOutlet NSSlider *massSld, *fricSld, *avoidSld;
	IBOutlet NSTextField *infecDgt, *infecDstDgt, *contagDDgt, *contagPDgt;
	IBOutlet NSTextField
		*mobDistMinDgt, *mobDistMaxDgt, *mobDistModeDgt,
		*incubMinDgt, *incubMaxDgt, *incubModeDgt,
		*fatalMinDgt, *fatalMaxDgt, *fatalModeDgt,
		*recovMinDgt, *recovMaxDgt, *recovModeDgt,
		*immunMinDgt, *immunMaxDgt, *immunModeDgt,
		*gatSZMinDgt, *gatSZMaxDgt, *gatSZModeDgt,
		*gatDRMinDgt, *gatDRMaxDgt, *gatDRModeDgt,
		*gatSTMinDgt, *gatSTMaxDgt, *gatSTModeDgt;
	IBOutlet NSSlider *infecSld, *infecDstSld, *contagDSld, *contagPSld;
	IBOutlet NSTextField *initPopDgt, *worldSizeDgt, *stepsPerDayDgt, *meshDgt, *nInfecDgt;
	IBOutlet NSStepper *initPopStp, *worldSizeStp, *stepsPerDayStp, *meshStp, *nInfecStp;
	IBOutlet NSTextField *dstSTDgt, *dstOBDgt, *mobFrDgt, *gatFrDgt, *cntctTrcDgt;
	IBOutlet NSSlider *dstSTSld, *dstOBSld, *mobFrSld, *gatFrSld, *cntctTrcSld;
	IBOutlet NSTextField *tstDelayDgt, *tstProcDgt, *tstIntvlDgt, *tstSensDgt, *tstSpecDgt,
		*tstSbjAsyDgt, *tstSbjSymDgt;
	IBOutlet NSSlider *tstDelaySld, *tstProcSld, *tstIntvlSld, *tstSensSld, *tstSpecSld,
		*tstSbjAsySld, *tstSbjSymSld;
	IBOutlet NSButton *revertUDBtn, *revertFDBtn, *clearUDBtn,
		*saveAsUDBtn, *makeInitBtn;
}
- (instancetype)initWithDoc:(Document *)dc;
- (void)adjustControls;
- (void)checkUpdate;
- (IBAction)changeStepsPerDay:(id)sender;
- (void)setParamsOfRuntime:(const RuntimeParams *)rp world:(const WorldParams *)wp;
- (IBAction)reset:(id)sender;
- (IBAction)resetToFactoryDefaults:(id)sender;
- (IBAction)saveAsUserDefaults:(id)sender;
- (IBAction)clearUserDefaults:(id)sender;
- (IBAction)makeItInitialParameters:(id)sender;
- (IBAction)saveDocument:(id)sender;
- (IBAction)loadDocument:(id)sender;
@end

NS_ASSUME_NONNULL_END
