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

@interface DistDigits : NSObject {
	DistInfo *distInfo;
	NSTextField __weak *minDgt, *maxDgt, *modDgt;
}
@end
@implementation DistDigits
static NSNumberFormatter *distDgtFmt = nil;
- (instancetype)initWithDigits:(NSArray<NSTextField *> *)digits
	index:(NSInteger)index var:(DistInfo *)var {
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
	minDgt.tag = maxDgt.tag = modDgt.tag = index;
	minDgt.target = maxDgt.target = modDgt.target = self;
	minDgt.action = maxDgt.action = modDgt.action = @selector(dValueChanged:);
	minDgt.formatter = maxDgt.formatter = modDgt.formatter = distDgtFmt;
	distInfo = var;
	return self;
}
- (void)adjustDigitsToCurrentValue {
	minDgt.doubleValue = distInfo->min;
	maxDgt.doubleValue = distInfo->max;
	modDgt.doubleValue = distInfo->mode;
}
- (NSUndoManager *)undoManager {
	NSWindow *window = minDgt.window;
	return [(ParamPanel *)window.delegate windowWillReturnUndoManager:window];
}
- (void)changeDistInfo:(DistInfo)newInfo {
	DistInfo orgInfo = *distInfo;
	*distInfo = newInfo;
	[self adjustDigitsToCurrentValue];
	[self.undoManager registerUndoWithTarget:self handler:^(DistDigits *dd) {
		[dd changeDistInfo:orgInfo];
	}];
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

@interface ParamPanel () {
	Document *doc;
	NSArray<NSTextField *> *fDigits, *iDigits;
	NSArray<DistDigits *> *dDigits;
	NSArray<NSSlider *> *fSliders;
	NSArray<NSStepper *> *iSteppers;
	NSUndoManager *undoManager;
	BOOL hasUserDefaults;
}
@end

@implementation ParamPanel
- (instancetype)initWithDoc:(Document *)dc {
	if (!(self = [super initWithWindowNibName:@"ParamPanel"])) return nil;
	doc = dc;
	undoManager = NSUndoManager.new;
	return self;
}
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return undoManager;
}
- (void)adjustControls {
	RuntimeParams *rp = doc.runtimeParamsP;
	WorldParams *wp = doc.tmpWorldParamsP;
	for (NSInteger i = 0; i < fDigits.count; i ++)
		fDigits[i].doubleValue = fSliders[i].doubleValue = (&rp->PARAM_F1)[i];
	for (DistDigits *d in dDigits) [d adjustDigitsToCurrentValue];
	for (NSInteger i = 0; i < iDigits.count; i ++)
		iDigits[i].integerValue = iSteppers[i].integerValue = (&wp->PARAM_I1)[i];
	stepsPerDayStp.integerValue = round(log2(wp->stepsPerDay));
	stepsPerDayDgt.integerValue = wp->stepsPerDay;
}
- (void)checkUpdate {
	revertUDBtn.enabled = hasUserDefaults &&
		(memcmp(doc.runtimeParamsP, &userDefaultRuntimeParams, sizeof(RuntimeParams)) ||
		memcmp(doc.tmpWorldParamsP, &userDefaultWorldParams, sizeof(WorldParams)));
	revertFDBtn.enabled =
		memcmp(doc.runtimeParamsP, &defaultRuntimeParams, sizeof(RuntimeParams)) ||
		memcmp(doc.tmpWorldParamsP, &defaultWorldParams, sizeof(WorldParams));
	saveAsUDBtn.enabled =
		memcmp(doc.runtimeParamsP, &userDefaultRuntimeParams, sizeof(RuntimeParams)) ||
		memcmp(doc.tmpWorldParamsP, &userDefaultWorldParams, sizeof(WorldParams));
	makeInitBtn.enabled = memcmp(doc.runtimeParamsP, doc.initParamsP, sizeof(RuntimeParams));
}
#define DDGT(d1,d2,d3,i) [DistDigits.alloc initWithDigits:@[d1,d2,d3]\
 index:i var:&doc.runtimeParamsP->PARAM_D1 + i]
- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.alphaValue = panelsAlpha;
    fDigits = @[infecDgt, infecDstDgt,
		qnsRtDgt, qnsDlDgt, qdsRtDgt, qdsDlDgt, dstSTDgt, dstOBDgt, mobFrDgt];
	fSliders = @[infecSld, infecDstSld,
		qnsRtSld, qnsDlSld, qdsRtSld, qdsDlSld, dstSTSld, dstOBSld, mobFrSld];
	dDigits = @[
		DDGT(mobDistMinDgt, mobDistMaxDgt, mobDistModeDgt, 0),
		DDGT(incubMinDgt, incubMaxDgt, incubModeDgt, 1),
		DDGT(fatalMinDgt, fatalMaxDgt, fatalModeDgt, 2),
		DDGT(recovMinDgt, recovMaxDgt, recovModeDgt, 3),
		DDGT(immunMinDgt, immunMaxDgt, immunModeDgt, 4) ];
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
	WorldParams *wp = doc.worldParamsP;
	NSInteger orgExp = round(log2(wp->stepsPerDay));
	[undoManager registerUndoWithTarget:stepsPerDayStp handler:^(NSStepper *target) {
		target.integerValue = orgExp;
		[target sendAction:target.action to:target.target];
	}];
	wp->stepsPerDay = round(pow(2., stepsPerDayStp.integerValue));
	stepsPerDayDgt.integerValue = wp->stepsPerDay;
	[self checkUpdate];
}
- (void)setParamsOfRuntime:(const RuntimeParams *)rp world:(const WorldParams *)wp {
	RuntimeParams rtPr = *(doc.runtimeParamsP);
	WorldParams wlPr = *(doc.tmpWorldParamsP);
	[undoManager registerUndoWithTarget:self handler:^(ParamPanel *panel) {
		[panel setParamsOfRuntime:&rtPr world:&wlPr];
	}];
	*(doc.runtimeParamsP) = *rp;
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
	RuntimeParams *rp = doc.runtimeParamsP;
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
- (IBAction)makeItInitialParameters:(id)sender {
	doc.initialParameters = [NSData dataWithBytes:doc.runtimeParamsP length:sizeof(RuntimeParams)];
}
- (IBAction)saveDocument:(id)sender {
	save_property_data(@"sEpP", self.window, param_dict(doc.runtimeParamsP, doc.tmpWorldParamsP));
}
- (IBAction)loadDocument:(id)sender {
	NSWindow *window = self.window;
	load_property_data(@[@"sEpi", @"sEpP"], self.window, NSDictionary.class,
		^(NSURL *url, NSObject *obj) {
		NSDictionary *dict = (NSDictionary *)obj;
		if ([url.pathExtension isEqualToString:@"sEpi"]) dict = dict[keyParameters];
		if (dict == nil) error_msg([NSString stringWithFormat:
			@"%@ doesn't include parameters.", url.path], window, NO);
		else {
			RuntimeParams tmpRP;
			WorldParams tmpWP;
			set_params_from_dict(&tmpRP, &tmpWP, dict);
			[self setParamsOfRuntime:&tmpRP world:&tmpWP];
		}
	});
}
#define VALUE_CHANGED(t,v,m,ds,ss) NSControl *d = ds[sender.tag], *s = ss[sender.tag];\
t orgValue = (&p->m)[sender.tag];\
t newValue = sender.v;\
if (orgValue == newValue) return;\
[undoManager registerUndoWithTarget:sender handler:^(NSControl *target) {\
	target.v = orgValue;\
	[target sendAction:target.action to:target.target]; }];\
if (sender != d) d.v = newValue;\
if (sender != s) s.v = newValue;\
(&p->m)[sender.tag] = newValue;\
[doc updateChangeCount:undoManager.isUndoing? NSChangeUndone :\
	undoManager.isRedoing? NSChangeRedone : NSChangeDone];\
[self checkUpdate];
- (void)fValueChanged:(NSControl *)sender {
	RuntimeParams *p = doc.runtimeParamsP;
	VALUE_CHANGED(CGFloat, doubleValue, PARAM_F1, fDigits, fSliders)
}
- (void)iValueChanged:(NSControl *)sender {
	WorldParams *p = doc.tmpWorldParamsP;
	VALUE_CHANGED(NSInteger, integerValue, PARAM_I1, iDigits, iSteppers)
}
@end
