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
@interface DistDigits : NSObject {
	DistInfo *distInfo;
	NSTextField __weak *minDgt, *maxDgt, *modDgt;
}
@property (readonly,weak) NSTabView *tabView;
@end
@implementation DistDigits
static NSNumberFormatter *distDgtFmt = nil;
- (instancetype)initWithDigits:(NSArray<NSTextField *> *)digits tabView:(NSTabView *)tabV {
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
	return self;
}
- (void)setIndex:(NSInteger)index {
	minDgt.tag = maxDgt.tag = modDgt.tag = index;
}
- (void)setDistInfo:(DistInfo *)dInfo { distInfo = dInfo; }
- (void)adjustDigitsToCurrentValue {
	minDgt.doubleValue = distInfo->min;
	maxDgt.doubleValue = distInfo->max;
	modDgt.doubleValue = distInfo->mode;
}
- (NSUndoManager *)undoManager {
	NSWindow *window = minDgt.window;
	return [(ParamPanel *)window.delegate windowWillReturnUndoManager:window];
}
- (NSTextField *)minDgt { return minDgt; }
- (void)changeDistInfo:(DistInfo)newInfo {
	DistInfo orgInfo = *distInfo;
	*distInfo = newInfo;
	[self adjustDigitsToCurrentValue];
	[self.undoManager registerUndoWithTarget:self handler:^(DistDigits *dd) {
		reveal_me_in_tabview(dd.minDgt, dd.tabView);
		[dd changeDistInfo:orgInfo];
	}];
	[(ParamPanel *)minDgt.window.delegate checkUpdate];
}
- (void)dValueChanged:(NSTextField *)sender {
	CGFloat newValue = sender.doubleValue;
	DistInfo newInfo = *distInfo;
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
	NSArray<NSTextField *> *fDigits, *iDigits;
	NSArray<DistDigits *> *dDigits;
	NSArray<NSSlider *> *fSliders;
	NSArray<NSStepper *> *iSteppers;
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
	stepsPerDayStp.integerValue = round(log2(wp->stepsPerDay));
	stepsPerDayDgt.integerValue = wp->stepsPerDay;
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
#define DDGT(d1,d2,d3) [DistDigits.alloc initWithDigits:@[d1,d2,d3] tabView:tabView]
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
		contagDDgt, contagPDgt, infecDgt, infecDstDgt,
		dstSTDgt, dstOBDgt, mobFrDgt, gatFrDgt, cntctTrcDgt,
		tstDelayDgt, tstProcDgt, tstIntvlDgt, tstSensDgt, tstSpecDgt,
		tstSbjAsyDgt, tstSbjSymDgt];
	fSliders = @[massSld, fricSld, avoidSld, maxSpdSld,
		contagDSld, contagPSld, infecSld, infecDstSld,
		dstSTSld, dstOBSld, mobFrSld, gatFrSld, cntctTrcSld,
		tstDelaySld, tstProcSld, tstIntvlSld, tstSensSld, tstSpecSld,
		tstSbjAsySld, tstSbjSymSld];
	dDigits = @[
		DDGT(mobDistMinDgt, mobDistMaxDgt, mobDistModeDgt),
		DDGT(incubMinDgt, incubMaxDgt, incubModeDgt),
		DDGT(fatalMinDgt, fatalMaxDgt, fatalModeDgt),
		DDGT(recovMinDgt, recovMaxDgt, recovModeDgt),
		DDGT(immunMinDgt, immunMaxDgt, immunModeDgt),
		DDGT(gatSZMinDgt, gatSZMaxDgt, gatSZModeDgt),
		DDGT(gatDRMinDgt, gatDRMaxDgt, gatDRModeDgt),
		DDGT(gatSTMinDgt, gatSTMaxDgt, gatSTModeDgt) ];
	iDigits = @[initPopDgt, worldSizeDgt, meshDgt, nInfecDgt];
	iSteppers = @[initPopStp, worldSizeStp, meshStp, nInfecStp];
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
	hasUserDefaults =
		memcmp(&userDefaultRuntimeParams, &defaultRuntimeParams, sizeof(RuntimeParams)) ||
		memcmp(&userDefaultWorldParams, &defaultWorldParams, sizeof(WorldParams));
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
- (void)setParamsOfRuntime:(const RuntimeParams *)rp world:(const WorldParams *)wp {
	RuntimeParams rtPr = *targetParams;
	WorldParams wlPr = *(doc.tmpWorldParamsP);
	[undoManager registerUndoWithTarget:self handler:^(ParamPanel *panel) {
		[panel setParamsOfRuntime:&rtPr world:&wlPr];
	}];
	*targetParams = *rp;
	*(doc.tmpWorldParamsP) = *wp;
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
- (IBAction)copyAsJSON:(id)sender {
	copy_plist_as_JSON_text(
		param_dict(targetParams, doc.tmpWorldParamsP),
		self.window);
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
	[self.window setFrame:wFrame display:YES animate:YES];
	initPrmRdBtn.hidden = crntPrmRdBtn.hidden = index == 0;
}
@end
