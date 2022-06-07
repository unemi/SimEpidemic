//
//  ParamPanel.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/06.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "ParamPanel.h"
#import "AppDelegate.h"
#import "Document.h"
#import "World.h"
#import "PopDist.h"
#import "VVPanel.h"

static void reveal_me_in_tabview(NSControl *me, NSTabView *tabView) {
	NSView *parent = me.superview;
	if (parent.superview != nil) return;
	for (NSTabViewItem *item in tabView.tabViewItems) if (item.view == parent)
		{ [tabView selectTabViewItem:item]; break; }
}
@implementation DistDigits
static NSNumberFormatter *distDgtFmt = nil;
- (instancetype)initWithDigits:(NSArray<NSTextField *> *)digits
	tabView:(nullable NSTabView *)tabV callBack:(void (^)(void))proc {
	if (!(self = [super init])) return nil;
	if (distDgtFmt == nil) {
		distDgtFmt = NSNumberFormatter.new;
		distDgtFmt.allowsFloats = YES;
		distDgtFmt.minimumFractionDigits = distDgtFmt.maximumFractionDigits =
		distDgtFmt.minimumIntegerDigits = 1;
	}
	minDgt = digits[0];
	maxDgt = digits[1];
	modDgt = digits[2];
	minDgt.target = maxDgt.target = modDgt.target = self;
	minDgt.action = maxDgt.action = modDgt.action = @selector(dValueChanged:);
	minDgt.formatter = maxDgt.formatter = modDgt.formatter = distDgtFmt;
	_tabView = tabV;
	valueChanedCB = proc;
	return self;
}
- (void)setIndex:(NSInteger)index {
	minDgt.tag = maxDgt.tag = modDgt.tag = index;
}
- (void)adjustDigitsToCurrentValue {
	minDgt.doubleValue = _distInfo->min;
	maxDgt.doubleValue = _distInfo->max;
	modDgt.doubleValue = _distInfo->mode;
}
- (NSUndoManager *)undoManager {
	NSWindow *window = minDgt.window;
	return [window.delegate windowWillReturnUndoManager:window];
}
- (NSTextField *)minDgt { return minDgt; }
- (void)changeDistInfo:(DistInfo)newInfo {
	DistInfo orgInfo = *_distInfo;
	*_distInfo = newInfo;
	[self adjustDigitsToCurrentValue];
	[self.undoManager registerUndoWithTarget:self handler:^(DistDigits *dd) {
		if (dd.tabView != nil) reveal_me_in_tabview(dd.minDgt, dd.tabView);
		[dd changeDistInfo:orgInfo];
	}];
	if (valueChanedCB != nil) valueChanedCB();
}
- (void)dValueChanged:(NSTextField *)sender {
	CGFloat newValue = sender.doubleValue;
	DistInfo newInfo = *_distInfo;
	if (sender == minDgt) {
		if (newValue == newInfo.min) return;
		newInfo.min = newValue;
		if (newInfo.max < newValue) newInfo.max = newValue;
		if (newInfo.mode < newValue) newInfo.mode = newValue;
	} else if (sender == maxDgt) {
		if (newValue == newInfo.max) return;
		newInfo.max = newValue;
		if (newInfo.min > newValue) newInfo.min = newValue;
		if (newInfo.mode > newValue) newInfo.mode = newValue;
	} else {
		if (newValue == newInfo.mode) return;
		newInfo.mode = newValue;
		if (newInfo.min > newValue) newInfo.min = newValue;
		if (newInfo.max < newValue) newInfo.max = newValue;
	}
	[self changeDistInfo:newInfo];
}
@end

@interface AgeSpanView : NSTableCellView
@property NSTextField *leftText, *rightText;
@end
@implementation AgeSpanView
- (instancetype)initWithFrame:(NSRect)frame
	lower:(NSInteger)low upper:(NSInteger)up max:(NSInteger)maxAge {
	if (!(self = [super initWithFrame:frame])) return nil;
	NSNumberFormatter *ageFmt = NSNumberFormatter.new;
	ageFmt.minimum = @(low);
	ageFmt.maximum = @(maxAge);
	_leftText = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld -", low]];
	_rightText = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld", up]];
	NSRect leftFrm = _leftText.frame, rightFrm = _rightText.frame;
	leftFrm.origin.x = (frame.size.width - leftFrm.size.width - rightFrm.size.width) / 2.;
	rightFrm.origin.x = NSMaxX(leftFrm);
	rightFrm.size.width = frame.size.width - rightFrm.origin.x;
	_leftText.frame = leftFrm;
	_rightText.frame = rightFrm;
	[self addSubview:_leftText];
	[self addSubview:_rightText];
	_rightText.editable = YES;
	_rightText.formatter = ageFmt;
	_rightText.cell.sendsActionOnEndEditing = YES;
	return self;
}
@end

#define N_SUBPANELS 5
@interface ParamPanel () {
	Document *doc;
	World *world;
	RuntimeParams *targetParams;
	NSArray<NSTextField *> *fDigits, *iDigits, *rDigits;
	NSArray<DistDigits *> *dDigits;
	NSArray<NSSlider *> *fSliders, *rSliders;
	NSArray<NSStepper *> *iSteppers;
	PopDist *popDist;
	DistDigits *dDigitW;
	NSUndoManager *undoManager;
	BOOL hasUserDefaults;
	NSSize viewSize[N_SUBPANELS];
	NSRect orgFrame;
	NSInteger vcnType, nAgeSpans;
}
@end

@implementation ParamPanel
- (instancetype)initWithDoc:(Document *)dc {
	if (!(self = [super initWithWindowNibName:@"ParamPanel"])) return nil;
	doc = dc;
	world = dc.world;
	targetParams = world.initParamsP;
	undoManager = NSUndoManager.new;
	_byUser = YES;
	return self;
}
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return undoManager;
}
static NSInteger spd_to_stpInt(NSInteger stepsPerDay) {
	return (stepsPerDay < 3)? 0 : round(log2(stepsPerDay / 3)) + 1;
}
static NSInteger stpInt_to_spd(NSInteger stpExp) {
	return (stpExp <= 0)? 1 : round(pow(2., stpExp - 1)) * 3;
}
- (void)adjustVcnInfoControls:(NSInteger)newIndex {
	vcnType = newIndex;
	[vcnTypePopUp selectItemAtIndex:vcnType];
	VaccinationInfo *vp = &targetParams->vcnInfo[vcnType];
	[vcnPriPopUp selectItemAtIndex:vp->priority];
	vcnPRateDgt.doubleValue = vcnPRateSld.doubleValue = vp->performRate;
	vcnRegularityDgt.doubleValue = vcnRegularitySld.doubleValue = vp->regularity;
}
- (void)adjustControls {
	WorldParams *wp = world.tmpWorldParamsP;
	for (NSInteger i = 0; i < fDigits.count; i ++)
		fDigits[i].doubleValue = fSliders[i].doubleValue = (&targetParams->PARAM_F1)[i];
	for (DistDigits *d in dDigits) [d adjustDigitsToCurrentValue];
	for (NSInteger i = 0; i < iDigits.count; i ++)
		iDigits[i].integerValue = iSteppers[i].integerValue = (&wp->PARAM_I1)[i];
	for (NSInteger i = 0; i < rDigits.count; i ++)
		rDigits[i].doubleValue = rSliders[i].doubleValue = (&wp->PARAM_R1)[i];
	stepsPerDayStp.integerValue = spd_to_stpInt(wp->stepsPerDay);
	stepsPerDayDgt.integerValue = wp->stepsPerDay;
	[dDigitW adjustDigitsToCurrentValue];
	[self adjustVcnInfoControls:0];
	[wrkPlcModePopUp selectItemAtIndex:wp->wrkPlcMode];
	popDistGammaDgt.enabled = popDistGammaSld.enabled = (wp->wrkPlcMode >= WrkPlcCentered);
	vaxFnlRtHelpTxt.hidden = targetParams == world.runtimeParamsP;
	nAgeSpans = 0;
	for (; nAgeSpans < MAX_N_AGE_SPANS; nAgeSpans ++)
		if (targetParams->vcnFnlRt[nAgeSpans].upperAge >= 150) { nAgeSpans ++; break; }
	[vaxFnlRtTable reloadData];
}
- (void)adjustParamControls:(NSArray<NSString *> *)paramNames {
	if (targetParams != world.runtimeParamsP) return;
	for (NSString *key in paramNames) {
		NSInteger idx = paramIndexFromKey[key].integerValue;
		if (idx < IDX_D) fDigits[idx].doubleValue =
			fSliders[idx].doubleValue = (&targetParams->PARAM_F1)[idx];
		else [dDigits[idx - IDX_D] adjustDigitsToCurrentValue];
	}
	[vaxFnlRtTable reloadData];
}
void adjust_vcnType_popUps(NSArray<NSPopUpButton *> *popUps, World *world) {
	NSArray<NSDictionary *> *vcnList = world.vaccineList;
	NSInteger nVcns = vcnList.count, selIdx = 0;
	for (NSPopUpButton *popUp in popUps) {
		NSInteger nItems = popUp.numberOfItems;
		NSString *orgSelected = popUp.titleOfSelectedItem;
		for (NSInteger i = 0; i < nVcns; i ++) {
			NSString *vcnName = vcnList[i][@"name"];
			if (i < nItems) [popUp itemAtIndex:i].title = vcnName;
			else [popUp addItemWithTitle:vcnName];
			if ([vcnName isEqualToString:orgSelected]) selIdx = i;
		}
		for (NSInteger i = nItems - 1; i >= nVcns; i --)
			[popUp removeItemAtIndex:i];
		[popUp selectItemAtIndex:selIdx];
	}
}
- (void)adjustVcnTypeMenu:(NSNotification *)note {
	adjust_vcnType_popUps(@[trcVcnTypePopUp, vcnTypePopUp], world);
	VaccinationInfo *vInfo = &targetParams->vcnInfo[vcnTypePopUp.indexOfSelectedItem];
	vcnPRateDgt.doubleValue = vcnPRateSld.doubleValue = vInfo->performRate;
	vcnRegularityDgt.doubleValue = vcnRegularitySld.doubleValue = vInfo->regularity;
	[vcnPriPopUp selectItemAtIndex:vInfo->priority];
}
- (void)checkUpdate {
	revertUDBtn.enabled = hasUserDefaults &&
		(memcmp(targetParams, &userDefaultRuntimeParams, sizeof(RuntimeParams)) ||
		memcmp(world.tmpWorldParamsP, &userDefaultWorldParams, sizeof(WorldParams)));
	revertFDBtn.enabled =
		memcmp(targetParams, &defaultRuntimeParams, sizeof(RuntimeParams)) ||
		memcmp(world.tmpWorldParamsP, &defaultWorldParams, sizeof(WorldParams));
	saveAsUDBtn.enabled =
		memcmp(targetParams, &userDefaultRuntimeParams, sizeof(RuntimeParams)) ||
		memcmp(world.tmpWorldParamsP, &userDefaultWorldParams, sizeof(WorldParams));
}
- (void)adjustAllControlls {
	for (NSInteger i = 0; i < dDigits.count; i ++)
		dDigits[i].distInfo = &targetParams->PARAM_D1 + i;
	[self adjustControls];
	[self checkUpdate];
}
- (void)doubleClickVaxFnlTbl:(id)sender {
	NSLog(@"doubleClickVaxFnlTbl %ld %ld", vaxFnlRtTable.clickedRow, vaxFnlRtTable.clickedColumn);
}
#define DDGT(d1,d2,d3) [DistDigits.alloc initWithDigits:@[d1,d2,d3]\
 tabView:tabView callBack:proc]
- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.alphaValue = panelsAlpha;
    NSArray<NSTabViewItem *> *tabs = tabView.tabViewItems;
    NSView *views[] = {worldPView, movePView, pathoPView, measPView, testPView};
    for (NSInteger i = 0; i < N_SUBPANELS; i ++) {
		viewSize[i] = views[i].frame.size;
		tabs[i].view = views[i];
	}
	NSRect wFrame = self.window.frame, scrRct = self.window.screen.frame;
	CGFloat dh = viewSize[0].height - tabs[0].view.frame.size.height;
	wFrame.size.height += dh;
	if ((wFrame.origin.y -= dh) < NSMinY(scrRct)) wFrame.origin.y = NSMinY(scrRct);
	[self.window setFrame:wFrame display:NO];
    fDigits = @[massDgt, fricDgt, avoidDgt, maxSpdDgt,
		actModeDgt, actKurtDgt, massActDgt, mobActDgt, gatActDgt,
		incubActDgt, fatalActDgt, immueActDgt, therapyEffcDgt,
		contagDDgt, contagPDgt, infecDgt, infecDstDgt,
		dstSTDgt, dstOBDgt, backHmDgt, gatFrDgt, gatRndDgt, cntctTrcDgt,
		tstDelayDgt, tstProcDgt, tstIntvlDgt, tstSensDgt, tstSpecDgt,
		tstSbjAsyDgt, tstSbjSymDgt, tstCapaDgt, tstDlyLimDgt,
		imnMaxDurDgt, imnMaxDurSvDgt, imnMaxEffcDgt, imnMaxEffcSvDgt];
	fSliders = @[massSld, fricSld, avoidSld, maxSpdSld,
		actModeSld, actKurtSld, massActSld, mobActSld, gatActSld,
		incubActSld, fatalActSld, immueActSld, therapyEffcSld,
		contagDSld, contagPSld, infecSld, infecDstSld,
		dstSTSld, dstOBSld, backHmSld, gatFrSld, gatRndSld, cntctTrcSld,
		tstDelaySld, tstProcSld, tstIntvlSld, tstSensSld, tstSpecSld,
		tstSbjAsySld, tstSbjSymSld, tstCapaSld, tstDlyLimSld,
		imnMaxDurSld, imnMaxDurSvSld, imnMaxEffcSld, imnMaxEffcSvSld];
	ParamPanel __weak *pp = self;
	void (^proc)(void) = ^{ [pp checkUpdate]; };
	dDigits = @[
		DDGT(mobDistMinDgt, mobDistMaxDgt, mobDistModeDgt),
		DDGT(incubMinDgt, incubMaxDgt, incubModeDgt),
		DDGT(fatalMinDgt, fatalMaxDgt, fatalModeDgt),
		DDGT(gatSZMinDgt, gatSZMaxDgt, gatSZModeDgt),
		DDGT(gatDRMinDgt, gatDRMaxDgt, gatDRModeDgt),
		DDGT(gatSTMinDgt, gatSTMaxDgt, gatSTModeDgt),
		DDGT(mobFreqMinDgt, mobFreqMaxDgt, mobFreqModeDgt),
		DDGT(gatFreqMinDgt, gatFreqMaxDgt, gatFreqModeDgt)];
	iDigits = @[initPopDgt, worldSizeDgt, meshDgt];
	iSteppers = @[initPopStp, worldSizeStp, meshStp];
	rDigits = @[initInfcDgt, initRecvDgt, initQAsymDgt, initQSympDgt,
		popDistGammaDgt, gatSptFxDgt,
		vaClstrRtDgt, vaClstrGrDgt, vaTestRtDgt,
		rcvBiasDgt, rcvTempDgt, rcvUpperDgt, rcvLowerDgt];
	rSliders = @[initInfcSld, initRecvSld, initQAsymSld, initQSympSld,
		popDistGammaSld, gatSptFxSld,
		vaClstrRtSld, vaClstrGrSld, vaTestRtSld,
		rcvBiasSld, rcvTempSld, rcvUpperSld, rcvLowerSld];
    for (NSInteger idx = 0; idx < fDigits.count; idx ++) {
		NSTextField *d = fDigits[idx];
		NSSlider *s = fSliders[idx];
		d.tag = s.tag = idx;
		d.action = s.action = @selector(fValueChanged:);
		d.target = s.target = self;
		NSNumberFormatter *fmt = paramFormatters[idx];
		d.formatter = fmt;
		s.minValue = fmt.minimum.doubleValue;
		s.maxValue = fmt.maximum.doubleValue;
	}
	for (NSInteger i = 0; i < dDigits.count; i ++) dDigits[i].index = i;
    for (NSInteger idx = 0; idx < iDigits.count; idx ++) {
		NSTextField *d = iDigits[idx];
		NSStepper *s = iSteppers[idx];
		d.tag = s.tag = idx;
		d.action = s.action = @selector(iValueChanged:);
		d.target = s.target = self;
		NSNumberFormatter *fmt = paramFormatters[idx + fDigits.count];
		d.formatter = fmt;
		s.minValue = fmt.minimum.doubleValue;
		s.maxValue = fmt.maximum.doubleValue;
	}
	NSInteger fmtBase = fDigits.count + iDigits.count + 1;
    for (NSInteger idx = 0; idx < rDigits.count; idx ++) {
		NSTextField *d = rDigits[idx];
		NSSlider *s = rSliders[idx];
		d.tag = s.tag = idx;
		d.action = s.action = @selector(rValueChanged:);
		d.target = s.target = self;
		NSNumberFormatter *fmt = paramFormatters[idx + fmtBase];
		d.formatter = fmt;
		s.minValue = fmt.minimum.doubleValue;
		s.maxValue = fmt.maximum.doubleValue;
	}
	[self adjustVcnTypeMenu:nil];
	[NSNotificationCenter.defaultCenter addObserver:self
		selector:@selector(adjustVcnTypeMenu:) name:VaccineListChanged object:world];
	NSArray<NSTableColumn *> *cols = vaxFnlRtTable.tableColumns;
	for (NSInteger i = 1; i < cols.count; i ++) cols[i].identifier = @(i - 1).stringValue;
	for (NSInteger i = cols.count; i <= MAX_N_AGE_SPANS; i ++) {
		NSTableColumn *tcol = [NSTableColumn.alloc initWithIdentifier:@(i - 1).stringValue];
		tcol.width = cols[1].width;
		tcol.resizingMask = cols[1].resizingMask;
		tcol.title = @"";
		[vaxFnlRtTable addTableColumn:tcol];
	}
//	vaxFnlRtTable.doubleAction = @selector(doubleClickVaxFnlTbl:);
	clearUDBtn.enabled = hasUserDefaults =
		memcmp(&userDefaultRuntimeParams, &defaultRuntimeParams, sizeof(RuntimeParams))
	 || memcmp(&userDefaultWorldParams, &defaultWorldParams, sizeof(WorldParams));
    [self adjustAllControlls];
    [doc setPanelTitle:self.window];
//
	gatSptFxDgt.toolTip = gatSptFxSld.toolTip = NSLocalizedString(@"per population", nil);
}
- (IBAction)changeStepsPerDay:(id)sender {
// steps/day's possible values = {1, 3, 6, 12, 24, 48, ... }, changed at ver.1.8.4
	WorldParams *wp = world.tmpWorldParamsP;
	NSInteger orgExp = spd_to_stpInt(wp->stepsPerDay);
	NSTabView *tabV = tabView;
	[undoManager registerUndoWithTarget:stepsPerDayStp handler:^(NSStepper *target) {
		reveal_me_in_tabview(target, tabV);
		target.integerValue = orgExp;
		[target sendAction:target.action to:target.target];
	}];
	NSInteger newExp =  stepsPerDayStp.integerValue;
	wp->stepsPerDay = stpInt_to_spd(newExp);
	stepsPerDayDgt.integerValue = wp->stepsPerDay;
	[self checkUpdate];
}
- (IBAction)chooseHomeMode:(id)sender {
	WorldParams *wp = world.tmpWorldParamsP;
	WrkPlcMode orgValue = wp->wrkPlcMode, newValue = (WrkPlcMode)wrkPlcModePopUp.indexOfSelectedItem;
	if (orgValue == newValue) return;
	NSTabView *tabV = tabView;
	[undoManager registerUndoWithTarget:wrkPlcModePopUp handler:^(NSPopUpButton *target) {
		reveal_me_in_tabview(target, tabV);
		[target selectItemAtIndex:orgValue];
		[target sendAction:target.action to:target.target];
	}];
	wp->wrkPlcMode = newValue;
	popDistGammaDgt.enabled = popDistGammaSld.enabled = (newValue >= WrkPlcCentered);
	[self checkUpdate];
}
- (IBAction)chooseTracingOperation:(id)sender {
	TracingOperation orgValue = targetParams->trcOpe,
		newValue = (TracingOperation)trcOpePopUp.indexOfSelectedItem;
	if (orgValue == newValue) return;
	NSTabView *tabV = tabView;
	[undoManager registerUndoWithTarget:trcOpePopUp handler:^(NSPopUpButton *target) {
		reveal_me_in_tabview(target, tabV);
		[target selectItemAtIndex:orgValue];
		[target sendAction:target.action to:target.target];
	}];
	targetParams->trcOpe = newValue;
	trcVcnTypePopUp.enabled = (newValue != TrcTst);
	[self checkUpdate];
}
- (IBAction)chooseTrcVaccineType:(id)sender {
	NSInteger orgValue = targetParams->trcVcnType,
		newValue = trcVcnTypePopUp.indexOfSelectedItem;
	if (orgValue == newValue) return;
	NSTabView *tabV = tabView;
	[undoManager registerUndoWithTarget:trcVcnTypePopUp handler:^(NSPopUpButton *target) {
		reveal_me_in_tabview(target, tabV);
		[target selectItemAtIndex:orgValue];
		[target sendAction:target.action to:target.target];
	}];
	targetParams->trcVcnType = (int)newValue;
	[self checkUpdate];
}
- (IBAction)chooseVaccinePriority:(id)sender {
	VaccinePriority orgValue = targetParams->vcnInfo[vcnType].priority,
		newValue = (VaccinePriority)vcnPriPopUp.indexOfSelectedItem;
	if (orgValue == newValue) return;
	NSTabView *tabV = tabView;
	[undoManager registerUndoWithTarget:vcnPriPopUp handler:^(NSPopUpButton *target) {
		reveal_me_in_tabview(target, tabV);
		[target selectItemAtIndex:orgValue];
		[target sendAction:target.action to:target.target];
	}];
	targetParams->vcnInfo[vcnType].priority = newValue;
	if (newValue == VcnPrBooster) [world resetBoostQueue];
	[self checkUpdate];
}
- (IBAction)chooseVcnType:(NSPopUpButton *)sender {
	NSInteger newIndex = sender.indexOfSelectedItem, orgIndex = vcnType;
	if (newIndex == orgIndex) return;
	[undoManager registerUndoWithTarget:sender handler:^(NSPopUpButton *target) {
		[sender selectItemAtIndex:orgIndex];
		[target sendAction:target.action to:target.target];
	}];
	[self adjustVcnInfoControls:newIndex];
}
- (IBAction)changeVcnPRate:(NSControl *)sender {
	CGFloat orgValue = targetParams->vcnInfo[vcnType].performRate,
		newValue = sender.doubleValue;
	if (orgValue == newValue) return;
	[undoManager registerUndoWithTarget:sender handler:^(NSControl *target) {
		sender.doubleValue = orgValue;
		[target sendAction:target.action to:target.target];
	}];
	if (sender != vcnPRateDgt) vcnPRateDgt.doubleValue = newValue;
	if (sender != vcnPRateSld) vcnPRateSld.doubleValue = newValue;
	targetParams->vcnInfo[vcnType].performRate = newValue;
}
- (IBAction)changeVcnRegularity:(NSControl *)sender {
	CGFloat orgValue = targetParams->vcnInfo[vcnType].regularity,
		newValue = sender.doubleValue;
	if (orgValue == newValue) return;
	[undoManager registerUndoWithTarget:sender handler:^(NSControl *target) {
		sender.doubleValue = orgValue;
		[target sendAction:target.action to:target.target];
	}];
	if (sender != vcnRegularityDgt) vcnRegularityDgt.doubleValue = newValue;
	if (sender != vcnRegularitySld) vcnRegularitySld.doubleValue = newValue;
	targetParams->vcnInfo[vcnType].regularity = newValue;
}
- (void)setParamsOfRuntime:(const RuntimeParams *)rp world:(const WorldParams *)wp {
	RuntimeParams rtPr = *targetParams;
	WorldParams wlPr = *(world.tmpWorldParamsP);
	[undoManager registerUndoWithTarget:self handler:^(ParamPanel *panel) {
		[panel setParamsOfRuntime:&rtPr world:&wlPr];
	}];
	*targetParams = *rp;
	*(world.tmpWorldParamsP) = *wp;
	[self adjustControls];
	[self checkUpdate];
}
- (IBAction)reset:(id)sender {
	[self setParamsOfRuntime:&userDefaultRuntimeParams world:&userDefaultWorldParams];
}
- (IBAction)resetToFactoryDefaults:(id)sender {
	[self setParamsOfRuntime:&defaultRuntimeParams world:&defaultWorldParams];
}
- (IBAction)saveAsUserDefaults:(id)sender {
	RuntimeParams *rp = targetParams;
	WorldParams *wp = world.tmpWorldParamsP;
	confirm_operation(@"Will overwrites the current user's defaults.", self.window, ^{
		NSDictionary<NSString *, NSNumber *> *dict = param_dict(rp, wp);
		NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
		for (NSString *key in dict.keyEnumerator)
			[ud setObject:dict[key] forKey:key];
		self->clearUDBtn.enabled = self->hasUserDefaults = YES;
		self->revertUDBtn.enabled = NO;
	});
}
- (IBAction)clearUserDefaults:(id)sender {
	confirm_operation(@"Will clear the current user's defaults.", self.window, ^{
		NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
		for (NSString *key in paramKeys)
			[ud removeObjectForKey:key];
		self->revertUDBtn.enabled = self->clearUDBtn.enabled =
		self->hasUserDefaults = NO;
	});
}
- (IBAction)switchInitOrCurrent:(id)sender {
	RuntimeParams *newTarget = (sender == initPrmRdBtn)? world.initParamsP : world.runtimeParamsP;
	if (newTarget != targetParams) {
		[undoManager registerUndoWithTarget:(sender == initPrmRdBtn)? crntPrmRdBtn : initPrmRdBtn
			handler:^(NSButton *target) {
				[target performClick:nil];
		}];
		targetParams = newTarget;
		[self adjustAllControlls];
	}
}
- (IBAction)saveDocument:(id)sender {
	save_property_data(@"sEpP", self.window, param_dict(targetParams, world.tmpWorldParamsP));
}
- (IBAction)loadDocument:(id)sender {
	NSWindow *window = self.window;
	load_property_data(@[@"sEpi", @"sEpP", @"json"], self.window, NSDictionary.class,
		^(NSURL *url, NSObject *obj) {
		NSDictionary *dict = (NSDictionary *)obj;
		if ([url.pathExtension isEqualToString:@"sEpi"]) dict = dict[keyParameters];
		if (dict == nil) error_msg([NSString stringWithFormat:
			@"%@ doesn't include parameters.", url.path], window, NO);
		else {
			RuntimeParams tmpRP;
			WorldParams tmpWP;
			memcpy(&tmpRP, &defaultRuntimeParams, sizeof(RuntimeParams));
			memcpy(&tmpWP, &defaultWorldParams, sizeof(WorldParams));
			set_params_from_dict(&tmpRP, &tmpWP, dict);
			[self setParamsOfRuntime:&tmpRP world:&tmpWP];
		}
	});
}
- (IBAction)copy:(id)sender {
	copy_plist_as_JSON_text(
		(NSEvent.modifierFlags & NSEventModifierFlagShift)?
		param_diff_dict(targetParams, &userDefaultRuntimeParams,
			world.tmpWorldParamsP, &userDefaultWorldParams) :
		param_dict(targetParams, world.tmpWorldParamsP),
		self.window);
}
- (void)copyParamsFromDict:(NSDictionary *)dict {
	RuntimeParams *rp = targetParams, orgRp = *rp;
	WorldParams *wp = world.tmpWorldParamsP, orgWp = *wp;
	set_params_from_dict(targetParams, wp, dict);
	NSDictionary *pDiff = param_diff_dict(&orgRp, targetParams, &orgWp, wp);
#ifdef DEBUG
	NSLog(@"copyParamsFromDict");
	for (NSString *key in pDiff.keyEnumerator)
		printf("%s <- %s\n", key.UTF8String, [dict[key] description].UTF8String);
#endif
	[undoManager registerUndoWithTarget:self handler:
		^(ParamPanel *target) { [target copyParamsFromDict:pDiff]; }];
	[self adjustAllControlls];
}
- (IBAction)paste:(id)sender {
	NSString *str = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
	if (str == nil) return;
	NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
	NSError *err;
	NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
	if (dict != nil) [self copyParamsFromDict:dict];
	else error_msg(err, self.window, NO);
}
- (void)fValueChanged:(NSControl *)sender {
	RuntimeParams *p = targetParams;
	NSControl *d = fDigits[sender.tag], *s = fSliders[sender.tag];
	CGFloat orgValue = (&p->PARAM_F1)[sender.tag];
	CGFloat newValue = sender.doubleValue;
	if (orgValue == newValue) return;
	NSTabView *tabV = tabView;
	[undoManager registerUndoWithTarget:sender handler:^(NSControl *target) {
		reveal_me_in_tabview(target, tabV);
		target.doubleValue = orgValue;
		[target sendAction:target.action to:target.target]; }];
	if (sender != d) d.doubleValue = newValue;
	if (sender != s) s.doubleValue = newValue;
	(&p->PARAM_F1)[sender.tag] = newValue;
	[doc updateChangeCount:undoManager.isUndoing? NSChangeUndone :
		undoManager.isRedoing? NSChangeRedone : NSChangeDone];
	[self checkUpdate];
}
- (void)iValueChanged:(NSControl *)sender {
	WorldParams *p = world.tmpWorldParamsP;
	NSControl *d = iDigits[sender.tag], *s = iSteppers[sender.tag];
	NSInteger orgValue = (&p->PARAM_I1)[sender.tag];
	NSInteger newValue = sender.integerValue;
	if (orgValue == newValue) return;
	NSTabView *tabV = tabView;
	[undoManager registerUndoWithTarget:sender handler:^(NSControl *target) {
		reveal_me_in_tabview(target, tabV);
		target.integerValue = orgValue;
		[target sendAction:target.action to:target.target]; }];
	if (sender != d) d.integerValue = newValue;
	if (sender != s) s.integerValue = newValue;
	(&p->PARAM_I1)[sender.tag] = newValue;
	[doc updateChangeCount:undoManager.isUndoing? NSChangeUndone :
		undoManager.isRedoing? NSChangeRedone : NSChangeDone];
	[self checkUpdate];
}
- (void)rValueChanged:(NSControl *)sender {
	WorldParams *p = world.tmpWorldParamsP;
	NSControl *d = rDigits[sender.tag], *s = rSliders[sender.tag];
	CGFloat orgValue = (&p->PARAM_R1)[sender.tag];
	CGFloat newValue = sender.doubleValue;
	if (orgValue == newValue) return;
	NSTabView *tabV = tabView;
	[undoManager registerUndoWithTarget:sender handler:^(NSControl *target) {
		reveal_me_in_tabview(target, tabV);
		target.doubleValue = orgValue;
		[target sendAction:target.action to:target.target]; }];
	if (sender != d) d.doubleValue = newValue;
	if (sender != s) s.doubleValue = newValue;
	(&p->PARAM_R1)[sender.tag] = newValue;
	[doc updateChangeCount:undoManager.isUndoing? NSChangeUndone :
		undoManager.isRedoing? NSChangeRedone : NSChangeDone];
	[self checkUpdate];
}
- (void)setPopDistImage:(NSImage *)image {
	NSImage *orgImage = world.popDistImage;
	[undoManager registerUndoWithTarget:self handler:^(ParamPanel *pp) {
		[pp setPopDistImage:orgImage];
	}];
	world.popDistImage = image;
}
- (IBAction)setupPopDistMap:(id)sender {
	if (popDist == nil) {
		popDist = PopDist.new;
		popDist.image = world.popDistImage;
	}
	PopDist *ppdst = popDist;
	[self.window beginSheet:popDist.window completionHandler:^(NSModalResponse returnCode) {
		if (returnCode == NSModalResponseOK) [self setPopDistImage:ppdst.image];
	}];
}
- (IBAction)openVaxAndVariantsPanel:(id)sender {
	[doc openVaxAndVariantsPanel:sender];
}
// tabview delegate
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	orgFrame = tabView.selectedTabViewItem.view.frame;
}
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	NSInteger index = [tabView indexOfTabViewItem:tabViewItem];
	NSSize newSz = viewSize[index];
	NSRect wFrame = self.window.frame, scrRct = self.window.screen.frame;
	wFrame.size.height += newSz.height - orgFrame.size.height;
	if ((wFrame.origin.y -= newSz.height - orgFrame.size.height) < NSMinY(scrRct))
		wFrame.origin.y = NSMinY(scrRct);
	[self.window setFrame:wFrame display:YES animate:_byUser];
	initPrmRdBtn.hidden = crntPrmRdBtn.hidden = index == 0;
	_byUser = YES;
}
// TableView Data Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return 2; }
// TableView Delegate
- (NSView *)tableView:(NSTableView *)tableView
	viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSString *ID = tableColumn.identifier;
	NSTableCellView *view;
	if ([ID isEqualToString:@"title"]) {
		view = [tableView makeViewWithIdentifier:ID owner:self];
		view.textField.stringValue =
			NSLocalizedString((row == 0)? @"Age" : @"Rate", nil);
	} else {
		NSInteger col = ID.integerValue;
		if (col < 0 || col >= nAgeSpans) return nil;
		VaccinationRate *fr = &targetParams->vcnFnlRt[col];
		view = [tableView makeViewWithIdentifier:@"0" owner:self];
		if (row > 0) {
			view.textField.formatter = percentForm;
			view.textField.doubleValue = fr->rate;
			view.textField.target = self;
			view.textField.action = @selector(changeRate:);
		} else if (fr->upperAge < 150) {
			AgeSpanView *ageView = [AgeSpanView.alloc initWithFrame:view.frame
				lower:(col == 0)? 0 : fr[-1].upperAge + 1 upper:fr->upperAge
				max:fr[1].upperAge - 1];
			if (targetParams == world.initParamsP) {
				NSMenu *mn = vaxFnlRtMenu.copy;
				[mn itemAtIndex:0].tag = col;
				[mn itemAtIndex:1].tag = col;
				ageView.menu = mn;
				ageView.rightText.target = self;
				ageView.rightText.action = @selector(changeUpperAge:);
			} else ageView.rightText.editable = ageView.rightText.selectable = NO;
			return ageView;
		} else {
			view.textField.stringValue = (col == 0)? @"-" :
				[NSString stringWithFormat:@"%ld ≤", fr[-1].upperAge + 1];
			view.textField.editable = view.textField.selectable = NO;
			if (col < MAX_N_AGE_SPANS && targetParams == world.initParamsP) {
				NSMenu *mn = vaxFnlRtMenu.copy;
				[mn itemAtIndex:0].enabled = NO;
				[mn itemAtIndex:1].tag = col;
				view.textField.menu = mn;
			}
		}
	}
	return view;
}
- (void)setRateOf:(NSInteger)col value:(CGFloat)newValue {
	NSTabView *tabV = tabView;
	VaccinationRate *fr = &targetParams->vcnFnlRt[col];
	CGFloat orgValue = fr->rate;
	[undoManager registerUndoWithTarget:vcnTypePopUp handler:^(NSControl *target) {
		reveal_me_in_tabview(target, tabV);
		[self setRateOf:col value:orgValue];
	}];
	fr->rate = newValue;
	if (undoManager.isUndoing || undoManager.isRedoing)
		[vaxFnlRtTable reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:1]
			columnIndexes:[NSIndexSet indexSetWithIndex:col + 1]];
}
- (void)changeRate:(NSTextField *)control {
	NSInteger col = [vaxFnlRtTable columnForView:control.superview] - 1;
	if (col < 0 || col > MAX_N_AGE_SPANS) return;
	VaccinationRate *fr = &targetParams->vcnFnlRt[col];
	CGFloat newA = control.doubleValue;
	if (fr->rate != newA) [self setRateOf:col value:newA];
}
- (void)setUpperAgeOf:(NSInteger)col value:(NSInteger)newValue {
	NSTabView *tabV = tabView;
	VaccinationRate *fr = &targetParams->vcnFnlRt[col];
	NSInteger orgValue = fr->upperAge;
	[undoManager registerUndoWithTarget:vcnTypePopUp handler:^(NSControl *target) {
		reveal_me_in_tabview(target, tabV);
		[self setUpperAgeOf:col value:orgValue];
	}];
	fr->upperAge = newValue;
	if (undoManager.isUndoing || undoManager.isRedoing)
		[vaxFnlRtTable reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:0]
			columnIndexes:[NSIndexSet indexSetWithIndexesInRange:(NSRange){col + 1, 2}]];
}
- (void)changeUpperAge:(NSTextField *)control {
	NSInteger col = [vaxFnlRtTable columnForView:control.superview] - 1;
	if (col < 0 || col > MAX_N_AGE_SPANS) return;
	VaccinationRate *fr = &targetParams->vcnFnlRt[col];
	NSInteger newA = control.integerValue;
	if (newA <= fr[-1].upperAge || newA >= fr[1].upperAge) return;
	if (fr->upperAge != newA) [self setUpperAgeOf:col value:newA];
}
typedef struct { NSInteger upperAge; CGFloat rate[2]; } VaxAgeSpanInfo;
- (void)unifyTwoColumns:(NSInteger)col {
	NSTabView *tabV = tabView;
	VaccinationRate *fr = targetParams->vcnFnlRt;
	VaxAgeSpanInfo org = { fr[col].upperAge, fr[col].rate, fr[col + 1].rate };
	[undoManager registerUndoWithTarget:vcnTypePopUp handler:^(NSControl *target) {
		reveal_me_in_tabview(target, tabV);
		[self splitColumnIntoTwo:col value:org];
	}];
	fr[col].rate = (fr[col].rate + fr[col + 1].rate) / 2.;
	fr[col].upperAge = fr[col + 1].upperAge;
	for (NSInteger i = col + 1; i < nAgeSpans; i ++) fr[i] = fr[i + 1];
	fr[-- nAgeSpans] = (VaccinationRate){ -1, 0. };
	[vaxFnlRtTable reloadDataForRowIndexes:
		[NSIndexSet indexSetWithIndexesInRange:(NSRange){0, 2}] columnIndexes:
		[NSIndexSet indexSetWithIndexesInRange:(NSRange){col + 1, nAgeSpans - col + 1}]];
}
- (void)splitColumnIntoTwo:(NSInteger)col value:(VaxAgeSpanInfo)info {
	NSTabView *tabV = tabView;
	[undoManager registerUndoWithTarget:vcnTypePopUp handler:^(NSControl *target) {
		reveal_me_in_tabview(target, tabV);
		[self unifyTwoColumns:col];
	}];
	VaccinationRate *fr = targetParams->vcnFnlRt;
	for (NSInteger i = (nAgeSpans < MAX_N_AGE_SPANS)? nAgeSpans : MAX_N_AGE_SPANS - 1;
		i > col; i --) fr[i] = fr[i - 1];
	fr[col].upperAge = info.upperAge;
	fr[col].rate = info.rate[0];
	fr[col + 1].rate = info.rate[1];
	if (nAgeSpans < MAX_N_AGE_SPANS) nAgeSpans ++;
	[vaxFnlRtTable reloadDataForRowIndexes:
		[NSIndexSet indexSetWithIndexesInRange:(NSRange){0, 2}] columnIndexes:
		[NSIndexSet indexSetWithIndexesInRange:(NSRange){col + 1, nAgeSpans - col}]];
}
- (IBAction)unifyColumn:(NSMenuItem *)sender {
	NSInteger col = sender.tag;
	if (col >= 0 && col < nAgeSpans) [self unifyTwoColumns:col];
}
- (IBAction)splitColumn:(NSMenuItem *)sender {
	NSInteger col = sender.tag;
	VaccinationRate *fr = targetParams->vcnFnlRt;
	if (col >= 0 && col < nAgeSpans) [self splitColumnIntoTwo:col value:(VaxAgeSpanInfo){
		(((col == 0)? 0 : fr[col - 1].upperAge) +
		 ((fr[col].upperAge >= 150)? 105 : fr[col].upperAge)) / 2,
		fr[col].rate, fr[col].rate}];
}
@end
