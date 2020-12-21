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

@interface DistDigits : NSObject {
	NSTextField __weak *minDgt, *maxDgt, *modDgt;
}
@property DistInfo *distInfo;
@property (readonly,weak) NSTabView *tabView;
- (instancetype)initWithDigits:(NSArray<NSTextField *> *)digits tabView:(nullable NSTabView *)tabV;
- (void)adjustDigitsToCurrentValue;
@end

@class Document;
@interface ParamPanel : NSWindowController
	<NSWindowDelegate, NSTabViewDelegate> {
	IBOutlet NSView *worldPView, *movePView, *pathoPView, *measPView, *testPView;
	IBOutlet NSTabView *tabView;
	IBOutlet NSTextField *fricDgt, *avoidDgt, *maxSpdDgt;
	IBOutlet NSSlider *fricSld, *avoidSld, *maxSpdSld;
	IBOutlet NSTextField *massDgt, *infecDgt, *infecDstDgt, *contagDDgt, *contagPDgt;
	IBOutlet NSTextField
		*mobDistMinDgt, *mobDistMaxDgt, *mobDistModeDgt,
		*incubMinDgt, *incubMaxDgt, *incubModeDgt,
		*fatalMinDgt, *fatalMaxDgt, *fatalModeDgt,
		*recovMinDgt, *recovMaxDgt, *recovModeDgt,
		*immunMinDgt, *immunMaxDgt, *immunModeDgt,
		*gatSZMinDgt, *gatSZMaxDgt, *gatSZModeDgt,
		*gatDRMinDgt, *gatDRMaxDgt, *gatDRModeDgt,
		*gatSTMinDgt, *gatSTMaxDgt, *gatSTModeDgt;
	IBOutlet NSSlider *massSld, *infecSld, *infecDstSld, *contagDSld, *contagPSld;
	IBOutlet NSTextField *initPopDgt, *worldSizeDgt, *stepsPerDayDgt, *meshDgt, *nInfecDgt;
	IBOutlet NSStepper *initPopStp, *worldSizeStp, *stepsPerDayStp, *meshStp, *nInfecStp;
	IBOutlet NSTextField *dstSTDgt, *dstOBDgt, *mobFrDgt, *gatFrDgt, *cntctTrcDgt;
	IBOutlet NSSlider *dstSTSld, *dstOBSld, *mobFrSld, *gatFrSld, *cntctTrcSld;
	IBOutlet NSTextField *tstDelayDgt, *tstProcDgt, *tstIntvlDgt, *tstSensDgt, *tstSpecDgt,
		*tstSbjAsyDgt, *tstSbjSymDgt;
	IBOutlet NSSlider *tstDelaySld, *tstProcSld, *tstIntvlSld, *tstSensSld, *tstSpecSld,
		*tstSbjAsySld, *tstSbjSymSld;
	IBOutlet NSButton *revertUDBtn, *revertFDBtn, *clearUDBtn, *saveAsUDBtn;
	IBOutlet NSButton *initPrmRdBtn, *crntPrmRdBtn; 
}
- (instancetype)initWithDoc:(Document *)dc;
- (void)adjustControls;
- (void)adjustParamControls:(NSArray<NSString *> *)paramNames;
- (void)checkUpdate;
- (IBAction)changeStepsPerDay:(id)sender;
- (void)setParamsOfRuntime:(const RuntimeParams *)rp world:(const WorldParams *)wp;
- (IBAction)reset:(id)sender;
- (IBAction)resetToFactoryDefaults:(id)sender;
- (IBAction)saveAsUserDefaults:(id)sender;
- (IBAction)clearUserDefaults:(id)sender;
- (IBAction)saveDocument:(id)sender;
- (IBAction)loadDocument:(id)sender;
@end

NS_ASSUME_NONNULL_END
