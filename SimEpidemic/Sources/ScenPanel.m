//
//  Scenario.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/17.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "ScenPanel.h"
#import "AppDelegate.h"
#import "Document.h"
#import "Scenario.h"
#import "StatPanel.h"
#import "ParamPanel.h"
#import "VVPanel.h"
#import "GatPanel.h"

@implementation StatInfo (PredicateExtension)
- (NSInteger)days { return days; }
- (NSInteger)susceptible { return self.statistics->cnt[Susceptible]; }
- (NSInteger)infected {
	NSUInteger *cntp = self.statistics->cnt;
	return cntp[Asymptomatic] + cntp[Symptomatic];
}
- (NSInteger)symptomatic { return self.statistics->cnt[Symptomatic]; }
- (NSInteger)recovered { return self.statistics->cnt[Recovered]; }
- (NSInteger)died { return self.statistics->cnt[Died]; }
- (NSInteger)quarantine {
	NSUInteger *cntp = self.statistics->cnt;
	return cntp[QuarantineAsym] + cntp[QuarantineSymp];
}
- (NSInteger)dailyInfection { return self.transit->cnt[Asymptomatic]; }
- (NSInteger)dailySymptomatic { return self.transit->cnt[Symptomatic]; }
- (NSInteger)dailyRecovery { return self.transit->cnt[Recovered]; }
- (NSInteger)dailyDeath { return self.transit->cnt[Died]; }
- (NSInteger)weeklyPositive { return self.testResultCnt.positive; }
- (CGFloat)weeklyPositiveRate {
	TestResultCount tr = self.testResultCnt;
	return (CGFloat)tr.positive / (tr.positive + tr.negative);
}
@end

@implementation NSTextField (UndoExtension)
- (void)changeDoubleUndoable:(CGFloat)newValue undoManager:(NSUndoManager *)undoManager {
	CGFloat orgValue = self.doubleValue;
	if (orgValue == newValue) return;
	[undoManager registerUndoWithTarget:self handler:^(NSTextField *target) {
		[target changeDoubleUndoable:orgValue undoManager:undoManager];
	}];
	self.doubleValue = newValue;
}
@end

static void set_subview(NSControl *cnt, NSView *parent, BOOL leftToRight) {
	if (![cnt isKindOfClass:NSTextField.class]) {
//		cnt.controlSize = [cnt isKindOfClass:NSButton.class]?
//			NSControlSizeSmall : NSControlSizeMini;
		cnt.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
		if ([cnt isKindOfClass:NSPopUpButton.class])
			((NSButton *)cnt).bezelStyle = NSBezelStyleRoundRect;
		if (!leftToRight && [cnt isMemberOfClass:NSButton.class])
			((NSButton *)cnt).bezelStyle = NSBezelStyleInline;
	}
	[cnt sizeToFit];
	if ([cnt isKindOfClass:NSPopUpButton.class]) {
		NSSize size = cnt.frame.size;
		size.width -= 28;
		[cnt setFrameSize:size];
	}
	if (leftToRight) {
		CGFloat rMax = 0.;
		for (NSView *view in parent.subviews) {
			CGFloat right = NSMaxX(view.frame);
			if (rMax < right) rMax = right;
		}
		[cnt setFrameOrigin:(NSPoint){rMax + 6,
			(parent.frame.size.height - cnt.frame.size.height) / 2.}];
	} else {
		CGFloat lMin = NSMaxX(parent.frame);
		for (NSView *view in parent.subviews) {
			CGFloat left = NSMinX(view.frame);
			if (lMin > left) lMin = left;
		}
		[cnt setFrameOrigin:(NSPoint){lMin - cnt.frame.size.width - 6,
			(parent.frame.size.height - cnt.frame.size.height) / 2.}];
	}
	[parent addSubview:cnt];
}
static NSTextField *label(void) {
	NSTextField *msg = NSTextField.new;
	msg.selectable = msg.editable = msg.drawsBackground = msg.bordered = NO;
	return msg;
}
static NSTextField *label_field(NSString *message) {
	NSTextField *msg = label();
	msg.stringValue = NSLocalizedString(message, nil);
	[msg sizeToFit];
	return msg;
}
static void setup_popup_menu(NSPopUpButton *popup, NSInteger n, NSString *(^block)(NSInteger)) {
 	NSInteger nItems = popup.numberOfItems, idx = 0;
	for (; idx < nItems && idx < n; idx ++) [popup itemAtIndex:idx].title = block(idx);
	for (; idx < nItems; idx ++) [popup removeItemAtIndex:popup.numberOfItems - 1];
	for (; idx < n; idx ++) [popup addItemWithTitle:block(idx)];
}
#define BUTTON_CELL_SIZE {128, 24}
#define LINEN_CELL_SIZE {30, 24}
#define CELL_SIZE {504, 24}
@interface ButtonsCellView : NSTableCellView
@property (readonly) NSArray<NSButton *> *buttons;
@end
@implementation ButtonsCellView
- (instancetype)initWithItem:(ScenarioItem *)pItem titles:(NSArray *)titles {
	NSSize fSize = BUTTON_CELL_SIZE;
	if (!(self = [super initWithFrame:(NSRect){0, 0, fSize}])) return nil;
	NSInteger n = titles.count;
	NSButton *btns[n];
	for (NSInteger i = 0; i < n; i ++) {
		NSButton *btn = btns[i] = NSButton.new;
		if ([titles[i] isKindOfClass:NSString.class]) btn.title = (NSString *)titles[i];
		else if ([titles[i] isKindOfClass:NSImage.class]) btn.image = (NSImage *)titles[i];
		set_subview(btn, self, NO);
		btn.target = pItem;
		btn.action = @selector(buttonAction:);
	}
	_buttons = [NSArray arrayWithObjects:btns count:n];
	return self;
}
@end

enum { CatMovement, CatInfection, CatMeasures, CatRegGat, CatTests, CatVax };
static NSArray<NSString *> *make_menu_info(NSString * const *info) {
	NSInteger cnt = 0;
	while (info[cnt] != nil) cnt ++;
	return [NSArray arrayWithObjects:info count:cnt];
}
static NSInteger regGatItemIdx = -1;
static NSArray<NSString *> *cat_name_info(void) {
	static NSString *info[] = { @"movement", @"infection", @"measures",
		@"regularGatherings", @"tests", @"vaccination", nil };
	static NSArray<NSString *> *array = nil;
	if (array == nil) {
		array = make_menu_info(info);
		for (NSInteger i = 0; info[i] != nil; i ++)
			if ([info[i] isEqualToString:@"regularGatherings"])
				{ regGatItemIdx = i; break; }
	}
	return array;
}
static NSArray<NSArray<NSString *> *> *param_name_info(void) {
	static NSString *mvInfo[] = { @"mass", @"friction", @"avoidance", @"maxSpeed", nil },
	*ptInfo[] = { @"infectionProberbility", @"infectionDistance", nil },
	*msInfo[] = { @"distancingStrength", @"distancingObedience",
		@"mobilityFrequency", @"mobilityDistance",
		@"gatheringFrequency", @"gatheringSize", @"gatheringDuration", @"gatheringStrength",
		@"contactTracing", nil },
	*rgInfo[] = { @"regGatNPP", @"regGatFrequency", @"regGatDuration",
		@"regGatSize", @"regGatStrength", nil },
	*tsInfo[] = { @"testDelay", @"testProcess", @"testInterval",
		@"testSensitivity", @"testSpecificity",
		@"subjectAsymptomatic", @"subjectSymptomatic", nil },
	*vxInfo[] = { @"vaccinePerformRate", @"vaccinePriority", @"vaccineRegularity",
		@"vaccineFinalRate", nil };
	static NSString * const *prmNames[] = { mvInfo, ptInfo, msInfo, rgInfo, tsInfo, vxInfo, nil };
	static NSArray<NSArray<NSString *> *> *arrays = nil;
	if (arrays == nil) {
		NSInteger nCats = 0; while (prmNames[nCats] != nil) nCats ++;
		NSArray<NSString *> *arrs[nCats];
		for (NSInteger i = 0; i < nCats; i ++) {
			NSInteger nItems = 0;
			for (NSString * const *p = prmNames[i]; *p != nil; p ++) nItems ++;
			arrs[i] = [NSArray arrayWithObjects:prmNames[i] count:nItems];
		}
		arrays = [NSArray arrayWithObjects:arrs count:nCats];
	}
	return arrays;
}
static NSArray<NSString *> *reg_gat_keys(void) {
	static NSArray<NSString *> *array = nil;
	if (array == nil) array = @[@"npp", @"freq", @"duration", @"size", @"strength"];
	return array;
}
static NSArray<NSString *> *vcnPr_menu_info(void) {
	static NSString *info[] = { @"Random", @"Elder", @"Center", @"Density", nil };
	static NSArray<NSString *> *array = nil;
	if (array == nil) array = make_menu_info(info);
	return array;
}
static void make_popUpMenu(NSPopUpButton *popUp, NSArray<NSString *> *titles) {
	for (NSString *title in titles) {
		if (title.length == 0) [popUp.menu addItem:NSMenuItem.separatorItem];
		else [popUp addItemWithTitle:NSLocalizedString(title, nil)];
	}
}
typedef enum {
	SPTypeScalar, SPTypeDistribution, SPTypeVaxScalar, SPTypeVaxPriority,
	SPTypeVaxFnlRt, SPTypeRegGathering
} ScenParameterType;
typedef struct { unsigned char cat, name; } ParamMenuIndex;

@interface ParamItem : ScenarioItem <NSMenuItemValidation> {
	NSMenuItem *regGatItem;
}
@property ParamMenuIndex index;
@property DistInfo distInfo;
@property NSInteger vcnType, priority, ageSpanIdx, gatIndex;
- (void)chooseVcnType:(NSPopUpButton *)sender;
- (void)choosePriority:(NSPopUpButton *)sender;
- (void)chooseAgeSpan:(NSPopUpButton *)sender;
- (void)chooseGat:(NSPopUpButton *)sender;
@end

@interface GatNamePopUpButton : NSPopUpButton {
	id ntfObserver;
}
@property (weak) World *world;
@end

@interface ParameterCellView : NSTableCellView {
	World * __weak world;
	ParamItem * __weak item;
	NSTextField *label, *transLabel, *daysUnitLabel;
}
@property (readonly) NSPopUpButton *categoryPopUp, *namePopUp,
	*vcnTypePopUp, *vcnPriorityPopUp, *vcnAgeSpanPopUp;
@property (readonly) GatNamePopUpButton *gatNamePopUp;
@property (readonly) NSButton *distBtn;
@property (readonly) NSTextField *digits, *days;
- (void)adjustGatNamePopUp;
@end
@implementation GatNamePopUpButton
- (void)viewDidMoveToWindow {
	if (self.window != nil) {
		ParameterCellView *view = (ParameterCellView *)self.superview;
		ntfObserver = [NSNotificationCenter.defaultCenter addObserverForName:nnRegGatChanged
			object:_world queue:nil usingBlock:^(NSNotification * _Nonnull note) {
			[view adjustGatNamePopUp];
		}];
	} else if (ntfObserver != nil) {
		[NSNotificationCenter.defaultCenter removeObserver:ntfObserver];
		ntfObserver = nil;
	}
}
@end

@implementation ParameterCellView
- (instancetype)initWithWorld:(World *)wd item:(ParamItem *)itm {
	NSSize fSize = CELL_SIZE;
	if (!(self = [super initWithFrame:(NSRect){0, 0, fSize}])) return nil;
	world = wd;
	item = itm;
	set_subview((label = label_field(@"Parameters")), self, YES);
	_categoryPopUp = NSPopUpButton.new;
	make_popUpMenu(_categoryPopUp, cat_name_info());
	set_subview(_categoryPopUp, self, YES);
	_namePopUp = NSPopUpButton.new;
	make_popUpMenu(_namePopUp, param_name_info()[0]);
	set_subview(_namePopUp, self, YES);
	set_subview(label_field(@"⇐"), self, YES);
	_digits = NSTextField.new;
	_digits.doubleValue = 999.9;
	set_subview(_digits, self, YES);
	set_subview((transLabel = label_field(NSLocalizedString(@"ParamTransitionPre", nil))), self, YES);
	_days = NSTextField.new;
	_days.doubleValue = 99.9;
	set_subview(_days, self, YES);
	set_subview((daysUnitLabel = label_field(NSLocalizedString(@"days", nil))), self, YES);
	_distBtn = [NSButton.alloc initWithFrame:_digits.frame];
	_distBtn.title = NSLocalizedString(@"Value...", nil);
	_distBtn.controlSize = NSControlSizeMini;
	_distBtn.bezelStyle = NSBezelStyleRounded;
	[_namePopUp selectItemAtIndex:0];
	return self;
}
- (void)showControl:(NSControl *)ctrl among:(NSArray<NSControl *> *)ctrls{
	if (ctrl.superview != nil) return;
	for (NSControl *c in ctrls)
		if (c != ctrl && c.superview != nil) [c removeFromSuperview];
	[self addSubview:ctrl];
}
- (void)showArgControl:(NSControl *)ctrl {
	NSMutableArray *ma = [NSMutableArray arrayWithArray:@[_digits, _distBtn]];
	if (_vcnPriorityPopUp != nil) [ma addObject:_vcnPriorityPopUp];
	[self showControl:ctrl among:ma];
}
- (void)showLabelControl:(NSControl *)ctrl {
	NSMutableArray *ma = [NSMutableArray arrayWithObject:label];
	if (_vcnTypePopUp != nil) [ma addObject:_vcnTypePopUp];
	if (_vcnAgeSpanPopUp != nil) [ma addObject:_vcnAgeSpanPopUp];
	if (_gatNamePopUp != nil) [ma addObject:_gatNamePopUp];
	[self showControl:ctrl among:ma];
}
static NSPopUpButton *setup_mini_popup(
	NSRect xFrame, NSRect yFrame, NSPopUpButton *(^creator)(NSRect)) {
	NSPopUpButton *popup = creator(
		(NSRect){xFrame.origin.x, yFrame.origin.y, xFrame.size.width, yFrame.size.height});
	popup.bezelStyle = NSBezelStyleRoundRect;
	popup.controlSize = NSControlSizeSmall;
	popup.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
	return popup;
}
static NSPopUpButton *make_mini_popup(NSRect xFrame, NSRect yFrame) {
	return setup_mini_popup(xFrame, yFrame, ^(NSRect frame){
		return [NSPopUpButton.alloc initWithFrame:frame]; });
}
static GatNamePopUpButton *make_gat_name_popup(NSRect xFrame, NSRect yFrame) {
	return (GatNamePopUpButton *)setup_mini_popup(xFrame, yFrame, ^(NSRect frame){
		return [GatNamePopUpButton.alloc initWithFrame:frame]; });
}
- (void)adjustGatNamePopUp {
	MutableDictArray gatList = world.gatheringsList;
	if (gatList == nil || gatList.count == 0)
		{ [_gatNamePopUp removeAllItems]; return; }
	setup_popup_menu(_gatNamePopUp, gatList.count, ^(NSInteger i) {
		NSString *name = gatList[i][@"name"];
		return [name hasPrefix:@"__"]? [NSString stringWithFormat:@"No.%ld", i + 1] : name; } );
}
- (void)adjustView:(ScenParameterType)pType {
	switch (pType) {
		case SPTypeScalar: case SPTypeDistribution:
		[self showLabelControl:label];
		break;
		case SPTypeVaxScalar: case SPTypeVaxPriority:
		if (_vcnTypePopUp == nil) {
			_vcnTypePopUp = make_mini_popup(label.frame, _namePopUp.frame);
			adjust_vcnType_popUps(@[_vcnTypePopUp], world);
			[NSNotificationCenter.defaultCenter addObserver:self
				selector:@selector(reviseVcnPopUp:) name:VaccineListChanged object:world];
			_vcnTypePopUp.target = item;
			_vcnTypePopUp.action = @selector(chooseVcnType:);
			[_vcnTypePopUp selectItemAtIndex:item.vcnType];
		}
		[self showLabelControl:_vcnTypePopUp];
		break;
		case SPTypeVaxFnlRt:
		if (_vcnAgeSpanPopUp == nil) {
			_vcnAgeSpanPopUp = make_mini_popup(label.frame, _namePopUp.frame);
			[_vcnAgeSpanPopUp addItemWithTitle:NSLocalizedString(@"Subj.", nil)];
			NSInteger low = 0;
			for (VaccineFinalRate *fr = world.initParamsP->vcnFnlRt; fr->upperAge < 150; fr ++) {
				[_vcnAgeSpanPopUp addItemWithTitle:[NSString stringWithFormat:
					@"%ld - %ld", low, fr->upperAge]];
				low = fr->upperAge + 1;
			}
			[_vcnAgeSpanPopUp addItemWithTitle:[NSString stringWithFormat:@"%ld ≤", low]];
			_vcnAgeSpanPopUp.target = item;
			_vcnAgeSpanPopUp.action = @selector(chooseAgeSpan:);
		}
		[self showLabelControl:_vcnAgeSpanPopUp];
		break;
		case SPTypeRegGathering:
		if (_gatNamePopUp == nil) {
			_gatNamePopUp = make_gat_name_popup(label.frame, _namePopUp.frame);
			_gatNamePopUp.target = item;
			_gatNamePopUp.action = @selector(chooseGat:);
			_gatNamePopUp.world = world;
		}
		[self adjustGatNamePopUp];
		[self showLabelControl:_gatNamePopUp];
	}
	switch (pType) {
		case SPTypeScalar: case SPTypeVaxScalar: case SPTypeVaxFnlRt:
		case SPTypeRegGathering:
		[self showArgControl:_digits];
		break;
		case SPTypeDistribution:
		[self showArgControl:_distBtn];
		break;
		case SPTypeVaxPriority:
		if (_vcnPriorityPopUp == nil) {
			_vcnPriorityPopUp = make_mini_popup(
				NSUnionRect(_digits.frame, _days.frame), _namePopUp.frame);
			make_popUpMenu(_vcnPriorityPopUp, vcnPr_menu_info());
			_vcnPriorityPopUp.target = item;
			_vcnPriorityPopUp.action = @selector(choosePriority:);
			[_vcnPriorityPopUp selectItemAtIndex:item.priority];
		}
		[self showArgControl:_vcnPriorityPopUp];
	}
	transLabel.hidden = _days.hidden = daysUnitLabel.hidden =
		(pType == SPTypeVaxPriority || pType == SPTypeVaxFnlRt);
}
- (void)reviseVcnPopUp:(NSNotification *)note {
	adjust_vcnType_popUps(@[_vcnTypePopUp], (World *)note.object);
}
@end
@interface CondCellView : NSTableCellView
@property (readonly) NSPopUpButton *typePopUp, *destPopUp;
@property (readonly) NSTextField *labelTxt, *sufixTxt;
@end
static NSPoint CCTxtOrg1 = {0,0}, CCTxtOrg2;
@implementation CondCellView
- (void)adjustViews:(NSInteger)index {
	switch (index) {
		case 0: _destPopUp.hidden = YES; _labelTxt.hidden = NO;
		_sufixTxt.stringValue = NSLocalizedString(@"satisfied", nil);
		[_sufixTxt setFrameOrigin:CCTxtOrg1];
		break;
		case 1: _destPopUp.hidden = NO; _labelTxt.hidden = YES;
		_sufixTxt.stringValue = NSLocalizedString(@"when satisfied", nil);
		[_sufixTxt setFrameOrigin:CCTxtOrg2];
	}
}
- (instancetype)init {
	NSSize fSize = CELL_SIZE;
	if (!(self = [super initWithFrame:(NSRect){0, 0, fSize}])) return nil;
	set_subview(label_field(@"Condition"), self, YES);
	_typePopUp = NSPopUpButton.new;
	[_typePopUp addItemWithTitle:NSLocalizedString(@"Run until", nil)];
	[_typePopUp addItemWithTitle:NSLocalizedString(@"Move to", nil)];
	set_subview(_typePopUp, self, YES);
	_destPopUp = NSPopUpButton.new;
	[_destPopUp addItemWithTitle:@"999"];
	set_subview(_destPopUp, self, YES);
	_destPopUp.lastItem.title = @"1";
	_sufixTxt = label_field(@"when satisfied");
	set_subview(_sufixTxt, self, YES);
	if (CCTxtOrg1.x == 0.) {
		CCTxtOrg1 = _destPopUp.frame.origin;
		CCTxtOrg2 = _sufixTxt.frame.origin;
	}
	_labelTxt = NSTextField.new;
	_labelTxt.selectable = _labelTxt.editable =
	_labelTxt.drawsBackground = _labelTxt.bordered = YES;
	_labelTxt.stringValue = @"This is a label for condition";
	set_subview(_labelTxt, self, YES);
	_labelTxt.stringValue = @"";
	[_labelTxt setFrameOrigin:
		(NSPoint){ _destPopUp.frame.origin.x, _labelTxt.frame.origin.y }];
	[self adjustViews:0];
	return self;
}
@end
@interface CompoundCellView : NSTableCellView
@property (readonly) NSPopUpButton *opePopUp;
@end
@implementation CompoundCellView
- (instancetype)init {
	NSSize fSize = CELL_SIZE;
	if (!(self = [super initWithFrame:(NSRect){0, 0, fSize}])) return nil;
	NSString *preWord = NSLocalizedString(@"PreConditionWord", nil);
	if (preWord.length > 0) {
		NSTextField *msg = label();
		msg.stringValue = preWord;
		set_subview(msg, self, YES);
	}
	_opePopUp = NSPopUpButton.new;
	NSTextField *msg = label();
	msg.stringValue = NSLocalizedString(@"of the following are true.", nil);
	[_opePopUp addItemWithTitle:NSLocalizedString(@"Any", nil)];
	[_opePopUp addItemWithTitle:NSLocalizedString(@"All", nil)];
	set_subview(_opePopUp, self, YES);
	set_subview(msg, self, YES);
	return self;
}
@end
@interface ComparisonCellView : NSTableCellView
@property (readonly) NSPopUpButton *varPopUp, *opePopUp, *unitPopUp;
@property (readonly) NSTextField *digits, *unitTxt;
@end
@implementation ComparisonCellView
#define N_VARIABLES 13
static NSString *varNames[] = {@"days", @"susceptible", @"infected", @"symptomatic",
	@"recovered", @"died", @"quarantine",
	@"dailyInfection", @"dailySymptomatic", @"dailyRecovery", @"dailyDeath",
	@"weeklyPositive", @"weeklyPositiveRate"
};
static VariableType varTypes[] = {VarAbsolute, VarNIndividuals, VarNIndividuals, VarNIndividuals,
	VarNIndividuals, VarNIndividuals, VarNIndividuals,
	VarNIndividuals, VarNIndividuals, VarNIndividuals, VarNIndividuals,
	VarNIndividuals, VarRate
};
#define N_OPERATORS 6
static NSString *operatorTitles[] = {@"=", @"≠", @">", @"<", @"≥", @"≤"};
static NSString *operatorStrings[] = {@"==", @"!=", @">", @"<", @">=", @"<="};
static NSPredicateOperatorType operatorTypes[] = {
	NSEqualToPredicateOperatorType, NSNotEqualToPredicateOperatorType,
	NSGreaterThanPredicateOperatorType, NSLessThanPredicateOperatorType,
	NSGreaterThanOrEqualToPredicateOperatorType, NSLessThanOrEqualToPredicateOperatorType
};
static NSNumberFormatter *absIntFormatter = nil, *percentFormatter;
- (instancetype)init {
	NSSize fSize = CELL_SIZE;
	if (!(self = [super initWithFrame:(NSRect){0, 0, fSize}])) return nil;
	if (absIntFormatter == nil) {
		absIntFormatter = NSNumberFormatter.new;
		absIntFormatter.minimum = @0;
		percentFormatter = NSNumberFormatter.new;
		percentFormatter.minimum = @(0.);
		percentFormatter.maximum = @(100.);
		percentFormatter.minimumFractionDigits =
		percentFormatter.maximumFractionDigits = 3;
	}
	_varPopUp = NSPopUpButton.new;
	_opePopUp = NSPopUpButton.new;
	_unitPopUp = NSPopUpButton.new;
	_digits = NSTextField.new;
	for (NSInteger i = 0; i < N_VARIABLES; i ++)
		[_varPopUp addItemWithTitle:NSLocalizedString(varNames[i], nil)];
	for (NSInteger i = 0; i < N_OPERATORS; i ++)
		[_opePopUp addItemWithTitle:operatorTitles[i]];
	for (NSString *title in @[@"people", @"per mille"])
		[_unitPopUp addItemWithTitle:NSLocalizedString(title, nil)];
	_digits.stringValue = @"999.999";
	for (NSControl *cnt in @[_varPopUp, _opePopUp, _digits, _unitPopUp])
		set_subview(cnt, self, YES);
	_unitPopUp.hidden = YES;
	_unitTxt = label_field(@"per mille");
	NSRect pFrm = _unitPopUp.frame;
	[_unitTxt setFrameOrigin:(NSPoint){pFrm.origin.x,
		pFrm.origin.y + (pFrm.size.height - _unitTxt.frame.size.height) / 2.}];
	[self addSubview:_unitTxt];
	_unitTxt.stringValue = NSLocalizedString(@"days", nil);
	_digits.formatter = absIntFormatter;
	return self;
}
@end

@interface InfecCellView : NSTableCellView
@property (readonly) NSTextField *digits;
@property (readonly) NSPopUpButton *variantPopUp, *locationPopUp;
@end
@implementation InfecCellView
- (instancetype)initWithWorld:(World *)world {
	NSSize fSize = CELL_SIZE;
	if (!(self = [super initWithFrame:(NSRect){0, 0, fSize}])) return nil;
	set_subview(label_field(@"Infection"), self, YES);
	_digits = NSTextField.new;
	_digits.stringValue = @"99999";
	set_subview(_digits, self, YES);
	_digits.integerValue = 1;
	_variantPopUp = NSPopUpButton.new;
	for (NSDictionary *vr in world.variantList)
		[_variantPopUp addItemWithTitle:vr[@"name"]];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(variantListChanged:)
		name:VariantListChanged object:world];
	set_subview(_variantPopUp, self, YES);
	_locationPopUp = NSPopUpButton.new;
	for (NSString *title in @[@"Scattered", @"Cluster at center", @"Cluster in random"])
		[_locationPopUp addItemWithTitle:NSLocalizedString(title, nil)];
	set_subview(_locationPopUp, self, YES);
	return self;
}
- (void)variantListChanged:(NSNotification *)note {
	World *world = note.object;
	setup_popup_menu(_variantPopUp, world.variantList.count,
		^NSString *(NSInteger idx) { return world.variantList[idx][@"name"]; });
}
@end

static NSImage *addImage = nil, *removeImage;
static void check_images(void) {
	if (addImage == nil) {
		addImage = [NSImage imageNamed:@"NSAddTemplate"];
		removeImage = [NSImage imageNamed:@"NSRemoveTemplate"];
	}
}

@implementation ScenarioItem
- (instancetype)initWithScenario:(Scenario *)scen {
	if (!(self = [super init])) return nil;
	scenario = scen;
	return self;
}
- (void)setLineNumber:(NSInteger)ln {
	_lnView.textField.integerValue = ln;
}
- (void)setupLineNumberView:(NSInteger)ln {
	_lnView = [NSTableCellView.alloc initWithFrame:(NSRect)LINEN_CELL_SIZE];
	NSTextField *dgt = label();
	dgt.frame = (NSRect)LINEN_CELL_SIZE;
	dgt.alignment = NSTextAlignmentRight;
	[_lnView addSubview:dgt];
	_lnView.textField = dgt;
	self.lineNumber = ln;
}
- (void)setupButtonView:(NSArray *)titles {
	_btnsView = [ButtonsCellView.alloc initWithItem:self titles:titles];
}
- (BOOL)removeChild:(ScenarioItem *)item { return NO; }
- (void)buttonAction:(NSButton *)button {
	if (button.image == removeImage) [scenario removeItem:self];
}
- (NSObject *)scenarioElement { return nil; }
- (NSObject *)propertyObject { return self.scenarioElement; }
@end

@implementation ParamItem
- (instancetype)initWithScenario:(Scenario *)scen {
	if (!(self = [super initWithScenario:scen])) return nil;
	[super setupButtonView:@[removeImage]];
	ParameterCellView *view = [ParameterCellView.alloc initWithWorld:scen.world item:self];
	self.view = view;
	NSPopUpButton *ctPopUp = view.categoryPopUp, *namePopUp = view.namePopUp;
	NSButton *distBtn = view.distBtn;
	ctPopUp.target = namePopUp.target = distBtn.target = self;
	ctPopUp.action = @selector(chooseCategory:);
	namePopUp.action = @selector(chooseParameterName:);
	distBtn.action = @selector(distParamBeginSheet:);
	regGatItem = [ctPopUp itemAtIndex:regGatItemIdx];
	view.digits.doubleValue = scen.world.runtimeParamsP->PARAM_F1;
	view.days.doubleValue = 0.;
	view.days.delegate = view.digits.delegate = scen;
	return self;
}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem == regGatItem) {
		MutableDictArray gatList = scenario.world.gatheringsList;
		return gatList != nil && gatList.count > 0;
	} else return YES;
}
- (CGFloat)value { return ((ParameterCellView *)self.view).digits.doubleValue; }
- (CGFloat)days { return ((ParameterCellView *)self.view).days.doubleValue; }
- (ScenParameterType)paramType:(ParamMenuIndex)index prmIdxReturn:(NSInteger *)prmIdxP {
	NSString *prmName = param_name_info()[index.cat][index.name];
	if ((index.cat) == regGatItemIdx) {
		if (prmIdxP != NULL) *prmIdxP = index.name;
		return SPTypeRegGathering;
	} else if ([prmName hasPrefix:@"vaccine"]) {
		if ([prmName hasSuffix:@"Priority"]) return SPTypeVaxPriority;
		else if ([prmName hasSuffix:@"FinalRate"]) return SPTypeVaxFnlRt;
		else {
			if (prmIdxP != NULL) *prmIdxP = [prmName hasSuffix:@"Rate"]? 0 : 1;
			return SPTypeVaxScalar;
		}
	} else {
		NSInteger prmIdx = paramIndexFromKey[prmName].integerValue;
		if (prmIdxP != NULL) *prmIdxP = prmIdx;
		return (prmIdx < IDX_D)? SPTypeScalar : SPTypeDistribution;
	}
}
- (void)reviseNameMenuIfNeededTo:(ParamMenuIndex)newIndex {
	ParameterCellView *view = (ParameterCellView *)self.view;
	if (_index.cat != newIndex.cat) {
		NSArray<NSString *> *titles = param_name_info()[newIndex.cat];
		setup_popup_menu(view.namePopUp, titles.count,
			^(NSInteger i) { return NSLocalizedString(titles[i], nil); });
	}
	NSUndoManager *ud = scenario.undoManager;
	if (ud.undoing || ud.redoing) {
		[view.categoryPopUp selectItemAtIndex:newIndex.cat];
		[view.namePopUp selectItemAtIndex:newIndex.name];
		[view adjustView:[self paramType:newIndex prmIdxReturn:NULL]];
	}
	_index = newIndex;
}
- (void)setParamUndoable:(ParamMenuIndex)newIndex value:(CGFloat)newValue {
	ParamMenuIndex orgIndex = _index;
	CGFloat orgValue = self.value;
	[scenario.undoManager registerUndoWithTarget:self handler:
		^(ParamItem *target) { [target setParamUndoable:orgIndex value:orgValue]; }];
	[self reviseNameMenuIfNeededTo:newIndex];
	((ParameterCellView *)self.view).digits.doubleValue = newValue;
}
- (void)setToolTipForDistBtn {
	((ParameterCellView *)self.view).distBtn.toolTip = [NSString stringWithFormat:
		@"%.1f, %.1f, %.1f", _distInfo.min, _distInfo.max, _distInfo.mode];
}
- (void)setDistUndoable:(ParamMenuIndex)newIndex value:(DistInfo)newValue {
	ParamMenuIndex orgIndex = _index;
	DistInfo orgValue = _distInfo;
	[scenario.undoManager registerUndoWithTarget:self handler:
		^(ParamItem *target) { [target setDistUndoable:orgIndex value:orgValue]; }];
	[self reviseNameMenuIfNeededTo:newIndex];
	_distInfo = newValue;
	[self setToolTipForDistBtn];
}
- (void)setVaxPriorityUndoable:(ParamMenuIndex)newIndex {
	ParamMenuIndex orgIndex = _index;
	[scenario.undoManager registerUndoWithTarget:self handler:
		^(ParamItem *target) { [target setVaxPriorityUndoable:orgIndex]; }];
	[self reviseNameMenuIfNeededTo:newIndex];
}
- (void)chooseParameter:(ParamMenuIndex)newIndex {
	NSInteger prmIdx;
	ScenParameterType pType = [self paramType:newIndex prmIdxReturn:&prmIdx];
	[(ParameterCellView *)self.view adjustView:pType];
	RuntimeParams *rp = scenario.world.runtimeParamsP;
	switch (pType) {
		case SPTypeScalar:
		[self setParamUndoable:newIndex value:(&rp->PARAM_F1)[prmIdx]]; break;
		case SPTypeDistribution:
		[self setDistUndoable:newIndex value:(&rp->PARAM_D1)[prmIdx - IDX_D]]; break;
		case SPTypeVaxPriority:
		[self setVaxPriorityUndoable:newIndex]; break;
		case SPTypeVaxScalar: {
		VaccinationInfo *vInfo = &rp->vcnInfo[_vcnType];
		[self setParamUndoable:newIndex value:
			(prmIdx == 0)? vInfo->performRate : vInfo->regularity];
		} break;
		case SPTypeVaxFnlRt:
		[self setParamUndoable:newIndex value:
			rp->vcnFnlRt[(_ageSpanIdx < 0)? 0 : _ageSpanIdx].rate];
		break;
		case SPTypeRegGathering: {
		NSDictionary *info = scenario.world.gatheringsList[_gatIndex];
		NSString *key = reg_gat_keys()[prmIdx];
		[self setParamUndoable:newIndex value:[info[key] doubleValue]];
		} break;
	}
}
- (void)chooseCategory:(NSPopUpButton *)sender {
	NSInteger newCat = sender.indexOfSelectedItem;
	if (newCat == _index.cat) return;
	if (_index.name > 0)
		[((ParameterCellView *)self.view).namePopUp selectItemAtIndex:0];
	[self chooseParameter:(ParamMenuIndex){newCat, 0}];
}
- (void)chooseParameterName:(NSPopUpButton *)sender {
	NSInteger newNameIdx = sender.indexOfSelectedItem;
	if (newNameIdx == _index.name) return;
	[self chooseParameter:(ParamMenuIndex){_index.cat, newNameIdx}];
}
- (void)distParamBeginSheet:(id)sender {
	[scenario distParamBySheetWithItem:self value:&_distInfo];
}
- (NSInteger)chooseItemInPopUp:(NSPopUpButton *)sender orgChoice:(NSInteger)orgChoice {
	[scenario.undoManager registerUndoWithTarget:self handler:^(ParamItem *target) {
		[sender selectItemAtIndex:orgChoice];
		[sender sendAction:sender.action to:target]; }];
	return sender.indexOfSelectedItem;
}
- (void)chooseVcnType:(NSPopUpButton *)sender {
	_vcnType = [self chooseItemInPopUp:sender orgChoice:_vcnType];
}
- (void)choosePriority:(NSPopUpButton *)sender {
	_priority = [self chooseItemInPopUp:sender orgChoice:_priority];
}
- (void)chooseAgeSpan:(NSPopUpButton *)sender {
	_ageSpanIdx = [self chooseItemInPopUp:sender orgChoice:_ageSpanIdx + 1] - 1;
}
- (void)chooseGat:(NSPopUpButton *)sender {
	_gatIndex = [self chooseItemInPopUp:sender orgChoice:_gatIndex];
}
- (NSObject *)scenarioElement {
	ParameterCellView *view = (ParameterCellView *)self.view;
	NSInteger catIdx = view.categoryPopUp.indexOfSelectedItem;
	NSInteger prmIdx = view.namePopUp.indexOfSelectedItem;
	NSString *key = param_name_info()[catIdx][prmIdx];
	NSObject *value;
	CGFloat days = self.days;
	if ([key hasPrefix:@"vaccine"]) {
		if ([key hasSuffix:@"Priority"]) { value = @(_priority); days = 0.; }
		else value = @(self.value);
		key = [key hasSuffix:@"FinalRate"]? (_ageSpanIdx < 0)? key :
			[key stringByAppendingFormat:@" %ld", _ageSpanIdx] :
			[key stringByAppendingFormat:@" %@", view.vcnTypePopUp.titleOfSelectedItem];
	} else if ([key hasPrefix:@"regGat"]) {
		NSInteger idx = view.gatNamePopUp.indexOfSelectedItem;
		MutableDictArray gatList = scenario.world.gatheringsList;
		if (idx >= 0 && idx < gatList.count)
			key = [NSString stringWithFormat:@"regGat %@ %@",
				reg_gat_keys()[prmIdx], gatList[idx][@"name"]];
		value = @(self.value);
	} else value = (paramIndexFromKey[key].integerValue < IDX_D)? @(self.value) :
		@[@(_distInfo.min), @(_distInfo.max), @(_distInfo.mode)];
	return (days == 0.)? @[key, value] : @[key, value, @(days)];
}
@end

@implementation CondElmItem
- (instancetype)initWithScenario:(Scenario *)scen parent:(ScenarioItem *)parnt {
	if (!(self = [super initWithScenario:scen])) return nil;
	self.parent = parnt;
	return self;
}
- (CondElmItem *)firstChild { return nil; }
- (NSInteger)numberOfLieves { return 1; }
- (void)buttonAction:(NSButton *)button {
	if (button.image == removeImage) [scenario removeItem:self];
	else if ([button.title isEqualToString:@"^C"]) {
		CompoundItem *cItem = [CompoundItem.alloc initWithScenario:scenario parent:_parent];
		[cItem.children addObject:self];
		if ([_parent isKindOfClass:CondItem.class])
			[(CondItem *)_parent replaceElementWithItem:cItem];
		else if ([_parent isKindOfClass:CompoundItem.class])
			[(CompoundItem *)_parent replaceChildAtIndex:
				[((CompoundItem *)_parent).children indexOfObject:self]
				withItem:cItem];
		_parent = cItem;
		[scenario.outlineView expandItem:_parent];
	} 
}
- (NSPredicate *)predicate { return nil; }
@end
@implementation ComparisonItem
- (instancetype)initWithScenario:(Scenario *)scen parent:(ScenarioItem *)parnt {
	if (!(self = [super initWithScenario:scen parent:parnt])) return nil;
	[super setupButtonView:@[removeImage, @"^C"]];
	ComparisonCellView *v = ComparisonCellView.new;
	self.view = v;
	maxValue = scen.intFormatter.maximum.integerValue;
	ratioValue = .5;
	v.digits.integerValue = days = 180;
	v.digits.delegate = self;
	v.varPopUp.target = v.opePopUp.target = v.unitPopUp.target = self;
	v.varPopUp.action = @selector(chooseVariable:);
	v.opePopUp.action = @selector(chooseOperation:);
	v.unitPopUp.action = @selector(chooseUnit:);
	return self;
}
- (NSPredicate *)predicate {
	ComparisonCellView *v = (ComparisonCellView *)self.view;
	NSInteger index = v.varPopUp.indexOfSelectedItem;
	return [NSComparisonPredicate.alloc initWithLeftExpression:
		[NSExpression expressionForKeyPath:varNames[index]]
		rightExpression:[NSExpression expressionForConstantValue:
			@((varTypes[index] == VarAbsolute)? days :
			 (varTypes[index] == VarNIndividuals)? self.intValue : ratioValue)]
		modifier:0 type:operatorTypes[opeIndex] options:0];
}
- (void)adjustValueAndUnit {
	ComparisonCellView *v = (ComparisonCellView *)self.view;
	switch (varTypes[varIndex]) {
	   case VarAbsolute:
	   v.unitPopUp.hidden = YES;
	   v.unitTxt.hidden = NO;
	   v.unitTxt.stringValue = NSLocalizedString(@"days", nil);
	   v.digits.formatter = absIntFormatter;
	   v.digits.integerValue = days;
	   break;
	   case VarNIndividuals:
	   v.unitPopUp.hidden = NO;
	   v.unitTxt.hidden = YES;
	   if (v.unitPopUp.indexOfSelectedItem == 0) {
		   v.digits.formatter = scenario.intFormatter;
		   v.digits.integerValue = self.intValue;
	   } else {
		   v.digits.formatter = percentFormatter;
		   v.digits.doubleValue = ratioValue * 1000.;
	   } break;
	   case VarRate:
	   v.unitPopUp.hidden = YES;
	   v.unitTxt.hidden = NO;
	   v.unitTxt.stringValue = NSLocalizedString(@"per mille", nil);
	   v.digits.formatter = percentFormatter;
	   v.digits.doubleValue = ratioValue * 1000.;
	}
}
- (void)setupWithPredicate:(NSComparisonPredicate *)predicate {
	ComparisonCellView *v = (ComparisonCellView *)self.view;
	NSString *varName = predicate.leftExpression.keyPath;
	NSInteger index;
	for (index = 0; index < N_VARIABLES; index ++)
		if ([varName isEqualToString:varNames[index]]) break;
	[v.varPopUp selectItemAtIndex:(varIndex = index)];
	NSNumber *num = predicate.rightExpression.constantValue;
	switch (varTypes[index]) {
		case VarAbsolute: days = num.integerValue; break;
		case VarNIndividuals: self.intValue = num.integerValue; break;
		case VarRate: ratioValue = num.doubleValue * 1000.;
	}
	[self adjustValueAndUnit];
	NSPredicateOperatorType opeType = predicate.predicateOperatorType;
	for (index = 0; index < N_OPERATORS; index ++)
		if (operatorTypes[index] == opeType) break;
	[v.opePopUp selectItemAtIndex:(opeIndex = index)];
}
- (NSInteger)intValue { return maxValue * ratioValue; }
- (void)setIntValue:(NSInteger)val {
	ratioValue = (CGFloat)val / maxValue;
}
- (void)chooseUnit:(id)sender {
	ComparisonCellView *v = (ComparisonCellView *)self.view;
	BOOL isNewAbs = (v.unitPopUp.indexOfSelectedItem == 0);
	NSNumberFormatter *newFmt = isNewAbs? scenario.intFormatter : percentFormatter;
	if (newFmt == v.digits.formatter) return;
	if (sender != nil) [scenario.undoManager registerUndoWithTarget:v.unitPopUp
		handler:^(NSPopUpButton *pb) {
			[pb selectItemAtIndex:isNewAbs? 1 : 0];
			[pb sendAction:pb.action to:pb.target];
	}];
	v.digits.formatter = newFmt;
	if (isNewAbs) v.digits.integerValue = self.intValue;
	else v.digits.doubleValue = ratioValue * 1000.;
}
- (void)chooseOperation:(id)sender {
	ComparisonCellView *v = (ComparisonCellView *)self.view;
	NSInteger orgIndex = opeIndex;
	[scenario.undoManager registerUndoWithTarget:v.opePopUp handler:^(NSPopUpButton *pb) {
		[pb selectItemAtIndex:orgIndex];
		[pb sendAction:pb.action to:pb.target];
	}];
	opeIndex = v.opePopUp.indexOfSelectedItem;
}
- (void)chooseVariable:(id)sender {
	ComparisonCellView *v = (ComparisonCellView *)self.view;
	NSInteger newIndex = v.varPopUp.indexOfSelectedItem;
	if (newIndex == varIndex) return;
	NSInteger orgIndex = varIndex;
	[scenario.undoManager registerUndoWithTarget:v.varPopUp
		handler:^(NSPopUpButton *pb) {
		[pb selectItemAtIndex:orgIndex];
		[pb sendAction:pb.action to:pb.target];
	}];
	varIndex = newIndex;
	if (varTypes[newIndex] != varTypes[orgIndex])
		[self adjustValueAndUnit];
}
- (void)setDays:(NSInteger)newDays digits:(NSTextField *)digits {
	NSInteger orgDays = days;
	[scenario.undoManager registerUndoWithTarget:self handler:^(ComparisonItem *item) {
		digits.integerValue = orgDays;
		[item setDays:orgDays digits:digits];
	}];
	days = newDays;
}
- (void)setNIndividuals:(CGFloat)newRatio digits:(NSTextField *)digits {
	NSInteger orgInt = ratioValue * maxValue;
	CGFloat orgRatio = ratioValue;
	[scenario.undoManager registerUndoWithTarget:self handler:^(ComparisonItem *item) {
		digits.integerValue = orgInt;
		[item setNIndividuals:orgRatio digits:digits];
	}];
	ratioValue = newRatio;
}
- (void)setRatio:(CGFloat)newRatio digits:(NSTextField *)digits {
	CGFloat orgRatio = ratioValue;
	[scenario.undoManager registerUndoWithTarget:self handler:^(ComparisonItem *item) {
		digits.doubleValue = orgRatio * 1000.;
		[item setRatio:orgRatio digits:digits];
	}];
	ratioValue = newRatio;
}
- (void)controlTextDidEndEditing:(NSNotification *)obj {
	ComparisonCellView *v = (ComparisonCellView *)self.view;
	switch (varTypes[v.varPopUp.indexOfSelectedItem]) {
		case VarAbsolute: {
			NSInteger newDays = v.digits.integerValue;
			if (newDays != days) [self setDays:newDays digits:v.digits];
		} break;
		case VarNIndividuals:
		if (v.unitPopUp.indexOfSelectedItem == 0) {
			CGFloat newRatio = (CGFloat)v.digits.integerValue / maxValue;
			if (newRatio != ratioValue) [self setNIndividuals:newRatio digits:v.digits];
		} else {
			CGFloat newRatio = v.digits.doubleValue / 1000.;
			if (newRatio != ratioValue) [self setRatio:newRatio digits:v.digits];
		} break;
		case VarRate: {
			CGFloat newRatio = v.digits.doubleValue / 1000.;
			if (newRatio != ratioValue) [self setRatio:newRatio digits:v.digits];
		}
	}
}
@end
static CondElmItem *new_item_by_button(NSButton *button, Scenario *scen, ScenarioItem *parnt) {
	return [button.title isEqualToString:@"+C"]?
		[CompoundItem.alloc initWithScenario:scen parent:parnt] :
		[ComparisonItem.alloc initWithScenario:scen parent:parnt];
}
@implementation CompoundItem
- (instancetype)initWithScenario:(Scenario *)scen parent:(ScenarioItem *)parnt {
	if (!(self = [super initWithScenario:scen parent:parnt])) return nil;
	[super setupButtonView:@[removeImage, @"+P", @"+C", @"^C"]];
	CompoundCellView *cv = CompoundCellView.new;
	self.view = cv;
	_children = NSMutableArray.new;
	cv.opePopUp.target = self;
	cv.opePopUp.action = @selector(chooseLogicalOperator:);
	return self;
}
- (ScenarioItem *)firstChild {
	return (_children.count < 1)? nil : _children[0]; 
}
- (void)removeChildAtIndex:(NSInteger)index {
	CondElmItem *orgItem = _children[index];
	[scenario.undoManager registerUndoWithTarget:self handler:
		^(CompoundItem *target) { [target insertChild:orgItem atIndex:index]; }];
	[_children removeObjectAtIndex:index];
	[scenario.outlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:index]
		inParent:self withAnimation:NSTableViewAnimationEffectFade];
}
- (void)replaceChildAtIndex:(NSInteger)index withItem:(CondElmItem *)newChild {
	CondElmItem *orgItem = _children[index];
	ScenarioItem *orgParent = newChild.parent;
	[scenario.undoManager registerUndoWithTarget:self handler:^(CompoundItem *target) {
		[target replaceChildAtIndex:index withItem:orgItem];
		newChild.parent = orgParent;
	}];
	[_children replaceObjectAtIndex:index withObject:newChild];
	((CondElmItem *)newChild).parent = self;
	[scenario.outlineView reloadItem:self reloadChildren:YES];
}
- (void)insertChild:(CondElmItem *)newChild atIndex:(NSInteger)index {
	[scenario.undoManager registerUndoWithTarget:self handler:
		^(CompoundItem *target) { [target removeChildAtIndex:index]; }];
	[_children insertObject:newChild atIndex:index];
	((CondElmItem *)newChild).parent = self;
	[scenario.outlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:index]
		inParent:self withAnimation:NSTableViewAnimationEffectFade];
	[scenario.outlineView expandItem:self];
}
- (BOOL)removeChild:(CondElmItem *)item {
	NSInteger index = [_children indexOfObject:item];
	if (index >= 0 && index < _children.count) {
		CondElmItem *fc = item.firstChild;
		if (fc == nil) [self removeChildAtIndex:index];
		else [self replaceChildAtIndex:index withItem:fc];
		return YES;
	} else for (ScenarioItem *child in _children)
		if ([child removeChild:item]) return YES;
	return NO;
}
- (void)chooseLogicalOperator:(NSPopUpButton *)sender {
	[scenario.undoManager registerUndoWithTarget:self handler:^(CompoundItem *target) {
		[sender selectItemAtIndex:1 - sender.indexOfSelectedItem];
		[target chooseLogicalOperator:sender];
	}];
}
- (void)buttonAction:(NSButton *)button {
	if ([button.title hasPrefix:@"+"]) {
		[self insertChild:new_item_by_button(button, scenario, self) atIndex:_children.count];
		[scenario.outlineView expandItem:self];
	} else [super buttonAction:button];
}
- (NSInteger)numberOfLieves {
	NSInteger count = 0;
	for (CondElmItem *item in _children)
		count +=  item.numberOfLieves;
	return count;
}
- (NSPredicate *)predicate {
	CompoundCellView *v = (CompoundCellView *)self.view;
	NSInteger nChildren = _children.count;
	NSPredicate *subpreds[nChildren];
	for (NSInteger i = 0; i < nChildren; i ++)
		subpreds[i] = _children[i].predicate;
	return [NSCompoundPredicate.alloc initWithType:
		(v.opePopUp.indexOfSelectedItem == 0)? NSOrPredicateType : NSAndPredicateType
		subpredicates:[NSArray arrayWithObjects:subpreds count:nChildren]];
}
- (void)setupWithPredicate:(NSCompoundPredicate *)predicate {
	CompoundCellView *v = (CompoundCellView *)self.view;
	[v.opePopUp selectItemAtIndex:
		(predicate.compoundPredicateType == NSOrPredicateType)? 0 : 1];
	for (NSPredicate *subp in predicate.subpredicates)
		[_children addObject:[scenario itemWithPredicate:subp parent:self]];
}
@end
static void adjust_num_menu(NSPopUpButton *pb, NSInteger n) {
	NSInteger m = pb.numberOfItems;
	if (m > n) for (NSInteger i = m; i > n; i --) [pb removeItemAtIndex:i - 1];
	else for (NSInteger i = m; i < n; i ++) [pb addItemWithTitle:@(i + 1).stringValue];
}
@implementation CondItem
- (instancetype)initWithScenario:(Scenario *)scen {
	if (!(self = [super initWithScenario:scen])) return nil;
	[super setupButtonView:@[removeImage, @"+P", @"+C"]];
	CondCellView *v = CondCellView.new;
	self.view = v;
	v.typePopUp.target = v.destPopUp.target = self;
	v.typePopUp.action = @selector(chooseType:);
	v.destPopUp.action = @selector(chooseDestination:);
	v.labelTxt.delegate = self;
	adjust_num_menu(v.destPopUp, scen.numberOfItems);
	orgLabel = @"";
	return self;
}
- (NSInteger)condType { return condType; }
- (NSString *)label { return ((CondCellView *)(self.view)).labelTxt.stringValue; }
- (void)setLabel:(NSString *)label {
	((CondCellView *)(self.view)).labelTxt.stringValue = label;
}
- (void)setLabelUndoable:(NSString *)newLabel {
	[scenario.undoManager registerUndoWithTarget:self
		selector:@selector(setLabelUndoable:) object:self.label];
	self.label = newLabel;
}
- (void)controlTextDidBeginEditing:(NSNotification *)obj {
	orgLabel = self.label;
}
- (void)controlTextDidEndEditing:(NSNotification *)obj {
	[scenario.undoManager registerUndoWithTarget:self
		selector:@selector(setLabelUndoable:) object:orgLabel];
}
- (NSInteger)destination { return destination; }
- (void)setDestination:(NSInteger)ln {
	destination = ln;
	condType = CondTypeMoveWhen;
}
- (void)removeDestMenuItemAtIndex:(NSInteger)idx {
	NSPopUpButton *pb = ((CondCellView *)self.view).destPopUp;
	[pb removeItemAtIndex:pb.numberOfItems - 1];
	if (destination > idx) [pb selectItemAtIndex:(-- destination)];
}
- (void)insertDestMenuItemAtIndex:(NSInteger)idx {
	NSPopUpButton *pb = ((CondCellView *)self.view).destPopUp;
	[pb addItemWithTitle:@(pb.numberOfItems + 1).stringValue];
	if (destination > idx) [pb selectItemAtIndex:(++ destination)];
}
- (void)chooseType:(NSPopUpButton *)sender {
	CondType newType = (CondType)sender.indexOfSelectedItem;
	if (condType == newType) return;
	CondType orgType = condType;
	[scenario.undoManager registerUndoWithTarget:self handler:^(CondItem *target) {
		NSPopUpButton *pb = ((CondCellView *)target.view).typePopUp;
		[pb selectItemAtIndex:orgType];
		[pb sendAction:pb.action to:pb.target];
	}];
	condType = newType;
	[(CondCellView *)self.view adjustViews:newType];
}
- (void)chooseDestination:(NSPopUpButton *)sender {
	NSInteger newDest = sender.indexOfSelectedItem;
	if (newDest == destination) return;
	NSInteger orgDest = destination;
	[scenario.undoManager registerUndoWithTarget:self handler:^(CondItem *target) {
		[sender selectItemAtIndex:orgDest];
		[target chooseDestination:sender];
	}];
	destination = newDest;
}
- (void)removeElement {
	CondElmItem *orgItem = _element;
	[scenario.undoManager registerUndoWithTarget:self handler:
		^(CondItem *target) { [target setNewElement:orgItem]; }];
	_element = nil;
	[scenario.outlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:0]
		inParent:self withAnimation:NSTableViewAnimationEffectFade];
	NSArray<NSButton *> *btns = self.btnsView.buttons;
	btns[1].enabled = btns[2].enabled = YES;
}
- (void)replaceElementWithItem:(CondElmItem *)newElement {
	CondElmItem *orgItem = _element;
	ScenarioItem *orgParent = newElement.parent;
	[scenario.undoManager registerUndoWithTarget:self handler:^(CondItem *target) {
		[target replaceElementWithItem:orgItem];
		newElement.parent = orgParent;
	}];
	_element = newElement;
	((CondElmItem *)newElement).parent = self;
	[scenario.outlineView reloadItem:self reloadChildren:YES];
}
- (void)setNewElement:(CondElmItem *)newElement {
	[scenario.undoManager registerUndoWithTarget:self handler:
		^(CondItem *target) { [target removeElement]; }];
	_element = newElement;
	((CondElmItem *)newElement).parent = self;
	[scenario.outlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:0]
		inParent:self withAnimation:NSTableViewAnimationEffectFade];
	[scenario.outlineView expandItem:self];
	NSArray<NSButton *> *btns = self.btnsView.buttons;
	btns[1].enabled = btns[2].enabled = NO;
}
- (BOOL)removeChild:(CondElmItem *)item {
	if (_element == item) {
		CondElmItem *fc = item.firstChild;
		if (fc == nil) [self removeElement];
		else [self replaceElementWithItem:fc];
		return YES;
	} return [_element removeChild:item];
}
- (void)buttonAction:(NSButton *)button {
	if (button.image == removeImage) [scenario removeItem:self];
	else if (_element == nil)
		[self setNewElement:new_item_by_button(button, scenario, self)];
}
- (NSObject *)representation:(NSObject *)element {
	switch (condType) {
		case CondTypeRunUntil: {
			NSString *label = self.label;
			if (element == nil) element = [NSPredicate predicateWithValue:YES];
			return (label.length == 0)? element : @[label, element];
		}
		case CondTypeMoveWhen:
		return (element != nil)? @[@(destination), element] : @[@(destination)];
	}
}
- (NSObject *)scenarioElement { return [self representation:_element.predicate]; }
- (NSObject *)propertyObject {
	return [self representation:_element.predicate.predicateFormat];
}
@end

@interface InfecItem : ScenarioItem
@end
@implementation InfecItem
- (instancetype)initWithScenario:(Scenario *)scen {
	if (!(self = [super initWithScenario:scen])) return nil;
	[super setupButtonView:@[removeImage]];
	self.view = [InfecCellView.alloc initWithWorld:scen.world];
	return self;
}
- (NSObject *)scenarioElement {
	InfecCellView *view = (InfecCellView *)self.view;
	return @[@(view.digits.integerValue),
		@(view.locationPopUp.indexOfSelectedItem),
		view.variantPopUp.titleOfSelectedItem];
}
@end

@interface Scenario () {
	NSArray *savedPList;
	NSInteger modificationCount, appliedCount;
	NSDictionary<NSNumber *, CondItem *> *orgIndexes;
	NSMutableDictionary<NSNumber *, NSNumber *> *valueDict;
	NSMutableSet<NSString *> *unknownNames;
	DistDigits *distDigits;
}
@end
@implementation Scenario
- (instancetype)initWithDoc:(Document *)dc {
	if (!(self = [super initWithWindowNibName:@"Scenario"])) return nil;
	check_images();
	_doc = dc;
	_world = dc.world;
	_undoManager = NSUndoManager.new;
	_intFormatter = NSNumberFormatter.new;
	_intFormatter.minimum = @0;
	_intFormatter.maximum = @(_world.worldParamsP->initPop);
	valueDict = NSMutableDictionary.new;
	for (NSString *name in @[NSUndoManagerDidCloseUndoGroupNotification,
		NSUndoManagerDidUndoChangeNotification, NSUndoManagerDidRedoChangeNotification])
		 [NSNotificationCenter.defaultCenter addObserver:self
			selector:@selector(checkUndoable:) name:name object:_undoManager];
	return self;
}
- (void)checkUndoable:(NSNotification *)note {
	NSUndoManager *um = note.object;
	if (um.undoing) modificationCount --;
	else modificationCount ++;
	applyBtn.enabled = modificationCount != appliedCount;
#ifdef DEBUG
NSLog(@"%@ %@", note.name, um.undoing? @"undo" : um.redoing? @"redo" : @"none");
#endif
}
- (void)adjustControls:(BOOL)undoOrRedo {
	if (undoOrRedo) appliedCount = -1;
	removeBtn.enabled = !_world.running && (_world.scenario != nil && _world.scenario.count > 0);
	applyBtn.enabled = !_world.running && modificationCount != appliedCount;
}
- (void)makeOrgIndexes {
	NSInteger n = itemList.count, nn = 0;
	CondItem *items[n];
	NSNumber *idxs[n];
	for (NSInteger i = 0; i < n; i ++) if ([itemList[i] isKindOfClass:CondItem.class]) {
		items[nn] = (CondItem *)itemList[i];
		idxs[nn ++] = @(i + 1);
	}
	orgIndexes = [NSDictionary dictionaryWithObjects:items forKeys:idxs count:nn];
}
- (void)makeDocItemList {
	appliedCount = modificationCount;
	modificationCount --;	// for reload the saved file.
    if (_world.scenario != nil) {
		[self setScenarioWithArray:_world.scenario];
		[self makeOrgIndexes];
	} else {
		itemList = NSMutableArray.new;
		orgIndexes = @{};
	}
}
- (void)windowDidLoad {
	[super windowDidLoad];
NSTableColumn *tc = [_outlineView tableColumnWithIdentifier:@"Content"];
tc.width = (NSSize)CELL_SIZE.width;	// for OS's BUG?
	self.window.alphaValue = panelsAlpha;
	[_doc setPanelTitle:self.window];
	removeBtn.toolTip = NSLocalizedString(@"Remove scenario from the simulator", nil);
	applyBtn.toolTip = NSLocalizedString(@"Apply this scenario to the simulator", nil);
	distParamSheet.alphaValue = .9;
	[self makeDocItemList];
	appliedCount = modificationCount;
	[self adjustControls:NO];
}
- (NSInteger)numberOfItems { return itemList.count; }
- (void)removeItem:(ScenarioItem *)item {
	if ([item isKindOfClass:ParamItem.class] ||
		[item isKindOfClass:CondItem.class] || [item isKindOfClass:InfecItem.class]) {
		[self removeItemAtIndex:[itemList indexOfObject:item]];
	} else if ([item isKindOfClass:CondElmItem.class])
		[((CondElmItem *)item).parent removeChild:item];
}
//
- (void)setScenarioWithUndo:(NSMutableArray<ScenarioItem *> *)new {
	if (itemList != nil) {
		NSMutableArray<ScenarioItem *> *org = itemList;
		[_undoManager registerUndoWithTarget:self handler:
			^(Scenario *target) { [target setScenarioWithUndo:org]; }];
		if (org.count > 0) [_outlineView removeItemsAtIndexes:
			[NSIndexSet indexSetWithIndexesInRange:(NSRange){0, org.count}]
			inParent:nil withAnimation:NSTableViewAnimationEffectFade];
	}
	itemList = new;
	if (new.count > 0) [_outlineView insertItemsAtIndexes:
		[NSIndexSet indexSetWithIndexesInRange:(NSRange){0, new.count}]
		inParent:nil withAnimation:NSTableViewAnimationEffectFade];
}
- (void)checkSelection {
	NSInteger row = _outlineView.selectedRow;
	if (row < 0) { shiftUpBtn.enabled = shiftDownBtn.enabled = deselectBtn.enabled = NO; return; }
	ScenarioItem *item = [_outlineView itemAtRow:row];
	NSInteger index = [itemList indexOfObject:item];
	if (index == NSNotFound) {
		shiftUpBtn.enabled = shiftDownBtn.enabled = NO;
		if ([item isKindOfClass:CompoundItem.class])
			[self.window makeFirstResponder:((CompoundCellView *)item.view).opePopUp];
		else if ([item isKindOfClass:ComparisonItem.class])
			[self.window makeFirstResponder:((ComparisonCellView *)item.view).varPopUp];
	} else if (index == 0) {
		shiftUpBtn.enabled = NO;
		shiftDownBtn.enabled = itemList.count > 1;
	} else if (index == itemList.count - 1)
		{ shiftUpBtn.enabled = YES; shiftDownBtn.enabled = NO; }
	else shiftUpBtn.enabled = shiftDownBtn.enabled = YES;
	deselectBtn.enabled = YES;
}
- (IBAction)resetScenario:(id)sender {
	[self setScenarioWithUndo:NSMutableArray.new];
}
- (void)removeItemAtIndex:(NSInteger)idx {
	ScenarioItem *orgItem = itemList[idx];
	[itemList removeObjectAtIndex:idx];
	for (NSInteger i = idx; i < itemList.count; i ++)
		itemList[i].lineNumber = i + 1;
	for (CondItem *itm in itemList) if ([itm isKindOfClass:CondItem.class])
		[itm removeDestMenuItemAtIndex:idx];
    void (^handler)(id);
	if ([orgItem isKindOfClass:ParamItem.class]) {
        ParameterCellView *cView = (ParameterCellView *)orgItem.view;
		NSTextField *digits = cView.digits, *days = cView.days;
        CGFloat value = digits.doubleValue, dVal = days.doubleValue;
        handler = ^(Scenario *scen) {
            digits.doubleValue = value;
            days.doubleValue = dVal;
            [scen insertItem:orgItem atIndex:idx];
        };
    } else handler = ^(Scenario *scen) { [scen insertItem:orgItem atIndex:idx]; };
	[_undoManager registerUndoWithTarget:self handler:handler];
	[_outlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:idx]
		inParent:nil withAnimation:NSTableViewAnimationEffectFade];
	[self checkSelection];
}
- (void)insertItem:(ScenarioItem *)item atIndex:(NSInteger)idx {
	[_undoManager registerUndoWithTarget:self handler:
		^(Scenario *scen) { [scen removeItemAtIndex:idx]; }];
	[itemList insertObject:item atIndex:idx];
	for (NSInteger i = idx + 1; i < itemList.count; i ++)
		itemList[i].lineNumber = i + 1;
	for (CondItem *itm in itemList) if ([itm isKindOfClass:CondItem.class])
		[itm insertDestMenuItemAtIndex:idx];
	[_outlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:idx]
		inParent:nil withAnimation:NSTableViewAnimationEffectFade];
	[self checkSelection];
}
- (void)addTopLevelItem:(ScenarioItem *)item {
	NSInteger row = _outlineView.selectedRow, index;
	if (row >= 0) {
		index = [itemList indexOfObject:[_outlineView itemAtRow:row]];
		if (index == NSNotFound) index = itemList.count;
	} else index = itemList.count;
	[item setupLineNumberView:index + 1];
	[self insertItem:item atIndex:index];
}
- (IBAction)addParameters:(id)sender {
	[self addTopLevelItem:[ParamItem.alloc initWithScenario:self]];
}
- (IBAction)addCondition:(id)sender {
	[self addTopLevelItem:[CondItem.alloc initWithScenario:self]];
}
- (IBAction)addInfection:(id)sender {
	[self addTopLevelItem:[InfecItem.alloc initWithScenario:self]];
}
- (IBAction)delete:(id)sender {
	[_outlineView.selectedRowIndexes enumerateIndexesUsingBlock:
		^(NSUInteger idx, BOOL * _Nonnull stop) {
		[self removeItem:[_outlineView itemAtRow:idx]];
	}];
}
- (void)swapItemsAtIndex:(NSInteger)index {
	ScenarioItem *itemA = itemList[index];
	[_outlineView moveItemAtIndex:index inParent:nil toIndex:index + 1 inParent:nil];
	[itemList removeObjectAtIndex:index];
	[itemList insertObject:itemA atIndex:index + 1];
	itemA.lineNumber = index + 2;
	itemList[index].lineNumber = index + 1;
	[self checkSelection];
	[_undoManager registerUndoWithTarget:self handler:
		^(Scenario *target) { [target swapItemsAtIndex:index]; }];
}
- (IBAction)shiftUp:(id)sender {
	NSInteger row = _outlineView.selectedRow;
	if (row < 1) return;
	NSInteger index = [itemList indexOfObject:[_outlineView itemAtRow:row]];
	if (index == NSNotFound || index < 1) return;
	[self swapItemsAtIndex:index - 1];
}
- (IBAction)shiftDown:(id)sender {
	NSInteger row = _outlineView.selectedRow;
	if (row < 0) return;
	NSInteger index = [itemList indexOfObject:[_outlineView itemAtRow:row]];
	if (index == NSNotFound || index >= itemList.count - 1) return;
	[self swapItemsAtIndex:index];
}
- (CondElmItem *)itemWithPredicate:(NSPredicate *)predicate parent:(ScenarioItem *)parent {
	if ([predicate isKindOfClass:NSComparisonPredicate.class]) {
		ComparisonItem *item = [ComparisonItem.alloc initWithScenario:self parent:parent];
		[item setupWithPredicate:(NSComparisonPredicate *)predicate];
		return item;
	} else if ([predicate isKindOfClass:NSCompoundPredicate.class]) {
		CompoundItem *item = [CompoundItem.alloc initWithScenario:self parent:parent];
		[item setupWithPredicate:(NSCompoundPredicate *)predicate];
		return item;
	} else return nil;
}
- (ParamItem *)paramItemWithKey:(NSString *)key value:(NSObject *)value days:(NSNumber *)days {
	NSString *vaxName = nil;
	BOOL isVax = NO, isAgeSpan = NO;
	NSInteger ageSpanIdx = -1;
	if ([key hasPrefix:@"vaccine"]) {
		NSString *newKey;
		NSScanner *scan = [NSScanner scannerWithString:key];
		[scan scanUpToString:@" " intoString:&newKey];
		if ([newKey hasSuffix:@"FinalRate"]) {
			if (!scan.atEnd) ageSpanIdx =
				[key substringFromIndex:scan.scanLocation + 1].integerValue;
			isAgeSpan = YES;
		} else {
			if (!scan.atEnd) vaxName = [key substringFromIndex:scan.scanLocation + 1];
			isVax = YES;
		}
		key = newKey;
	}
	ParamMenuIndex idx = {0, 0};
	NSString *gatName = nil;
	NSArray<NSArray<NSString *> *> *info = param_name_info();
	if ([key hasPrefix:@"regGat "]) {
		idx.cat = [cat_name_info() indexOfObject:@"regularGatherings"];
		NSArray<NSString *> *words = [key componentsSeparatedByString:@" "];
		idx.name = (words.count > 1)? [reg_gat_keys() indexOfObject:words[1]] : 0;
		if (words.count > 2) gatName = words[2];
		else return nil;
		MutableDictArray info = _world.gatheringsList;
		if ([gatName hasPrefix:@"__"]) {
			NSInteger idx = [gatName substringFromIndex:2].integerValue;
			if (idx < 0 || idx >= info.count) {
				error_msg([NSString stringWithFormat:
					@"No regular gathering No.%ld is found.", idx + 1], self.window, NO);
				return nil;
			}
		} else {
			BOOL found = NO;
			for (NSDictionary *gatItem in info) {
				NSString *name = gatItem[@"name"];
				if (name != nil && [gatName isEqualToString:name]) { found = YES; break; }
			}
			if (!found) {
				error_msg([NSString stringWithFormat:
					@"No regular gathering named %@ is found.", gatName], self.window, NO);
				return nil;
			}
		}
	} else {
		BOOL cont = YES;
		for (; idx.cat < info.count && cont; idx.cat ++)
			for (idx.name = 0; idx.name < info[idx.cat].count; idx.name ++)
				if ([key isEqualToString:info[idx.cat][idx.name]]) { cont = NO; break; }
		if (cont) return nil;
	}
	ParamItem *item = [ParamItem.alloc initWithScenario:self];
	ParameterCellView *cView = (ParameterCellView *)item.view;
	[item reviseNameMenuIfNeededTo:idx];
	[cView.categoryPopUp selectItemAtIndex:idx.cat];
	[cView.namePopUp selectItemAtIndex:idx.name];
	if (isVax) {
		if (vaxName != nil) {
			NSArray<NSDictionary *> *list = _world.vaccineList;
			int vt; for (vt = 0; vt < list.count; vt ++)
				if ([list[vt][@"name"] isEqualToString:vaxName]) break;
			if (vt < list.count) item.vcnType = vt;
			else [unknownNames addObject:vaxName];
		}
		if ([key hasSuffix:@"Priority"]) item.priority = ((NSNumber *)value).intValue;
		else cView.digits.doubleValue = ((NSNumber *)value).doubleValue;
	} else if ([value isKindOfClass:NSNumber.class]) {
		if (isAgeSpan) item.ageSpanIdx = ageSpanIdx;
		cView.digits.doubleValue = ((NSNumber *)value).doubleValue;
	} else if ([value isKindOfClass:NSArray.class]) {
		NSArray<NSNumber *> *arr = (NSArray<NSNumber *> *)value;
		item.distInfo = (DistInfo)
			{arr[0].doubleValue, arr[1].doubleValue, arr[2].doubleValue};
		[item setToolTipForDistBtn];
	}
	cView.days.doubleValue = (days == nil)? 0. : days.doubleValue;
	[cView adjustView:[item paramType:idx prmIdxReturn:NULL]];
	if (isAgeSpan) [cView.vcnAgeSpanPopUp selectItemAtIndex:ageSpanIdx + 1];
	else if (gatName) {
		NSPopUpButton *gnPopUp = cView.gatNamePopUp;
		if ([gatName hasPrefix:@"__"])
			[gnPopUp selectItemAtIndex:[gatName substringFromIndex:2].integerValue];
		else [gnPopUp selectItemWithTitle:gatName];
	}
	return item;
}
- (CondItem *)condItemFromObject:(NSObject *)elm label:(NSString *)label {
	CondItem *item;
	if ([elm isKindOfClass:NSString.class]) {
		item = [CondItem.alloc initWithScenario:self];
		item.element = [self itemWithPredicate:
			[NSPredicate predicateWithFormat:(NSString *)elm] parent:item];
	} else if ([elm isKindOfClass:NSPredicate.class]) {
		item = [CondItem.alloc initWithScenario:self];
		item.element = [self itemWithPredicate:(NSPredicate *)elm parent:item];
	} else return nil;
	if (label != nil) item.label = label;
	return item;
}
- (void)setScenarioWithArray:(NSArray *)array {
	unknownNames = NSMutableSet.new;
	NSMutableArray<ScenarioItem *> *ma = NSMutableArray.new;
	for (NSObject *elm in array) {
		ScenarioItem *item = nil;
		if ([elm isKindOfClass:NSArray.class]) {
			if (((NSArray *)elm).count == 0) continue;
			else if ([((NSArray *)elm)[0] isKindOfClass:NSNumber.class]) {
				if (((NSArray *)elm).count > 2) {	// add infected individuals
					item = [InfecItem.alloc initWithScenario:self];
					InfecCellView *view = (InfecCellView *)item.view;
					view.digits.integerValue = [((NSArray *)elm)[0] integerValue];
					NSInteger loc = [((NSArray *)elm)[1] isKindOfClass:NSNumber.class]?
						[((NSArray *)elm)[1] integerValue] : 0;
					[view.locationPopUp selectItemAtIndex:loc];
					NSString *varName = ((NSArray *)elm)[2];
					NSArray<NSDictionary *> *list = _world.variantList;
					NSInteger idx; for (idx = 0; idx < list.count; idx ++)
						if ([list[idx][@"name"] isEqualToString:varName]) break;
					if (idx < list.count) [view.variantPopUp selectItemAtIndex:idx];
					else [unknownNames addObject:varName];
				} else {	// goto N when ...
					item = [CondItem.alloc initWithScenario:self];
					if (((NSArray *)elm).count > 1) ((CondItem *)item).element =
						[self itemWithPredicate:
							[((NSArray *)elm)[1] isKindOfClass:NSString.class]?
								[NSPredicate predicateWithFormat:(NSString *)((NSArray *)elm)[1]] :
								(NSPredicate *)((NSArray *)elm)[1]
							parent:item];
					((CondItem *)item).destination = [((NSArray *)elm)[0] integerValue];
					[((CondCellView *)item.view).typePopUp selectItemAtIndex:CondTypeMoveWhen];
					[(CondCellView *)item.view adjustViews:CondTypeMoveWhen];
				}
			} else if (((NSArray *)elm).count < 2) continue;
			else if (![((NSArray *)elm)[0] isKindOfClass:NSString.class]) continue;
			else if ([((NSArray *)elm)[1] isKindOfClass:NSNumber.class] ||
				[((NSArray *)elm)[1] isKindOfClass:NSArray.class])
				item = [self paramItemWithKey:((NSArray *)elm)[0] value:((NSArray *)elm)[1]
					days:(((NSArray *)elm).count > 2)? ((NSArray *)elm)[2] : nil];
			else item = [self condItemFromObject:((NSArray *)elm)[1] label:((NSArray *)elm)[0]];
		} else if ([elm isKindOfClass:NSDictionary.class]) { // for upper compatibility
			for (NSString *key in ((NSDictionary *)elm).keyEnumerator) {
				item = [self paramItemWithKey:key value:((NSDictionary *)elm)[key] days:nil];
				if (item != nil) [ma addObject:item];
			}
			item = nil;
		} else if ([elm isKindOfClass:NSNumber.class]) { // for upper compatibility
			item = [InfecItem.alloc initWithScenario:self];
			((InfecCellView *)(item.view)).digits.integerValue = ((NSNumber *)elm).integerValue;
		} else item = [self condItemFromObject:elm label:nil];
		if (item == nil) continue;
		if ([item isKindOfClass:CondItem.class] && ((CondItem *)item).element != nil)
			for (NSButton *btn in item.btnsView.buttons)
				if (btn.title.length == 2) btn.enabled = NO;
		[ma addObject:item];
	}
	for (NSInteger i = 0; i < ma.count; i ++) {
		[ma[i] setupLineNumberView:i + 1];
		if ([ma[i] isKindOfClass:CondItem.class]) {
			CondItem *item = (CondItem *)ma[i];
			NSPopUpButton *pb = ((CondCellView *)item.view).destPopUp;
			adjust_num_menu(pb, ma.count);
			if (item.condType == CondTypeMoveWhen) [pb selectItemAtIndex:item.destination];
		}
	}
	[self setScenarioWithUndo:ma];
	if (unknownNames.count > 0) {
		NSMutableString *msg = [NSMutableString stringWithString:
			@"The following names of vaccines and variants were not in the current list."];
		NSString *pre = @"\n";
		for (NSString *name in unknownNames)
			{ [msg appendFormat:@"%@%@", pre, name]; pre = @", "; }
		error_msg(msg, self.window, NO);
	}
}
- (IBAction)loadDocument:(id)sender {
	NSWindow *window = self.window;
	load_property_data(@[@"sEpi", @"sEpS", @"json"], self.window, NULL,
		^(NSURL *url, NSObject *object) {
		if ([url.pathExtension isEqualToString:@"sEpi"]) {
			if (![object isKindOfClass:NSDictionary.class])
				{ error_msg(@"Property is invalid class.", window, NO); return; }
			else if ((object = ((NSDictionary *)object)[keyScenario]) == nil)
				{ error_msg([NSString stringWithFormat:@"%@ doesn't include scenario.",
					url.path], window, NO); return; }
		}
		if (![object isKindOfClass:NSArray.class])
			{ error_msg(@"Property is invalid class.", window, NO); return; }
		[self setScenarioWithArray:(NSArray *)object];
		self->savedPList = (NSArray *)object;
		self->applyBtn.enabled = YES;
	});
}
static NSArray *plist_of_all_items(NSArray *itemList) {
	NSMutableArray *ma = NSMutableArray.new;
	for (ScenarioItem *item in itemList) {
		NSObject *elm = item.propertyObject;
		if (elm != nil) [ma addObject:elm];
	}
	return ma;
}
- (IBAction)saveDocument:(id)sender {
	NSArray *ma = plist_of_all_items(itemList);
	save_property_data(@"sEpS", self.window, ma);
	savedPList = [NSArray arrayWithArray:ma];
}
- (IBAction)revertToSaved:(id)sender {
	if (savedPList != nil) [self setScenarioWithArray:savedPList];
}
- (IBAction)copy:(id)sender {
	copy_plist_as_JSON_text(plist_of_all_items(itemList), self.window);
}
- (IBAction)paste:(id)sender {
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	NSData *data = [pb dataForType:NSPasteboardTypeString];
	if (data == nil) return;
	NSError *error;
	NSArray *object = [NSJSONSerialization JSONObjectWithData:data
		options:0 error:&error];
	if (object == nil) { error_msg(error, self.window, NO); return; }
	if (![object isKindOfClass:NSArray.class])
		{ error_msg(@"Property is invalid class.", self.window, NO); return; }
	[self setScenarioWithArray:object];
	self->savedPList = object;
	self->applyBtn.enabled = YES;
}
- (IBAction)remove:(id)sender {
	[_world setScenario:@[] index:0];
}
- (IBAction)apply:(id)sender {
	NSMutableArray *ma = NSMutableArray.new;
	for (ScenarioItem *item in itemList) {
		NSObject *elm = item.scenarioElement;
		if (elm != nil) [ma addObject:elm];
	}
	NSInteger scenIndex = 0;
	if (orgIndexes != nil) {
		CondItem *item = orgIndexes[@(_world.scenarioIndex)];
		if (item != nil) {
			NSInteger idx = [itemList indexOfObject:item];
			if (idx != NSNotFound) scenIndex = idx + 1;
	}}
	[_world setScenario:[NSArray arrayWithArray:ma] index:scenIndex];
	[_world setupPhaseInfo];
	[self makeOrgIndexes];
	appliedCount = modificationCount;
	applyBtn.enabled = NO;
	removeBtn.enabled = ma.count > 0;
}
- (IBAction)ok:(NSButton *)button {
	[distParamSheet orderOut:nil];
}
- (void)distParamBySheetWithItem:(ParamItem *)item value:(DistInfo *)info {
	if (distParamSheet.isVisible && distDigits.distInfo == info) { [self ok:nil]; return; }
	ParameterCellView *view = (ParameterCellView *)item.view;
	distParamSheet.title = [NSString stringWithFormat:@"%ld %@",
		[itemList indexOfObject:item] + 1, view.namePopUp.titleOfSelectedItem];
	if (distDigits == nil) distDigits =
		[DistDigits.alloc initWithDigits:@[minDgt, maxDgt, modeDgt] tabView:nil
			callBack:^{ [item setToolTipForDistBtn]; }];
	distDigits.distInfo = info;
	[distDigits adjustDigitsToCurrentValue];
	NSPoint pt = [self.window convertPointToScreen:
		[view.distBtn convertPoint:(NSPoint){NSMidX(view.distBtn.bounds), 0.}
			toView:self.window.contentView]];
	[distParamSheet setFrameOrigin:(NSPoint){pt.x - distParamSheet.frame.size.width / 2, pt.y}];
	[distParamSheet makeKeyAndOrderFront:nil];
}
// NSWindowDelagate methods
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return _undoManager;
}
// NSTextFieldDelegate to enable undoing
- (void)controlTextDidBeginEditing:(NSNotification *)note {
	NSTextField *dgt = note.object;
	valueDict[@((NSUInteger)dgt)] = @(dgt.doubleValue);
}
- (void)controlTextDidEndEditing:(NSNotification *)note {
	NSTextField *dgt = note.object;
	NSNumber *key = @((NSUInteger)dgt);
	CGFloat value = valueDict[key].doubleValue;
	[valueDict removeObjectForKey:key];
	if (value == dgt.doubleValue) return;
	[_undoManager registerUndoWithTarget:dgt handler:^(NSTextField *target) {
		[target changeDoubleUndoable:value undoManager:self.undoManager]; }];
}
// NSOutlineViewDataSource methods
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(ScenarioItem *)item {
	return (item == nil)? itemList[index] :
		[item isKindOfClass:CondItem.class]? ((CondItem *)item).element :
		[item isKindOfClass:CompoundItem.class]? ((CompoundItem *)item).children[index] :
		nil;
}
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(ScenarioItem *)item {
	return ([item isKindOfClass:CondItem.class] && ((CondItem *)item).element != nil) ||
		([item isKindOfClass:CompoundItem.class] && ((CompoundItem *)item).children.count > 0);
}
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(ScenarioItem *)item {
	return (item == nil)? itemList.count :
		[item isKindOfClass:CondItem.class]? (((CondItem *)item).element != nil)? 1 : 0 :
		[item isKindOfClass:CompoundItem.class]? ((CompoundItem *)item).children.count : 0;
}
// NSOutlineViewDelagate methods
- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:
	(NSTableColumn *)tableColumn item:(ScenarioItem *)item {
	NSString *idStr = tableColumn.identifier;
	if ([idStr isEqualToString:@"LineNumber"]) return item.lnView;
	else if ([idStr isEqualToString:@"Content"]) return item.view;
	else if ([idStr isEqualToString:@"Buttons"]) return item.btnsView;
	else return nil;
}
//- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
//	return [item isKindOfClass:ParamItem.class] ||
//		[item isKindOfClass:CondItem.class] ||
//		[item isKindOfClass:InfecItem.class];
//}
- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
	[self checkSelection];
}
@end
