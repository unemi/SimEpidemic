//
//  GatPanel.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2022/03/09.
//  Copyright © 2022 Tatsuo Unemi. All rights reserved.
//

#import "GatPanel.h"
#import "VVPanel.h"
#import "Gatherings.h"

@interface GatPanel () {
	World * __weak world;
	NSUndoManager *undoManager;
	MutableDictArray gatheringsList;
	IBOutlet NSTableView *tableView;
	IBOutlet NSButton *remBtn, *copyBtn, *pasteBtn, *saveBtn, *applyBtn;
}
@end

@implementation GatPanel
- (NSString *)windowNibName { return @"GatheringPanel"; }
- (instancetype)initWithWorld:(World *)wd {
	if (!(self = [super init])) return nil;
	undoManager = NSUndoManager.new;
	gatheringsList = wd.gatheringsList.vvListCopy;
	for (NSMutableDictionary *item in gatheringsList)
		if ([(NSString *)item[@"name"] hasPrefix:@"__"]) item[@"name"] = nil;
	world = wd;
	return self;
}
- (void)checkApplyBtn {
	applyBtn.enabled = ![world.gatheringsList isEqultToVVList:gatheringsList];
}
- (void)checkCopySaveBtn {
    copyBtn.enabled = saveBtn.enabled = gatheringsList.count > 0;
}
- (void)windowDidLoad {
    [super windowDidLoad];
	[tableView reloadData];
    [self checkCopySaveBtn];
}
- (void)removeItemAtIndexes:(NSIndexSet *)idxSet {
	NSArray<NSMutableDictionary *> *items = [gatheringsList objectsAtIndexes:idxSet];
	[undoManager registerUndoWithTarget:self handler:^(GatPanel *target) {
		[target addItems:items atIndexes:idxSet];
	}];
	[gatheringsList removeObjectsAtIndexes:idxSet];
	[tableView reloadData];
    [self checkCopySaveBtn];
    [self checkApplyBtn];
}
- (void)addItems:(NSArray <NSMutableDictionary *> *)items atIndexes:(NSIndexSet *)idxSet {
	[undoManager registerUndoWithTarget:self handler:^(GatPanel *target) {
		[target removeItemAtIndexes:idxSet];
	}];
	if (gatheringsList == nil) gatheringsList = NSMutableArray.new;
	[gatheringsList insertObjects:items atIndexes:idxSet];
	[tableView reloadData];
    [self checkCopySaveBtn];
    [self checkApplyBtn];
}
- (IBAction)addItem:(id)sender {
	[self addItems:@[[NSMutableDictionary dictionaryWithDictionary:
		@{@"npp":@(100),@"freq":@(5),@"duration":@(2),@"size":@(8),@"strength":@(80)}]]
		atIndexes:[NSIndexSet indexSetWithIndex:gatheringsList.count]];
    [tableView reloadData];
}
- (IBAction)removeItem:(id)sender {
	[self removeItemAtIndexes:[tableView selectedRowIndexes]];
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
	if (col == 1) {
		NSString *name = sender.stringValue;
		NSInteger k = -1;
		for (NSInteger i = 0; i < gatheringsList.count; i ++) if (i != row) {
			NSString *nm = gatheringsList[i][@"name"];
			if (nm != nil && [nm isEqualToString:name]) { k = i; break; }
		}
		if (k >= 0) error_msg([NSString stringWithFormat:
			@"\"%@\" is already used for No.%ld.", name, k], self.window, NO);
		else [self assignObject:name forID:@"name" inItem:item];
	} else [self assignObject:@(sender.doubleValue)
		forID:tableView.tableColumns[col].identifier inItem:item];
}
- (NSData *)dataOfList:(BOOL)isPlist error:(NSError **)errorp {
	NSArray *items = (tableView.selectedRow < 0)? gatheringsList :
		[gatheringsList objectsAtIndexes:[tableView selectedRowIndexes]];
	return isPlist? [NSPropertyListSerialization dataWithPropertyList:items
			format:NSPropertyListXMLFormat_v1_0 options:0 error:errorp] :
		[NSJSONSerialization dataWithJSONObject:items options:0 error:errorp];
}
- (BOOL)addListFromData:(NSData *)data plist:(BOOL)isPlist error:(NSError **)errorp {
	MutableDictArray items = [NSJSONSerialization JSONObjectWithData:data
		options:NSJSONReadingMutableContainers error:errorp];
	if (items == nil) return NO;
	NSIndexSet *idxes = (tableView.selectedRow >= 0)? [tableView selectedRowIndexes] :
		[NSIndexSet indexSetWithIndexesInRange:(NSRange){gatheringsList.count, items.count}];
	[self addItems:items atIndexes:idxes];
	[tableView reloadData];
    [self checkCopySaveBtn];
    [self checkApplyBtn];
    return YES;
}
- (IBAction)copy:(id)sender {
	NSError *error;
	NSData *data = [self dataOfList:NO error:&error];
	if (data == nil) { error_msg(error, self.window, NO); return; }
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	[pb declareTypes:@[NSPasteboardTypeString] owner:NSApp];
	[pb setData:data forType:NSPasteboardTypeString];
}
- (IBAction)cut:(id)sender {
	if (tableView.selectedRow < 0) return;
	NSIndexSet *idxes = tableView.selectedRowIndexes;
	NSError *error;
	NSData *data = [NSJSONSerialization dataWithJSONObject:
		[gatheringsList objectsAtIndexes:idxes] options:0 error:&error];
	if (data == nil) { error_msg(error, self.window, NO); return; }
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	[pb declareTypes:@[NSPasteboardTypeString] owner:NSApp];
	[pb setData:data forType:NSPasteboardTypeString];
	[self removeItemAtIndexes:idxes];
}
- (IBAction)paste:(id)sender {
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	NSData *data = [pb dataForType:NSPasteboardTypeString];
	if (data == nil) return;
	NSError *error;
	if (![self addListFromData:data plist:NO error:&error])
		error_msg(error, self.window, NO);
}
- (IBAction)apply:(id)sender {
	NSInteger i = 0;
	world.gatheringsList = gatheringsList.vvListCopy;
	for (NSMutableDictionary *item in world.gatheringsList)
		if (item[@"name"] == nil) item[@"name"] = [NSString stringWithFormat:@"__%04ld", i++];
	[world resetRegGatInfo];
	applyBtn.enabled = NO;
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
// Window Delegate
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return undoManager;
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
		NSNumber *num = rowDict[ID];
		if (num == nil) txtFld.stringValue = @"---";
		else txtFld.doubleValue = num.doubleValue;
	}
	return view;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
	remBtn.enabled = tableView.selectedRow >= 0;
}
@end
