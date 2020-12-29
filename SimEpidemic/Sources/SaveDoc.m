//
//  SaveDoc.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/12/14.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "SaveDoc.h"
#import "MyView.h"
#import "StatPanel.h"
#import "ParamPanel.h"
#import "Scenario.h"
#import "DataPanel.h"
#import "Agent.h"
#import "Gatherings.h"
#import "DataCompress.h"
#import <zlib.h>

static NSString *keyIncubation = @"incubation",
	*keyRecovery = @"recovery", *keyFatality = @"fatality",
	*keyInfects = @"infects",
	*keyStatCumm = @"statCumm", *keyTransDaily = @"transDaily", *keyTransCumm = @"transCumm",
	*keyTestCumm = @"testCumm", *keyTestResults = @"testResults",
	*keyPRateInfo = @"pRateInfo", *keyMaxValues = @"maxValues", *keyStepsAndSkips = @"stepsAndSkips",
	*keyScenarioPhases = @"scenarioPhases",
	*keyStatCnt = @"cnt", *keyStatPRate = @"pRate",
	*keyStatType = @"statType", *keyTimeEvoBits = @"timeEvoBits";

@implementation ParamPanel (SaveDocExtension)
static NSString *keySelectedTabIndex = @"selectedTabIndex";
- (NSDictionary *)UIInfoPlist {
	NSMutableDictionary *md = dict_of_window_geom(self.window);
	md[keySelectedTabIndex] = @([tabView indexOfTabViewItem:tabView.selectedTabViewItem]);
	return md;
}
- (void)applyUIInfo:(NSDictionary *)info {
	NSNumber *num;
	if ((num = info[keySelectedTabIndex]) != nil)
		[tabView selectTabViewItemAtIndex:num.integerValue];
	NSRect frm = frame_rect_from_dict(info);
	if (frm.size.width > 0.) [self.window setFrameOrigin:frm.origin];
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
		if (timeEvoInfo.idxBits & MskTransit)
			transitCBox.state = NSControlStateValueOn;
		[self setupColorForCBoxes];
	}
}
@end

@implementation StatInfo (SaveDocExtension)
static NSArray *counter_array(NSUInteger cnt[NIntIndexes]) {
	NSNumber *nums[NIntIndexes];
	for (NSInteger i = 0; i < NIntIndexes; i ++) nums[i] = @(cnt[i]);
	return [NSArray arrayWithObjects:nums count:NIntIndexes];
}
static NSDictionary *statData_plist(StatData *stat) {
	return @{keyStatCnt:counter_array(stat->cnt), keyStatPRate:@(stat->pRate)};
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
		keyScenarioPhases,
	nil };
	NSObject *values[] = { statData_plist(&statCumm),
		statData_plist(&transDaily), statData_plist(&transCumm),
		[NSArray arrayWithObjects:nums count:NIntTestTypes],
		[NSArray arrayWithObjects:trNums count:16],
		@[@(maxStepPRate), @(maxDailyPRate), @(pRateCumm)],
		@[counter_array(maxCounts), counter_array(maxTransit)],
		@[@(steps), @(skip), @(days), @(skipDays)],
		scenarioPhases
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
	NSNumber *num = plist[keyStatPRate];
	if (num != nil) stat->pRate = num.doubleValue;
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
	if ((arr = plist[keyTestResults]) != nil && arr.count >= 3) {
		maxStepPRate = arr[0].doubleValue;
		maxDailyPRate = arr[1].doubleValue;
		pRateCumm = arr[2].doubleValue;
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
	if ((arr = plist[keyScenarioPhases]) != nil)
		scenarioPhases = [NSMutableArray arrayWithArray:arr];
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
static NSData *data_from_stat(StatData *stat) {
	NSInteger n = 0;
	for (StatData *p = stat; p; p = p->next) n ++;
	if (n <= 0) return nil;
	NSMutableData *mdata = [NSMutableData dataWithLength:sizeof(StatDataSave) * n];
	StatDataSave *sv = mdata.mutableBytes;
	for (StatData *p = stat; p; p = p->next, sv ++) {
		memcpy(sv->cnt, p->cnt, sizeof(sv->cnt));
		sv->pRate = p->pRate;
	}
	return [mdata zippedData];
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
		if (stPrev != NULL) stPrev->next = st;
		stPrev = st;
	}
	return stHead;
}
- (NSData *)dataOfImageBitmap {
	return [NSData dataWithBytes:imgBm length:IMG_WIDTH * IMG_HEIGHT * 4];
}
- (void)copyImageBitmapFromData:(NSData *)data {
	memcpy(imgBm, data.bytes, IMG_WIDTH * IMG_HEIGHT * 4);
}
- (void)setPopsize:(NSInteger)psz { popSize = psz; }
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

@implementation Document (SaveDocExtension)
static NSString *fnParamsPList = @"initParams.plist",
	*fnPopulation = @"population.gz", *fnContacts = @"contacts.gz",
	*fnTestees = @"testees.gz", *fnWarps = @"warps.gz", *fnGatherings = @"gatherings.gz",
	*fnStatIndexes = @"statIndexes.gz", *fnStatTransit = @"statTransit.gz",
	*fnStatImageBM = @"statImageBitmap.gz",
	*fnStatInfo = @"statInfo.plist", *fnHistograms = @"hitograms.plist",
	*fnUIInfo = @"UIInfo.plist",
	*keyCurrentParams = @"currentParams",
	*keyStep = @"step", *keyScenarioIndex = @"scenarioIndex",
	*keyParamChangers = @"paramChangers",
	*keyViewOffsetAndScale = @"viewOffsetAndScale",
	*keyDocWindow = @"documentWindow",
	*keyStatWindows = @"statWindows", *keyParamPanel = @"paramPanel",
	*keyScenarioPanel = @"scenarioPanel", *keyDataPanel = @"dataPanel";
- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel {
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
		[self openScenarioPanel:nil];
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
		[statInfo setupPanelsWithPlist:dArr parent:view.window windowList:winList];
	if ((dict = info[keyDocWindow]) != nil) {
		NSRect frm = frame_rect_from_dict(dict);
		if (frm.size.width > 0.) [view.window setFrame:frm display:YES];
		window_order_info(view.window, dict, winList);
	}
	NSArray<NSNumber *> *nArr;
	if ((nArr = info[keyViewOffsetAndScale]) != nil && nArr.count >= 3) {
		view.offset = (CGPoint){nArr[0].doubleValue, nArr[1].doubleValue};
		view.scale = nArr[2].doubleValue;
		view.needsDisplay = YES;
	}
	rearrange_window_order(winList);
}
static NSFileWrapper *fileWrapper_from_plist(NSObject *plist) {
	if (plist == nil) return nil;
	NSError *error;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
		format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
	if (data == nil) @throw error;
	return [NSFileWrapper.alloc initRegularFileWithContents:data];
}
#define SAVE_AGENT_PROP(z) z(app); z(prf); z(x); z(y); z(vx); z(vy);\
z(orgPt); z(daysInfected); z(daysDiseased);\
z(daysToRecover); z(daysToOnset); z(daysToDie); z(imExpr); z(activeness);\
z(health); z(nInfects); z(distancing); z(isOutOfField); z(isWarping);\
z(inTestQueue); z(lastTested);

#define CP_S(m) as[i].m = a->m
- (NSFileWrapper *)fileWrapperOfType:(NSString *)typeName error:(NSError **)outError {
	@try {
	NSMutableDictionary *dict = NSMutableDictionary.new;
	dict[keyAnimeSteps] = @(animeSteps);
	if (stopAtNDays > 0) dict[keyDaysToStop] = @(stopAtNDays);
	dict[keyParameters] = param_dict(&initParams, &worldParams);
	NSDictionary *dif = param_diff_dict(&runtimeParams, &initParams);
	if (dif.count > 0) dict[keyCurrentParams] = dif;
	if (scenario != nil) dict[keyScenario] = [self scenarioPList];
	if (savePopCBox.state == NSControlStateValueOff || runtimeParams.step <= 0)
		return fileWrapper_from_plist(dict);
	NSMutableDictionary<NSString *,NSFileWrapper *> *md = NSMutableDictionary.new;
	if (scenario != nil) dict[keyScenarioIndex] = @(scenarioIndex);
	dict[keyStep] = @(runtimeParams.step);
	if (paramChangers != nil && paramChangers.count > 0)
		dict[keyParamChangers] = paramChangers;
	md[fnParamsPList] = fileWrapper_from_plist(dict);
	[dict removeAllObjects];

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
			for (ContactInfo *p = a->contactInfoHead; p; p = p->next) np[0] ++;
		}};
		if (j < unitJ - 1) [self addOperation:block]; else block();
	}
	[self waitAllOperations];
	md[fnPopulation] = [NSFileWrapper.alloc initRegularFileWithContents:[mdata zippedData]];
	for (NSInteger j = 0; j < unitJ; j ++) n += nn[j];

	if (n > 0) {
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
	
	md[fnStatInfo] = fileWrapper_from_plist([statInfo statiInfoPList]);
	md[fnHistograms] = fileWrapper_from_plist([statInfo dictOfHistograms]);
	NSData *data;
	if ((data = data_from_stat(statInfo.statistics)) != nil)
		md[fnStatIndexes] = [NSFileWrapper.alloc initRegularFileWithContents:data];
	if ((data = data_from_stat(statInfo.transit)) != nil)
		md[fnStatTransit] = [NSFileWrapper.alloc initRegularFileWithContents:data];
	md[fnStatImageBM] = [NSFileWrapper.alloc initRegularFileWithContents:
		[[statInfo dataOfImageBitmap] zippedData]];

	dict[keyDocWindow] = dict_of_window_geom(view.window);
	if (view.scale > 1.) dict[keyViewOffsetAndScale] =
		@[@(view.offset.x), @(view.offset.y), @(view.scale)];
	dict[keyStatWindows] = [statInfo UIInfoPlist];
	if (paramPanel != nil) dict[keyParamPanel] = [paramPanel UIInfoPlist];
	if (scenarioPanel != nil) dict[keyScenarioPanel] = [scenarioPanel UIInfoPlist];
	if (dataPanel != nil) dict[keyDataPanel] = [dataPanel UIInfoPlist];	
	md[fnUIInfo] = fileWrapper_from_plist(dict);

	return [NSFileWrapper.alloc initDirectoryWithFileWrappers:md];
	} @catch (NSError *error) { if (outError != NULL) *outError = error; return nil; }
}
static NSDictionary *plist_from_data(NSData *data) {
	NSError *error;
	NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data
		options:NSPropertyListImmutable format:NULL error:&error];
	if (plist == nil) @throw error;
	return plist;
}
- (BOOL)readParamsFromData:(NSData *)data error:(NSError **)outError {
	NSDictionary *dict = plist_from_data(data);
	NSNumber *num = dict[keyAnimeSteps];
	if (num != nil) animeSteps = num.integerValue;
	if ((num = dict[keyDaysToStop]) != nil) stopAtNDays = num.integerValue;
	NSDictionary *pDict = dict[keyParameters];
	if (pDict != nil) {
		set_params_from_dict(&initParams, &worldParams, pDict);
		memcpy(&tmpWorldParams, &worldParams, sizeof(WorldParams));
		memcpy(&runtimeParams, &initParams, sizeof(RuntimeParams));
	}
	if ((pDict = dict[keyCurrentParams]) != nil)
		set_params_from_dict(&runtimeParams, NULL, pDict);
	NSArray *seq = dict[keyScenario];
	if (seq != nil) {
		@try { [self setScenarioWithPList:seq]; }
		@catch (NSString *msg) { error_msg(msg, nil, NO); }
	}
	if ((num = dict[keyScenarioIndex]) != nil) scenarioIndex = num.integerValue;
	if ((num = dict[keyStep]) != nil) runtimeParams.step = num.integerValue;
	if ((pDict = dict[keyParamChangers]) != nil) paramChangers =
		[NSMutableDictionary dictionaryWithDictionary:pDict];
	return YES;
}
#define CP_L(m) a->m = as[i].m
- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper
	ofType:(NSString *)typeName error:(NSError **)outError {
	@try {
	if (fileWrapper.regularFile)
		return [self readParamsFromData:fileWrapper.regularFileContents error:outError];
	if (!fileWrapper.directory) return NO;
	NSDictionary *dict = fileWrapper.fileWrappers;
	NSFileWrapper *fw = dict[fnParamsPList];
	if (fw != nil && ![self readParamsFromData:fw.regularFileContents error:outError]) return NO;

	if ((fw = dict[fnPopulation]) != nil) {
		[self allocateMemory];
		NSData *data = [fw.regularFileContents unzippedData];
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
	} else return YES;

	if ((fw = dict[fnContacts]) != nil) {
		NSData *data = [fw.regularFileContents unzippedData];
		const NSInteger *vp = data.bytes;
		for (NSInteger i = 0; i < worldParams.initPop; i ++) {
			NSInteger n = vp[0];
			ContactInfoSave *sv = (ContactInfoSave *)(vp + 1);
			ContactInfo **cInfoP = &self.agents[i].contactInfoHead;
			for (NSInteger j = 0; j < n; j ++, sv ++) {
				ContactInfo *ci = self.agents[i].contactInfoTail = new_cinfo();
				ci->agent = self.agents + sv->agentID;
				ci->timeStamp = sv->timeStamp;
				ci->prev = *cInfoP; ci->next = NULL;
				*cInfoP = ci; cInfoP = &ci->next;
			}
			vp = (NSInteger *)sv;
		}
	}
	if ((fw = dict[fnTestees]) != nil) {
		NSData *data = [fw.regularFileContents unzippedData];
		const TestEntrySave *vp = data.bytes;
		NSInteger n = data.length / sizeof(TestEntrySave);
		TestEntry **tP = &testQueHead;
		for (NSInteger i = 0; i < n; i ++, vp ++) {
			TestEntry *te = testQueTail = new_testEntry();
			te->agent = self.agents + vp->agentID;
			te->timeStamp = vp->timeStamp;
			te->isPositive = vp->isPositive;
			te->prev = *tP; te->next = NULL;
			*tP = te; tP = &te->next;
		}
	}
	if ((fw = dict[fnWarps]) != nil) {
		NSData *data = [fw.regularFileContents unzippedData];
		const WarpInfoSave *vp = data.bytes;
		NSInteger n = data.length / sizeof(WarpInfoSave);
		for (NSInteger i = 0; i < n; i ++, vp ++) {
			WarpInfo info = (WarpInfo){self.agents + vp->agentID, vp->mode, vp->goal};
			self.WarpList[@(vp->agentID)] = [NSValue valueWithWarpInfo:info];
		}
	}
	if ((fw = dict[fnGatherings]) != nil) {
		NSData *data = [fw.regularFileContents unzippedData];
		const GatheringSave *sv = data.bytes;
		for (NSInteger nBytes = 0; nBytes < data.length; ) {
			Gathering *gat = new_n_gatherings(1);
			setup_with_saved_data(gat, sv, self.agents);
			gat->next = gatherings; gat->prev = NULL;
			if (gatherings) gatherings->prev = gat;
			gatherings = gat;
			NSInteger sz = sizeof(GatheringSave) + sizeof(NSInteger) * (sv->nAgents - 1);
			sv = (GatheringSave *)((char *)sv + sz);
			nBytes += sz;
		}
	}
	NSMutableArray *statProcs = NSMutableArray.new;
	if ((fw = dict[fnStatInfo]) != nil) [statProcs addObject:^(StatInfo *st) {
		[st setStatInfoFromPList:plist_from_data(fw.regularFileContents)]; }];
	if ((fw = dict[fnHistograms]) != nil) [statProcs addObject:^(StatInfo *st) {
		[st setHistgramsFromPList:plist_from_data(fw.regularFileContents)]; }];
	if ((fw = dict[fnStatIndexes]) != nil) [statProcs addObject:^(StatInfo *st) {
		st.statistics = stat_chain_from_data(fw.regularFileContents); }];
	if ((fw = dict[fnStatTransit]) != nil) [statProcs addObject:^(StatInfo *st) {
		st.transit = stat_chain_from_data(fw.regularFileContents); }];
	if ((fw = dict[fnStatImageBM]) != nil) [statProcs addObject:^(StatInfo *st) {
		[st copyImageBitmapFromData:[fw.regularFileContents unzippedData]]; }];
	NSInteger popSize = worldParams.initPop;
	[statProcs addObject:^(StatInfo *st) { st.popsize = popSize; }];
	void (^panelBlock)(Document *) = ((fw = dict[fnUIInfo]) == nil)? nil : ^(Document *doc){
		[doc setupPanelsWithInfo:plist_from_data(fw.regularFileContents)];
	};
	if (statInfo == nil) {
		statPanelInitializer = statProcs;
		if (panelBlock != nil) panelInitializer = panelBlock;
	} else {
		for (void (^block)(StatInfo *) in statProcs) block(statInfo);
		if (panelBlock != nil) panelBlock(self);
	}
	} @catch (NSError *error) { if (outError != NULL) *outError = error; return NO; }
	return YES;
}
@end
