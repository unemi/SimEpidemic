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
#import "../SimEpidemic/Sources/Document.h"
#import "../SimEpidemic/Sources/StatPanel.h"
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
	if (batchJobDir == nil) batchJobDir =
		[dataDirectory stringByAppendingPathComponent:@"BatchJob"];
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
- (void)tryNewTrial:(BOOL)trialFinished {
	[lock lock];
	if (trialFinished) nRunningTrials --;
	while (jobQueue.count > 0 && nRunningTrials < maxTrialsAtSameTime) {
		if ([jobQueue[0] runNextTrial]) nRunningTrials ++;
		else [jobQueue removeObjectAtIndex:0];
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
- (void)forAllLiveDocuments:(void (^)(Document *))block {
	[lock lock];
	NSArray *jobs = theJobs.allValues;
	[lock unlock];
	for (BatchJob *job in jobs)
		[job forAllLiveDocuments:block];
}
@end
// to check how much this machine is busy now. called from Contract.m
void for_all_bacth_job_documents(void (^block)(Document *)) {
	[the_job_controller() forAllLiveDocuments:block];
}

@implementation BatchJob
#ifdef DEBUG
- (void)monitorProgress {
	if (runningTrials.count == 0) return;
	char buf[128];
	int k = 0;
	for (NSNumber *num in runningTrials) {
		k += snprintf(buf + k, 128 - k, "%ld:%ld, ", num.integerValue,
			runningTrials[num].runtimeParamsP->step);
		if (k >= 127) break;
	}
	MY_LOG("%s", buf);
}
#endif
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
			@throw [NSString stringWithFormat:@"417 Invalid element in scenatio: %@", errMsg];
	}
	NSNumber *num;
	_stopAt = ((num = info[@"stopAt"]) == nil)? 0 : num.integerValue;
	_nIteration = ((num = info[@"n"]) == nil)? 1 : num.integerValue;
	loadState = info[@"loadState"];
	if (_nIteration <= 1) _nIteration = 1;
	NSArray<NSString *> *output = info[@"out"];
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
		else if ([key isEqualToString:@"saveState"]) shouldSaveState = YES;
	}
	output_n = [NSArray arrayWithObjects:an count:nn];
	output_d = [NSArray arrayWithObjects:ad count:nd];
	output_D = [NSArray arrayWithObjects:aD count:nD];
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
		MY_LOG("Data strage %@ %@.", dataDirectory, msg); return NO;
	} @catch (NSError *error) {
		MY_LOG("%@", error.localizedDescription); return NO;
	}
	return YES;
}
- (void)makeDataFileWith:(NSNumber *)number type:(NSString *)type names:(NSArray *)names
	makeObj:(NSObject * (^)(StatInfo *, NSArray *))makeObj {
	if (names.count <= 0) return;
	NSError *error;
	NSData *data = [NSJSONSerialization dataWithJSONObject:
		@{@"jobID":_ID, @"n":number, @"type":type, @"table":
			makeObj(runningTrials[number].statInfo, names)}
		options:0 error:&error];
	if (data == nil) @throw error;
	NSString *path = [jobDirPath stringByAppendingPathComponent:
		[NSString stringWithFormat:@"%@_%@", type, number]];
	if (![data writeToFile:path options:0 error:&error]) @throw error;
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
		if (shouldSaveState)
			[runningTrials[number] saveStateTo:
				[NSString stringWithFormat:@"%@_%@", _ID, number]];
	} @catch (NSError *error) {
		MY_LOG("%@", error.localizedDescription);
	}
// check next trial
	[lock lock];
	[availableWorlds addObject:runningTrials[number]];
	[runningTrials removeObjectForKey:number];
	if (nextTrialNumber >= _nIteration && runningTrials.count == 0) {
	// Job completed.
		for (Document *doc in availableWorlds) [doc discardMemory];
		[availableWorlds removeAllObjects];
		[the_job_controller() finishJobID:_ID];
	}
	[lock unlock];
	[the_job_controller() tryNewTrial:YES];
}
- (BOOL)runNextTrial {	// called only from JobController's tryNewTrial:
	Document *doc = nil;
	NSString *failedReason = nil;
	[lock lock];
	@try {
		if (loadState == nil) {
			if (availableWorlds.count <= 0) {
				doc = make_new_world(@"Job", nil);
				set_params_from_dict(doc.runtimeParamsP, doc.worldParamsP, _parameters);
				set_params_from_dict(doc.initParamsP, doc.tmpWorldParamsP, _parameters);
				[doc setScenarioWithPList:_scenario];
			} else {
				doc = [availableWorlds lastObject];
				[availableWorlds removeLastObject];
			}
			[doc resetPop];
		} else {
			if (availableWorlds.count <= 0) doc = make_new_world(@"Job", nil);
			else {
				doc = [availableWorlds lastObject];
				[availableWorlds removeLastObject];
			}
			[doc loadStateFrom:loadState];
			MY_LOG("Doc %@ load state %@.", doc.ID, loadState);
			if (_parameters != nil) load_params_from_dict(doc, NULL, _parameters);
		}
		NSNumber *trialNumb = @(++ nextTrialNumber);
		runningTrials[trialNumb] = doc;
		if (nextTrialNumber >= _nIteration)
			[the_job_controller() removeJobFromQueue:self shouldLock:NO];
		doc.stopCallBack = ^(LoopMode mode){
			[self trialDidFinish:trialNumb mode:mode];
		};
		NSInteger stopAt = _stopAt, nIte = _nIteration;
		NSString *jobID = _ID;
		in_main_thread(^{
			[doc start:stopAt maxSPS:0 priority:-.2];
			MY_LOG("Trial %@/%ld of job %@ started on world %@.",
				trialNumb, nIte, jobID, doc.ID);
		});
	} @catch (NSError *error) { failedReason = error.localizedDescription;
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
- (NSDictionary *)jobStatus {
	[lock lock];
	NSInteger nowProcessed = runningTrials.count;
#ifdef DEBUGz
	NSNumber *steps[nowProcessed * 2];
#else
	NSNumber *steps[nowProcessed];
#endif
	NSInteger n = 0;
	for (Document *doc in runningTrials.objectEnumerator) {
		steps[n ++] = @(doc.runtimeParamsP->step);
#ifdef DEBUGz
		steps[n ++] = @(doc.phaseInStep);
#endif
	}
	[lock unlock];
	return @{@"notYet":@(_nIteration - nextTrialNumber),
		@"nowProcessed":[NSArray arrayWithObjects:steps count:n],
		@"finished":@(nextTrialNumber - nowProcessed) };
}
- (void)stop {
	[lock lock];
	for (Document *doc in runningTrials.objectEnumerator)
		[doc stop:LoopEndByUser];
	if (nextTrialNumber < _nIteration) {
		[the_job_controller() removeJobFromQueue:self shouldLock:YES];
		_nIteration = nextTrialNumber;
	}
	[the_job_controller() finishJobID:_ID];
	[lock unlock];
}
- (void)forAllLiveDocuments:(void (^)(Document *))block {
	[lock lock];
	NSArray *docs = runningTrials.allValues;
	[lock unlock];
	for (Document *doc in docs) block(doc);
}
@end

@implementation ProcContext (BatchJobExtension)
- (void)submitJob {
	if (the_job_controller().queueLength >= maxJobsInQueue)
		@throw [NSString stringWithFormat:
			@"500 The job queue is full (%ld jobs).", maxJobsInQueue];
	NSString *jobStr = query[@"JSON"];
	if (jobStr == nil) jobStr = query[@"job"].stringByRemovingPercentEncoding;
	if (jobStr == nil) @throw @"417 Job data is missing.";
	NSData *jobData = [jobStr dataUsingEncoding:NSUTF8StringEncoding];
	NSError *error;
	NSDictionary *jobInfo = [NSJSONSerialization JSONObjectWithData:
		jobData options:0 error:&error];
	if (jobInfo == nil)
		@throw [NSString stringWithFormat:@"417 %@", error.localizedDescription];
	BatchJob *job = [BatchJob.alloc initWithInfo:jobInfo ID:nil];
	if (job == nil) @throw @"500 Couldn't make a batch job.";
	MY_LOG("%@ Job %@ was submitted.", ip4_string(ip4addr), job.ID);
	[job saveInfoData:jobData];
	[the_job_controller() submitJob:job];
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
	[self setJSONDataAsResponse:self.targetJob.jobStatus];
}
- (void)getJobQueueStatus {
	NSMutableDictionary *md = NSMutableDictionary.new;
	md[@"length"] = @(the_job_controller().queueLength);
	for (NSString *jobID in query) {
		if (query[jobID].integerValue != 1) continue;
		BatchJob *job = [the_job_controller() jobFromID:jobID];
		if (job == nil) continue;
		NSInteger index = [the_job_controller() indexOfJobInQueue:job];
		if (index != NSNotFound) md[jobID] = @(index);
	}
	[self setJSONDataAsResponse:md];
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
- (void)deleteJob {
	NSString *jobID = query[@"job"];
	if (jobID == nil) @throw @"500 Job ID is missing.";
	NSError *error;
	NSFileManager *fm = NSFileManager.defaultManager;
	BOOL jInfo = [fm removeItemAtPath:
		[batch_job_dir() stringByAppendingPathComponent:jobID] error:&error];
	NSDirectoryEnumerator *dEnm = [fm enumeratorAtPath:save_state_dir()];
	NSInteger cnt = 0;
	if (dEnm != nil) {
		[dEnm skipDescendants];
		for (NSString *dname in dEnm) if ([dname hasPrefix:jobID]) {
			NSString *fullPath = [save_state_dir() stringByAppendingPathComponent:dname];
			if (![fm removeItemAtPath:fullPath error:&error])
				@throw [NSString stringWithFormat:@"500 Could not remove %@. %@",
					fullPath, error.localizedDescription];
			cnt ++;
		}
	}
	type = @"text/plain";
	content = [NSString stringWithFormat:@"Job information %@. %@.",
		jInfo? @"was deleted" : @"could not be found",
		(cnt == 0)? @"No saved state was found" :
		(cnt == 1)? @"One saved state was deleted" : 
		[NSString stringWithFormat:@"%ld job states were deleted", cnt]];
	code = (jInfo || cnt > 0)? 200 : 417;
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
	NSArray<NSString *> *filePrefixes = @[@"indexes", @"daily", @"distribution"];
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
