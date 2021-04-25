//
//  DataPanel.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/10.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "DataPanel.h"
#import "StatPanel.h"
#import "Document.h"
#import "World.h"

static NSInteger intervalDays[] = {0, 1, 2, 7, 10, 14, 30};
@implementation StatInfo (DataTableExtension)
- (void)buildTimeEvoData:(NSMutableArray<NSDictionary *> *)ma interval:(NSInteger)interval {
	NSInteger spd = self.world.worldParamsP->stepsPerDay;
	NSInteger skp = ((interval == 0)? 1 : interval * spd) / skip;
	if (skp <= 0) return;
	StatData *stat = self.statistics;
	for (NSInteger i = steps / skip; stat; i --, stat = stat->next) if (i % skp == 0) {
		NSUInteger *cnt = stat->cnt;
		[ma insertObject:@{
			@"Step":@(i * skip), @"Day":@(i * skip / spd), @"Susceptible":@(cnt[Susceptible]),
			@"Asymptomatic":@(cnt[Asymptomatic]), @"Symptomatic":@(cnt[Symptomatic]),
			@"Recovered":@(cnt[Recovered]), @"Died":@(cnt[Died]),
			@"Q(A)":@(cnt[QuarantineAsym]), @"Q(S)":@(cnt[QuarantineSymp])}
			atIndex:0];
	};
}
- (void)buildTransitData:(NSMutableArray<NSDictionary *> *)ma interval:(NSInteger)interval {
	NSInteger skp = interval / skipDays;
	if (skp <= 0) return;
	StatData *tran = self.transit;
	for (NSInteger i = days / skipDays; tran; i --, tran = tran->next) if (i % skp == 0) {
		NSUInteger *cnt = tran->cnt;
		[ma insertObject:@{
			@"Day":@(i * skipDays), @"Susceptible":@(cnt[Susceptible]),
			@"Asymptomatic":@(cnt[Asymptomatic]), @"Symptomatic":@(cnt[Symptomatic]),
			@"Recovered":@(cnt[Recovered]), @"Died":@(cnt[Died]),
			@"Q(A)":@(cnt[QuarantineAsym]), @"Q(S)":@(cnt[QuarantineSymp])}
			atIndex:0];
	};
}
- (void)buildTestsData:(NSMutableArray<NSDictionary *> *)ma interval:(NSInteger)interval {
	NSInteger skp = interval / skipDays;
	if (skp <= 0) return;
	StatData *tran = self.transit;
	NSInteger count[NIntTestTypes], *data = malloc(sizeof(NSInteger) * NIntTestTypes * days);
	for (NSInteger i = days - 1; tran && i >= 0; tran = tran->next, i --)
		memcpy(&data[i * NIntTestTypes], &tran->cnt[NStateIndexes], sizeof(NSInteger) * NIntTestTypes);
	for (NSInteger i = 0; i < days; i ++) {
		if (i % skp == 0) memcpy(count, &data[i * NIntTestTypes], sizeof(count));
		else for (NSInteger j = 0; j < NIntTestTypes; j ++)
			count[j] += data[i * NIntTestTypes + j];
		if (i % skp == skp - 1) [ma addObject:@{
			@"Day":@(i + 1), @"Total":@(count[TestTotal]),
			@"Symptomatic":@(count[TestAsSymptom]), @"Contact":@(count[TestAsContact]),
			@"Suspected":@(count[TestAsSuspected]),
			@"Positive":@(count[TestPositive]), @"Negative":@(count[TestNegative])}];
	};
	free(data);
}
- (void)buildHistogramData:(NSMutableArray<NSDictionary *> *)ma {
	NSInteger n[3] = {self.IncubPHist.count, self.RecovPHist.count, self.DeathPHist.count};
	NSInteger nMax = n[0];
	if (nMax < n[1]) nMax = n[1]; if (nMax < n[2]) nMax = n[2];
	for (NSInteger i = 0; i < nMax; i ++)
		[ma addObject:@{@"Days":@(i),
			@"Incubation":@((i < n[0])? self.IncubPHist[i].cnt : 0),
			@"Recovery":@((i < n[1])? self.RecovPHist[i].cnt : 0),
			@"Fatality":@((i < n[2])? self.DeathPHist[i].cnt : 0)
		}];
}
- (NSArray<NSDictionary<NSString *, NSNumber *> *> *)buildDataArray:(TableType)type
	interval:(NSInteger)interval {
	NSMutableArray<NSDictionary *> *ma = NSMutableArray.new;
	switch (type) {
		case TableTimeEvo: [self buildTimeEvoData:ma interval:interval]; break;
		case TableTransit: [self buildTransitData:ma interval:interval]; break;
		case TableTests: [self buildTestsData:ma interval:interval]; break;
		case TableHistgram: [self buildHistogramData:ma]; break;
	}
	return [NSArray arrayWithArray:ma];
}
- (BOOL)validateInterval:(NSInteger)interval type:(TableType)type {
	switch (type) {
		case TableTimeEvo:
		return (((interval == 0)? 1 : interval * self.world.worldParamsP->stepsPerDay) / skip > 0);
		case TableTransit: case TableTests:
		return (interval / skipDays > 0);
		default: return YES;
	}
}
@end

@implementation DataPanel
- (instancetype)initWithInfo:(StatInfo *)info {
	if (!(self = [super initWithWindowNibName:@"DataPanel"])) return nil;
	statInfo = info;
	return self;
}
- (NSTableView *)currentTableView {
	return (tableType == TableTimeEvo)? timeEvoTableView :
		(tableType == TableTransit)? transitTableView :
		(tableType == TableTests)? testsTableView : histogramTableView;
}
- (IBAction)buildData:(NSObject *)sender {
	TableType newType = (TableType)typePopUp.indexOfSelectedItem;
	if (newType != tableType) {
		tableType = newType;
		intervalPopUp.enabled = (newType != TableHistgram);
		timeEvoScrlView.hidden = (newType != TableTimeEvo);
		transitScrlView.hidden = (newType != TableTransit);
		testsScrView.hidden = (newType != TableTests);
		histogramScrlView.hidden = (newType != TableHistgram);
	}
	tableData = [statInfo buildDataArray:newType
		interval:intervalDays[intervalPopUp.indexOfSelectedItem]];
	[self.currentTableView reloadData];
}
- (IBAction)copy:(id)sender {
	NSMutableString *ms = NSMutableString.new;
	NSMutableArray<NSString *> *keys = NSMutableArray.new;
	NSArray<NSTableColumn *> *cols = self.currentTableView.tableColumns;
	NSString *sep = @"";
	for (NSTableColumn *col in cols) {
		[keys addObject:col.identifier];
		[ms appendFormat:@"%@%@", sep, col.title];
		sep = @"\t";
	}
	for (NSDictionary<NSString *, NSNumber *> *item in tableData) {
		sep = @"\n";
		for (NSString *key in keys) {
			[ms appendFormat:@"%@%ld", sep, item[key].integerValue];
			sep = @"\t";
		}
	}
	[ms appendString:@"\n"];
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	[pb declareTypes:@[NSPasteboardTypeString] owner:self];
	[pb setData:[ms dataUsingEncoding:NSUTF8StringEncoding]
		forType:NSPasteboardTypeString];
}
- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.alphaValue = panelsAlpha;
    tableType = (TableType)typePopUp.indexOfSelectedItem;
    NSInteger idx = intervalPopUp.indexOfSelectedItem;
    while (idx < intervalPopUp.numberOfItems
		&& ![statInfo validateInterval:intervalDays[idx] type:tableType]) idx ++;
    if (idx < intervalPopUp.numberOfItems)
		[intervalPopUp selectItemAtIndex:idx];
    [self buildData:self];
    [statInfo.doc setPanelTitle:self.window];
}
//
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem.menu != intervalPopUp.menu) return YES;
	return [statInfo validateInterval:
		intervalDays[[menuItem.menu indexOfItem:menuItem]] type:tableType];
}
//
- (BOOL)isDisplayedView:(NSTableView *)tableView {
	return tableView == self.currentTableView;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return [self isDisplayedView:tableView]? tableData.count : 0;
}
- (id)tableView:(NSTableView *)tableView
	objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	return [self isDisplayedView:tableView]? tableData[row][tableColumn.identifier] : nil;
}
- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object
	forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {}
@end
