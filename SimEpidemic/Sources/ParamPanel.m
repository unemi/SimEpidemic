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

@interface ParamPanel () {
	Document *doc;
	NSArray<NSTextField *> *fDigits, *iDigits;
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
	Params *p = doc.paramsP;
	for (NSInteger i = 0; i < fDigits.count; i ++)
		fDigits[i].doubleValue = fSliders[i].doubleValue = (&p->infec)[i];
	for (NSInteger i = 0; i < iDigits.count; i ++)
		iDigits[i].integerValue = iSteppers[i].integerValue = (&p->initPop)[i];
	stepsPerDayStp.integerValue = round(log2(p->stepsPerDay));
	stepsPerDayDgt.integerValue = p->stepsPerDay;
}
- (void)checkUpdate {
	revertUDBtn.enabled = hasUserDefaults &&
		(memcmp(doc.paramsP, &userDefaultParams, sizeof(Params)) != 0);
	revertFDBtn.enabled = (memcmp(doc.paramsP, &defaultParams, sizeof(Params)) != 0);
	saveAsUDBtn.enabled = (memcmp(doc.paramsP, &userDefaultParams, sizeof(Params)) != 0);
}
- (void)windowDidLoad {
    [super windowDidLoad];
    fDigits = @[infecDgt, infecDstDgt, recovMeanDgt, recovSTDDgt,
		incubPMinDgt, incubPMaxDgt, incubPBiasDgt, diseaRtDgt, imunMeanDgt, imunSTDDgt,
		qnsRtDgt, qnsDlDgt, qdsRtDgt, qdsDlDgt, dstSTDgt, dstOBDgt, mobFrDgt, mobDsDgt];
	fSliders = @[infecSld, infecDstSld, recovMeanSld, recovSTDSld,
		incubPMinSld, incubPMaxSld, incubPBiasSld, diseaRtSld, imunMeanSld, imunSTDSld,
		qnsRtSld, qnsDlSld, qdsRtSld, qdsDlSld, dstSTSld, dstOBSld, mobFrSld, mobDsSld];
	iDigits = @[initPopDgt, worldSizeDgt, meshDgt, nInfecDgt];
	iSteppers = @[initPopStp, worldSizeStp, meshStp, nInfecStp];
    for (NSInteger idx = 0; idx < fDigits.count; idx ++) {
		NSControl *d = fDigits[idx], *s = fSliders[idx];
		d.tag = s.tag = idx;
		d.action = s.action = @selector(fValueChanged:);
		d.target = s.target = self;
		NSNumberFormatter *fmt = paramFormatters[idx];
		d.formatter = fmt;
		((NSSlider *)s).minValue = fmt.minimum.doubleValue;
		((NSSlider *)s).maxValue = fmt.maximum.doubleValue;
	}
    for (NSInteger idx = 0; idx < iDigits.count; idx ++) {
		NSControl *d = iDigits[idx], *s = iSteppers[idx];
		d.tag = s.tag = idx;
		d.action = s.action = @selector(iValueChanged:);
		d.target = s.target = self;
	}
	hasUserDefaults = (memcpy(&userDefaultParams, &defaultParams, sizeof(Params)) != 0);
    [self adjustControls];
	[self checkUpdate];
    [doc setPanelTitle:self.window];
}
- (IBAction)changeStepsPerDay:(id)sender {
	Params *p = doc.paramsP;
	NSInteger orgExp = round(log2(p->stepsPerDay));
	[undoManager registerUndoWithTarget:stepsPerDayStp handler:^(NSStepper *target) {
		target.integerValue = orgExp;
		[target sendAction:target.action to:target.target];
	}];
	p->stepsPerDay = round(pow(2., stepsPerDayStp.integerValue));
	stepsPerDayDgt.integerValue = p->stepsPerDay;
	[self checkUpdate];
}
- (void)setParamsWithPointer:(Params *)paramsP {
	NSData *orgData = [NSData dataWithBytes:doc.paramsP length:sizeof(Params)];
	[undoManager registerUndoWithTarget:self handler:^(ParamPanel *panel) {
		[panel setParamsWithPointer:(Params *)orgData.bytes];
	}];
	memcpy(doc.paramsP, paramsP, sizeof(Params));
	[self adjustControls];
	[self checkUpdate];
}
- (IBAction)reset:(id)sender {
	[self setParamsWithPointer:&userDefaultParams];
}
- (IBAction)resetToFactoryDefaults:(id)sender {
	[self setParamsWithPointer:&defaultParams];
}
- (IBAction)saveAsUserDefaults:(id)sender {
	Params *p = doc.paramsP;
	confirm_operation(@"Will overwrites the current user's defaults.", self.window, ^{
		NSDictionary<NSString *, NSNumber *> *dict = param_dict(p);
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
	doc.initialParameters = [NSData dataWithBytes:doc.paramsP length:sizeof(Params)];
}
- (IBAction)saveDocument:(id)sender {
	save_property_data(@"sEpP", self.window, param_dict(doc.paramsP));
}
- (IBAction)loadDocument:(id)sender {
	Params *p = doc.paramsP;
	load_property_data(@"sEpP", self.window, NSDictionary.class, ^(NSObject *dict) {
		set_params_from_dict(p, (NSDictionary *)dict); });
}
#define VALUE_CHANGED(t,v,m,ds,ss) NSControl *d = ds[sender.tag], *s = ss[sender.tag];\
Params *p = doc.paramsP;\
t orgValue = (&p->m)[sender.tag];\
t newValue = sender.v;\
if (orgValue == newValue) return;\
[undoManager registerUndoWithTarget:sender handler:^(NSControl *target) {\
	target.v = orgValue;\
	[target sendAction:target.action to:target.target]; }];\
if (sender != d) d.v = newValue;\
if (sender != s) s.v = newValue;\
(&p->m)[sender.tag] = newValue;
- (void)fValueChanged:(NSControl *)sender {
	VALUE_CHANGED(CGFloat, doubleValue, infec, fDigits, fSliders)
	[self checkUpdate];
}
- (void)iValueChanged:(NSControl *)sender {
	VALUE_CHANGED(NSInteger, integerValue, initPop, iDigits, iSteppers)
	[self checkUpdate];
}
@end
