//
//  Scenario.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/17.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "Scenario.h"
#import "AppDelegate.h"
#import "Document.h"
#import "StatPanel.h"

@implementation StatInfo (PredicateExtension)
- (NSInteger)days { return days; }
- (NSInteger)susceptible { return self.statistics->cnt[Susceptible]; }
- (NSInteger)infected { return self.statistics->cnt[Asymptomatic]; }
- (NSInteger)symptomatic { return self.statistics->cnt[Symptomatic]; }
- (NSInteger)recovered { return self.statistics->cnt[Recovered]; }
- (NSInteger)died { return self.statistics->cnt[Died]; }
- (NSInteger)quarantine {
	NSUInteger *q = &self.statistics->cnt[QuarantineAsym];
	return q[0] + q[1];
}
- (NSInteger)dailyInfection { return self.transit->cnt[Asymptomatic]; }
- (NSInteger)dailySymptomatic { return self.transit->cnt[Symptomatic]; }
- (NSInteger)dailyRecovery { return self.transit->cnt[Recovered]; }
- (NSInteger)dailyDeath { return self.transit->cnt[Died]; }
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
#define BUTTON_CELL_SIZE {135, 24}
#define LINEN_CELL_SIZE {30, 24}
#define CELL_SIZE {346, 24}
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

@implementation ParameterCellView
- (instancetype)initWithValue:(CGFloat)value {
	NSSize fSize = CELL_SIZE;
	if (!(self = [super initWithFrame:(NSRect){0, 0, fSize}])) return nil;
	set_subview(label_field(@"Parameters"), self, YES);
	_namePopUp = NSPopUpButton.new; 
	for (NSString *title in paramNames) {
		if ([paramKeyFromName[title] isEqualTo:@"initPop"]) break;
		[_namePopUp addItemWithTitle:title];
	}
	set_subview(_namePopUp, self, YES);
	set_subview(label_field(@"⇐"), self, YES);
	_digits = NSTextField.new;
	_digits.doubleValue = 999.9;
	set_subview(_digits, self, YES);
	_digits.doubleValue = value;
	[_namePopUp selectItemAtIndex:0];
	return self;
}
@end
@interface CondCellView : NSTableCellView
@property (readonly) NSPopUpButton *typePopUp, *destPopUp;
@property (readonly) NSTextField *sufixTxt;
@end
static NSPoint CCTxtOrg1 = {0,0}, CCTxtOrg2;
@implementation CondCellView
- (void)adjustViews:(NSInteger)index {
	switch (index) {
		case 0: _destPopUp.hidden = YES;
		_sufixTxt.stringValue = NSLocalizedString(@"satisfied", nil);
		[_sufixTxt setFrameOrigin:CCTxtOrg1];
		break;
		case 1: _destPopUp.hidden = NO;
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
@property (readonly) NSTextField *digits;
@end
@implementation ComparisonCellView
#define N_VARIABLES 11
static NSString *varNames[] = {@"days", @"susceptible", @"infected", @"symptomatic",
	@"recovered", @"died", @"quarantine",
	@"dailyInfection", @"dailySymptomatic", @"dailyRecovery", @"dailyDeath"};
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
	_digits.formatter = absIntFormatter;
	return self;
}
@end

@interface InfecCellView : NSTableCellView
@property (readonly) NSTextField *digits;
@end
@implementation InfecCellView
- (instancetype)init {
	NSSize fSize = CELL_SIZE;
	if (!(self = [super initWithFrame:(NSRect){0, 0, fSize}])) return nil;
	set_subview(label_field(@"Infection"), self, YES);
	_digits = NSTextField.new;
	_digits.stringValue = @"99999";
	set_subview(_digits, self, YES);
	_digits.integerValue = 1;
	return self;
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

@interface ParamItem : ScenarioItem
@property NSInteger index;
@end
@implementation ParamItem
- (instancetype)initWithScenario:(Scenario *)scen {
	if (!(self = [super initWithScenario:scen])) return nil;
	[super setupButtonView:@[removeImage]];
	self.view = [ParameterCellView.alloc initWithValue:scen.doc.runtimeParamsP->PARAM_F1];
	NSPopUpButton *namePopUp = ((ParameterCellView *)self.view).namePopUp;
	namePopUp.target = self;
	namePopUp.action = @selector(chooseParameter:);
	return self;
}
- (void)setParamUndoable:(NSInteger)newIndex value:(CGFloat)newValue {
	NSInteger orgIndex = _index;
	CGFloat orgValue = ((ParameterCellView *)self.view).digits.doubleValue;
	[scenario.undoManager registerUndoWithTarget:self handler:
		^(ParamItem *target) { [target setParamUndoable:orgIndex value:orgValue]; }];
	if (newIndex >= 0) [((ParameterCellView *)self.view).namePopUp selectItemAtIndex:newIndex];
	else _index = newIndex;
	((ParameterCellView *)self.view).digits.doubleValue = newValue;
}
- (void)chooseParameter:(NSPopUpButton *)sender {
	NSInteger idx = sender.indexOfSelectedItem;
	if (idx == _index) return;
	[self setParamUndoable:-1 value:(&scenario.doc.runtimeParamsP->PARAM_F1)[idx]];
	_index = idx;
}
- (CGFloat)value { return ((ParameterCellView *)self.view).digits.doubleValue; }
- (NSObject *)scenarioElement {
	return @[paramKeys[_index], @(self.value)];
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
	v.digits.delegate = (NSObject<NSTextFieldDelegate> *)self;
	v.varPopUp.target = v.unitPopUp.target = self;
	v.varPopUp.action = @selector(chooseVariable:);
	v.unitPopUp.action = @selector(chooseUnit:);
	v.unitPopUp.enabled = NO;
	return self;
}
- (NSPredicate *)predicate {
	ComparisonCellView *v = (ComparisonCellView *)self.view;
	NSInteger index = v.varPopUp.indexOfSelectedItem;
	return [NSComparisonPredicate.alloc initWithLeftExpression:
		[NSExpression expressionForKeyPath:varNames[index]]
		rightExpression:[NSExpression expressionForConstantValue:
			@((index == 0)? days : self.intValue)]
		modifier:0 type:operatorTypes[v.opePopUp.indexOfSelectedItem] options:0];
}
- (void)setupWithPredicate:(NSComparisonPredicate *)predicate {
	ComparisonCellView *v = (ComparisonCellView *)self.view;
	NSString *varName = predicate.leftExpression.keyPath;
	NSInteger index;
	for (index = 0; index < N_VARIABLES; index ++)
		if ([varName isEqualToString:varNames[index]]) break;
	[v.varPopUp selectItemAtIndex:index];
	v.unitPopUp.enabled = index > 0;
	NSNumber *num = predicate.rightExpression.constantValue;
	if (index == 0) days = num.integerValue;
	else self.intValue = num.integerValue;
	NSPredicateOperatorType opeType = predicate.predicateOperatorType;
	for (index = 0; index < N_OPERATORS; index ++)
		if (operatorTypes[index] == opeType) break;
	[v.opePopUp selectItemAtIndex:index];
}
- (NSInteger)intValue { return maxValue * ratioValue; }
- (void)setIntValue:(NSInteger)val {
	ComparisonCellView *v = (ComparisonCellView *)self.view;
	ratioValue = (CGFloat)val / maxValue;
	if  (v.unitPopUp.indexOfSelectedItem == 0)
		v.digits.integerValue = self.intValue;
	else v.digits.doubleValue = ratioValue * 1000.;
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
	BOOL isAbsValue = (newIndex == 0);
	if (v.unitPopUp.enabled == isAbsValue) {
		v.unitPopUp.enabled = !isAbsValue;
		if (isAbsValue) {
			v.digits.formatter = absIntFormatter;
			v.digits.integerValue = days;
		} else [self chooseUnit:nil];
	}
}
- (void)setDays:(NSInteger)newDays digits:(NSTextField *)digits {
	NSInteger orgDays = days;
	[scenario.undoManager registerUndoWithTarget:self handler:^(ComparisonItem *item) {
		digits.integerValue = orgDays;
		[item setDays:orgDays digits:digits];
	}];
	days = newDays;
}
- (void)setRatio:(CGFloat)newRatio digits:(NSTextField *)digits isAbs:(BOOL)isAbs {
	NSInteger orgInt = ratioValue * maxValue;
	CGFloat orgRatio = ratioValue;
	[scenario.undoManager registerUndoWithTarget:self handler:^(ComparisonItem *item) {
		if (isAbs) digits.integerValue = orgInt;
		else digits.doubleValue = orgRatio * 1000.;
		[item setRatio:orgRatio digits:digits isAbs:isAbs];
	}];
	ratioValue = newRatio;
}
- (void)controlTextDidEndEditing:(NSNotification *)obj {
	ComparisonCellView *v = (ComparisonCellView *)self.view;
	if (v.varPopUp.indexOfSelectedItem == 0) {
		NSInteger newDays = v.digits.integerValue;
		if (newDays != days) [self setDays:newDays digits:v.digits];
	} else {
		BOOL isAbs = (v.unitPopUp.indexOfSelectedItem == 0);
		CGFloat newRatio = isAbs?
			(CGFloat)v.digits.integerValue / maxValue : v.digits.doubleValue / 1000.;
		if (newRatio != ratioValue)
			[self setRatio:newRatio digits:v.digits isAbs:isAbs];
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
	if (m > n) for (NSInteger i = n; i < m; i ++) [pb removeItemAtIndex:i];
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
	adjust_num_menu(v.destPopUp, scen.numberOfItems);
	return self;
}
- (NSInteger)condType { return condType; }
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
	return (condType == CondTypeRunUntil)? element :
		(element != nil)? @[@(destination), element] : @[@(destination)];
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
	self.view = InfecCellView.new;
	return self;
}
- (NSObject *)scenarioElement {
	return @(((InfecCellView *)self.view).digits.integerValue);
}
@end

@interface Scenario () {
	NSMutableArray<ScenarioItem *> *itemList;
	NSArray *savedPList;
}
@end
@implementation Scenario
- (instancetype)initWithDoc:(Document *)dc {
	if (!(self = [super initWithWindowNibName:@"Scenario"])) return nil;
	check_images();
	_doc = dc;
	_undoManager = NSUndoManager.new;
	_intFormatter = NSNumberFormatter.new;
	_intFormatter.minimum = @0;
	_intFormatter.maximum = @(dc.worldParamsP->initPop);
	return self;
}
- (void)adjustControls {
	removeBtn.enabled = applyBtn.enabled = !_doc.running;
}
- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.alphaValue = panelsAlpha;
    [_doc setPanelTitle:self.window];
	removeBtn.toolTip = NSLocalizedString(@"Remove scenario from the simulator", nil);
	applyBtn.toolTip = NSLocalizedString(@"Apply this scenario to the simulator", nil);
    if (_doc.scenario != nil) [self setScenarioWithArray:_doc.scenario];
    else itemList = NSMutableArray.new;
    [self adjustControls];
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
	[_undoManager registerUndoWithTarget:self handler:
		^(Scenario *scen) { [scen insertItem:orgItem atIndex:idx]; }];
	[_outlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:idx]
		inParent:nil withAnimation:NSTableViewAnimationEffectFade];
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
- (void)checkSelection {
	NSInteger row = _outlineView.selectedRow;
	if (row < 0) { shiftUpBtn.enabled = shiftDownBtn.enabled = NO; return; }
	ScenarioItem *item = [_outlineView itemAtRow:row];
	NSInteger index = [itemList indexOfObject:item];
	if (index == NSNotFound) {
		shiftUpBtn.enabled = shiftDownBtn.enabled = NO;
		if ([item isKindOfClass:CompoundItem.class])
			[self.window makeFirstResponder:((CompoundCellView *)item.view).opePopUp];
		else if ([item isKindOfClass:ComparisonItem.class])
			[self.window makeFirstResponder:((ComparisonCellView *)item.view).varPopUp];
	} else if (index == 0) { shiftUpBtn.enabled = NO; shiftDownBtn.enabled = YES; }
	else if (index == itemList.count - 1)
		{ shiftUpBtn.enabled = YES; shiftDownBtn.enabled = NO; }
	else shiftUpBtn.enabled = shiftDownBtn.enabled = YES;
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
- (ParamItem *)paramItemWithKey:(NSString *)key value:(NSNumber *)num {
	NSInteger idx = [paramKeys indexOfObject:key];
	if (idx == NSNotFound) return nil;
	ParamItem *item = [ParamItem.alloc initWithScenario:self];
	((ParamItem *)item).index = idx;
	ParameterCellView *cView = (ParameterCellView *)item.view;
	[cView.namePopUp selectItemAtIndex:idx];
	cView.digits.doubleValue = num.doubleValue;
	return item;
}
- (void)setScenarioWithArray:(NSArray *)array {
	NSMutableArray<ScenarioItem *> *ma = NSMutableArray.new;
	for (NSObject *elm in array) {
		ScenarioItem *item = nil;
		if ([elm isKindOfClass:NSArray.class]) {
			if ([((NSArray *)elm)[0] isKindOfClass:NSString.class])
				item = [self paramItemWithKey:((NSArray *)elm)[0] value:((NSArray *)elm)[1]];
			else if ([((NSArray *)elm)[0] isKindOfClass:NSNumber.class]) {
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
		} else if ([elm isKindOfClass:NSDictionary.class]) { // for upper compatibility
			for (NSString *key in ((NSDictionary *)elm).keyEnumerator) {
				item = [self paramItemWithKey:key value:((NSDictionary *)elm)[key]];
				[ma addObject:item];
			}
			item = nil;
		} else if ([elm isKindOfClass:NSString.class]) {
			item = [CondItem.alloc initWithScenario:self];
			((CondItem *)item).element = [self itemWithPredicate:
				[NSPredicate predicateWithFormat:(NSString *)elm] parent:item];
		} else if ([elm isKindOfClass:NSPredicate.class]) {
			item = [CondItem.alloc initWithScenario:self];
			((CondItem *)item).element = [self itemWithPredicate:(NSPredicate *)elm parent:item];
		} else if ([elm isKindOfClass:NSNumber.class]) {
			item = [InfecItem.alloc initWithScenario:self];
			((InfecCellView *)(item.view)).digits.integerValue = ((NSNumber *)elm).integerValue;
		}
		if (item != nil) [ma addObject:item];
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
}
- (IBAction)loadDocument:(id)sender {
	NSWindow *window = self.window;
	load_property_data(@[@"sEpi", @"sEpS"], self.window, NULL,
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
	});
}
- (IBAction)saveDocument:(id)sender {
	NSMutableArray *ma = NSMutableArray.new;
	for (ScenarioItem *item in itemList) {
		NSObject *elm = item.propertyObject;
		if (elm != nil) [ma addObject:item.propertyObject];
	}
	save_property_data(@"sEpS", self.window, ma);
	savedPList = [NSArray arrayWithArray:ma];
}
- (IBAction)revertToSaved:(id)sender {
	if (savedPList != nil) [self setScenarioWithArray:savedPList];
}
- (IBAction)remove:(id)sender {
	_doc.scenario = NSMutableArray.new;
}
- (IBAction)apply:(id)sender {
	NSMutableArray *ma = NSMutableArray.new;
	for (ScenarioItem *item in itemList) {
		NSObject *elm = item.scenarioElement;
		if (elm != nil) [ma addObject:elm];
	}
	_doc.scenario = [NSArray arrayWithArray:ma];
}
// NSWindowDelagate methods
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return _undoManager;
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
