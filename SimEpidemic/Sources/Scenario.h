//
//  Scenario.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/17.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@class Document, Scenario, ButtonsCellView;

@interface ParameterCellView : NSTableCellView
@property (readonly) NSPopUpButton *namePopUp;
@end
@interface ParamElmCellView : NSTableCellView
@property (readonly) NSTextField *digits;
@end
@interface ScenarioItem : NSObject {
	Scenario *scenario;
}
@property NSTableCellView *view;
@property (readonly) ButtonsCellView *btnsView;
- (void)buttonAction:(NSButton *)button;
@end
@interface CondElmItem : ScenarioItem
@property (weak) ScenarioItem *parent;
@end
@interface ComparisonItem : CondElmItem
@end
@interface CompoundItem : CondElmItem
@property NSMutableArray<CondElmItem *> *children;
- (void)replaceChildAtIndex:(NSInteger)index withItem:(CondElmItem *)newChild;
@end
@interface CondItem : ScenarioItem
@property CondElmItem *element;
@property NSPredicate *predicate;
- (void)replaceElementWithItem:(CondElmItem *)newElement;
@end

@interface Scenario : NSWindowController 
	<NSWindowDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate> {
	IBOutlet NSButton *shiftUpBtn, *shiftDownBtn;
	IBOutlet NSButton *removeBtn, *applyBtn;
}
@property IBOutlet NSOutlineView *outlineView;
@property (readonly) Document *doc;
@property (readonly) NSUndoManager *undoManager;
@property (readonly) NSNumberFormatter *intFormatter;
- (instancetype)initWithDoc:(Document *)dc;
- (void)removeItem:(ScenarioItem *)item;
- (CondElmItem *)itemWithPredicate:(NSPredicate *)predicate parent:(ScenarioItem *)parent;
- (void)setScenarioWithArray:(NSArray *)array;
@end

NS_ASSUME_NONNULL_END
