//
//  VVPanel.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2021/08/17.
//  Copyright © 2021 Tatsuo Unemi. All rights reserved.
//

#import "VVPanel.h"
#import "World.h"
#import "SaveDoc.h"
#define VAR_PNL_EXCOLS 3
#define VAX_PNL_EXCOLS 2
NSString *VaccineListChanged = @"VaccineListChanged";
NSString *VariantListChanged = @"VariantListChanged";

@implementation NSMutableArray (CopyVVListExtension)
- (NSMutableArray *)vvListCopy {
	NSMutableArray *ma = NSMutableArray.new;
	for (NSDictionary *elm in self)
		[ma addObject:[NSMutableDictionary dictionaryWithDictionary:elm]];
	return ma;
}
- (BOOL)isEqultToVVList:(NSArray<NSDictionary *> *)list {
	if (self.count != list.count) return NO;
	for (NSInteger i = 0; i < self.count; i ++) {
		NSDictionary *elmA = self[i], *elmB = list[i];
		for (NSString *key in elmA) if (![elmA[key] isEqualTo:elmB[key]]) return NO;
	}
	return YES;
}
@end

@implementation NSTableView (VVPanelExtension)
- (NSTableColumn *)tableColumnWithTitle:(NSString *)title {
	for (NSTableColumn *tcol in self.tableColumns)
		if ([tcol.title isEqualToString:title]) return tcol;
	return nil;
}
@end

@interface VVPanel () {
	World * __weak world;
	MutableDictArray variantList, vaccineList;
	NSUndoManager *undoManager;
	NSInteger vaxNextID, vrnNextID;
	NSTableColumn *vaxColToEdit;
	NSArray<NSTextField *> *vcnDgts;
	NSArray<NSSlider *> *vcnSlds;
}
@end

@implementation VVPanel
- (NSString *)windowNibName { return @"VirusVariantPanel"; }
- (instancetype)initWithWorld:(World *)wd {
	if (!(self = [super init])) return nil;
	undoManager = NSUndoManager.new;
	variantList = wd.variantList.vvListCopy;
	vaccineList = wd.vaccineList.vvListCopy;
	for (NSInteger i = 0; i < vaccineList.count; i ++)
		vaccineList[i][@".orgIndex"] = @(i);
	world = wd;
	return self;
}
static void copy_tableColumn_properties(NSTableColumn *dst, NSTableColumn *src) {
	dst.width = src.width;
	dst.minWidth = src.minWidth;
	dst.maxWidth = src.maxWidth;
	dst.resizingMask = src.resizingMask;
	NSTextFieldCell *dHeader = dst.headerCell, *sHeader = src.headerCell;
	dHeader.alignment = sHeader.alignment;
}
- (void)addVariantColumn:(NSString *)name {
	NSTableColumn *colTmp = variantTable.tableColumns[VAR_PNL_EXCOLS],
		*tblColVir = NSTableColumn.new, *tblColVax = NSTableColumn.new;
	tblColVir.title = tblColVax.title = name;
	copy_tableColumn_properties(tblColVir, colTmp);
	copy_tableColumn_properties(tblColVax, colTmp);
	[variantTable addTableColumn:tblColVir];
	[vaccineTable addTableColumn:tblColVax];
}
- (void)windowDidLoad {
	vaxNextID = vrnNextID = 1;
	NSTableColumn *colVir = [variantTable tableColumnWithIdentifier:@"variant0"],
		*colVax = [vaccineTable tableColumnWithIdentifier:@"variant0"];
	colVir.title = colVax.title = variantList[0][@"name"];
	for (NSInteger i = 1; i < variantList.count; i ++)
		[self addVariantColumn:variantList[i][@"name"]];
	if (vaccineList.count >= MAX_N_VAXEN) addVaccineBtn.enabled = NO;
	vaccineTable.headerView.needsDisplay = YES;
	vcnDgts = @[vcn1stEffcDgt, vcnMaxEffcDgt, vcnMaxEffcSDgt,
		vcnEDelayDgt, vcnEPeriodDgt, vcnEDecayDgt, vcnSvEffcDgt];
	vcnSlds = @[vcn1stEffcSld, vcnMaxEffcSld, vcnMaxEffcSSld,
		vcnEDelaySld, vcnEPeriodSld, vcnEDecaySld, vcnSvEffcSld];
	CGFloat *p = &world.tmpWorldParamsP->vcn1stEffc;
	ParamInfo *prmInfo = paramInfo;
	while (prmInfo->key != nil &&
		![prmInfo->key isEqualToString:@"vaccineFirstDoseEfficacy"]) prmInfo ++;
	for (NSInteger i = 0; i < vcnDgts.count; i ++) {
		vcnDgts[i].tag = vcnSlds[i].tag = i;
		vcnDgts[i].target = vcnSlds[i].target = self;
		vcnDgts[i].action = vcnSlds[i].action = @selector(changeFValue:);
		if (prmInfo->key != nil) {
			vcnSlds[i].minValue = prmInfo[i].v.f.minValue;
			vcnSlds[i].maxValue = prmInfo[i].v.f.maxValue;
		}
		vcnDgts[i].doubleValue = vcnSlds[i].doubleValue = p[i];
	}
	[variantTable reloadData];
	[vaccineTable reloadData];
}
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return undoManager;
}
- (void)adjustApplyBtnEnabled {
	applyBtn.enabled = ! (world.running || (
		[vaccineList isEqultToVVList:world.vaccineList] &&
		[variantList isEqultToVVList:world.variantList]));
}
- (void)setFValue:(CGFloat)newValue index:(NSInteger)idx {
	CGFloat *p = &world.tmpWorldParamsP->vcn1stEffc, orgValue = p[idx];
	[undoManager registerUndoWithTarget:self handler:^(VVPanel *target) {
		[target setFValue:orgValue index:idx];
	}];
	vcnDgts[idx].doubleValue = vcnSlds[idx].doubleValue = p[idx] = newValue;
}
- (void)changeFValue:(NSControl *)sender {
	[self setFValue:sender.doubleValue index:sender.tag];
}
- (void)addVariants:(NSDictionary *)info {
	NSArray<NSMutableDictionary *> *rows = info[@"rows"];
	NSIndexSet *indexes = info[@"indexes"];
	NSDictionary<NSString *, NSDictionary *>
		*vrnEfc = info[@"varientEfficacy"], *vaxEfc = info[@"vaccineEfficacy"];
	NSEnumerator *enm = rows.objectEnumerator;
	[indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
		NSMutableDictionary *newRow = enm.nextObject;
		[variantList insertObject:newRow atIndex:idx];
		[self addVariantColumn:newRow[@"name"]];
		[variantTable moveColumn:variantTable.numberOfColumns - 1 toColumn:idx + VAR_PNL_EXCOLS];
		[vaccineTable moveColumn:vaccineTable.numberOfColumns - 1 toColumn:idx + VAX_PNL_EXCOLS];
	}];
	if (vrnEfc == nil) {
		for (NSMutableDictionary *newRow in rows) {
			NSString *name = newRow[@"name"];
			for (NSMutableDictionary *row in variantList) row[name] = @(1.);
			for (NSMutableDictionary *row in vaccineList) row[name] = @(1.);
		}
	} else {
		for (NSMutableDictionary *newRow in rows) {
			NSString *name = newRow[@"name"];
			NSDictionary *efc = vrnEfc[name];
			for (NSMutableDictionary *row in variantList) row[name] = efc[row[@"name"]];
			efc = vaxEfc[name];
			for (NSMutableDictionary *row in vaccineList) row[name] = efc[row[@"name"]];
		}
	}
	[undoManager registerUndoWithTarget:self
		selector:@selector(removeVariantsAtIndexes:) object:indexes];
	[variantTable reloadData];
	[vaccineTable reloadData];
	[self adjustApplyBtnEnabled];
}
- (void)removeVariantsAtIndexes:(NSIndexSet *)indexes {
	NSMutableDictionary *vrnEfc = NSMutableDictionary.new, *vaxEfc = NSMutableDictionary.new;
	[indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
		NSString *name = variantList[idx][@"name"];
		[variantTable removeTableColumn:[variantTable tableColumnWithTitle:name]];
		[vaccineTable removeTableColumn:[vaccineTable tableColumnWithTitle:name]];
		NSMutableDictionary *md = NSMutableDictionary.new;
		for (NSMutableDictionary *row in variantList) {
			md[row[@"name"]] = row[name];
			[row removeObjectForKey:name];
		}
		vrnEfc[name] = md;
		md = NSMutableDictionary.new;
		for (NSMutableDictionary *row in vaccineList) {
			md[row[@"name"]] = row[name];
			[row removeObjectForKey:name];
		}
		vaxEfc[name] = md;
	}];
	NSMutableArray *rows = NSMutableArray.new;
	[indexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:
		^(NSUInteger idx, BOOL * _Nonnull stop) {
		[rows insertObject:variantList[idx] atIndex:0];
		[variantList removeObjectAtIndex:idx];
	}];
	[undoManager registerUndoWithTarget:self selector:@selector(addVariants:) object:
		@{@"rows":rows, @"indexes":indexes, @"varientEfficacy":vrnEfc, @"vaccineEfficacy":vaxEfc}];
	[variantTable reloadData];
	[vaccineTable reloadData];
	[self adjustApplyBtnEnabled];
}
- (IBAction)addVariant:(id)sender {
	NSInteger row = variantTable.selectedRow;
	if (row < 0) row = variantList.count - 1;
	NSMutableDictionary *newRow = [NSMutableDictionary dictionaryWithDictionary:variantList[row]];
	newRow[@"name"] = [NSString stringWithFormat:@"variant%ld", vrnNextID ++];
	[self addVariants:@{@"rows":@[newRow], @"indexes":[NSIndexSet indexSetWithIndex:row + 1]}];
}
- (IBAction)removeVariant:(id)sender {
	[self removeVariantsAtIndexes:variantTable.selectedRowIndexes];
}
- (void)addVaccines:(NSArray<NSDictionary *> *)rows atIndexes:(NSIndexSet *)indexes {
	NSEnumerator *enm = rows.objectEnumerator;
	[indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
		[vaccineList insertObject:enm.nextObject atIndex:idx];
	}];
	if (vaccineList.count >= MAX_N_VAXEN) addVaccineBtn.enabled = NO;
	[undoManager registerUndoWithTarget:self
		selector:@selector(removeVaccinesAtIndexes:) object:indexes];
	[vaccineTable reloadData];
	[self adjustApplyBtnEnabled];
}
- (void)removeVaccinesAtIndexes:(NSIndexSet *)indexes {
	NSMutableArray<NSDictionary *> *rows = NSMutableArray.new;
	if (vaccineList.count == MAX_N_VAXEN) addVaccineBtn.enabled = YES;
	[indexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:
		^(NSUInteger idx, BOOL * _Nonnull stop) {
		[rows insertObject:vaccineList[idx] atIndex:0];
		[vaccineList removeObjectAtIndex:idx];
	}];
	[undoManager registerUndoWithTarget:self handler:^(VVPanel *target) {
		[target addVaccines:rows atIndexes:indexes];
	}];
	[vaccineTable reloadData];
	[self adjustApplyBtnEnabled];
}
- (IBAction)addVaccine:(id)sender {
	NSInteger row = vaccineTable.selectedRow;
	if (row < 0) row = vaccineList.count - 1;
	NSMutableDictionary *newRow = [NSMutableDictionary dictionaryWithDictionary:vaccineList[row]];
	newRow[@"name"] = [NSString stringWithFormat:@"vaccine%ld", vaxNextID ++];
	[self addVaccines:@[newRow] atIndexes:[NSIndexSet indexSetWithIndex:row + 1]];
}
- (IBAction)removeVaccine:(id)sender {
	[self removeVaccinesAtIndexes:vaccineTable.selectedRowIndexes];
}
- (void)assignObject:(NSObject *)newValue dict:(NSMutableDictionary *)dict key:(NSString *)key
	tableView:(NSTableView *)tableView row:(NSInteger)row col:(NSInteger)col {
	NSObject *orgValue = dict[key];
	if ([newValue isEqualTo:orgValue]) return;
	[undoManager registerUndoWithTarget:self handler:^(VVPanel *target) {
		[target assignObject:orgValue dict:dict key:key tableView:tableView row:row col:col];
	}];
	dict[key] = newValue;
	[tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
		columnIndexes:[NSIndexSet indexSetWithIndex:col]];
	[self adjustApplyBtnEnabled];
}
- (void)renameVariantNameAtRow:(NSInteger)row to:(NSString *)newName {
	NSMutableDictionary *rowDict = variantList[row];
	NSString *orgName = rowDict[@"name"];
	if ([newName isEqualToString:orgName]) return;
	[undoManager registerUndoWithTarget:self handler:^(VVPanel *target) {
		[target renameVariantNameAtRow:row to:orgName];
	}];
	rowDict[@"name"] = newName;
	[variantTable tableColumnWithTitle:orgName].title =
	[vaccineTable tableColumnWithTitle:orgName].title = newName;
	for (NSArray<NSMutableDictionary *> *list in @[variantList, vaccineList])
	for (NSMutableDictionary *d in list) {
		d[newName] = d[orgName];
		[d removeObjectForKey:orgName];
	}
	variantTable.headerView.needsDisplay =
	vaccineTable.headerView.needsDisplay = YES;
	[variantTable reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
		columnIndexes:[NSIndexSet indexSetWithIndex:0]];
	[self adjustApplyBtnEnabled];
}
- (IBAction)valueChangedInVariantTable:(NSTextField *)sender {
	NSInteger row = [variantTable rowForView:sender], col = [variantTable columnForView:sender];
	if (row < 0 || row >= variantList.count) return;
	if (col < 0 || col >= variantTable.numberOfColumns) return;
	if (col == 0) [self renameVariantNameAtRow:row to:sender.stringValue];
	else {
		NSTableColumn *tblCol = variantTable.tableColumns[col];
		[self assignObject:@(sender.doubleValue) dict:variantList[row]
			key:(col < VAR_PNL_EXCOLS)? tblCol.identifier : tblCol.title
			tableView:variantTable row:row col:col];
	}
}
- (IBAction)valueChangedInVaccineTable:(NSControl *)sender {
	NSInteger row = [vaccineTable rowForView:sender], col = [vaccineTable columnForView:sender];
	if (row < 0 || row >= vaccineList.count) return;
	if (col < 0 || col >= vaccineTable.numberOfColumns) return;
	NSMutableDictionary *rowDict = vaccineList[row];
	NSTableColumn *tblCol = vaccineTable.tableColumns[col];
	if (col == 0) {	// name
		[self assignObject:sender.stringValue dict:rowDict key:@"name"
			tableView:vaccineTable row:row col:col];
	} else if (col > 1) {	// efficacy
		[self assignObject:@(sender.doubleValue) dict:rowDict key:tblCol.title
			tableView:vaccineTable row:row col:col];
	} else if ([sender isKindOfClass:NSTextField.class]) {	// interval days
		[self assignObject:@(sender.integerValue) dict:rowDict key:@"intervalDays"
			tableView:vaccineTable row:row col:col];
	} else if ([sender isKindOfClass:NSButton.class]) {
		[self assignObject:@(((NSButton *)sender).state) dict:rowDict key:@"intervalOn"
			tableView:vaccineTable row:row col:col];
	}
}
- (NSMutableArray *)strippedVaxList {
	NSMutableArray *ma = NSMutableArray.new;
	for (NSDictionary *elm in vaccineList) {
		NSMutableDictionary *md = NSMutableDictionary.new;
		for (NSString *key in elm) if (![key hasPrefix:@".org"]) md[key] = elm[key];
		[ma addObject:md];
	}
	return ma;
}
- (IBAction)apply:(id)sender {
	BOOL changed = NO;
	if (![world.variantList isEqultToVVList:variantList]) {
		world.variantList = variantList;
		[NSNotificationCenter.defaultCenter postNotificationName:VariantListChanged object:world];
		changed = YES;
	}
	if (![world.vaccineList isEqultToVVList:vaccineList]) {
		NSInteger nVaxen = vaccineList.count;
		VaccinationInfo *iP = world.initParamsP->vcnInfo, *rP = world.runtimeParamsP->vcnInfo;
		VaccinationInfo iInfo[nVaxen], rInfo[nVaxen];
		for (NSInteger i = 0; i < nVaxen; i ++) {
			if (vaccineList[i][@".orgIndex"] != nil) {
				NSInteger orgIdx = [vaccineList[i][@".orgIndex"] integerValue];
				iInfo[i] = iP[orgIdx];
				rInfo[i] = rP[orgIdx];
			} else iInfo[i] = rInfo[i] = (VaccinationInfo){0., 100., VcnPrRandom};
		}
		memcpy(iP, iInfo, sizeof(VaccinationInfo) * nVaxen);
		memcpy(rP, rInfo, sizeof(VaccinationInfo) * nVaxen);
		world.vaccineList = [self strippedVaxList];
		[NSNotificationCenter.defaultCenter postNotificationName:VaccineListChanged object:world];
		changed = YES;
	}
	applyBtn.enabled = NO;
	if (changed && world.runtimeParamsP->step == 0) [world setupVaxenAndVariantsFromLists];
}
- (NSData *)dataOfVVInfo:(BOOL)isPlist {
	NSDictionary *info = @{@"variantList":variantList, @"vaccineList":[self strippedVaxList]};
	return isPlist? [NSPropertyListSerialization dataWithPropertyList:info
			format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL] : 
		[NSJSONSerialization dataWithJSONObject:info
			options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];
}
static void check_vvlist(NSMutableArray *ma, NSArray *varList, NSDictionary *keys) {
	if (![ma isKindOfClass:NSMutableArray.class]) @throw @"Given list is not in array form.";
	for (NSInteger idx = 0; idx < ma.count; idx ++) {
		NSMutableDictionary *elm = ma[idx];
		if (![elm isKindOfClass:NSMutableDictionary.class]) @throw [NSString stringWithFormat:
			@"Element [%ld] is not in dictionary form.", idx];
		if (elm[@"name"] == nil) @throw [NSString stringWithFormat:
			@"Element [%ld] lacks the name.", idx];
		for (NSString *key in keys) if (elm[key] == nil) elm[key] = keys[key];
	}
	for (NSDictionary *md in varList) {
		NSString *vrName = md[@"name"];
		for (NSMutableDictionary *elm in ma) if (elm[vrName] == nil) elm[vrName] = @(1.);
	}
}
- (void)setupVVInfoWithPlist:(NSDictionary *)md {
	BOOL loaded = NO;
	NSMutableArray *ma = md[@"variantList"];
	if (ma != nil && [ma isKindOfClass:NSArray.class]) {
		ma = mutablized_array_of_dicts(ma);
		check_vvlist(ma, ma, @{@"reproductivity":@(1.), @"toxicity":@(1.)});
		NSArray<NSTableColumn *> *varTabCols = variantTable.tableColumns,
			*vaxTabCols = vaccineTable.tableColumns;
		NSInteger newVarCnt = ma.count, orgVarCnt = variantList.count;
		for (NSInteger i = 0; i < newVarCnt; i ++) {
			NSString *varName = ma[i][@"name"];
			if (i < orgVarCnt) varTabCols[i + VAR_PNL_EXCOLS].title =
				vaxTabCols[i + VAX_PNL_EXCOLS].title = varName; 
			else [self addVariantColumn:varName];
		}
		for (NSInteger i = orgVarCnt - 1; i >= newVarCnt; i --) {
			[variantTable removeTableColumn:varTabCols[i + VAR_PNL_EXCOLS]];
			[vaccineTable removeTableColumn:vaxTabCols[i + VAX_PNL_EXCOLS]];
		}
		variantList = ma;
		[variantTable reloadData];
		loaded = YES;
	}
	ma = md[@"vaccineList"];
	if (ma != nil && [ma isKindOfClass:NSArray.class]) {
		ma = mutablized_array_of_dicts(ma);
		check_vvlist(ma, variantList, @{@"intervalDays":@(21), @"intervalOn":@YES});
		vaccineList = ma;
		[vaccineTable reloadData];
		loaded = YES;
	}
	if (!loaded) @throw @"No valid data were found.";
}
- (void)setupVVInfoWithData:(NSData *)data isPlist:(BOOL)isPlist {
	NSError *error;
	NSMutableDictionary *md = isPlist?
		[NSPropertyListSerialization propertyListWithData:data
			options:NSPropertyListMutableContainers format:NULL error:&error] :
		[NSJSONSerialization JSONObjectWithData:data
			options:NSJSONReadingMutableContainers error:&error];
	if (md == nil) @throw [error.localizedDescription stringByAppendingFormat:
		@" %@ format.", isPlist? @"Property List" : @"JSON"];
	if (![md isKindOfClass:NSDictionary.class]) @throw @"Data is not in dictionary format.";
	return [self setupVVInfoWithPlist:md];
}
- (IBAction)copy:(id)sender {
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	[pb declareTypes:@[NSPasteboardTypeString] owner:NSApp];
	[pb setData:[self dataOfVVInfo:NO] forType:NSPasteboardTypeString];
}
- (IBAction)paste:(id)sender {
	NSData *data = [NSPasteboard.generalPasteboard dataForType:NSPasteboardTypeString];
	if (data == nil) return;
	@try {
		[self setupVVInfoWithData:data isPlist:NO];
	} @catch (NSObject *obj) { error_msg(obj, self.window, NO); }
}
- (IBAction)saveDocument:(id)sender {
	NSSavePanel *sp = NSSavePanel.new;
	sp.allowedFileTypes = @[@"sEpV", @"json"];
	[sp beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		[[self dataOfVVInfo:[sp.URL.pathExtension isEqualToString:@"sEpV"]]
			writeToURL:sp.URL atomically:YES];
	}];
}
- (IBAction)loadDocument:(id)sender {
	NSOpenPanel *op = NSOpenPanel.new;
	op.allowedFileTypes = @[@"sEpi", @"sEpV", @"json"];
	[op beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		@try {
			NSError *error;
			if ([op.URL.pathExtension isEqualToString:@"sEpi"]) {
				NSFileWrapper *fw = [NSFileWrapper.alloc initWithURL:op.URL options:0 error:&error];
				if (fw == nil) @throw error;
				if (fw.directory) {
					fw = fw.fileWrappers[fnParamsPList];
					if (fw == nil) @throw @"Couldn't find a prameter list.";
				}
				if (!fw.regularFile) @throw @"Illegular format.";
				NSDictionary *plist = plist_from_data(fw.regularFileContents);
				[self setupVVInfoWithPlist:plist];
			} else {
				NSData *data = [NSData dataWithContentsOfURL:op.URL options:0 error:&error];
				if (data == nil) @throw error;
				[self setupVVInfoWithData:data isPlist:
					[op.URL.pathExtension isEqualToString:@"sEpV"]];
			}
		} @catch (NSObject *obj) { error_msg(obj, self.window, NO); return; }
	}];
}
// TableView Data Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return (tableView == variantTable)? variantList.count : vaccineList.count;
}
// TableView Delegate
- (NSView *)tableView:(NSTableView *)tableView
	viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSString *ID = tableColumn.identifier;
	NSTableCellView *view = [tableView makeViewWithIdentifier:ID owner:self];
	NSArray *list = (tableView == variantTable)? variantList : vaccineList;
	NSDictionary *rowDict = list[row];
	if ([ID isEqualToString:@"name"]) {
		VVNameTextField *txtFld = (VVNameTextField *)view.textField;
		txtFld.stringValue = rowDict[ID];
		txtFld.row = row;
		txtFld.list = list;
	} else if ([@[@"reproductivity", @"toxicity"] containsObject:ID]) {
		view.textField.doubleValue = [rowDict[ID] doubleValue];
	} else if ([ID isEqualToString:@"interval"]) {
		view.textField.integerValue = [rowDict[@"intervalDays"] integerValue];
		NSControlStateValue value = [rowDict[@"intervalOn"] integerValue];
		((ShotIntervalView *)view).checkBox.state = value;
		view.textField.enabled = value == NSControlStateValueOn;
	} else {
		if (![ID isEqualToString:@"variant0"])
			view = [tableView makeViewWithIdentifier:@"variant0" owner:self];
		view.textField.doubleValue = [rowDict[tableColumn.title] doubleValue];
	}
	return view;
}
- (BOOL)tableView:(NSTableView *)tableView
	shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	return tableView == vaccineTable ||
		row > 0 || [tableColumn.identifier hasPrefix:@"variant"];
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
	[rmVariantBtn setEnabled:variantTable.selectedRow > 0];
	[rmVaccineBtn setEnabled:vaccineTable.selectedRow > 0];
}
@end

@implementation VVNameTextField
- (BOOL)textShouldEndEditing:(NSText *)textObject {
	NSString *str = textObject.string;
	if (str.length == 0) return NO;
	for (NSInteger i = 0; i < _list.count; i ++)
		if (i != _row && [str isEqualToString:_list[i][@"name"]]) return NO;
	return YES;
}
@end

@implementation ShotIntervalView
@end
