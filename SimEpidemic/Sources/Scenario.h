//
//  Scenario.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/17.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CommonTypes.h"

NS_ASSUME_NONNULL_BEGIN
typedef enum { CondTypeRunUntil, CondTypeMoveWhen } CondType;
typedef enum { VarAbsolute, VarNIndividuals, VarRate } VariableType;
@class Document, Scenario, ButtonsCellView, ParamItem;

@interface ParameterCellView : NSTableCellView
@property (readonly) NSPopUpButton *namePopUp;
@property (readonly) NSButton *distBtn;
@property (readonly) NSTextField *digits, *days;
@end
@interface ScenarioItem : NSObject {
	Scenario *scenario;
}
@property NSTableCellView *view;
@property (readonly) NSTableCellView *lnView;
@property (readonly) ButtonsCellView *btnsView;
- (void)buttonAction:(NSButton *)button;
@end
@interface CondElmItem : ScenarioItem
@property (weak) ScenarioItem *parent;
@end
@interface ComparisonItem : CondElmItem <NSTextFieldDelegate> {
	NSInteger varIndex, opeIndex;
	NSInteger maxValue;
	CGFloat ratioValue;
	NSInteger days;
}
@end
@interface CompoundItem : CondElmItem
@property NSMutableArray<CondElmItem *> *children;
- (void)replaceChildAtIndex:(NSInteger)index withItem:(CondElmItem *)newChild;
@end
@interface CondItem : ScenarioItem <NSTextFieldDelegate> {
	CondType condType;
	NSString *orgLabel;
	NSInteger destination;
}
@property CondElmItem *element;
@property NSPredicate *predicate;
- (void)replaceElementWithItem:(CondElmItem *)newElement;
@end

@interface Scenario : NSWindowController 
	<NSWindowDelegate, NSTextFieldDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate> {
	IBOutlet NSButton *shiftUpBtn, *shiftDownBtn, *deselectBtn;
	IBOutlet NSButton *removeBtn, *applyBtn;
	IBOutlet NSWindow *distParamSheet;
	IBOutlet NSTextField *itemIdx, *paramNameTxt, *minDgt, *maxDgt, *modeDgt;
}
@property IBOutlet NSOutlineView *outlineView;
@property (readonly) Document *doc;
@property (readonly) NSUndoManager *undoManager;
@property (readonly) NSNumberFormatter *intFormatter;
- (instancetype)initWithDoc:(Document *)dc;
- (void)adjustControls:(BOOL)undoOrRedo;
- (NSInteger)numberOfItems;
- (void)removeItem:(ScenarioItem *)item;
- (CondElmItem *)itemWithPredicate:(NSPredicate *)predicate parent:(ScenarioItem *)parent;
- (void)setScenarioWithArray:(NSArray *)array;
- (void)distParamBySheetWithItem:(ParamItem *)item value:(DistInfo *)info;
@end

NS_ASSUME_NONNULL_END
