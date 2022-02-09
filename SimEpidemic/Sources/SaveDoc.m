//
//  SaveDoc.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/12/14.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "SaveDoc.h"
#import "Scenario.h"
#ifdef NOGUI
#import "../../SimEpidemicSV/noGUI.h"
#else
#import "Document.h"
#import "MyView.h"
#import "ParamPanel.h"
#import "ScenPanel.h"
#import "DataPanel.h"
#endif
#import "Agent.h"
#import "StatPanel.h"
#import "Gatherings.h"
#import "../../SimEpidemicSV/DataCompress.h"
#import <zlib.h>
#define FORMAT_VER 2

static NSString *keyFormatVersion = @"formatVersion", *keyIncubation = @"incubation",
	*keyRecovery = @"recovery", *keyFatality = @"fatality", *keyInfects = @"infects",
	*keyStatCumm = @"statCumm", *keyTransDaily = @"transDaily", *keyTransCumm = @"transCumm",
	*keyTestCumm = @"testCumm", *keyTestResults = @"testResults",
	*keyPRateInfo = @"pRateInfo", *keyMaxValues = @"maxValues", *keyStepsAndSkips = @"stepsAndSkips",
	*keyScenarioPhases = @"scenarioPhases",
	*keyStatCnt = @"cnt", *keyStatPRate = @"pRate", *keyStatRRate = @"rRate",
	*keyInfecInfo = @"infecInfo",
	*keyStatType = @"statType", *keyWantDblDay = @"wantDoublingDay",
	*keyTimeEvoBits = @"timeEvoBits";
static NSString *keyVariantList = @"variantList", *keyVaccineList = @"vaccineList";
NSString *fnParamsPList = @"initParams.plist";
static NSString *fnPopulation = @"population.gz", *fnContacts = @"contacts.gz",
	*fnTestees = @"testees.gz", *fnWarps = @"warps.gz", *fnGatherings = @"gatherings.gz",
	*fnGatSpotsFixed = @"gatSpotsFixed.gz", *fnVaccineQueue = @"vaccineQueue.gz",
	*fnStatIndexes = @"statIndexes.gz", *fnStatTransit = @"statTransit.gz",
	*fnStatInfo = @"statInfo.plist", *fnHistograms = @"hitograms.plist",
	*keyCurrentParams = @"currentParams",
	*keyStep = @"step", *keyScenarioIndex = @"scenarioIndex",
	*keyParamChangers = @"paramChangers",
	*fnPopDensMap = @"populationDesityMap.gz",
	*fnSeverityStats = @"severityStats.gz",
	*fnVariantsStats = @"variantsStats.gz";
#ifndef NOGUI
static NSString *fnStatImageBM = @"statImageBitmap.gz",
	*fnUIInfo = @"UIInfo.plist",
	*keyViewOffsetAndScale = @"viewOffsetAndScale",
	*keyDocWindow = @"documentWindow",
	*keyStatWindows = @"statWindows", *keyParamPanel = @"paramPanel",
	*keyScenarioPanel = @"scenarioPanel", *keyDataPanel = @"dataPanel";
#endif
#ifndef NOGUI
@implementation ParamPanel (SaveDocExtension)
static NSString *keySelectedTabIndex = @"selectedTabIndex";
- (NSDictionary *)UIInfoPlist {
	NSMutableDictionary *md = dict_of_window_geom(self.window);
	md[keySelectedTabIndex] = @([tabView indexOfTabViewItem:tabView.selectedTabViewItem]);
	return md;
}
- (void)applyUIInfo:(NSDictionary *)info {
	NSNumber *num;
	self.byUser = NO;
	if ((num = info[keySelectedTabIndex]) != nil)
		[tabView selectTabViewItemAtIndex:num.integerValue];
	NSRect frm = frame_rect_from_dict(info);
	if (frm.size.width > 0.) [self.window setFrameOrigin:frm.origin];
	[self adjustControls];
}
@end

@implementation Scenario (SaveDocExtension)
static NSString *keyScrollY = @"scrollY", *keyExpandedItems = @"expandedItems";
static NSObject *expansion_info(NSOutlineView *outline, CondElmItem *item) {
	if (![item isKindOfClass:CompoundItem.class]) return @YES;
	NSMutableArray *ma = NSMutableArray.new;
	for (CondElmItem *subItem in ((CompoundItem *)item).children)
	if ([subItem isKindOfClass:CompoundItem.class]) {
		NSObject *elm = expansion_info(outline, subItem);
		[ma addObject:elm];
	}
	return ma;
}
- (NSDictionary *)UIInfoPlist {
	NSMutableDictionary *md = dict_of_window_geom(self.window);
	if (itemList == nil) return md;
	NSClipView *clpv = (NSClipView *)self.outlineView.superview;
	CGFloat y = clpv.documentVisibleRect.origin.y;
	if (y > 0.) md[keyScrollY] = @(y);
	NSMutableArray *ma = NSMutableArray.new;
	BOOL isExpanded = NO;
	for (ScenarioItem *item in itemList) if ([item isKindOfClass:CondItem.class]) {
		if ([self.outlineView isItemExpanded:item]) {
			[ma addObject:expansion_info(self.outlineView, ((CondItem *)item).element)];
			isExpanded = YES;
		} else [ma addObject:@NO];
	}
	if (isExpanded) md[keyExpandedItems] = ma;
	return md;
}
static void expand_item(NSOutlineView *outline, CondElmItem *item, NSArray *info) {
	[outline expandItem:item];
	NSEnumerator *enm = info.objectEnumerator;
	for (CondElmItem *subItem in ((CompoundItem *)item).children)
	if ([subItem isKindOfClass:CompoundItem.class]) {
		NSObject *obj = enm.nextObject;
		if (obj == nil || [obj isEqualTo:@NO]) continue;
		if ([obj isKindOfClass:NSArray.class])
			expand_item(outline, subItem, (NSArray *)obj);
		else [outline expandItem:subItem];
	}
}
- (void)applyUIInfo:(NSDictionary *)info {
	NSArray *arr;
	if ((arr = info[keyExpandedItems]) != nil) {
		NSEnumerator *enm = arr.objectEnumerator;
		for (ScenarioItem *item in itemList) if ([item isKindOfClass:CondItem.class]) {
			NSObject *obj = enm.nextObject;
			if ([obj isEqualTo:@NO]) continue;
			[self.outlineView expandItem:item];
			if ([obj isKindOfClass:NSArray.class])
				expand_item(self.outlineView, ((CondItem *)item).element, (NSArray *)obj);
		}
	}
	NSRect frm = frame_rect_from_dict(info);
	if (frm.size.width > 0.) [self.window setFrame:frm display:self.window.isVisible];
}
@end

@implementation DataPanel (SaveDocExtension)
static NSString *keyTableType = @"tableType", *keyIntervalIdx = @"intervalIndex";
- (NSDictionary *)UIInfoPlist {
	NSMutableDictionary *md = dict_of_window_geom(self.window);
	md[keyTableType] = @(typePopUp.indexOfSelectedItem);
	md[keyIntervalIdx] = @(intervalPopUp.indexOfSelectedItem);
	return md;
}
- (void)applyUIInfo:(NSDictionary *)info {
	NSNumber *num;
	if ((num = info[keyTableType]) != nil) {
		[typePopUp selectItemAtIndex:num.integerValue];
		[typePopUp sendAction:typePopUp.action to:typePopUp.target];
	}
	if ((num = info[keyIntervalIdx]) != nil) {
		[intervalPopUp selectItemAtIndex:num.integerValue];
		[intervalPopUp sendAction:intervalPopUp.action to:intervalPopUp.target];
	}
	NSRect frm = frame_rect_from_dict(info);
	if (frm.size.width > 0.) [self.window setFrame:frm display:self.window.isVisible];
}
@end

@implementation StatPanel (SaveDocExtension)
- (StatType)statType { return (StatType)typePopUp.indexOfSelectedItem; }
- (NSInteger)indexBits { return timeEvoInfo.idxBits; }
- (void)applyUIInfo:(NSDictionary *)dict {
	NSRect frm = frame_rect_from_dict(dict);
	if (frm.size.width > 0.) [self.window setFrame:frm display:YES];
	NSNumber *num;
	if ((num = dict[keyStatType]) != nil) {
		StatType type = (StatType)num.integerValue;
		[typePopUp selectItemAtIndex:type];
		[typePopUp sendAction:typePopUp.action to:typePopUp.target];
	}
	if ((num = dict[keyTimeEvoBits]) != nil) {
		timeEvoInfo.idxBits = num.integerValue;
		timeEvoInfo.nIndexes = 0;
		for (ULinedButton *btn in indexCBoxes) {
			BOOL isOn = (btn.tag & timeEvoInfo.idxBits) != 0;
			if (isOn) timeEvoInfo.nIndexes ++;
			btn.state = isOn? NSControlStateValueOn : NSControlStateValueOff;
		}
		transitCBox.state = (timeEvoInfo.idxBits & MskTransit)?
			NSControlStateValueOn : NSControlStateValueOff;
		[self setupColorForCBoxes];
	}
}
@end
#endif
@implementation StatInfo (SaveDocExtension)
static NSArray *counter_array(NSUInteger cnt[NIntIndexes]) {
	NSNumber *nums[NIntIndexes];
	for (NSInteger i = 0; i < NIntIndexes; i ++) nums[i] = @(cnt[i]);
	return [NSArray arrayWithObjects:nums count:NIntIndexes];
}
static NSDictionary *statData_plist(StatData *stat) {
	return @{keyStatCnt:counter_array(stat->cnt),
		keyStatPRate:@(stat->pRate), keyStatRRate:@(stat->reproRate)};
}
- (NSDictionary *)statiInfoPList {
	NSNumber *nums[NIntTestTypes], *trNums[16];
	for (NSInteger i = 0; i < NIntTestTypes; i ++) nums[i] = @(testCumm[i]);
	trNums[0] = @(self.testResultCnt.positive);
	trNums[1] = @(self.testResultCnt.negative);
	for (NSInteger i = 0; i < 7; i ++) {
		trNums[i * 2 + 2] = @(testResultsW[i].positive);
		trNums[i * 2 + 3] = @(testResultsW[i].negative);
	}
	NSString *keys[] = {keyStatCumm, keyTransDaily, keyTransCumm,
		keyTestCumm, keyTestResults, keyPRateInfo, keyMaxValues, keyStepsAndSkips,
		keyInfecInfo,
#ifndef NOGUI 
		keyScenarioPhases,
#endif
	nil };
	NSObject *values[] = { statData_plist(&statCumm),
		statData_plist(&transDaily), statData_plist(&transCumm),
		[NSArray arrayWithObjects:nums count:NIntTestTypes],
		[NSArray arrayWithObjects:trNums count:16],
		@[@(maxStepPRate), @(maxDailyPRate), @(minReproRate), @(maxReproRate)],
		@[counter_array(maxCounts), counter_array(maxTransit)],
		@[@(steps), @(skip), @(days), @(skipDays)],
		@{@"len":@(infectedSeq.len), @"n":@(infectedSeq.n), @"tail":@(infectedSeq.tail),
			@"rec":[NSData dataWithBytes:infectedSeq.rec length:sizeof(CGFloat) * infectedSeq.len]
		}
#ifndef NOGUI
		, scenarioPhases
#endif
	};
	NSMutableDictionary *md = NSMutableDictionary.new;
	for (NSInteger i = 0; keys[i] != nil; i ++)
		if (values[i] != nil) md[keys[i]] = values[i];
	return md;
}
static void setCounter_from_array(NSArray<NSNumber *> *arr, NSUInteger *cnt, NSInteger n) {
	if (arr != nil) for (NSInteger i = 0; i < arr.count && i < n; i ++)
		cnt[i] = arr[i].integerValue;
}
static void statData_from_plist(NSDictionary *plist, StatData *stat) {
	setCounter_from_array(plist[keyStatCnt], stat->cnt, NIntIndexes);
	NSNumber *num;
	if ((num = plist[keyStatPRate]) != nil) stat->pRate = num.doubleValue;
	if ((num = plist[keyStatRRate]) != nil) stat->reproRate = num.doubleValue;
}
- (void)setStatInfoFromPList:(NSDictionary *)plist {
	NSDictionary *dct; NSArray<NSNumber *> *arr;
	if ((dct = plist[keyStatCumm]) != nil) statData_from_plist(dct, &statCumm);
	if ((dct = plist[keyTransDaily]) != nil) statData_from_plist(dct, &transDaily);
	if ((dct = plist[keyTransCumm]) != nil) statData_from_plist(dct, &transCumm);
	if ((arr = plist[keyTestCumm]) != nil) setCounter_from_array(arr, testCumm, NIntTestTypes);
	if ((arr = plist[keyTestResults]) != nil && arr.count >= 16) {
		self.testResultCnt = (TestResultCount){arr[0].integerValue, arr[1].integerValue};
		for (NSInteger i = 0; i < 7; i ++) {
			testResultsW[i].positive = arr[i * 2 + 2].integerValue;
			testResultsW[i].negative = arr[i * 2 + 3].integerValue;
		}
	}
	if ((arr = plist[keyTestResults]) != nil && arr.count >= 4) {
		maxStepPRate = arr[0].doubleValue;
		maxDailyPRate = arr[1].doubleValue;
		minReproRate = arr[2].doubleValue;
		maxReproRate = arr[3].doubleValue;
	}
	NSArray<NSArray<NSNumber *> *> *arar;
	if ((arar = plist[keyMaxValues]) != nil && arar.count >= 2) {
		setCounter_from_array(arar[0], maxCounts, NIntIndexes);
		setCounter_from_array(arar[1], maxTransit, NIntIndexes);
	}
	if ((arr = plist[keyStepsAndSkips]) != nil && arr.count >= 4) {
		steps = arr[0].integerValue;
		skip = arr[1].integerValue;
		days = arr[2].integerValue;
		skipDays = arr[3].integerValue;
	}
	if ((dct = plist[keyInfecInfo]) != nil) {
		infectedSeq.len = [dct[@"len"] integerValue];
		infectedSeq.n = [dct[@"n"] integerValue];
		infectedSeq.tail = [dct[@"tail"] integerValue];
		NSInteger recLen = sizeof(CGFloat) * infectedSeq.len;
		infectedSeq.rec = realloc(infectedSeq.rec, recLen);
		NSData *data = dct[@"rec"];
		if (data != nil && data.length == recLen)
			memcpy(infectedSeq.rec, data.bytes, recLen);
	}
#ifndef NOGUI
	if ((arr = plist[keyScenarioPhases]) != nil)
		scenarioPhases = [NSMutableArray arrayWithArray:arr];
#endif
}
static NSArray *array_from_hist(NSMutableArray<MyCounter *> *hist) {
	if (hist == nil || hist.count == 0) return @[];
	NSNumber *nums[hist.count];
	for (NSInteger i = 0; i < hist.count; i ++) nums[i] = @(hist[i].cnt);
	return [NSArray arrayWithObjects:nums count:hist.count];
}
- (NSDictionary *)dictOfHistograms {
	NSString *keys[] = {keyIncubation, keyRecovery, keyFatality, keyInfects};
	NSArray *values[] = { array_from_hist(self.IncubPHist),
		array_from_hist(self.RecovPHist), array_from_hist(self.DeathPHist),
		array_from_hist(self.NInfectsHist) };
	return [NSDictionary dictionaryWithObjects:values forKeys:keys count:4];
}
static void hist_from_array(NSArray<NSNumber *> *array,
	NSMutableArray<MyCounter *> *hist) {
	[hist removeAllObjects];
	for (NSInteger i = 0; i < array.count; i ++)
		[hist addObject:[MyCounter.alloc initWithCount:array[i].integerValue]];
}
- (void)setHistgramsFromPList:(NSDictionary *)plist {
	NSString *keys[] = {keyIncubation, keyRecovery, keyFatality, keyInfects};
	NSMutableArray<MyCounter *> *hists[] =
		{ self.IncubPHist, self.RecovPHist, self.DeathPHist, self.NInfectsHist };
	for (NSInteger i = 0; i < 4; i ++) {
		NSArray<NSNumber *> *array;
		if ((array = plist[keys[i]]) != nil) hist_from_array(array, hists[i]);
	}
}
static StatData *stat_chain_from_data(NSData *data) {
	data = [data unzippedData];
	const StatDataSave *sv = data.bytes;
	NSInteger n = data.length / sizeof(StatDataSave);
	StatData *stHead = new_stat(), *stPrev = NULL;
	for (NSInteger i = 0; i < n; i ++, sv ++) {
		StatData *st = (i == 0)? stHead : new_stat();
		memcpy(st->cnt, sv->cnt, sizeof(st->cnt));
		st->pRate = sv->pRate;
		st->reproRate = sv->reproRate;
		if (stPrev != NULL) stPrev->next = st;
		stPrev = st;
	}
	return stHead;
}
- (void)setPopsize:(NSInteger)psz { popSize = psz; }
- (NSData *)dataOfSeverityStats {
	NSInteger nSteps = days / skipDays;
	return (nSteps <= 0)? nil : [NSData dataWithBytes:self.sspData.bytes
		length:sizeof(NSInteger) * nSteps * SSP_NRanks];
}
- (NSData *)dataOfVariantsStats {
	NSInteger nSteps = days / skipDays;
	return (nSteps <= 0)? nil : [NSData dataWithBytes:self.variantsData.bytes
		length:sizeof(NSInteger) * nSteps * MAX_N_VARIANTS];
}
#ifndef NOGUI
- (NSData *)dataOfImageBitmap {
	return [NSData dataWithBytes:imgBm length:IMG_WIDTH * IMG_HEIGHT * 4];
}
- (void)copyImageBitmapFromData:(NSData *)data {
	memcpy(imgBm, data.bytes, IMG_WIDTH * IMG_HEIGHT * 4);
}
- (NSArray *)UIInfoPlist {
	NSMutableArray *ma = NSMutableArray.new;
	for (StatPanel *sp in self.statPanels) {
		NSMutableDictionary *md = dict_of_window_geom(sp.window);
		md[keyStatType] = @(sp.statType);
		if (sp.statType == StatTimeEvo) md[keyTimeEvoBits] = @(sp.indexBits);
		[ma addObject:md];
	}
	return ma;
}
- (void)setupPanelsWithPlist:(NSArray *)info parent:(NSWindow *)parentWindow
	windowList:(NSMutableArray *)winList {
	NSEnumerator *enm = self.statPanels.objectEnumerator;
	StatPanel *panel;
	for (NSDictionary *dict in info) {
		if (enm == nil || (panel = enm.nextObject) == nil) {
			[self openStatPanel:parentWindow];
			panel = self.statPanels.lastObject;
		}
		[panel applyUIInfo:dict];
		window_order_info(panel.window, dict, winList);
	}
	while ((panel = enm.nextObject) != nil) [panel close];
}
#endif
@end

static void set_save_data(Gathering *gat, GatheringSave *sv) {
	sv->size = gat->size;
	sv->duration = gat->duration;
	sv->strength = gat->strength;
	sv->p = gat->p;
	NSInteger j = 0;
	for (NSInteger i = 0; i < gat->nAgents; i ++)
		if (gat->agents[i] != NULL) sv->agentIDs[j ++] = gat->agents[i]->ID;
	sv->nAgents = j;
}
static void setup_with_saved_data(Gathering *gat, const GatheringSave *sv, Agent *agents) {
	gat->size = sv->size;
	gat->duration = sv->duration;
	gat->strength = sv->strength;
	gat->p = sv->p;
	gat->nAgents = sv->nAgents;
	gat->agents = malloc(sizeof(void *) * sv->nAgents);
	for (NSInteger i = 0; i < sv->nAgents; i ++)
		gat->agents[i] = agents + sv->agentIDs[i];
}
static NSFileWrapper *fileWrapper_from_plist(NSObject *plist) {
	if (plist == nil) return nil;
	NSError *error;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
		format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
	if (data == nil) @throw error;
	return [NSFileWrapper.alloc initRegularFileWithContents:data];
}
static NSData *data_from_stat(StatData *stat) {
	NSInteger n = 0;
	for (StatData *p = stat; p; p = p->next) n ++;
	if (n <= 0) return nil;
	NSMutableData *mdata = [NSMutableData dataWithLength:sizeof(StatDataSave) * n];
	StatDataSave *sv = mdata.mutableBytes;
	for (StatData *p = stat; p; p = p->next, sv ++) {
		memcpy(sv->cnt, p->cnt, sizeof(sv->cnt));
		sv->pRate = p->pRate;
		sv->reproRate = p->reproRate;
	}
	return [mdata zippedData];
}
NSDictionary *plist_from_data(NSData *data) {
	NSError *error;
	NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data
		options:NSPropertyListImmutable format:NULL error:&error];
	if (plist == nil) @throw error;
	return plist;
}
MutableDictArray mutablized_array_of_dicts(NSArray<NSDictionary *> *list) {
	if (![list isKindOfClass:NSArray.class]) return nil;
	else if ([list isKindOfClass:NSMutableArray.class]) {
		BOOL mutable = YES;
		for (NSDictionary *dict in list)
			if (![dict isKindOfClass:NSMutableDictionary.class]) { mutable = NO; break; }
		if (mutable) return (NSMutableArray *)list;
	}
	NSMutableArray *ma = NSMutableArray.new;
	for (NSDictionary *dict in list) {
		if (![dict isKindOfClass:NSDictionary.class]) continue;
		else if ([dict isKindOfClass:NSMutableDictionary.class]) [ma addObject:dict];
		else [ma addObject:[NSMutableDictionary dictionaryWithDictionary:dict]];
	}
	return ma;
}

@implementation World (SaveDocExtension)
- (void)addParams:(NSMutableDictionary *)dict {
	if (stopAtNDays > 0) dict[keyDaysToStop] = @(stopAtNDays);
	dict[keyParameters] = param_dict(&initParams, &worldParams);
	NSDictionary *dif = param_diff_dict(&runtimeParams, &initParams, NULL, NULL);
	if (dif.count > 0) dict[keyCurrentParams] = dif;
	if (scenario != nil) dict[keyScenario] = [self scenarioPList];
	dict[keyVariantList] = self.variantList;
	dict[keyVaccineList] = self.vaccineList;
}
#define SAVE_AGENT_PROP(z) z(app); z(prf); z(x); z(y); z(vx); z(vy);\
z(orgPt); z(daysInfected); z(daysDiseased); z(severity);\
z(daysToRecover); z(daysToOnset); z(daysToDie); z(imExpr); z(firstDoseDate); z(agentImmunity);\
z(mass); z(mobFreq); z(gatFreq); z(age); z(activeness);\
z(health); z(forVcn); z(nInfects); z(virusVariant); z(vaccineType);\
z(distancing); z(isOutOfField); z(isWarping); z(inTestQueue); z(onRecovery); z(lastTested);

#define CP_S(m) as[i].m = a->m
- (void)addSavePop:(NSMutableDictionary *)md info:(NSMutableDictionary *)dict {
	if (scenario != nil) dict[keyScenarioIndex] = @(scenarioIndex);
	dict[keyStep] = @(runtimeParams.step);
	if (paramChangers != nil && paramChangers.count > 0)
		dict[keyParamChangers] = paramChangers;

	NSInteger nPop = worldParams.initPop, unitJ = 8, n = 0, nn[unitJ];
	NSMutableData *mdata = [NSMutableData dataWithLength:sizeof(AgentSave) * nPop];
	AgentSave *as = mdata.mutableBytes;
	Agent *agents = self.agents;
	for (NSInteger j = 0; j < unitJ; j ++) {
		nn[j] = 0; NSInteger *np = nn + j;
		NSInteger start = j * nPop / unitJ, end = (j + 1) * nPop / unitJ;
		void (^block)(void) = ^{ for (NSInteger i = start; i < end; i ++) {
			Agent *a = agents + i;
			SAVE_AGENT_PROP(CP_S)
			for (ContactInfo *p = a->contactInfoHead; p; p = p->next) np[0] ++; // count contancts
		}};
		if (j < unitJ - 1) [self addOperation:block]; else block();
	}
	[self waitAllOperations];
	md[fnPopulation] = [NSFileWrapper.alloc initRegularFileWithContents:[mdata zippedData]];
	for (NSInteger j = 0; j < unitJ; j ++) n += nn[j];

	if (n > 0) {	// save contacts
		mdata = [NSMutableData dataWithLength:sizeof(ContactInfoSave) * n + sizeof(NSInteger) * nPop];
		NSInteger *saveP = mdata.mutableBytes, kStart = 0;
		for (NSInteger j = 0; j < unitJ; j ++) {
			NSInteger start = j * nPop / unitJ, end = (j + 1) * nPop / unitJ;
			void (^block)(void) = ^{
				NSInteger *vp = saveP + kStart;
				for (NSInteger i = start; i < end; i ++) {
					Agent *a = agents + i;
					NSInteger count = 0;
					for (ContactInfo *p = a->contactInfoHead; p; p = p->next)
						((ContactInfoSave *)(vp + 1))[count ++] =
							(ContactInfoSave){p->timeStamp, p->agent->ID};
					vp[0] = count;
					vp += 1 + (sizeof(ContactInfoSave) / sizeof(NSInteger)) * count;
			}};
			if (j < unitJ - 1) [self addOperation:block]; else block();
			kStart += end - start + sizeof(ContactInfoSave) / sizeof(NSInteger) * nn[j];
		}
		[self waitAllOperations];
		md[fnContacts] = [NSFileWrapper.alloc initRegularFileWithContents:
			[mdata zippedDataWithLevel:Z_BEST_SPEED]];
	}

	n = 0;
	for (TestEntry *p = testQueHead; p; p = p->next) n ++;
	if (n > 0) {
		mdata = [NSMutableData dataWithLength:sizeof(TestEntrySave) * n];
		TestEntrySave *vp = mdata.mutableBytes;
		for (TestEntry *p = testQueHead; p; p = p->next, vp ++) {
			vp->timeStamp = p->timeStamp;
			vp->isPositive = p->isPositive;
			vp->agentID = p->agent->ID;
		}
		md[fnTestees] = [NSFileWrapper.alloc initRegularFileWithContents:[mdata zippedData]];
	}

	if (self.WarpList.count > 0) {
		mdata = [NSMutableData dataWithLength:sizeof(WarpInfoSave) * self.WarpList.count];
		WarpInfoSave *vp = mdata.mutableBytes;
		for (NSValue *v in self.WarpList.objectEnumerator) {
			WarpInfo info = v.warpInfoValue;
			vp->mode = info.mode;
			vp->goal = info.goal;
			vp->agentID = info.agent->ID;
			vp ++;
		}
		md[fnWarps] = [NSFileWrapper.alloc initRegularFileWithContents:[mdata zippedData]];
	}
	
	NSInteger nGatherings = 0;
	for (Gathering *gat = gatherings; gat != NULL; gat = gat->next) nGatherings ++;
	if (nGatherings > 0) {
		NSInteger agentsCount = 0;
		for (Gathering *gat = gatherings; gat != NULL; gat = gat->next) {
			NSInteger ac = 0;
			for (NSInteger i = 0; i < gat->nAgents; i ++) if (gat->agents[i] != NULL) ac ++;
			agentsCount += ac;
		}
		mdata = [NSMutableData dataWithLength:
			(sizeof(GatheringSave) - sizeof(NSInteger)) * nGatherings +
			sizeof(NSInteger) * agentsCount];
		GatheringSave *sv = mdata.mutableBytes;
		for (Gathering *gat = gatherings; gat != NULL; gat = gat->next) {
			set_save_data(gat, sv);
			sv = (GatheringSave *)((NSInteger *)(sv + 1) + sv->nAgents - 1);
		}
		md[fnGatherings] = [NSFileWrapper.alloc initRegularFileWithContents:[mdata zippedData]];
	}

	if (nGatSpotsFixed > 0) md[fnGatSpotsFixed] = [NSFileWrapper.alloc
		initRegularFileWithContents:[[NSData dataWithBytesNoCopy:gatSpotsFixed
		length:sizeof(NSPoint) * nGatSpotsFixed] zippedData]];

	mdata = [NSMutableData dataWithLength:
		sizeof(VaccineQueueSave) + sizeof(NSInteger) * (nPop * N_VCN_QUEQUE - 1)];
	VaccineQueueSave *vcnMem = mdata.mutableBytes;
	memcpy(vcnMem->subjRem, vcnSubjRem, sizeof(vcnSubjRem));
	memcpy(vcnMem->index, vcnQueIdx, sizeof(vcnQueIdx));
	memcpy(vcnMem->queue, vcnQueue, sizeof(NSInteger) * nPop * N_VCN_QUEQUE);
	md[fnVaccineQueue] = [NSFileWrapper.alloc initRegularFileWithContents:[mdata zippedData]];
	md[fnStatInfo] = fileWrapper_from_plist([statInfo statiInfoPList]);
	md[fnHistograms] = fileWrapper_from_plist([statInfo dictOfHistograms]);
	NSData *data;
	if ((data = data_from_stat(statInfo.statistics)) != nil)
		md[fnStatIndexes] = [NSFileWrapper.alloc initRegularFileWithContents:data];
	if ((data = data_from_stat(statInfo.transit)) != nil)
		md[fnStatTransit] = [NSFileWrapper.alloc initRegularFileWithContents:data];
	if ((data = [statInfo dataOfSeverityStats]) != nil)
		md[fnSeverityStats] = [NSFileWrapper.alloc initRegularFileWithContents:[data zippedData]];
	if ((data = [statInfo dataOfVariantsStats]) != nil)
		md[fnVariantsStats] = [NSFileWrapper.alloc initRegularFileWithContents:[data zippedData]];
#ifndef NOGUI
	md[fnStatImageBM] = [NSFileWrapper.alloc initRegularFileWithContents:
		[[statInfo dataOfImageBitmap] zippedData]];
#endif
}
- (void)addSavePopDens:(NSMutableDictionary *)md {
	NSBitmapImageRep *imgRep = make_bm_with_image(self.popDistImage);
	md[fnPopDensMap] = [NSFileWrapper.alloc initRegularFileWithContents:
		[[NSData dataWithBytes:imgRep.bitmapData
			length:imgRep.bytesPerRow * imgRep.pixelsHigh] zippedData]];
}
- (NSDictionary *)readParamsFromDict:(NSDictionary *)dict {
	NSNumber *num;
	NSDictionary *pDict;
	NSArray *seq;
	if ((num = dict[keyDaysToStop]) != nil) stopAtNDays = num.integerValue;
	if ((pDict = dict[keyParameters]) != nil) {
		set_params_from_dict(&initParams, &worldParams, pDict);
		memcpy(&tmpWorldParams, &worldParams, sizeof(WorldParams));
		memcpy(&runtimeParams, &initParams, sizeof(RuntimeParams));
	}
	if ((pDict = dict[keyCurrentParams]) != nil)
		set_params_from_dict(&runtimeParams, NULL, pDict);
	if ((num = dict[keyStep]) != nil) {
		runtimeParams.step = num.integerValue;
		loopMode = LoopNone;
	}
//
	if ((seq = dict[keyScenario]) != nil) {
		@try { [self setScenarioPList:seq]; }
		@catch (NSString *msg) { ERROR_MSG(msg); }
	}
	if (scenario != nil && (num = dict[keyScenarioIndex]) != nil) {
		scenarioIndex = num.integerValue;
		if (scenarioIndex > 0 && scenarioIndex <= scenario.count) {
			predicateToStop = predicate_in_item(scenario[scenarioIndex - 1], NULL);
			if (predicateToStop == nil) ERROR_MSG(@"Indexed scenario item is not a predicate.");
		} else predicateToStop = nil;
	}
	if ((pDict = dict[keyParamChangers]) != nil) paramChangers =
		[NSMutableDictionary dictionaryWithDictionary:pDict];
	BOOL vvLoaded = NO;
	if ((seq = dict[keyVariantList]) != nil)
		{ self.variantList = mutablized_array_of_dicts(seq); vvLoaded = YES; }
	if ((seq = dict[keyVaccineList]) != nil)
		{ self.vaccineList = mutablized_array_of_dicts(seq); vvLoaded = YES; }
	if (vvLoaded) [self setupVaxenAndVariantsFromLists];
	return dict;
}
#define CP_L(m) a->m = as[i].m
- (void)readPopFromFileWrapper:(NSFileWrapper *)fw {
	if (!fw.regularFile) return;
	[self allocateMemory];
	NSData *data = [fw.regularFileContents unzippedData];
	if (data.length != sizeof(AgentSave) * worldParams.initPop)
		@throw @"Saved population data was short.";
	const AgentSave *as = data.bytes;
	for (NSInteger i = 0; i < worldParams.initPop; i ++) {
		Agent *a = self.agents + i;
		SAVE_AGENT_PROP(CP_L)
		a->ID = i;
		a->prev = a->next = NULL;
		a->contactInfoHead = a->contactInfoTail = NULL;
		a->newHealth = a->health;
		a->isOutOfField = YES;
		if (!as[i].isOutOfField) add_agent(a, &worldParams, self.Pop);
		else if (!a->isWarping) {
			if (a->health == Died) add_to_list(a, self.CListP);
			else add_to_list(a, self.QListP);
		}
	}
	[self organizeAgeSpanInfo];
}
- (void)readContactsFromFileWrapper:(NSFileWrapper *)fw {
	if (!fw.regularFile) return;
	NSData *data = [fw.regularFileContents unzippedData];
	const NSInteger *vp = data.bytes;
	for (NSInteger i = 0; i < worldParams.initPop; i ++) {
		NSInteger n = vp[0];
		ContactInfoSave *sv = (ContactInfoSave *)(vp + 1);
		ContactInfo **cInfoP = &self.agents[i].contactInfoHead, *ciPre = NULL;
		for (NSInteger j = 0; j < n; j ++, sv ++) {
			ContactInfo *ci = self.agents[i].contactInfoTail = [self newCInfo];
			ci->agent = self.agents + sv->agentID;
			ci->timeStamp = sv->timeStamp;
			ci->prev = ciPre; ciPre = ci; ci->next = NULL;
			*cInfoP = ci; cInfoP = &ci->next;
		}
		vp = (NSInteger *)sv;
	}
}
- (void)readTestsFromFileWrapper:(NSFileWrapper *)fw {
	if (!fw.regularFile) return;
	NSData *data = [fw.regularFileContents unzippedData];
	const TestEntrySave *vp = data.bytes;
	NSInteger n = data.length / sizeof(TestEntrySave);
	TestEntry **tP = &testQueHead, *tPre = NULL;
	for (NSInteger i = 0; i < n; i ++, vp ++) {
		TestEntry *te = testQueTail = [self newTestEntry];
		te->agent = self.agents + vp->agentID;
		te->timeStamp = vp->timeStamp;
		te->isPositive = vp->isPositive;
		te->prev = tPre; tPre = te; te->next = NULL;
		*tP = te; tP = &te->next;
	}
}
- (void)readWarpsFromFileWrapper:(NSFileWrapper *)fw {
	if (!fw.regularFile) return;
	NSData *data = [fw.regularFileContents unzippedData];
	const WarpInfoSave *vp = data.bytes;
	NSInteger n = data.length / sizeof(WarpInfoSave);
	for (NSInteger i = 0; i < n; i ++, vp ++) {
		WarpInfo info = (WarpInfo){self.agents + vp->agentID, vp->mode, vp->goal};
		self.WarpList[@(vp->agentID)] = [NSValue valueWithWarpInfo:info];
	}
}
- (void)readGatheringsFromFileWrapper:(NSFileWrapper *)fw {
	if (!fw.regularFile) return;
	NSData *data = [fw.regularFileContents unzippedData];
	const GatheringSave *sv = data.bytes;
	for (NSInteger nBytes = 0; nBytes < data.length; ) {
		Gathering *gat = [self newNGatherings:1];
		setup_with_saved_data(gat, sv, self.agents);
		gat->next = gatherings; gat->prev = NULL;
		if (gatherings) gatherings->prev = gat;
		gatherings = gat;
		NSInteger sz = sizeof(GatheringSave) + sizeof(NSInteger) * (sv->nAgents - 1);
		sv = (GatheringSave *)((char *)sv + sz);
		nBytes += sz;
	}
}
- (void)readVaccineQueueFromFileWrapper:(NSFileWrapper *)fw {
	if (!fw.regularFile) return;
	NSData *data = [fw.regularFileContents unzippedData];
	NSInteger dtSz = sizeof(NSInteger) * (worldParams.initPop * N_VCN_QUEQUE - 1);
	if (data.length >= sizeof(VaccineQueueSave) + dtSz) {
		const VaccineQueueSave *sv = data.bytes;
		memcpy(vcnSubjRem, sv->subjRem, sizeof(vcnSubjRem));
		memcpy(vcnQueIdx, sv->index, sizeof(vcnQueIdx));
		memcpy(vcnQueue, sv->queue, sizeof(NSInteger) * worldParams.initPop * N_VCN_QUEQUE);
	}
}
- (void)resetVaccineQueueIfNecessary {
	if (vcnQueue != NULL) [self resetVaccineQueue];
}
- (void)readPopDensMapFromFileWrapper:(NSFileWrapper *)fw {
	if (!fw.regularFile) return;
	NSData *data = [fw.regularFileContents unzippedData];
	NSBitmapImageRep *imgRep = make_pop_dist_bm();
	NSInteger nBytes = imgRep.bytesPerRow * imgRep.pixelsHigh;
	if (data.length >= nBytes) {
		memcpy(imgRep.bitmapData, data.bytes, nBytes);
		NSImage *img = [NSImage.alloc initWithSize:imgRep.size];
		[img addRepresentation:imgRep];
		self.popDistImage = img;
	}
}
#ifdef NOGUI
- (NSFileWrapper *)fileWrapperOfWorld {
	NSMutableDictionary *dict = NSMutableDictionary.new;
	dict[keyFormatVersion] = @(FORMAT_VER);
	[self addParams:dict];
	NSMutableDictionary<NSString *,NSFileWrapper *> *md = NSMutableDictionary.new;
	[self addSavePop:md info:dict];
	if (self.popDistImage != nil) [self addSavePopDens:md];
	md[fnParamsPList] = fileWrapper_from_plist(dict);
	return [NSFileWrapper.alloc initDirectoryWithFileWrappers:md];;
}
#else
- (NSFileWrapper *)fileWrapperOfSaveDoc:(SavePopFlags)flag
	paramDict:(NSDictionary *)pDict fileDict:(NSDictionary *)fDict {
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:pDict];
	dict[keyFormatVersion] = @(FORMAT_VER);
	[self addParams:dict];
	if (flag == SaveOnlyParams) return fileWrapper_from_plist(dict);
	NSMutableDictionary<NSString *,NSFileWrapper *> *md =
		[NSMutableDictionary dictionaryWithDictionary:fDict];
	if (flag & SavePopulation) [self addSavePop:md info:dict];
	if ((flag & SavePMap) && self.popDistImage != nil) [self addSavePopDens:md];
	md[fnParamsPList] = fileWrapper_from_plist(dict);
	return [NSFileWrapper.alloc initDirectoryWithFileWrappers:md];;
}
#endif
static void copy_data_from_fw(NSFileWrapper *fw, NSMutableData *dstData) {
	if (!fw.regularFile) return;
	NSData *srcData = [fw.regularFileContents unzippedData];
	NSInteger srcLen = srcData.length, dstLen = dstData.length;
	memcpy(dstData.mutableBytes, srcData.bytes, (srcLen < dstLen)? srcLen : dstLen);
	if (dstLen > srcLen) memset(dstData.mutableBytes + srcLen, 0, dstLen - srcLen);
}
- (BOOL)readFromDict:(NSDictionary *)dict error:(NSError **)outError {
	@try {
	NSFileWrapper *fw = dict[fnParamsPList];
	if (fw == nil || !fw.regularFile) @throw @"Parameters are missing.";
	NSDictionary *pDict = [self readParamsFromDict:plist_from_data(fw.regularFileContents)];
	NSNumber *num = pDict[keyFormatVersion];
	if ((num == nil && dict[fnStatIndexes] != nil)
		|| num.integerValue < FORMAT_VER) @throw @"The file format seems to be old.";
	else if (num.integerValue > FORMAT_VER) @throw @"The file format is too new.";
	if ((fw = dict[fnPopulation]) != nil) [self readPopFromFileWrapper:fw];
	if ((fw = dict[fnContacts]) != nil) [self readContactsFromFileWrapper:fw];
	if ((fw = dict[fnTestees]) != nil) [self readTestsFromFileWrapper:fw];
	if ((fw = dict[fnWarps]) != nil) [self readWarpsFromFileWrapper:fw];
	if ((fw = dict[fnGatherings]) != nil) [self readGatheringsFromFileWrapper:fw];
	if ((fw = dict[fnVaccineQueue]) != nil) [self readVaccineQueueFromFileWrapper:fw];
	else [self resetVaccineQueueIfNecessary];
	if ((fw = dict[fnSeverityStats]) != nil) copy_data_from_fw(fw, statInfo.sspData);
	if ((fw = dict[fnVariantsStats]) != nil) copy_data_from_fw(fw, statInfo.variantsData);
	NSMutableArray *statProcs = NSMutableArray.new;
	if ((fw = dict[fnStatInfo]) != nil) [statProcs addObject:^(StatInfo *st) {
		[st setStatInfoFromPList:plist_from_data(fw.regularFileContents)]; }];
	if ((fw = dict[fnHistograms]) != nil) [statProcs addObject:^(StatInfo *st) {
		[st setHistgramsFromPList:plist_from_data(fw.regularFileContents)]; }];
	if ((fw = dict[fnStatIndexes]) != nil) [statProcs addObject:^(StatInfo *st) {
		st.statistics = stat_chain_from_data(fw.regularFileContents); }];
	if ((fw = dict[fnStatTransit]) != nil) [statProcs addObject:^(StatInfo *st) {
		st.transit = stat_chain_from_data(fw.regularFileContents); }];
	if ((fw = dict[fnPopDensMap]) != nil) [self readPopDensMapFromFileWrapper:fw];
	NSInteger popSize = worldParams.initPop;
	[statProcs addObject:^(StatInfo *st) { st.popsize = popSize; }];
	if (statInfo != nil) for (void (^block)(StatInfo *) in statProcs) block(statInfo);
	} @catch (NSError *error) { if (outError != NULL) *outError = error; return NO;
	} @catch (NSString *msg) {
		if (outError != NULL) *outError = [NSError errorWithDomain:@"SimEpi" code:1
			userInfo:@{NSLocalizedFailureReasonErrorKey:NSLocalizedString(msg, nil)}];
		return NO;
	}
	return YES;
}
#ifdef NOGUI
- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper error:(NSError **)outError {
	if (fileWrapper.regularFile) {
		NSDictionary *dict = plist_from_data(fileWrapper.regularFileContents);
		if ([self readParamsFromDict:dict] == nil) return NO;
		[self resetVaccineQueueIfNecessary];
		return YES;
	} else if (!fileWrapper.directory) return NO;
	NSDictionary *dict = fileWrapper.fileWrappers;
	return [self readFromDict:dict error:outError];
}
#endif
@end

#ifndef NOGUI
@implementation Document (SaveDocExtension)
- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel {
	savePMapCBox.enabled = (world.popDistImage != nil);
	savePanel.accessoryView = savePanelAccView;
	return YES;
}
- (void)setupPanelsWithInfo:(NSDictionary *)info {
	NSDictionary *dict;
	NSMutableArray<NSArray *> *winList = NSMutableArray.new;
	if ((dict = info[keyParamPanel]) != nil) {
		[self openParamPanel:nil];
		[paramPanel applyUIInfo:dict];
		window_order_info(paramPanel.window, dict, winList);
	}
	if ((dict = info[keyScenarioPanel]) != nil) {
		BOOL alreadyOpen = scenarioPanel != nil;
		[self openScenarioPanel:nil];
		if (alreadyOpen) [scenarioPanel makeDocItemList];
		[scenarioPanel applyUIInfo:dict];
		window_order_info(scenarioPanel.window, dict, winList);
	}
	if ((dict = info[keyDataPanel]) != nil) {
		[self openDataPanel:nil];
		[dataPanel applyUIInfo:dict];
		window_order_info(dataPanel.window, dict, winList);
	}
	NSArray<NSDictionary *> *dArr;
	if ((dArr = info[keyStatWindows]) != nil)
		[world.statInfo setupPanelsWithPlist:dArr parent:view.window windowList:winList];
	if ((dict = info[keyDocWindow]) != nil) {
		NSRect frm = frame_rect_from_dict(dict);
		if (frm.size.width > 0.) [view.window setFrame:frm display:YES];
		window_order_info(view.window, dict, winList);
	}
	NSArray<NSNumber *> *nArr;
	if ((nArr = info[keyViewOffsetAndScale]) != nil && nArr.count >= 3) {
		view.offset = (NSPoint){nArr[0].doubleValue, nArr[1].doubleValue};
		view.scale = nArr[2].doubleValue;
		view.needsDisplay = YES;
	}
	rearrange_window_order(winList);
}
- (NSMutableDictionary *)dictOfSaveGUI {
	NSMutableDictionary *dict = NSMutableDictionary.new;
	dict[keyDocWindow] = dict_of_window_geom(view.window);
	if (view.scale > 1.) dict[keyViewOffsetAndScale] =
		@[@(view.offset.x), @(view.offset.y), @(view.scale)];
	dict[keyStatWindows] = [world.statInfo UIInfoPlist];
	if (paramPanel != nil) dict[keyParamPanel] = [paramPanel UIInfoPlist];
	if (scenarioPanel != nil) dict[keyScenarioPanel] = [scenarioPanel UIInfoPlist];
	if (dataPanel != nil) dict[keyDataPanel] = [dataPanel UIInfoPlist];
	return dict;
//	md[fnUIInfo] = fileWrapper_from_plist(dict);
}
- (NSFileWrapper *)fileWrapperOfType:(NSString *)typeName error:(NSError **)outError {
	SavePopFlags flag = SaveOnlyParams;
	if (savePopCBox.state == NSControlStateValueOn && world.runtimeParamsP->step > 0)
		flag |= SavePopulation;
	if (saveGUICBox.state == NSControlStateValueOn) flag |= SaveGUI;
	if (savePMapCBox.state == NSControlStateValueOn) flag |= SavePMap;
	return [world fileWrapperOfSaveDoc:flag
		paramDict:@{keyAnimeSteps:@(animeSteps)}
		fileDict:((flag & SaveGUI) == 0)? nil :
			@{fnUIInfo:fileWrapper_from_plist([self dictOfSaveGUI])}];
}
- (NSDictionary *)readParamsFromFileWrapper:(NSFileWrapper *)fw {
	NSDictionary *dict = plist_from_data(fw.regularFileContents);
	NSNumber *num;
	if ((num = dict[keyAnimeSteps]) != nil) animeSteps = num.integerValue;
	return (world == nil)? dict : [world readParamsFromDict:dict];
}
- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper
	ofType:(NSString *)typeName error:(NSError **)outError {
	@try {
	if (fileWrapper.regularFile) {
		NSDictionary *dict = [self readParamsFromFileWrapper:fileWrapper];
		if (dict == nil) return NO;
		if (world == nil) worldInitializer = ^(World *wd, NSError **outError) {
				[wd readParamsFromDict:dict];
				[wd resetVaccineQueueIfNecessary]; return YES;
			};
		else [world resetVaccineQueueIfNecessary];
		return YES;
	} else if (!fileWrapper.directory) return NO;
	NSDictionary *dict = fileWrapper.fileWrappers;
	NSFileWrapper *fw;
	NSMutableArray *statProcs = NSMutableArray.new;
	if ((fw = dict[fnStatImageBM]) != nil) [statProcs addObject:^(StatInfo *st) {
		[st copyImageBitmapFromData:[fw.regularFileContents unzippedData]]; }];
	void (^panelBlock)(Document *) = ((fw = dict[fnUIInfo]) == nil)? nil : ^(Document *doc){
		[doc setupPanelsWithInfo:plist_from_data(fw.regularFileContents)];
	};
	if (world == nil) {
		worldInitializer = ^(World *wd, NSError **outError) {
			return [wd readFromDict:dict error:outError]; };
		statPanelInitializer = statProcs;
		panelInitializer = panelBlock;
	} else {
		[world readFromDict:dict error:outError];
		for (void (^block)(StatInfo *) in statProcs) block(world.statInfo);
		if (panelBlock != nil) panelBlock(self);
		[self adjustScenarioText:nil];
	}
	} @catch (NSError *error) { if (outError != NULL) *outError = error; return NO;
	} @catch (NSString *msg) {
		if (outError != NULL) *outError = [NSError errorWithDomain:@"SimEpi" code:1
			userInfo:@{NSLocalizedFailureReasonErrorKey:NSLocalizedString(msg, nil)}];
		return NO;
	}
	return YES;
}
@end
#endif
