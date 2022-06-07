//
//  GatPanel.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2022/03/09.
//  Copyright © 2022 Tatsuo Unemi. All rights reserved.
//

#import "GatPanel.h"
#import "VVPanel.h"
#import "Document.h"
#import "Gatherings.h"

NSString *nnRegGatChanged = @"RegularGatheringsChanged";

@implementation NSMutableArray (CopyGatListExtension)
- (NSMutableArray *)gatListCopy {
	NSMutableArray *ma = NSMutableArray.new;
	for (NSDictionary *elm in self) {
		NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:elm];
		for (NSString *key in dict.keyEnumerator) if ([dict[key] isKindOfClass:NSDictionary.class])
			dict[key] = [NSMutableDictionary
				dictionaryWithDictionary:((NSDictionary *)dict)[key]];
		[ma addObject:dict];
	}
	return ma;
}
- (BOOL)isEqultToGatList:(NSArray<NSDictionary *> *)list {
	if (self.count != list.count) return NO;
	for (NSInteger i = 0; i < self.count; i ++) {
		NSDictionary *elmA = self[i], *elmB = list[i];
		for (NSString *key in elmA) if (![elmA[key] isEqualTo:elmB[key]]) return NO;
	}
	return YES;
}
@end

@interface GatPanel () {
	Document * __weak document;
	World * __weak world;
	NSUndoManager *undoManager;
	MutableDictArray gatheringsList;
	BOOL isCurrentValue;
	IBOutlet NSTableView *tableView;
	IBOutlet NSButton *copyBtn, *pasteBtn, *remBtn, *saveBtn, *applyBtn,
		*crntPrmRdBtn, *initPrmRdBtn;
}
@end

@implementation GatPanel
- (instancetype)initWithDocument:(Document *)doc {
	if (!(self = [super initWithWindowNibName:@"GatheringPanel"])) return nil;
	undoManager = NSUndoManager.new;
	document = doc;
	world = doc.world;
	gatheringsList = world.gatheringsList.gatListCopy;
	for (NSMutableDictionary *item in gatheringsList)
		if ([(NSString *)item[@"name"] hasPrefix:@"__"]) item[@"name"] = nil;
	return self;
}
- (void)checkRemBtn {
	remBtn.enabled = tableView.selectedRow >= 0;
}
- (void)checkApplyBtn {
	applyBtn.enabled = ![world.gatheringsList isEqultToGatList:gatheringsList]
		&& (world.gatheringsList != nil || gatheringsList.count > 0);
}
- (void)checkSaveBtn {
    copyBtn.enabled = saveBtn.enabled = gatheringsList.count > 0;
}
- (void)windowDidLoad {
    [super windowDidLoad];
    [document setPanelTitle:self.window];
	[tableView reloadData];
    [self checkSaveBtn];
}
- (void)removeItemAtIndexes:(NSIndexSet *)idxSet {
	NSArray<NSMutableDictionary *> *items = [gatheringsList objectsAtIndexes:idxSet];
	[undoManager registerUndoWithTarget:self handler:^(GatPanel *target) {
		[target addItems:items atIndexes:idxSet];
	}];
	[gatheringsList removeObjectsAtIndexes:idxSet];
	[tableView reloadData];
	[self checkRemBtn];
    [self checkSaveBtn];
    [self checkApplyBtn];
}
- (void)addItems:(NSArray <NSMutableDictionary *> *)items atIndexes:(NSIndexSet *)idxSet {
	[undoManager registerUndoWithTarget:self handler:^(GatPanel *target) {
		[target removeItemAtIndexes:idxSet];
	}];
	if (gatheringsList == nil) gatheringsList = NSMutableArray.new;
	[gatheringsList insertObjects:items atIndexes:idxSet];
	[tableView reloadData];
    [self checkSaveBtn];
    [self checkApplyBtn];
}
- (IBAction)addItem:(id)sender {
	NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:item_template()],
		*initParams = NSMutableDictionary.new;
	for (NSString *name in variable_gat_params()) initParams[name] = item[name];
	item[@"initParams"] = initParams;
	[self addItems:@[item] atIndexes:[NSIndexSet indexSetWithIndex:gatheringsList.count]];
}
- (IBAction)delete:(id)sender {
	NSIndexSet *idxes = tableView.selectedRowIndexes;
	if (idxes.firstIndex != NSNotFound) [self removeItemAtIndexes:idxes];
}
- (void)assignObject:(NSObject *)newObj forID:(NSString *)ID inItem:(NSMutableDictionary *)item {
	NSObject *orgObj = item[ID];
	[undoManager registerUndoWithTarget:self handler:^(GatPanel *target) {
		[self assignObject:orgObj forID:ID inItem:item];
	}];
	item[ID] = newObj;
	[tableView reloadData];
    [self checkApplyBtn];
}
- (IBAction)textChanged:(NSTextField *)sender {
	NSInteger row = [tableView rowForView:sender], col = [tableView columnForView:sender];
	if (row < 0 || row >= gatheringsList.count) return;
	if (col <= 0 || col >= tableView.numberOfColumns) return;
	NSMutableDictionary *item = gatheringsList[row];
	NSString *ID = tableView.tableColumns[col].identifier;
	if ([ID isEqualToString:@"name"]) {
		NSString *name = sender.stringValue;
		NSInteger k = -1;
		for (NSInteger i = 0; i < gatheringsList.count; i ++) if (i != row) {
			NSString *nm = gatheringsList[i][@"name"];
			if (nm != nil && [nm isEqualToString:name]) { k = i; break; }
		}
		if (k >= 0) error_msg([NSString stringWithFormat:
			@"\"%@\" is already used for No.%ld.", name, k], self.window, NO);
		else [self assignObject:name forID:ID inItem:item];
	} else if (isCurrentValue || ![variable_gat_params() containsObject:ID])
		[self assignObject:@(sender.doubleValue) forID:ID inItem:item];
	else {
		NSMutableDictionary<NSString *, NSNumber *> *initParams = item[@"initParams"];
		if (initParams == nil) item[@"initParams"] = initParams = NSMutableDictionary.new;
		if (initParams[ID] == nil) initParams[ID] = item[ID];
		[self assignObject:@(sender.doubleValue) forID:ID inItem:initParams];
	}
}
- (NSData *)dataOfList:(BOOL)isPlist error:(NSError **)errorp {
	NSArray *items = (tableView.selectedRow < 0)? gatheringsList :
		[gatheringsList objectsAtIndexes:[tableView selectedRowIndexes]];
	return isPlist? [NSPropertyListSerialization dataWithPropertyList:items
			format:NSPropertyListXMLFormat_v1_0 options:0 error:errorp] :
		[NSJSONSerialization dataWithJSONObject:items options:JSONFormat error:errorp];
}
- (BOOL)addListFromData:(NSData *)data plist:(BOOL)isPlist error:(NSError **)errorp {
	MutableDictArray items = isPlist?
	[NSPropertyListSerialization propertyListWithData:data
		options:NSPropertyListMutableContainers format:NULL error:errorp] :
	[NSJSONSerialization JSONObjectWithData:data
		options:NSJSONReadingMutableContainers error:errorp];
	if (items == nil) return NO;
	if (![items isKindOfClass:NSArray.class]) {
		*errorp = error_obj(2, @"It is not an array.", items.class.description);
		return NO;
	}
	for (NSObject *elm in items) if (![elm isKindOfClass:NSDictionary.class]) {
		*errorp = error_obj(2, @"An element is not a dictionary.", elm.class.description);
		return NO;
	}
	correct_gathering_list(items);
	NSIndexSet *idxes = (tableView.selectedRow >= 0)? [tableView selectedRowIndexes] :
		[NSIndexSet indexSetWithIndexesInRange:(NSRange){gatheringsList.count, items.count}];
	[self addItems:items atIndexes:idxes];
    [self checkSaveBtn];
    [self checkApplyBtn];
    return YES;
}
- (IBAction)switchInitOrCurrent:(id)sender {
	BOOL newValue = crntPrmRdBtn.state == NSControlStateValueOn;
	if (newValue == isCurrentValue) return;
	[undoManager registerUndoWithTarget:newValue? initPrmRdBtn : crntPrmRdBtn
		handler:^(NSButton *target) { [target performClick:nil]; }];
	isCurrentValue = newValue;
	[tableView reloadData];
}
- (IBAction)copy:(id)sender {
	NSError *error;
	NSData *data = [self dataOfList:NO error:&error];
	if (data == nil) { error_msg(error, self.window, NO); return; }
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	[pb declareTypes:@[NSPasteboardTypeString] owner:NSApp];
	[pb setData:data forType:NSPasteboardTypeString];
	pasteBtn.enabled = YES;
}
- (IBAction)cut:(id)sender {
	if (tableView.selectedRow < 0) return;
	NSIndexSet *idxes = tableView.selectedRowIndexes;
	NSError *error;
	NSData *data = [NSJSONSerialization dataWithJSONObject:
		[gatheringsList objectsAtIndexes:idxes] options:JSONFormat error:&error];
	if (data == nil) { error_msg(error, self.window, NO); return; }
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	[pb declareTypes:@[NSPasteboardTypeString] owner:NSApp];
	[pb setData:data forType:NSPasteboardTypeString];
	[self removeItemAtIndexes:idxes];
	pasteBtn.enabled = YES;
}
- (IBAction)paste:(id)sender {
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	NSData *data = [pb dataForType:NSPasteboardTypeString];
	if (data == nil) { error_msg(@"No string", self.window, NO); return;}
	NSError *error;
	if (![self addListFromData:data plist:NO error:&error])
		error_msg(error, self.window, NO);
}
- (IBAction)apply:(id)sender {
	world.gatheringsList = gatheringsList.gatListCopy;
	correct_gathering_names(world.gatheringsList);
	[world resetRegGatInfo];
	applyBtn.enabled = NO;
    [NSNotificationCenter.defaultCenter postNotificationName:nnRegGatChanged object:world];
}
- (IBAction)loadDocument:(id)sender {
	NSOpenPanel *op = NSOpenPanel.new;
	op.allowedFileTypes = @[@"sEpG", @"json"];
	[op beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		NSError *error;
		NSData *data = [NSData dataWithContentsOfURL:op.URL options:0 error:&error];
		if (data == nil) error_msg(error, self.window, NO);
		else if (![self addListFromData:data plist:
			[op.URL.pathExtension isEqualToString:@"sEpG"] error:&error])
			error_msg(error, self.window, NO);
	}];
}
- (IBAction)saveDocument:(id)sender {
	NSSavePanel *sp = NSSavePanel.new;
	sp.allowedFileTypes = @[@"sEpG", @"json"];
	[sp beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		NSError *error;
		NSData *data = [self dataOfList:
			[sp.URL.pathExtension isEqualToString:@"sEpG"] error:&error];
		if (data == nil) { error_msg(error, self.window, NO); return; }
		if (![data writeToURL:sp.URL options:0 error:&error])
			error_msg(error, self.window, NO);
	}];
}
//
- (void)checkPasteButton {
	pasteBtn.enabled = [NSPasteboard.generalPasteboard
		canReadItemWithDataConformingToTypes:@[NSPasteboardTypeString]];
}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem.action == @selector(delete:) || menuItem.action == @selector(cut:))
		return tableView.selectedRow >= 0;
	else if (menuItem.action == @selector(copy:)
		|| menuItem.action == @selector(saveDocument:)) return gatheringsList.count > 0;
	else if (menuItem.action == @selector(paste:)) return
		[NSPasteboard.generalPasteboard canReadItemWithDataConformingToTypes:
			@[NSPasteboardTypeString]];
	return YES;
}
// Window Delegate
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return undoManager;
}
- (void)windowDidBecomeKey:(NSNotification *)notification {
	[self checkPasteButton];
}
// TableView Data Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return gatheringsList.count;
}
// TableView Delegate
- (NSView *)tableView:(NSTableView *)tableView
	viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSString *ID = tableColumn.identifier;
	NSTableCellView *view = [tableView makeViewWithIdentifier:ID owner:self];
	NSTextField *txtFld = view.textField;
	NSDictionary *rowDict = gatheringsList[row];
	if ([ID isEqualToString:@"no."]) txtFld.integerValue = row + 1;
	else if ([ID isEqualToString:@"name"]) {
		NSString *name = rowDict[ID];
		txtFld.stringValue = (name == nil)? @"---" : name;
	} else {
		NSNumber *num = (isCurrentValue || ![variable_gat_params() containsObject:ID])?
			rowDict[ID] : (NSDictionary *)(rowDict[@"initParams"])[ID];
		if (num == nil) txtFld.stringValue = @"---";
		else txtFld.doubleValue = num.doubleValue;
	}
	return view;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
	[self checkRemBtn];
}
@end
