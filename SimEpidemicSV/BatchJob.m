//
//  BatchJob.m
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/09/14.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "BatchJob.h"
#import "noGUI.h"
#import "SaveState.h"
#import "../SimEpidemic/Sources/Gatherings.h"
#import "../SimEpidemic/Sources/StatPanel.h"
#import "../SimEpidemic/Sources/Scenario.h"
#import "../SimEpidemic/Sources/SaveDoc.h"
#import <os/log.h>

@implementation StatInfo (JobResultExtension)
- (NSArray *)objectWithStatData:(StatData *)statData
	skip:(NSInteger)stepSkip names:(NSArray *)names {
	struct { IndexType type; NSInteger idx; } idxs[names.count];
	for (NSInteger i = 0; i < names.count; i ++) {
		NSNumber *num;
		if ((num = indexNameToIndex[names[i]]) != nil)
			{ idxs[i].type = IdxTypeIndex; idxs[i].idx = num.integerValue; }
		else if ((num = testINameToIdx[names[i]]) != nil)
			{ idxs[i].type = IdxTypeTestI; idxs[i].idx = num.integerValue; }
		else if ([names[i] isEqualToString:@"testPositiveRate"]) idxs[i].type = IdxTypePRate;
		else if ([names[i] isEqualToString:@"reproductionRate"]) idxs[i].type = IdxTypeRRate;
		else idxs[i].type = IdxTypeUnknown;
	}
	NSInteger nRows = 1;
	StatData *stat = statData;
	for (; stat; stat = stat->next) nRows ++;
	NSMutableArray *rows = NSMutableArray.new;
	stat = statData;
	for (NSInteger i = nRows - 1; stat; stat = stat->next, i --) {
		NSMutableArray *row = [NSMutableArray arrayWithObject:@(i * stepSkip)];
		for (NSInteger j = 0; j < names.count; j ++) switch (idxs[j].type) {
			case IdxTypeIndex:
				[row addObject:@(stat->cnt[idxs[j].idx])]; break;
			case IdxTypeTestI:
				[row addObject:@(stat->cnt[idxs[j].idx + NStateIndexes])]; break;
			case IdxTypePRate: [row addObject:@(stat->pRate)]; break;
			case IdxTypeRRate: [row addObject:@(stat->reproRate)]; break;
			default: [row addObject:@0];
		}
		[rows insertObject:row atIndex:0];
	}
	NSMutableArray *head = [NSMutableArray arrayWithArray:names];
	[head insertObject:@"" atIndex:0];
	[rows insertObject:head atIndex:0];
	return rows;
}
- (NSArray *)objectOfTimeEvoTableWithNames:(NSArray *)names {
	return [self objectWithStatData:self.statistics skip:skip names:names];
}
- (NSArray *)objectOfTransitTableWithNames:(NSArray *)names {
	return [self objectWithStatData:self.transit skip:skipDays names:names];
}
- (NSArray *)objectOfHistgramTableWithNames:(NSArray *)names {
	NSMutableArray<NSString *> *head = [NSMutableArray arrayWithArray:names];
	NSMutableArray<NSMutableArray<MyCounter *> *> *cols = NSMutableArray.new;
	NSDictionary *histDict = [NSDictionary dictionaryWithObjects:
		@[self.IncubPHist, self.RecovPHist, self.DeathPHist, self.NInfectsHist]
		forKeys:distributionNames];
	for (NSString *name in names) {
		NSMutableArray<MyCounter *> *hist = histDict[name];
		if (hist != nil) [cols addObject:hist];
		else [head removeObject:name];
	}
	[head insertObject:@"" atIndex:0];
	NSMutableArray *rows = [NSMutableArray arrayWithObject:head];
	NSInteger nRest = cols.count, n[nRest];
	for (NSInteger i = 0; i < cols.count; i ++)
		if ((n[i] = cols[i].count) == 0) nRest --;
	for (NSInteger i = 0; nRest > 0; i ++) {
		NSMutableArray *row = [NSMutableArray arrayWithObject:@(i)];
		for (NSInteger j = 0; j < cols.count; j ++) {
			[row addObject:@((i < n[j])? cols[j][i].cnt : 0)];
			if (i == n[j] - 1) nRest --;
		}
		[rows addObject:row];
	}
	return rows;
}
- (NSArray *)objectOfStatsInData:(NSData *)data unit:(NSInteger)unit days:(BOOL)isDays {
	NSInteger *p = (NSInteger *)data.bytes, nSteps, nSkip;
	if (isDays) { nSteps = days / skipDays; nSkip = skipDays; }
	else { nSteps = steps / skip; nSkip = skip; }
	NSMutableArray *rows = NSMutableArray.new;
	NSNumber *row[unit + 1];
	for (NSInteger i = 0; i < nSteps; i ++, p += unit) {
		row[0] = @((i + 1) * skip);
		for (NSInteger j = 0; j < unit; j ++) row[j + 1] = @(p[j]);
		[rows addObject:[NSArray arrayWithObjects:row count:unit + 1]];
	}
	return rows;
}
@end

static NSString *batchJobInfoFileName = @"info.json";
static NSString *unfinishedJobListFileName = @"UnfinishedJobIDs.txt";
static JobController *the_job_controller(void) {
	static JobController *theJobController = nil;
	if (theJobController == nil) theJobController = JobController.new;
	return theJobController;
}
NSString *batch_job_dir(void) {
	static NSString *batchJobDir = nil;
	if (batchJobDir == nil) batchJobDir = data_hostname_path(@"BatchJob");
	return batchJobDir;
}
@implementation JobController
- (instancetype)init {
	if (!(self = [super init])) return nil;
	lock = NSLock.new;
	theJobs = NSMutableDictionary.new;
	jobQueue = NSMutableArray.new;
	unfinishedJobIDs = NSMutableArray.new;
	return self;
}
- (void)tryNewTrialInJobQueue {
	NSInteger index = 0;
	while (index < jobQueue.count && nRunningTrials < maxTrialsAtSameTime) {
		BatchJob *jb = jobQueue[index];
		if (![jb checkStateDependency]) index ++;
		else if ([jb runNextTrial]) nRunningTrials ++;
		else [jobQueue removeObjectAtIndex:index];
	}
}
- (void)checkStateWaitingJob:(NSTimer *)timer {
	[lock lock];
	[self tryNewTrialInJobQueue];
	if (nRunningTrials == maxTrialsAtSameTime || jobQueue.count == 0) [timer invalidate];
	[lock unlock];
}
- (void)tryNewTrial:(BOOL)trialFinished {
	[lock lock];
	if (trialFinished) nRunningTrials --;
	if (jobQueue.count > 0) {
		[self tryNewTrialInJobQueue];
		if (nRunningTrials == 0 && jobQueue.count > 0) {
			[NSTimer scheduledTimerWithTimeInterval:20 target:self
				selector:@selector(checkStateWaitingJob:) userInfo:nil repeats:YES];
			BatchJob *bj = jobQueue[0];
			MY_LOG("Job %@ is waiting for state file %@.", bj.ID, bj.loadState);
		}
	}
	[lock unlock];
}
- (void)saveUnfinishedJobIDs {
	NSString *path = [batch_job_dir() stringByAppendingPathComponent:unfinishedJobListFileName];
	NSMutableString *jobIDList = NSMutableString.new;
	for (NSString *ID in unfinishedJobIDs) [jobIDList appendFormat:@"%@\n", ID];
	NSError *error;
	if (![jobIDList writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error])
		MY_LOG("Unfinished JOB ID list could not be saved in %@. %@",
			path, error.localizedDescription);
}
- (void)submitJob:(BatchJob *)job {
	[lock lock];
	theJobs[job.ID] = job;
	[jobQueue addObject:job];
	[unfinishedJobIDs addObject:job.ID];
	[self saveUnfinishedJobIDs];
	[lock unlock];
	[self tryNewTrial:NO];
}
- (void)finishJobID:(NSString *)jobID {
	[lock lock];
	[unfinishedJobIDs removeObject:jobID];
	[self saveUnfinishedJobIDs];
	[lock unlock];
}
- (void)removeJobFromQueue:(BatchJob *)job shouldLock:(BOOL)shouldLock {
	if (shouldLock) [lock lock];
	[jobQueue removeObject:job];
	if (shouldLock) [lock unlock];
}
- (BatchJob *)jobFromID:(NSString *)jobID { return theJobs[jobID]; }
- (NSInteger)queueLength { return jobQueue.count; }
- (NSInteger)nRunningTrials { return nRunningTrials; }
- (NSInteger)indexOfJobInQueue:(BatchJob *)job {
	return [jobQueue indexOfObject:job];
}
- (void)forAllLiveWorlds:(void (^)(World *))block {
	[lock lock];
	NSArray *jobs = theJobs.allValues;
	[lock unlock];
	for (BatchJob *job in jobs)
		[job forAllLiveWorlds:block];
}
@end
// to check how much this machine is busy now. called from Contract.m
void for_all_bacth_job_documents(void (^block)(World *)) {
	[the_job_controller() forAllLiveWorlds:block];
}

@implementation BatchJob
#ifdef DEBUG
- (void)monitorProgress {
	if (runningTrials.count == 0) return;
	char buf[128];
	int k = 0;
	for (NSNumber *num in runningTrials) {
		k += snprintf(buf + k, 128 - k, "%ld:%d, ", num.integerValue,
			runningTrials[num].runtimeParamsP->step);
		if (k >= 127) break;
	}
	MY_LOG("%s", buf);
}
#endif
static NSString *check_paramname_in_chng_prm_elm(NSArray *prop) {
	NSString *paramName = prop[0];
	if (![paramName isKindOfClass:NSString.class]) return nil;
	@try {
		NSNumber *idxNum = paramIndexFromKey[(NSString *)prop[0]];
		if (idxNum != nil) {
			NSInteger idx = idxNum.integerValue;
			if ((idx >= IDX_I && idx < IDX_E) || idx >= IDX_H) {
				if (![paramName hasPrefix:@"vaccine"] || prop.count > 2)
					@throw @"invalid to modify in scenario.";
			}
		} else if ([paramName hasPrefix:@"vaccine"]) {
			NSString *suffix;
			NSScanner *scan = [NSScanner scannerWithString:paramName];
			[scan scanString:@"vaccine" intoString:NULL];
			[scan scanUpToString:@" " intoString:&suffix];
			if ([@[@"PerformRate", @"Priority", @"Regularity", @"FinalRate"]
				indexOfObject:suffix] == NSNotFound) @throw @"unknown parameter name";
		} else if ([paramName hasPrefix:@"regGat "]) {
			NSArray<NSString *> *args = [paramName componentsSeparatedByString:@" "];
			if (args.count < 2) @throw @"invalid parameter form";
			if ([@[@"minAge", @"maxAge",
				@"duration", @"freq", @"npp", @"size", @"strength", @"participation"]
				indexOfObject:args[1]] == NSNotFound) @throw @"unknown parameter name";
		} else @throw @"unknown parameter name";
	} @catch (NSString *msg) {
		return [NSString stringWithFormat:@"\"%@\" is %@.", paramName, msg]; }
	return nil;
}
static NSString *check_scenario_element_from_property(NSObject *prop) {
// returns nil when it looks OK, otherwise return a string of error message
	NSString *predForm = nil;
	if ([prop isKindOfClass:NSString.class]) predForm = (NSString *)prop;
	else if (![prop isKindOfClass:NSArray.class]) return nil;
	else if (((NSArray *)prop).count != 2) return check_paramname_in_chng_prm_elm((NSArray *)prop);
	else if (![((NSArray *)prop)[1] isKindOfClass:NSString.class])
		return check_paramname_in_chng_prm_elm((NSArray *)prop);
	else predForm = (NSString *)((NSArray *)prop)[1];
	if (predForm == nil || predForm.length == 0) return @"Null predicate";
	@try { return ([NSPredicate predicateWithFormat:predForm] == nil)? @"Null" : nil; }
	@catch (NSException *e) { return e.reason; }
}
static void add_vv_list(MutableDictArray base, MutableDictArray new) {
	for (NSMutableDictionary *elm in base) {
		NSString *name = elm[@"name"];
		for (NSInteger j = new.count - 1; j >= 0; j --)
		if ([name isEqualToString:new[j][@"name"]]) {
			for (NSString *key in new[j]) elm[key] = new[j][key];
			[new removeObjectAtIndex:j];
			break;
		}
	}
	if (new.count > 0) [base addObjectsFromArray:new];
}
- (instancetype)initWithInfo:(NSDictionary *)info ID:(NSString *)ID {
	if (!(self = [super init])) return nil;
	_ID = (ID != nil)? ID : new_uniq_string();
	jobDirPath = [batch_job_dir() stringByAppendingPathComponent:_ID];
	_parameters = info[@"params"];
	_scenario = info[@"scenario"];
	if (_scenario != nil && ![_scenario isKindOfClass:NSArray.class])
		@throw @"417 Scenario is not an array.";
	for (NSObject *elm in _scenario) {
		NSString *errMsg = check_scenario_element_from_property(elm);
		if (errMsg != nil)
			@throw [NSString stringWithFormat:@"417 Invalid element in scenario: %@", errMsg];
	}
	NSNumber *num;
	_stopAt = ((num = info[@"stopAt"]) == nil)? 0 : num.integerValue;
	_nIteration = ((num = info[@"n"]) == nil)? 1 : num.integerValue;
	if ((_loadState = info[@"loadState"]) != nil) _loadState = fullpath_of_load_state(_loadState);
	popDistMap = info[@"popDistMap"];
	loadVV = info[@"loadVariantsAndVaccines"];
	moreVaccines = info[@"vaccines"];
	moreVariants = info[@"variants"];
	loadGatherings = info[@"loadGatherings"];
	moreGatherings = info[@"gatherings"];
	if (_nIteration <= 1) _nIteration = 1;
	NSArray<NSString *> *output = info[@"out"];
	if (output != nil && output.count > 0) {
		NSInteger n = output.count, nn = 0, nd = 0, nD = 0;
		NSString *an[n], *ad[n], *aD[n];
		for (NSString *key in output) {
			if (indexNames[key] != nil || [key isEqualToString:@"reproductionRate"]) an[nn ++] = key;
			else if ([key hasPrefix:@"daily"]) {
				unichar uc = [key characterAtIndex:5];
				if (uc < 'A' || uc > 'Z') continue;
				NSString *newKey = key.stringByRemovingFirstWord;
				if (indexNames[newKey] != nil || [key isEqualToString:@"testPositiveRate"])
					ad[nd ++] = newKey;
			} else if ([distributionNames containsObject:key]) aD[nD ++] = key;
			else if ([key isEqualToString:@"severityStats"]) shouldSaveSeverityStats = YES;
			else if ([key isEqualToString:@"variantsStats"]) shouldSaveVariantsStats = YES;
			else if ([key isEqualToString:@"vaccination"]) shouldSaveVcnRecord = YES;
			else if ([key isEqualToString:@"saveState"]) shouldSaveState = YES;
		}
		output_n = [NSArray arrayWithObjects:an count:nn];
		output_d = [NSArray arrayWithObjects:ad count:nd];
		output_D = [NSArray arrayWithObjects:aD count:nD];
	}
	lock = NSLock.new;
	runningTrials = NSMutableDictionary.new;
	availableWorlds = NSMutableArray.new;
#ifdef DEBUG
	in_main_thread(^{
		[NSTimer scheduledTimerWithTimeInterval:10. repeats:YES block:
			^(NSTimer * _Nonnull timer) { [self monitorProgress]; }]; });
#endif
	return self;
}
- (BOOL)checkStateDependency {
	return (_loadState == nil || stateDependencyIsOK)? YES : (stateDependencyIsOK =
		[NSFileManager.defaultManager fileExistsAtPath:_loadState] );
}
- (BOOL)saveInfoData:(NSData *)infoData {
	@try {
		BOOL isDir;
		NSError *error;
		NSFileManager *fm = NSFileManager.defaultManager;
		if (![fm fileExistsAtPath:jobDirPath isDirectory:&isDir]) {
			if (![fm createDirectoryAtPath:jobDirPath withIntermediateDirectories:YES
				attributes:@{NSFilePosixPermissions:@(0755)} error:&error])
				@throw error;
		} else if (!isDir) @throw @"exists but not a directory";
		NSString *infoPath = [jobDirPath stringByAppendingPathComponent:batchJobInfoFileName];
		if (![infoData writeToFile:infoPath options:0 error:&error]) @throw error;
	} @catch (NSString *msg) {
		MY_LOG("Job info directory %@ %@.", jobDirPath, msg); return NO;
	} @catch (NSError *error) {
		MY_LOG("%@ %@", error.localizedDescription, error.localizedFailureReason); return NO;
	}
	return YES;
}
- (void)makeDataFileWith:(NSNumber *)number type:(NSString *)type names:(NSArray *)names
	makeObj:(NSObject * (^)(StatInfo *, NSArray *))makeObj {
	if (names == nil || names.count <= 0) return;
	NSError *error = nil;
	@autoreleasepool {
		NSData *data = [NSJSONSerialization dataWithJSONObject:
			@{@"jobID":_ID, @"n":number, @"type":type, @"table":
				makeObj(runningTrials[number].statInfo, names)}
			options:0 error:&error];
		if (data != nil) {
			NSString *path = [jobDirPath stringByAppendingPathComponent:
				[NSString stringWithFormat:@"%@_%@", type, number]];
			[data writeToFile:path options:0 error:&error];
		}
	}
	if (error != nil) @throw error;
}
- (void)trialDidFinish:(NSNumber *)number mode:(LoopMode)mode {
// output the results
	MY_LOG("Trial %@/%ld of job %@ finished as %@.",
		number, _nIteration, _ID,
		(mode == LoopFinished)? @"no more infected individuals" :
		(mode == LoopEndByCondition)? @"condition in scenario" :
		(mode == LoopEndAsDaysPassed)? @"specified days passed" :
		(mode == LoopEndByUser)? @"user's request" :
		(mode == LoopEndByTimeLimit)? @"time limit reached" : @"unknown reason");
	@try {
		[self makeDataFileWith:number type:@"indexes" names:output_n
			makeObj:^(StatInfo *stInfo, NSArray *names)
				{ return [stInfo objectOfTimeEvoTableWithNames:names]; }];
		[self makeDataFileWith:number type:@"daily" names:output_d
			makeObj:^(StatInfo *stInfo, NSArray *names)
				{ return [stInfo objectOfTransitTableWithNames:names]; }];
		[self makeDataFileWith:number type:@"distribution" names:output_D
			makeObj:^(StatInfo *stInfo, NSArray *names)
				{ return [stInfo objectOfHistgramTableWithNames:names]; }];
		if (shouldSaveSeverityStats)
			[self makeDataFileWith:number type:@"severity" names:nil
				makeObj:^(StatInfo *stInfo, NSArray *names)
					{ return [stInfo objectOfStatsInData:stInfo.sspData unit:SSP_NRanks days:YES]; }];
		if (shouldSaveVariantsStats) {
			MutableDictArray vrList = runningTrials[number].variantList;
			NSInteger nVariants = (vrList == nil)? 1 : vrList.count;
			if (nVariants > MAX_N_VARIANTS) nVariants = MAX_N_VARIANTS;
			[self makeDataFileWith:number type:@"variants" names:nil
				makeObj:^(StatInfo *stInfo, NSArray *names) {
				return [stInfo objectOfStatsInData:stInfo.variantsData unit:MAX_N_VARIANTS days:YES];
			}];
		}
		if (shouldSaveVcnRecord)
			[self makeDataFileWith:number type:@"vaccination" names:nil
				makeObj:^(StatInfo *stInfo, NSArray *names) { return
					[stInfo objectOfStatsInData:stInfo.vaccinesData unit:N_ELMS_VCN_REC days:NO]; }];
		if (shouldSaveState)
			[runningTrials[number] saveStateTo:
				[NSString stringWithFormat:@"%@_%@", _ID, number]];
	} @catch (NSError *error) {
		MY_LOG("%@ %@", error.localizedDescription, error.localizedFailureReason);
	} @catch (NSString *msg) { MY_LOG("%@", msg); }
// check next trial
	[lock lock];
	[availableWorlds addObject:runningTrials[number]];
	[runningTrials removeObjectForKey:number];
	if (nextTrialNumber >= _nIteration && runningTrials.count == 0) {
	// Job completed.
		for (World *world in availableWorlds) [world discardMemory];
		[availableWorlds removeAllObjects];
		[the_job_controller() finishJobID:_ID];
	}
	[lock unlock];
	[the_job_controller() tryNewTrial:YES];
}
- (void)organizeVariantsAndVaccines:(World *)world {
	if (loadVV != nil) {
		NSDictionary *vvDict = variants_vaccines_from_path(loadVV);
		if (vvDict != nil) {
			world.vaccineList = vvDict[@"vaccineList"];
			world.variantList = vvDict[@"variantList"];
		}
	}
	if (moreVaccines != nil) {
		MutableDictArray moreV = mutablized_array_of_dicts(moreVaccines);
		add_vv_list(world.vaccineList, moreV);
		correct_vaccine_list(world.variantList, world.vaccineList);
	}
	if (moreVariants != nil) {
		MutableDictArray moreV = mutablized_array_of_dicts(moreVariants);
		add_vv_list(world.variantList, moreV);
		correct_variant_list(world.variantList, world.vaccineList);
	}
	[world setupVaxenAndVariantsFromLists];
}
static MutableDictArray correct_gat_list(MutableDictArray list) {
	if (![list isKindOfClass:NSMutableArray.class])
		list = [NSMutableArray arrayWithArray:list];
	for (NSInteger i = list.count - 1; i >= 0; i --)
		if (![list[i] isKindOfClass:NSMutableDictionary.class]) {
			if ([list[i] isKindOfClass:NSDictionary.class])
				list[i] = [NSMutableDictionary dictionaryWithDictionary:list[i]];
			else [list removeObjectAtIndex:i];
	}
	correct_gathering_list(list);
	return list;
}
- (void)organizeGatheringsList:(World *)world {
	if (loadGatherings != nil) {
		MutableDictArray list = gatherings_list_from_path(loadGatherings);
		if (list != nil) world.gatheringsList = correct_gat_list(list);
	}
	if (moreGatherings != nil) {
		if (world.gatheringsList == nil)
			world.gatheringsList = correct_gat_list(moreGatherings);
		else {
			NSMutableDictionary *md = NSMutableDictionary.new;
			for (NSDictionary *item in world.gatheringsList) {
				NSString *nm = item[@"name"];
				if (nm != nil) md[nm] = item;
			}
			MutableDictArray ma = NSMutableArray.new;
			for (NSMutableDictionary *item in moreGatherings) {
				NSString *nm = item[@"name"];
				NSMutableDictionary *dst = (nm != nil)? md[nm] : nil;
				if (dst != nil) for (NSString *key in item) dst[key] = item[key];
				else [ma addObject:item];
			}
			[world.gatheringsList addObjectsFromArray:correct_gat_list(ma)];
		}
		[world resetRegGatInfo];
	}
}
#define CP_WP(m) dst->m = src->m;
static void copy_allowed_world_params(World *world) {
	[world applyWorldSize];
	WorldParams *src = world.tmpWorldParamsP, *dst = world.worldParamsP;
	CP_WP(rcvBias) CP_WP(rcvBias) CP_WP(rcvTemp) // coefficients to calculate recovery from age
	CP_WP(rcvUpper) CP_WP(rcvLower) // boundaries of period to start recovery
	CP_WP(vcn1stEffc) CP_WP(vcnMaxEffc) CP_WP(vcnEffcSymp)
	CP_WP(vcnEDelay) CP_WP(vcnEPeriod) CP_WP(vcnEDecay) CP_WP(vcnSvEffc) // standard vaccine efficacy
	CP_WP(infecDistBias)	// coefficient for furthest distance of infection
	CP_WP(contagBias) CP_WP(startDate)
}
- (BOOL)runNextTrial {	// called only from JobController's tryNewTrial:
	World *world = nil;
	NSString *failedReason = nil;
	[lock lock];
	@try {
		if (_loadState == nil) {
			if (availableWorlds.count <= 0) {
				world = make_new_world(@"Job", nil);
				set_params_from_dict(world.runtimeParamsP, world.worldParamsP, _parameters);
				set_params_from_dict(world.initParamsP, world.tmpWorldParamsP, _parameters);
				[world setScenarioPList:_scenario];
				if (popDistMap != nil) [world loadPopDistMapFrom:popDistMap];
			} else {
				world = [availableWorlds lastObject];
				[availableWorlds removeLastObject];
			}
			[world resetPop];
		} else {
			if (availableWorlds.count <= 0) {
				world = make_new_world(@"Job", nil);
				if (popDistMap != nil) [world loadPopDistMapFrom:popDistMap];
			} else {
				world = [availableWorlds lastObject];
				[availableWorlds removeLastObject];
			}
			[world loadStateFrom:_loadState];
			if (_parameters != nil) {
				set_params_from_dict(world.runtimeParamsP, NULL, _parameters);
				copy_allowed_world_params(world);
			}
			if (_scenario != nil) [world setScenarioPList:_scenario];
		}
		[self organizeVariantsAndVaccines:world];
		[self organizeGatheringsList:world];
		if (world.runtimeParamsP->step > 0) [world execScenario];
		NSNumber *trialNumb = @(++ nextTrialNumber);
		runningTrials[trialNumb] = world;
		if (nextTrialNumber >= _nIteration)
			[the_job_controller() removeJobFromQueue:self shouldLock:NO];
		world.stopCallBack = ^(LoopMode mode){
			[self trialDidFinish:trialNumb mode:mode];
		};
		NSInteger stopAt = _stopAt, nIte = _nIteration;
		NSString *jobID = _ID;
		in_main_thread(^{
			[world start:stopAt maxSPS:0 priority:-.2];
			MY_LOG("Trial %@/%ld of job %@ started on world %@.",
				trialNumb, nIte, jobID, world.ID);
		});
	} @catch (NSError *error) { failedReason = [NSString stringWithFormat:@"%@ %@",
		error.localizedDescription, error.localizedFailureReason];
	} @catch (NSException *excp) { failedReason = excp.reason;
	} @catch (NSString *msg) { failedReason = msg; }
	if (failedReason != nil) {
		MY_LOG("Trial %ld/%ld of job %@ could not start. %@",
			nextTrialNumber + 1, _nIteration, _ID, failedReason);
	}
	[lock unlock];
	return (failedReason == nil);
}
- (void)setNextTrialNumber:(NSInteger)number {
	nextTrialNumber = number;
}
- (NSDictionary *)jobStatus:(BOOL)withWorldIDs {
	[lock lock];
	NSInteger nowProcessed = runningTrials.count;
	NSNumber *steps[nowProcessed];
	NSString *worldIDs[nowProcessed];
	NSInteger n = 0;
	for (World *world in runningTrials.objectEnumerator) {
		worldIDs[n] = world.ID;
#ifdef DEBUGz
		steps[n ++] = @[@(world.runtimeParamsP->step), @(world.phaseInStep)];
#else
		steps[n ++] = @(world.runtimeParamsP->step);
#endif
	}
	[lock unlock];
	NSString *keys[] = {@"notYet", @"nowProcessed", @"finished", @"worldIDs"};
	NSObject *objs[] = {@(_nIteration - nextTrialNumber),
		[NSArray arrayWithObjects:steps count:n],
		@(nextTrialNumber - nowProcessed), nil};
	NSInteger nElms = 3;
	if (withWorldIDs) {
		nElms = 4;
		objs[3] = [NSArray arrayWithObjects:worldIDs count:n];
	}
	return [NSDictionary dictionaryWithObjects:objs forKeys:keys count:nElms];
}
- (void)stop {
	[lock lock];
	for (World *world in runningTrials.objectEnumerator)
		[world stop:LoopEndByUser];
	if (nextTrialNumber < _nIteration) {
		[the_job_controller() removeJobFromQueue:self shouldLock:YES];
		_nIteration = nextTrialNumber;
	}
	[the_job_controller() finishJobID:_ID];
	[lock unlock];
}
- (void)forAllLiveWorlds:(void (^)(World *))block {
	[lock lock];
	NSArray *worlds = runningTrials.allValues;
	[lock unlock];
	for (World *world in worlds) block(world);
}
@end

@implementation ProcContext (BatchJobExtension)
- (void)submitJob {
	if (the_job_controller().queueLength >= maxJobsInQueue)
		@throw [NSString stringWithFormat:
			@"500 The job queue is full (%ld jobs).", maxJobsInQueue];
	NSString *jobStr = query[@"JSON"];
	if (jobStr == nil) jobStr = [query[@"job"] stringByReplacingOccurrencesOfString:
		@"+" withString:@" "].stringByRemovingPercentEncoding;
	if (jobStr == nil) @throw @"417 Job data is missing.";
	NSData *jobData = [jobStr dataUsingEncoding:NSUTF8StringEncoding];
	NSError *error;
	NSDictionary *jobInfo = [NSJSONSerialization JSONObjectWithData:
		jobData options:0 error:&error];
	if (jobInfo == nil) @throw [NSString stringWithFormat:@"417 %@ %@",
		error.localizedDescription, error.localizedFailureReason];
	BatchJob *job = [BatchJob.alloc initWithInfo:jobInfo ID:nil];
	if (job == nil) @throw @"500 Couldn't make a batch job.";
	MY_LOG("%@ Job %@ was submitted.", ip4_string(ip4addr), job.ID);
	[job saveInfoData:jobData];
	in_main_thread(^{ [the_job_controller() submitJob:job]; });
	content = job.ID;
	type = @"text/plain";
	code = 200;
}
- (BatchJob *)targetJob {
	NSString *jobID = query[@"job"];
	if (jobID == nil) @throw @"500 Job ID is missing.";
	BatchJob *job = [the_job_controller() jobFromID:jobID];
	if (job == nil) @throw [NSString stringWithFormat:
		@"500 Job %@ doesn't exist.", jobID];
	return job;
}
- (void)getJobStatus {
	NSString *worldOption = query[@"worlds"];
	BOOL withWorldIDs = worldOption != nil &&
		([worldOption caseInsensitiveCompare:@"on"] == NSOrderedSame || worldOption.boolValue);
	[self setJSONDataAsResponse:[self.targetJob jobStatus:withWorldIDs]];
}
- (void)getJobQueueStatus {
	NSMutableDictionary *md = NSMutableDictionary.new;
	md[@"length"] = @(the_job_controller().queueLength);
	md[@"runningTrials"] = @(the_job_controller().nRunningTrials);
	for (NSString *jobID in query) {
		if (query[jobID].integerValue != 1) continue;
		BatchJob *job = [the_job_controller() jobFromID:jobID];
		if (job == nil) continue;
		NSInteger index = [the_job_controller() indexOfJobInQueue:job];
		if (index != NSNotFound) md[jobID] = @(index);
	}
	[self setJSONDataAsResponse:md];
}
- (void)getJobInfo {
	NSString *jobID = query[@"job"];
	if (jobID == nil) @throw @"500 Job ID is missing.";
	NSString *jobInfoPath = [[batch_job_dir() stringByAppendingPathComponent:jobID]
		stringByAppendingPathComponent:@"info.json"];
	NSError *error;
	NSString *str = [NSString stringWithContentsOfFile:jobInfoPath
		encoding:NSUTF8StringEncoding error:&error];
	if (str == nil) @throw [NSString stringWithFormat:
		@"500 Couldn't find job info for %@, because %@.", jobID, error.localizedDescription];
	str = [str stringByRemovingPercentEncoding];
	NSData *data = [NSData dataWithBytes:str.UTF8String length:
		[str lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
	NSObject *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	if (obj == nil) @throw [NSString stringWithFormat:
		@"500 Job info for %@ is broken.", jobID];
	[self setJSONDataAsResponse:obj];
}
- (void)stopJob {
	[self.targetJob stop];
	[self setOKMessage];
}
- (void)getJobResultsWithProc:(void (^)(NSObject *))proc {
	NSString *jobID = query[@"job"];
	@try {
		NSString *jobDir = [batch_job_dir() stringByAppendingPathComponent:jobID];
		for (NSString *fname in
			[NSFileManager.defaultManager enumeratorAtPath:jobDir])
		if (![fname isEqualToString:@"info.json"]) {
			NSData *data = [NSData dataWithContentsOfFile:
				[jobDir stringByAppendingPathComponent:fname]];
			if (data == nil) @throw [NSString stringWithFormat:
				@"500 Couldn't read result file %@.", fname];
			NSError *error;
			NSObject *obj = [NSJSONSerialization JSONObjectWithData:data
				options:0 error:&error];
			if (obj == nil) @throw error;
			proc(obj);
		}
	} @catch (NSException *excp) {
		@throw [NSString stringWithFormat:
			@"500 Error in getting results of job %@. %@", jobID, excp.reason];
	} @catch (NSObject *obj) { @throw obj; }
}
- (void)getJobResults { // [self notImplementedYet];
	static char nonFnameChars[] = "/:;<>?[\\]^{|}~";
	NSString *jobID = query[@"job"];
	if (jobID == nil) @throw @"500 Job ID is missing.";
	NSString *save = query[@"save"];
//	replace inappriate characters for a filename to under score.
	if (save != nil) {
		NSInteger len = save.length;
		if (len <= 0) save = nil;
		else {
			unichar ch[len];
			[save getCharacters:ch range:(NSRange){0, len}];
			for (NSInteger i = 0; i < len; i ++) {
				if (ch[i] <= '*' || ch[i] == 0x7f) { ch[i] = '_'; continue; }
				char *p = nonFnameChars;
				while (*p) if (ch[i] == *(p ++)) { ch[i] = '_'; break; }
			}
			save = [NSString stringWithCharacters:ch length:len];
		}
	}
	if (save == nil) {
		NSMutableArray *ma = NSMutableArray.new;
		[self getJobResultsWithProc:^(NSObject *obj) { [ma addObject:obj]; }];
		[self setJSONDataAsResponse:ma];
	} else {
		NSString *tmpDir = [NSString stringWithFormat:@"/tmp/simepi/%@", jobID],
			*myTmpDir = [tmpDir stringByAppendingPathComponent:save];
		NSError *error;
		if (![NSFileManager.defaultManager createDirectoryAtPath:myTmpDir
			withIntermediateDirectories:YES
			attributes:@{NSFilePosixPermissions:@(0755)} error:&error]) {
			MY_LOG("Couldn't create directory %@.", myTmpDir);
			@throw @"500 Couldn't create a temporary directory.";
		}
		NSString *sepKey = query[@"sep"], *nlKey = query[@"nl"];
		NSString *sep = nil, *nl = nil;
		if (sepKey != nil) sep = @{@"comma":@",", @"space":@" ", @"tab":@"\t"}[sepKey];
		if (sep == nil) sep = @",";
		if (nlKey != nil) nl = @{@"lf":@"\n", @"crlf":@"\r\n"}[nlKey];
		if (nl == nil) nl = @"\n";
		[self getJobResultsWithProc:^(NSObject *obj) {
				NSDictionary *content = (NSDictionary *)obj;
				NSArray<NSArray *> *table = content[@"table"];
				NSMutableString *ms = NSMutableString.new;
				for (NSArray<NSObject *> *row in table) {
					for (NSInteger i = 0; i < row.count; i ++) {
						if ([row[i] isKindOfClass:NSString.class])
							[ms appendFormat:@"\"%@\"", row[i]];
						else if ([row[i] isKindOfClass:NSNumber.class])
							[ms appendString:((NSNumber *)row[i]).stringValue];
						else [ms appendString:row[i].description];
						[ms appendString:(i < row.count - 1)? sep : nl];
				}}
				NSString *path = [myTmpDir stringByAppendingFormat:
					@"/%@_%@.csv", content[@"type"], content[@"n"]];
				NSError *error;
				if (![ms writeToFile:path atomically:NO
					encoding:NSUTF8StringEncoding error:&error])
					@throw [NSString stringWithFormat:
						@"500 Couldn't write data to temporary file %@.", path];
			}];
		NSString *com = [NSString stringWithFormat:
			@"cd %@; zip -rq %@ %@", tmpDir, save, save];
		int exitCode = system(com.UTF8String); // make a zip archive.
		if (exitCode != 0) @throw [NSString stringWithFormat:
			@"500 Error (%d) in making a zip archive.", exitCode];
		content = [NSData dataWithContentsOfFile:
			[myTmpDir stringByAppendingPathExtension:@"zip"]];
		if (![NSFileManager.defaultManager removeItemAtPath:tmpDir error:&error])
			MY_LOG("%@", error.localizedDescription);
		moreHeader = [NSString stringWithFormat:
			@"Content-Disposition: attachment; filename=\"%@.zip\"\n", save];
		type = @"application/zip";
		code = 200;
	}
}
- (void)forAllJobsInArgs:(BOOL (^)(NSString *, NSError **))block
	opeName:(NSArray<NSString *>*)opeName {
	NSString *jobIDs = query[@"job"];
	if (jobIDs == nil) @throw @"500 Job ID is missing.";
	NSError *error;
	NSArray<NSString *> *jobIDArry = [jobIDs componentsSeparatedByString:@","];
	NSMutableString *results = NSMutableString.new;
	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *jobID in jobIDArry) if (jobID.length > 0) {
		NSString *fullPath = [batch_job_dir() stringByAppendingPathComponent:jobID];
		BOOL jInfo = (fullPath.length > batch_job_dir().length + 1)?
			block(fullPath, &error) : NO;
		NSDirectoryEnumerator *dEnm = [fm enumeratorAtPath:save_state_dir()];
		NSInteger cnt = 0;
		if (dEnm != nil) for (NSString *dname in dEnm) {
			if ([dname hasPrefix:jobID]) {
				fullPath = [save_state_dir() stringByAppendingPathComponent:dname];
				if (!block(fullPath, &error))
					@throw [NSString stringWithFormat:@"500 Could not %@ %@. %@",
						opeName[0], fullPath, error.localizedDescription];
				cnt ++;
			}
			[dEnm skipDescendants];
		}
		[results appendFormat:@"Job information of %@ %@. %@.\n", jobID,
			jInfo? [@"was " stringByAppendingString:opeName[1]] : @"could not be found",
			(cnt == 0)? @"No saved state was found" :
			(cnt == 1)? [@"One saved state was " stringByAppendingString:opeName[1]] : 
			[NSString stringWithFormat:@"%ld saved states were %@", cnt, opeName[1]]];
	}
	type = @"text/plain";
	content = results;
	code = 200;
}
- (void)deleteJob {
	[self forAllJobsInArgs:^BOOL(NSString *path, NSError **error) {
		return [NSFileManager.defaultManager removeItemAtPath:path error:error];
	} opeName:@[@"remove", @"deleted"]];
}
- (void)touchJob {
	NSDate *date = NSDate.date;
	[self forAllJobsInArgs:^BOOL(NSString *path, NSError **error) {
		return [NSFileManager.defaultManager setAttributes:
			@{NSFileModificationDate:date} ofItemAtPath:path error:error];
	} opeName:@[@"touch", @"touched"]];
}
@end

void check_batch_jobs_to_restart(void) {	// called from main()
	NSFileManager *fm = NSFileManager.defaultManager;
	BOOL isDirectory;
	if (![fm fileExistsAtPath:batch_job_dir() isDirectory:&isDirectory]) return;
	if (!isDirectory) return;
	NSString *IDsStr = [NSString stringWithContentsOfFile:
		[batch_job_dir() stringByAppendingPathComponent:unfinishedJobListFileName]
		encoding:NSUTF8StringEncoding error:NULL];
	if (IDsStr == nil || IDsStr.length == 0) return;
	NSScanner *scan = [NSScanner scannerWithString:IDsStr];
	NSString *ID;
	NSCharacterSet *chSet = NSCharacterSet.newlineCharacterSet;
	NSError *error;
	NSArray<NSString *> *filePrefixes =
		@[@"indexes", @"daily", @"distribution", @"severity", @"variants"];
	while ([scan scanUpToCharactersFromSet:chSet intoString:&ID]) {
		NSString *jobDir = [batch_job_dir() stringByAppendingPathComponent:ID];
		if (![fm fileExistsAtPath:jobDir isDirectory:&isDirectory]) continue;
		if (!isDirectory) continue;
		NSString *infoPath = [jobDir stringByAppendingPathComponent:batchJobInfoFileName];
		NSData *infoData = [NSData dataWithContentsOfFile:infoPath options:0 error:&error];
		if (infoData == nil) { MY_LOG("%@ %@.", infoPath, error.localizedDescription); continue; }
		NSDictionary *info = [NSJSONSerialization JSONObjectWithData:infoData options:0 error:&error];
		if (info == nil) { MY_LOG("%@ %@.", infoPath, error.localizedDescription); continue; }
		NSMutableArray<NSNumber *> *nums[filePrefixes.count];
		for (NSInteger i = 0; i < filePrefixes.count; i ++) nums[i] = NSMutableArray.new;
		for (NSString *fname in [fm contentsOfDirectoryAtPath:jobDir error:NULL]) {
			NSArray<NSString *> *arr = [fname componentsSeparatedByString:@"_"];
			if (arr.count < 2) continue;
			NSInteger idx = [filePrefixes indexOfObject:arr[0]];
			if (idx == NSNotFound) continue;
			[nums[idx] addObject:@(arr[1].integerValue)];
		}
		NSInteger k = 0, nFinished = 0, idxes[filePrefixes.count];
		for (NSInteger i = 0; i < filePrefixes.count; i ++) if (nums[i].count > 0) {
			[nums[i] sortUsingSelector:@selector(compare:)];
			idxes[k ++] = i;
		}
		if (k > 0) {
			nFinished = nums[idxes[0]].count;
			for (NSInteger i = 0; i < nFinished; i ++) {
				NSNumber *num = nums[idxes[0]][i];
				for (NSInteger j = 1; j < k; j ++)
					if (nums[idxes[j]].count <= i || ![nums[idxes[j]][i] isEqualTo:num])
						{ nFinished = i; break; }
			}
			NSNumber *num = info[@"n"];
			NSInteger nTrials = num? num.integerValue : 1;
			if (nTrials < 1) nTrials = 1;
			if (nTrials <= nFinished)
				{ [the_job_controller() finishJobID:ID]; continue; }
			@try { for (NSInteger i = 0; i < k; i ++) {
				NSInteger idx = idxes[i];
				if (nums[idx].count > nFinished)
				for (NSInteger j = nFinished; j < nums[idx].count; j ++) {
					NSString *path = [jobDir stringByAppendingPathComponent:
						[NSString stringWithFormat:@"%@_%@", filePrefixes[idx], nums[idx][j]]];
					if (![fm removeItemAtPath:path error:&error]) @throw path;
				}}
				for (NSInteger i = 0; i < nFinished; i ++)
				if (nums[idxes[0]][i].integerValue > i + 1) for (NSInteger j = 0; j < k; j ++) {
					NSInteger idx = idxes[j];
					NSString *pathOrg = [jobDir stringByAppendingPathComponent:
						[NSString stringWithFormat:@"%@_%@", filePrefixes[idx], nums[idx][i]]];
					NSString *pathNew = [jobDir stringByAppendingPathComponent:
						[NSString stringWithFormat:@"%@_%ld", filePrefixes[idx], i + 1]];
					if (![fm moveItemAtPath:pathOrg toPath:pathNew error:&error])
						@throw [NSString stringWithFormat:@"mv %@ %@.", pathOrg, pathNew];
				}
			} @catch (NSString *path)
				{ MY_LOG("%@ %@.", path, error.localizedDescription); continue; }
		}
		BatchJob *job = [BatchJob.alloc initWithInfo:info ID:ID];
		if (job == nil) { MY_LOG("Couldn't make a batch job %@.", ID); continue; }
		if (nFinished > 0) [job setNextTrialNumber:nFinished];
		[the_job_controller() submitJob:job];
		MY_LOG("Job %@ restarted.", ID);
	}
}
