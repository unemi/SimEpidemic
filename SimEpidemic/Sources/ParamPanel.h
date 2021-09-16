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
	void (^valueChanedCB)(void);
}
@property DistInfo *distInfo;
@property (readonly,weak) NSTabView *tabView;
- (instancetype)initWithDigits:(NSArray<NSTextField *> *)digits
	tabView:(nullable NSTabView *)tabV callBack:(void (^)(void))proc;
- (void)adjustDigitsToCurrentValue;
@end

@class Document, World;
@interface ParamPanel : NSWindowController
	<NSWindowDelegate, NSTabViewDelegate> {
	IBOutlet NSView *worldPView, *movePView, *pathoPView, *measPView, *testPView;
	IBOutlet NSTabView *tabView;
	IBOutlet NSTextField *massDgt, *fricDgt, *avoidDgt, *maxSpdDgt;
	IBOutlet NSSlider *massSld, *fricSld, *avoidSld, *maxSpdSld;
	IBOutlet NSTextField *actModeDgt, *actKurtDgt, *massActDgt, *mobActDgt, *gatActDgt;
	IBOutlet NSSlider *actModeSld, *actKurtSld, *massActSld, *mobActSld, *gatActSld;
	IBOutlet NSTextField *incubActDgt, *fatalActDgt, *recovActDgt, *immueActDgt;
	IBOutlet NSSlider *incubActSld, *fatalActSld, *recovActSld, *immueActSld;
	IBOutlet NSTextField *infecDgt, *infecDstDgt, *contagDDgt, *contagPDgt;
	IBOutlet NSSlider *infecSld, *infecDstSld, *contagDSld, *contagPSld;
	IBOutlet NSTextField *imnMaxDurDgt, *imnMaxDurSvDgt, *imnMaxEffcDgt, *imnMaxEffcSvDgt;
	IBOutlet NSSlider *imnMaxDurSld, *imnMaxDurSvSld, *imnMaxEffcSld, *imnMaxEffcSvSld;
	IBOutlet NSTextField
		*mobDistMinDgt, *mobDistMaxDgt, *mobDistModeDgt,
		*incubMinDgt, *incubMaxDgt, *incubModeDgt,
		*fatalMinDgt, *fatalMaxDgt, *fatalModeDgt,
		*recovMinDgt, *recovMaxDgt, *recovModeDgt,
		*gatSZMinDgt, *gatSZMaxDgt, *gatSZModeDgt,
		*gatDRMinDgt, *gatDRMaxDgt, *gatDRModeDgt,
		*gatSTMinDgt, *gatSTMaxDgt, *gatSTModeDgt,
		*mobFreqMinDgt, *mobFreqMaxDgt, *mobFreqModeDgt,
		*gatFreqMinDgt, *gatFreqMaxDgt, *gatFreqModeDgt;
	IBOutlet NSTextField *initPopDgt, *worldSizeDgt, *stepsPerDayDgt, *meshDgt;
	IBOutlet NSStepper *initPopStp, *worldSizeStp, *stepsPerDayStp, *meshStp;
	IBOutlet NSTextField *initInfcDgt, *initRecvDgt, *initQAsymDgt, *initQSympDgt;
	IBOutlet NSSlider *initInfcSld, *initRecvSld, *initQAsymSld, *initQSympSld;
	IBOutlet NSTextField *dstSTDgt, *dstOBDgt, *backHmDgt, *gatFrDgt, *cntctTrcDgt;
	IBOutlet NSSlider *dstSTSld, *dstOBSld, *backHmSld, *gatFrSld, *cntctTrcSld;
	IBOutlet NSTextField *tstDelayDgt, *tstProcDgt, *tstIntvlDgt, *tstSensDgt, *tstSpecDgt,
		*tstSbjAsyDgt, *tstSbjSymDgt;
	IBOutlet NSSlider *tstDelaySld, *tstProcSld, *tstIntvlSld, *tstSensSld, *tstSpecSld,
		*tstSbjAsySld, *tstSbjSymSld;
	IBOutlet NSTextField *vcnPRateDgt, *vcnRegularityDgt, *vcnAntiRateDgt;
	IBOutlet NSSlider *vcnPRateSld, *vcnRegularitySld, *vcnAntiRateSld;
	IBOutlet NSTextField *vaClstrRtDgt, *vaClstrGrDgt, *vaTestRtDgt;
	IBOutlet NSSlider *vaClstrRtSld, *vaClstrGrSld, *vaTestRtSld;
	IBOutlet NSPopUpButton *wrkPlcModePopUp, *trcOpePopUp, *trcVcnTypePopUp,
		*vcnPriPopUp, *vcnTypePopUp;
	IBOutlet NSButton *revertUDBtn, *revertFDBtn, *clearUDBtn, *saveAsUDBtn;
	IBOutlet NSButton *initPrmRdBtn, *crntPrmRdBtn;
}
@property BOOL byUser;
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

extern void adjust_vcnType_popUps(NSArray<NSPopUpButton *> *popUps, World *world);

NS_ASSUME_NONNULL_END
