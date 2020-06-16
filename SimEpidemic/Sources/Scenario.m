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
#define CELL_SIZE {347, 24}
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
static CGFloat maxWidthOfParamName = 0.;
- (instancetype)init {
	NSSize fSize = CELL_SIZE;
	if (!(self = [super initWithFrame:(NSRect){0, 0, fSize}])) return nil;
	set_subview(label_field(@"Parameters"), self, YES);
	_namePopUp = NSPopUpButton.new; 
	for (NSString *title in paramNames) {
		if ([paramKeyFromName[title] isEqualTo:@"initPop"]) break;
		[_namePopUp addItemWithTitle:title];
	}
	set_subview(_namePopUp, self, YES);
	if (maxWidthOfParamName == 0.) maxWidthOfParamName = _namePopUp.frame.size.width;
	return self;
}
@end
@implementation ParamElmCellView
- (instancetype)initWithKey:(NSString *)key value:(CGFloat)value {
	NSSize fSize = CELL_SIZE;
	if (!(self = [super initWithFrame:(NSRect){0, 0, fSize}])) return nil;
	NSTextField *nameLabel = label_field(key);
	nameLabel.alignment = NSTextAlignmentRight;
	set_subview(nameLabel, self, YES);
	NSSize sz = nameLabel.frame.size;
	sz.width = maxWidthOfParamName;
	[nameLabel setFrameSize:sz];
	_digits = NSTextField.new;
	_digits.formatter = paramFormatters[paramIndexFromKey[key].integerValue] ;
	_digits.doubleValue = 999.9;
	set_subview(_digits, self, YES);
	_digits.doubleValue = value;
	return self;
}
@end
@interface CondCellView : NSTableCellView
@end
@implementation CondCellView
- (instancetype)init {
	NSSize fSize = CELL_SIZE;
	if (!(self = [super initWithFrame:(NSRect){0, 0, fSize}])) return nil;
	set_subview(label_field(@"Condition"), self, YES);
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
@interface ComparisonCellView : NSTableCellView {
	__weak NSNumberFormatter *intFormatter;
	NSInteger maxValue;
	CGFloat ratioValue;
}
@property NSInteger days;
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
- (instancetype)initWithFormatter:(NSNumberFormatter *)fmt {
	NSSize fSize = CELL_SIZE;
	if (!(self = [super initWithFrame:(NSRect){0, 0, fSize}])) return nil;
	intFormatter = fmt;
	if (absIntFormatter == nil) {
		absIntFormatter = NSNumberFormatter.new;
		absIntFormatter.minimum = @0;
		percentFormatter = NSNumberFormatter.new;
		percentFormatter.minimum = @(0.);
		percentFormatter.maximum = @(100.);
		percentFormatter.minimumFractionDigits =
		percentFormatter.maximumFractionDigits = 3;
	}
	maxValue = fmt.maximum.integerValue;
	ratioValue = .5;
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
	_digits.integerValue = _days = 180;
	_digits.formatter = absIntFormatter;
	_digits.delegate = (NSObject<NSTextFieldDelegate> *)self;
	_varPopUp.target = _unitPopUp.target = self;
	_varPopUp.action = @selector(chooseVariable:);
	_unitPopUp.action = @selector(chooseUnit:);
	_unitPopUp.enabled = NO;
	return self;
}
- (NSInteger)intValue { return maxValue * ratioValue; }
- (void)setIntValue:(NSInteger)val {
	ratioValue = (CGFloat)val / maxValue;
	if  (_unitPopUp.indexOfSelectedItem == 0)
		_digits.integerValue = self.intValue;
	else _digits.doubleValue = ratioValue * 1000.;
}
- (void)chooseUnit:(id)sender {
	if (_unitPopUp.indexOfSelectedItem == 0) {
		_digits.formatter = intFormatter;
		_digits.integerValue = self.intValue;
	} else {
		_digits.formatter = percentFormatter;
		_digits.doubleValue = ratioValue * 1000.;
	}
}
- (void)chooseVariable:(id)sender {
	BOOL isAbsValue = (_varPopUp.indexOfSelectedItem == 0);
	if (_unitPopUp.enabled == isAbsValue) {
		_unitPopUp.enabled = !isAbsValue;
		if (isAbsValue) {
			_digits.formatter = absIntFormatter;
			_digits.integerValue = _days;
		} else [self chooseUnit:nil];
	}
}
- (void)controlTextDidEndEditing:(NSNotification *)obj {
	if (_varPopUp.indexOfSelectedItem == 0)
		_days = _digits.integerValue;
	else ratioValue = (_unitPopUp.indexOfSelectedItem == 0)?
		(CGFloat)_digits.integerValue / maxValue : _digits.doubleValue / 1000.;
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

@interface ParamElmItem : ScenarioItem
@property NSInteger index;
@end
@implementation ParamElmItem
- (instancetype)initWithScenario:(Scenario *)scen index:(NSInteger)index value:(NSInteger)value {
	if (!(self = [super initWithScenario:scen])) return nil;
	[super setupButtonView:@[removeImage]];
	self.view = [ParamElmCellView.alloc initWithKey:paramNames[index] value:value];
	_index = index;
	return self;
}
- (NSInteger)value { return ((ParamElmCellView *)self.view).digits.integerValue; }
@end
@interface ParamItem : ScenarioItem
@property NSMutableArray<ParamElmItem *> *children;
@end
@implementation ParamItem
- (instancetype)initWithScenario:(Scenario *)scen {
	if (!(self = [super initWithScenario:scen])) return nil;
	[super setupButtonView:@[removeImage, addImage]];
	self.view = ParameterCellView.new;
	_children = NSMutableArray.new;
	NSPopUpButton *namePopUp = ((ParameterCellView *)self.view).namePopUp;
	namePopUp.target = self;
	namePopUp.action = @selector(dummyAction:);
	return self;
}
- (ScenarioItem *)childItemAt:(NSInteger)idx {
	return (idx >= 0 && idx < _children.count)? _children[idx] : nil;
}
- (void)addChild:(ParamElmItem *)item {
	ParameterCellView *pView = (ParameterCellView *)self.view;
	NSInteger index = item.index, aIdx;
	for (aIdx = 0; aIdx < _children.count; aIdx ++) {
		NSInteger cIndex = _children[aIdx].index;
		if (cIndex == index) return;
		else if (cIndex > index) break;
	}
	[_children insertObject:item atIndex:aIdx];
	pView.namePopUp.selectedItem.tag = 1;
	[scenario.outlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:aIdx]
		inParent:self withAnimation:NSTableViewAnimationEffectFade];
	[scenario.outlineView expandItem:self];
	NSInteger nParams = pView.namePopUp.numberOfItems;
	if (_children.count < nParams) {
		NSArray<NSMenuItem *> *mnItems = pView.namePopUp.itemArray;
		NSInteger nextIndex = 0;
		for (NSInteger i = 1; i < nParams; i ++)
			if (mnItems[(nextIndex = (index + i) % nParams)].tag == 0) break;
		[pView.namePopUp selectItemAtIndex:nextIndex];
	} else self.btnsView.buttons[1].enabled = pView.namePopUp.enabled = NO;
	[scenario.undoManager registerUndoWithTarget:self handler:
		^(ParamItem *prmItem) { [prmItem removeChild:item]; }];
}
- (BOOL)removeChild:(ParamElmItem *)item {
	NSInteger index = [_children indexOfObject:item];
	if (index == NSNotFound) return NO;
	NSPopUpButton *namePopUp = ((ParameterCellView *)self.view).namePopUp;
	if (_children.count == namePopUp.numberOfItems) {
		self.btnsView.buttons[1].enabled = namePopUp.enabled = YES;
		[namePopUp selectItemAtIndex:item.index];
	}
	[namePopUp.menu itemAtIndex:item.index].tag = 0;
	[_children removeObjectAtIndex:index];
	[scenario.outlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:index]
		inParent:self withAnimation:NSTableViewAnimationEffectFade];
	[scenario.undoManager registerUndoWithTarget:self handler:
		^(ParamItem *prmItem) { [prmItem addChild:item]; }];
	return YES;
}
- (void)buttonAction:(NSButton *)button {
	if (button.image == addImage) {
		ParameterCellView *pView = (ParameterCellView *)self.view;
		NSInteger index = pView.namePopUp.indexOfSelectedItem;
		[self addChild:[ParamElmItem.alloc initWithScenario:scenario index:index
			value:((CGFloat *)scenario.doc.paramsP)[index]]];
	} else [super buttonAction:button];
}
- (void)dummyAction:(id)sender {}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	return menuItem.tag == 0;
}
- (NSObject *)scenarioElement {
	NSInteger n = _children.count;
	NSString *keys[n]; NSNumber *vals[n];
	for (NSInteger i = 0; i < n; i ++) {
		keys[i] = paramKeys[_children[i].index];
		vals[i] = @(_children[i].value);
	}
	return [NSDictionary dictionaryWithObjects:vals forKeys:keys count:n];
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
	self.view = [ComparisonCellView.alloc initWithFormatter:scen.intFormatter];
	return self;
}
- (NSPredicate *)predicate {
	ComparisonCellView *v = (ComparisonCellView *)self.view;
	NSInteger index = v.varPopUp.indexOfSelectedItem;
	return [NSComparisonPredicate.alloc initWithLeftExpression:
		[NSExpression expressionForKeyPath:varNames[index]]
		rightExpression:[NSExpression expressionForConstantValue:
			@((index == 0)? v.days : v.intValue)]
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
	if (index == 0) v.days = num.integerValue;
	else v.intValue = num.integerValue;
	NSPredicateOperatorType opeType = predicate.predicateOperatorType;
	for (index = 0; index < N_OPERATORS; index ++)
		if (operatorTypes[index] == opeType) break;
	[v.opePopUp selectItemAtIndex:index];
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
	self.view = CompoundCellView.new;
	_children = NSMutableArray.new;
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
@implementation CondItem
- (instancetype)initWithScenario:(Scenario *)scen {
	if (!(self = [super initWithScenario:scen])) return nil;
	[super setupButtonView:@[removeImage, @"+P", @"+C"]];
	self.view = CondCellView.new;
	return self;
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
- (NSObject *)scenarioElement { return _element.predicate; }
- (NSObject *)propertyObject { return _element.predicate.predicateFormat; }
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
	itemList = NSMutableArray.new;
	_intFormatter = NSNumberFormatter.new;
	_intFormatter.minimum = @0;
	_intFormatter.maximum = @(dc.paramsP->initPop);
	return self;
}
- (void)windowDidLoad {
    [super windowDidLoad];
    [_doc setPanelTitle:self.window];
}
- (void)removeItem:(ScenarioItem *)item {
	if ([item isKindOfClass:ParamItem.class] ||
		[item isKindOfClass:CondItem.class] || [item isKindOfClass:InfecItem.class]) {
		[self removeItemAtIndex:[itemList indexOfObject:item]];
	} else if ([item isKindOfClass:ParamElmItem.class]) {
		for (ScenarioItem *parent in itemList)
		if ([parent isKindOfClass:ParamItem.class] &&
			[(ParamItem *)parent removeChild:(ParamElmItem *)item]) break;
	} else if ([item isKindOfClass:CondElmItem.class])
		[((CondElmItem *)item).parent removeChild:item];
}
//
- (void)setScenarioWithUndo:(NSMutableArray<ScenarioItem *> *)new {
	NSMutableArray<ScenarioItem *> *org = itemList;
	[_undoManager registerUndoWithTarget:self handler:
		^(Scenario *target) { [target setScenarioWithUndo:org]; }];
	if (org.count > 0) [_outlineView removeItemsAtIndexes:
		[NSIndexSet indexSetWithIndexesInRange:(NSRange){0, org.count}]
		inParent:nil withAnimation:NSTableViewAnimationEffectFade];
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
	[_undoManager registerUndoWithTarget:self handler:
		^(Scenario *scen) { [scen insertItem:orgItem atIndex:idx]; }];
	[itemList removeObjectAtIndex:idx];
	[_outlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:idx]
		inParent:nil withAnimation:NSTableViewAnimationEffectFade];
}
- (void)insertItem:(ScenarioItem *)item atIndex:(NSInteger)idx {
	[_undoManager registerUndoWithTarget:self handler:
		^(Scenario *scen) { [scen removeItemAtIndex:idx]; }];
	[itemList insertObject:item atIndex:idx];
	[_outlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:idx]
		inParent:nil withAnimation:NSTableViewAnimationEffectFade];
}
- (void)addTopLevelItem:(ScenarioItem *)item {
	NSInteger row = _outlineView.selectedRow, index;
	if (row >= 0) {
		index = [itemList indexOfObject:[_outlineView itemAtRow:row]];
		if (index == NSNotFound) index = itemList.count;
	} else index = itemList.count;
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
		if ([item isKindOfClass:ParamElmItem.class])
			[self.window makeFirstResponder:((ParamElmCellView *)item.view).digits];
		else if ([item isKindOfClass:CompoundItem.class])
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
- (void)setScenarioWithArray:(NSArray *)array {
	NSMutableArray<ScenarioItem *> *ma = NSMutableArray.new;
	for (NSObject *elm in array) {
		ScenarioItem *item = nil;
		if ([elm isKindOfClass:NSDictionary.class]) {
			item = [ParamItem.alloc initWithScenario:self];
			for (NSString *key in ((NSDictionary *)elm).keyEnumerator) {
				NSInteger index;
				for (index = 0; index < paramKeys.count; index ++)
					if ([key isEqualToString:paramKeys[index]]) break;
				[((ParamItem *)item).children addObject:[ParamElmItem.alloc
					initWithScenario:self index:index
						value:[((NSDictionary *)elm)[key] integerValue]]];
			}
		} else if ([elm isKindOfClass:NSString.class]) {
			item = [CondItem.alloc initWithScenario:self];
			((CondItem *)item).element = [self itemWithPredicate:
				[NSPredicate predicateWithFormat:(NSString *)elm] parent:item];
		} else if ([elm isKindOfClass:NSNumber.class]) {
			item = [InfecItem.alloc initWithScenario:self];
			((InfecCellView *)(item.view)).digits.integerValue = ((NSNumber *)elm).integerValue;
		}
		if (item != nil) [ma addObject:item];
	}
	[self setScenarioWithUndo:ma];
}
- (IBAction)loadDocument:(id)sender {
	load_property_data(@"sEpS", self.window, NSArray.class, ^(NSObject *object) {
		[self setScenarioWithArray:(NSArray *)object];
		self->savedPList = (NSArray *)object;
	});
}
- (IBAction)saveDocument:(id)sender {
	NSMutableArray *ma = NSMutableArray.new;
	for (ScenarioItem *item in itemList) [ma addObject:item.propertyObject];
	save_property_data(@"sEpS", self.window, ma);
	savedPList = [NSArray arrayWithArray:ma];
}
- (IBAction)revertToSaved:(id)sender {
	if (savedPList != nil) [self setScenarioWithArray:savedPList];
}
- (IBAction)apply:(id)sender {
	NSMutableArray *ma = NSMutableArray.new;
	if (enabledCBox.state == NSControlStateValueOn) {
		for (ScenarioItem *item in itemList) {
			NSObject *elm = item.scenarioElement;
			if (elm != nil) [ma addObject:elm];
		}
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
		[item isKindOfClass:ParamItem.class]? [(ParamItem *)item childItemAt:index] :
		[item isKindOfClass:CondItem.class]? ((CondItem *)item).element :
		[item isKindOfClass:CompoundItem.class]? ((CompoundItem *)item).children[index] :
		nil;
}
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(ScenarioItem *)item {
	return ([item isKindOfClass:ParamItem.class] && ((ParamItem *)item).children.count > 0) ||
		([item isKindOfClass:CondItem.class] && ((CondItem *)item).element != nil) ||
		([item isKindOfClass:CompoundItem.class] && ((CompoundItem *)item).children.count > 0);
}
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(ScenarioItem *)item {
	return (item == nil)? itemList.count :
		[item isKindOfClass:ParamItem.class]? ((ParamItem *)item).children.count:
		[item isKindOfClass:CondItem.class]? (((CondItem *)item).element != nil)? 1 : 0 :
		[item isKindOfClass:CompoundItem.class]? ((CompoundItem *)item).children.count : 0;
}
// NSOutlineViewDelagate methods
- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:
	(NSTableColumn *)tableColumn item:(ScenarioItem *)item {
	NSString *idStr = tableColumn.identifier;
	if ([idStr isEqualToString:@"Content"]) return item.view;
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
