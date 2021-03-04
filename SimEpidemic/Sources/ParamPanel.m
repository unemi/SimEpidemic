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

#define N_SUBPANELS 5
@interface ParamPanel () {
	Document *doc;
	RuntimeParams *targetParams;
	NSArray<NSTextField *> *fDigits, *iDigits, *rDigits;
	NSArray<DistDigits *> *dDigits;
	NSArray<NSSlider *> *fSliders, *rSliders;
	NSArray<NSStepper *> *iSteppers;
	DistDigits *dDigitW;
	NSUndoManager *undoManager;
	BOOL hasUserDefaults;
	NSSize viewSize[N_SUBPANELS];
	NSRect orgFrame;
}
@end

@implementation ParamPanel
- (instancetype)initWithDoc:(Document *)dc {
	if (!(self = [super initWithWindowNibName:@"ParamPanel"])) return nil;
	doc = dc;
	targetParams = dc.initParamsP;
	undoManager = NSUndoManager.new;
	_byUser = YES;
	return self;
}
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return undoManager;
}
- (void)adjustControls {
	WorldParams *wp = doc.tmpWorldParamsP;
	for (NSInteger i = 0; i < fDigits.count; i ++)
		fDigits[i].doubleValue = fSliders[i].doubleValue = (&targetParams->PARAM_F1)[i];
	for (DistDigits *d in dDigits) [d adjustDigitsToCurrentValue];
	for (NSInteger i = 0; i < iDigits.count; i ++)
		iDigits[i].integerValue = iSteppers[i].integerValue = (&wp->PARAM_I1)[i];
	for (NSInteger i = 0; i < rDigits.count; i ++)
		rDigits[i].doubleValue = rSliders[i].doubleValue = (&wp->PARAM_R1)[i];
	stepsPerDayStp.integerValue = round(log2(wp->stepsPerDay));
	stepsPerDayDgt.integerValue = wp->stepsPerDay;
	[dDigitW adjustDigitsToCurrentValue];
	[vcnPriPopUp selectItemAtIndex:targetParams->vcnPri];
}
- (void)adjustParamControls:(NSArray<NSString *> *)paramNames {
	if (targetParams == doc.runtimeParamsP) for (NSString *key in paramNames) {
		NSInteger idx = paramIndexFromKey[key].integerValue;
		if (idx < IDX_D) fDigits[idx].doubleValue =
			fSliders[idx].doubleValue = (&targetParams->PARAM_F1)[idx];
		else [dDigits[idx - IDX_D] adjustDigitsToCurrentValue];
	}
}
- (void)checkUpdate {
	revertUDBtn.enabled = hasUserDefaults &&
		(memcmp(targetParams, &userDefaultRuntimeParams, sizeof(RuntimeParams)) ||
		memcmp(doc.tmpWorldParamsP, &userDefaultWorldParams, sizeof(WorldParams)));
	revertFDBtn.enabled =
		memcmp(targetParams, &defaultRuntimeParams, sizeof(RuntimeParams)) ||
		memcmp(doc.tmpWorldParamsP, &defaultWorldParams, sizeof(WorldParams));
	saveAsUDBtn.enabled =
		memcmp(targetParams, &userDefaultRuntimeParams, sizeof(RuntimeParams)) ||
		memcmp(doc.tmpWorldParamsP, &userDefaultWorldParams, sizeof(WorldParams));
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
	NSRect wFrame = self.window.frame;
	CGFloat dh = viewSize[0].height - tabs[0].view.frame.size.height;
	wFrame.size.height += dh; wFrame.origin.y -= dh;
	[self.window setFrame:wFrame display:NO];
    fDigits = @[massDgt, fricDgt, avoidDgt, maxSpdDgt,
		actModeDgt, actKurtDgt, massActDgt, mobActDgt, gatActDgt,
		incubActDgt, fatalActDgt, recovActDgt, immueActDgt,
		contagDDgt, contagPDgt, infecDgt, infecDstDgt,
		dstSTDgt, dstOBDgt, gatFrDgt, cntctTrcDgt,
		tstDelayDgt, tstProcDgt, tstIntvlDgt, tstSensDgt, tstSpecDgt,
		tstSbjAsyDgt, tstSbjSymDgt,
		vcnPRateDgt, vcn1stEffDgt, vcnMaxEffDgt, vcnEDelayDgt, vcnEPeriodDgt, vcnAntiRateDgt];
	fSliders = @[massSld, fricSld, avoidSld, maxSpdSld,
		actModeSld, actKurtSld, massActSld, mobActSld, gatActSld,
		incubActSld, fatalActSld, recovActSld, immueActSld,
		contagDSld, contagPSld, infecSld, infecDstSld,
		dstSTSld, dstOBSld, gatFrSld, cntctTrcSld,
		tstDelaySld, tstProcSld, tstIntvlSld, tstSensSld, tstSpecSld,
		tstSbjAsySld, tstSbjSymSld,
		vcnPRateSld, vcn1stEffSld, vcnMaxEffSld, vcnEDelaySld, vcnEPeriodSld, vcnAntiRateSld];
	ParamPanel __weak *pp = self;
	void (^proc)(void) = ^{ [pp checkUpdate]; };
	dDigits = @[
		DDGT(mobDistMinDgt, mobDistMaxDgt, mobDistModeDgt),
		DDGT(incubMinDgt, incubMaxDgt, incubModeDgt),
		DDGT(fatalMinDgt, fatalMaxDgt, fatalModeDgt),
		DDGT(recovMinDgt, recovMaxDgt, recovModeDgt),
		DDGT(immunMinDgt, immunMaxDgt, immunModeDgt),
		DDGT(gatSZMinDgt, gatSZMaxDgt, gatSZModeDgt),
		DDGT(gatDRMinDgt, gatDRMaxDgt, gatDRModeDgt),
		DDGT(gatSTMinDgt, gatSTMaxDgt, gatSTModeDgt),
		DDGT(mobFreqMinDgt, mobFreqMaxDgt, mobFreqModeDgt),
		DDGT(gatFreqMinDgt, gatFreqMaxDgt, gatFreqModeDgt)];
	iDigits = @[initPopDgt, worldSizeDgt, meshDgt];
	iSteppers = @[initPopStp, worldSizeStp, meshStp];
	rDigits = @[initInfcDgt, initRecvDgt, initQAsymDgt, initQSympDgt];
	rSliders = @[initInfcSld, initRecvSld, initQAsymSld, initQSympSld];
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
	for (NSInteger i = 0; i < dDigits.count; i ++) {
		dDigits[i].index = i;
		dDigits[i].distInfo = &targetParams->PARAM_D1 + i;
	}
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
	clearUDBtn.enabled = hasUserDefaults =
		memcmp(&userDefaultRuntimeParams, &defaultRuntimeParams, sizeof(RuntimeParams))
	 || memcmp(&userDefaultWorldParams, &defaultWorldParams, sizeof(WorldParams));
    [self adjustControls];
	[self checkUpdate];
    [doc setPanelTitle:self.window];
}
- (IBAction)changeStepsPerDay:(id)sender {
	WorldParams *wp = doc.tmpWorldParamsP;
	NSInteger orgExp = round(log2(wp->stepsPerDay));
	NSTabView *tabV = tabView;
	[undoManager registerUndoWithTarget:stepsPerDayStp handler:^(NSStepper *target) {
		reveal_me_in_tabview(target, tabV);
		target.integerValue = orgExp;
		[target sendAction:target.action to:target.target];
	}];
	wp->stepsPerDay = round(pow(2., stepsPerDayStp.integerValue));
	stepsPerDayDgt.integerValue = wp->stepsPerDay;
	[self checkUpdate];
}
- (IBAction)chooseVaccinePriority:(id)sender {
	VaccinePriority orgValue = targetParams->vcnPri,
		newValue = (VaccinePriority)vcnPriPopUp.indexOfSelectedItem;
	if (orgValue == newValue) return;
	NSTabView *tabV = tabView;
	[undoManager registerUndoWithTarget:vcnPriPopUp handler:^(NSPopUpButton *target) {
		reveal_me_in_tabview(target, tabV);
		[target selectItemAtIndex:orgValue];
		[target sendAction:target.action to:target.target];
	}];
	[doc setVaccinePriority:newValue toInit:targetParams == doc.initParamsP];
	[self checkUpdate];
}
- (void)setParamsOfRuntime:(const RuntimeParams *)rp world:(const WorldParams *)wp {
	RuntimeParams rtPr = *targetParams;
	WorldParams wlPr = *(doc.tmpWorldParamsP);
	[undoManager registerUndoWithTarget:self handler:^(ParamPanel *panel) {
		[panel setParamsOfRuntime:&rtPr world:&wlPr];
	}];
	VaccinePriority orgVcnPri = targetParams->vcnPri;
	*targetParams = *rp;
	*(doc.tmpWorldParamsP) = *wp;
	if (rp->vcnPri != orgVcnPri) {
		targetParams->vcnPri = orgVcnPri;
		[doc setVaccinePriority:rp->vcnPri toInit:targetParams == doc.initParamsP];
	}
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
	WorldParams *wp = doc.tmpWorldParamsP;
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
	RuntimeParams *newTarget = (sender == initPrmRdBtn)? doc.initParamsP : doc.runtimeParamsP;
	if (newTarget != targetParams) {
		[undoManager registerUndoWithTarget:(sender == initPrmRdBtn)? crntPrmRdBtn : initPrmRdBtn
			handler:^(NSButton *target) {
				[target performClick:nil];
		}];
		targetParams = newTarget;
		for (NSInteger i = 0; i < dDigits.count; i ++)
			dDigits[i].distInfo = &targetParams->PARAM_D1 + i;
		[self adjustControls];
		[self checkUpdate];
	}
}
- (IBAction)saveDocument:(id)sender {
	save_property_data(@"sEpP", self.window, param_dict(targetParams, doc.tmpWorldParamsP));
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
			doc.tmpWorldParamsP, &userDefaultWorldParams) :
		param_dict(targetParams, doc.tmpWorldParamsP),
		self.window);
}
- (void)copyParamsFromDict:(NSDictionary *)dict {
	RuntimeParams *rp = targetParams, orgRp = *rp;
	WorldParams *wp = doc.tmpWorldParamsP, orgWp = *wp;
	set_params_from_dict(targetParams, wp, dict);
	NSDictionary *pDiff = param_diff_dict(&orgRp, targetParams, &orgWp, wp);
#ifdef DEBUG
	NSLog(@"copyParamsFromDict");
	for (NSString *key in pDiff.keyEnumerator)
		printf("%s <- %s\n", key.UTF8String, [dict[key] description].UTF8String);
#endif
	[undoManager registerUndoWithTarget:self handler:
		^(ParamPanel *target) { [target copyParamsFromDict:pDiff]; }];
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
	WorldParams *p = doc.tmpWorldParamsP;
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
	WorldParams *p = doc.tmpWorldParamsP;
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
// tabview delegate
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	orgFrame = tabView.selectedTabViewItem.view.frame;
}
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	NSInteger index = [tabView indexOfTabViewItem:tabViewItem];
	NSSize newSz = viewSize[index];
	NSRect wFrame = self.window.frame;
	wFrame.size.height += newSz.height - orgFrame.size.height;
	if ((wFrame.origin.y -= newSz.height - orgFrame.size.height) < 0)
		wFrame.origin.y = 0.;
	[self.window setFrame:wFrame display:YES animate:_byUser];
	initPrmRdBtn.hidden = crntPrmRdBtn.hidden = index == 0;
	_byUser = YES;
}
@end
