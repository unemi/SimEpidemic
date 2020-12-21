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
#import "Agent.h"
#import "Gatherings.h"
#import "DataCompress.h"

static NSString *keyIncubation = @"incubation",
	*keyRecovery = @"recovery", *keyFatality = @"fatality",
	*keyInfects = @"infects",
	*keyStatCumm = @"statCumm", *keyTransDaily = @"transDaily", *keyTransCumm = @"transCumm",
	*keyTestCumm = @"testCumm", *keyTestResults = @"testResults",
	*keyPRateInfo = @"pRateInfo", *keyMaxValues = @"maxValues", *keyStepsAndSkips = @"stepsAndSkips",
	*keyScenarioPhases = @"scenarioPhases",
	*keyStatCnt = @"cnt", *keyStatPRate = @"pRate";

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
@end

@implementation Gathering (SaveDocExtension)
- (GatheringSave)saveData {
	return (GatheringSave){ size, duration, strength, p };
}
- (instancetype)initWithSavedData:(const GatheringSave *)sv
	map:(GatheringMap *)map world:(WorldParams *)wp {
	if (!(self = [super init])) return nil;
	size = sv->size;
	duration = sv->duration;
	strength = sv->strength;
	p = sv->p;
	[self setupCellIndexes:wp map:map];
	return self;
}
@end

@implementation Document (SaveDocExtension)
static NSString *fnParamsPList = @"initParams.plist",
	*fnPopulation = @"population.gz", *fnContacts = @"contacts.gz",
	*fnTestees = @"testees.gz", *fnWarps = @"warps.gz", *fnGatherings = @"gatherings.gz",
	*fnStatIndexes = @"statIndexes.gz", *fnStatTransit = @"statTransit.gz",
	*fnStatImageBM = @"statImageBitmap.gz",
	*fnStatInfo = @"statInfo.plist", *fnHistograms = @"hitograms.plist",
	*keyCurrentParams = @"currentParams",
	*keyStep = @"step", *keyScenarioIndex = @"scenarioIndex",
	*keyViewOffsetAndScale = @"viewOffsetAndScale";
- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel {
	savePanel.accessoryView = savePanelAccView;
	return YES;
}
static NSFileWrapper *fileWrapper_from_plist(NSObject *plist) {
	if (plist == nil) return nil;
	NSError *error;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
		format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
	if (data == nil) @throw error;
	return [NSFileWrapper.alloc initRegularFileWithContents:data];
}
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
	if (view.scale > 1.) dict[keyViewOffsetAndScale] =
		@[@(view.offset.x), @(view.offset.y), @(view.scale)];
	md[fnParamsPList] = fileWrapper_from_plist(dict);
	[dict removeAllObjects];

	NSInteger nPop = worldParams.initPop, unitJ = 8, n = 0, nn[unitJ];
	NSMutableData *mdata = [NSMutableData dataWithLength:sizeof(AgentSave) * nPop];
	AgentSave *as = mdata.mutableBytes;
	for (NSInteger j = 0; j < unitJ; j ++) {
		nn[j] = 0; NSInteger *np = nn + j;
		NSInteger start = j * nPop / unitJ, end = (j + 1) * nPop / unitJ;
		void (^block)(void) = ^{ for (NSInteger i = start; i < end; i ++) {
			Agent *a = self.agents + i;
			CP_S(app); CP_S(prf); CP_S(x); CP_S(y); CP_S(vx); CP_S(vy);
			CP_S(orgPt); CP_S(daysInfected); CP_S(daysDiseased);
			CP_S(daysToRecover); CP_S(daysToOnset); CP_S(daysToDie); CP_S(imExpr);
			CP_S(health); CP_S(nInfects);
			CP_S(distancing); CP_S(isOutOfField); CP_S(isWarping); CP_S(gotAtHospital);
			CP_S(inTestQueue); CP_S(lastTested);
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
					Agent *a = self.agents + i;
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
		md[fnContacts] = [NSFileWrapper.alloc initRegularFileWithContents:[mdata zippedData]];
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
	
	if (gatherings.count > 0) {
		mdata = [NSMutableData dataWithLength:sizeof(GatheringSave) * gatherings.count];
		GatheringSave *vp = mdata.mutableBytes;
		for (Gathering *gat in gatherings) *(vp ++) = gat.saveData;
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
	NSArray<NSNumber *> *arr;
	if ((arr = dict[keyViewOffsetAndScale]) != nil && arr.count >= 3) {
		CGPoint pt = (CGPoint){arr[0].doubleValue, arr[1].doubleValue};
		CGFloat sc = arr[2].doubleValue;
		void (^block)(MyView *) = ^(MyView *v){ v.offset = pt; v.scale = sc; };
		if (view == nil) {
			if (UIInitializers == nil) UIInitializers = NSMutableDictionary.new;
			UIInitializers[keyViewInits] = @[block];
		} else block(view);
	}
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
			CP_L(app); CP_L(prf); CP_L(x); CP_L(y); CP_L(vx); CP_L(vy);
			CP_L(orgPt); CP_L(daysInfected); CP_L(daysDiseased);
			CP_L(daysToRecover); CP_L(daysToOnset); CP_L(daysToDie); CP_L(imExpr);
			CP_L(health); CP_L(nInfects);
			CP_L(distancing); CP_L(isWarping); CP_L(gotAtHospital);
			CP_L(inTestQueue); CP_L(lastTested);
			a->ID = i;
			a->prev = a->next = NULL;
			a->contactInfoHead = a->contactInfoTail = NULL;
			a->isOutOfField = YES;
			if (!as[i].isOutOfField) add_agent(a, &worldParams, self.Pop);
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
		WarpInfo info = (WarpInfo){self.agents + vp->agentID, vp->mode, vp->goal};
		self.WarpList[@(vp->agentID)] = [NSValue valueWithWarpInfo:info];
	}
	if ((fw = dict[fnGatherings]) != nil) {
		NSData *data = [fw.regularFileContents unzippedData];
		const GatheringSave *vp = data.bytes;
		NSInteger n = data.length / sizeof(GatheringSave);
		for (NSInteger i = 0; i < n; i ++, vp ++) [gatherings addObject:
			[Gathering.alloc initWithSavedData:vp map:gatheringsMap world:&worldParams]];
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
	if (statInfo == nil) {
		if (UIInitializers == nil) UIInitializers = NSMutableDictionary.new;
		UIInitializers[keyStatInits] = statProcs;
	} else for (void (^block)(StatInfo *) in statProcs) block(statInfo);
	} @catch (NSError *error) { if (outError != NULL) *outError = error; return NO; }
	return YES;
}
@end
