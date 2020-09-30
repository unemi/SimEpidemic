//
//  BatchJob.m
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/09/14.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "BatchJob.h"
#import "noGUI.h"
#import "ProcContext.h"
#import "Document.h"
#import "StatPanel.h"
#import <os/log.h>

typedef enum { IdxTypeIndex, IdxTypeTestI, IdxTypeTestF, IdxTypeUnknown } IndexType;
static NSDictionary *indexNameToIndex = nil, *testINameToIdx = nil;
@implementation StatInfo (JobResultExtension)
- (NSArray *)objectWithStatData:(StatData *)statData
	skip:(NSInteger)stepSkip names:(NSArray *)names {
	if (indexNameToIndex == nil) indexNameToIndex = @{
		@"susceptible":@(Susceptible),
		@"asymptomatic":@(Asymptomatic),
		@"symptomatic":@(Symptomatic),
		@"recovered":@(Recovered),
		@"died":@(Died),
		@"quarantineAsym":@(QuarantineAsym),
		@"quarantineSymp":@(QuarantineSymp)};
	if (testINameToIdx == nil) testINameToIdx = @{
		@"testTotal":@(TestTotal),
		@"testAsSymptom":@(TestAsSymptom),
		@"testAsContact":@(TestAsContact),
		@"testAsSuspected":@(TestAsSuspected),
		@"testPositive":@(TestPositive),
		@"testNegative":@(TestNegative)};
	struct { IndexType type; NSInteger idx; } idxs[names.count];
	for (NSInteger i = 0; i < names.count; i ++) {
		NSNumber *num;
		if ((num = indexNameToIndex[names[i]]) != nil)
			{ idxs[i].type = IdxTypeIndex; idxs[i].idx = num.integerValue; }
		else if ((num = testINameToIdx[names[i]]) != nil)
			{ idxs[i].type = IdxTypeTestI; idxs[i].idx = num.integerValue; }
		else if ([names[i] isEqualToString:@"testPositiveRate"])
			idxs[i].type = IdxTypeTestF; 
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
			case IdxTypeTestF: [row addObject:@(stat->pRate)]; break;
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
	for (NSInteger i = 0; i < nRest; i ++) n[i] = cols[i].count;
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

static JobController *theJobController = nil;
@implementation JobController
- (instancetype)init {
	if (!(self = [super init])) return nil;
	lock = NSLock.new;
	theJobs = NSMutableDictionary.new;
	jobQueue = NSMutableArray.new;
	return self;
}
- (void)tryNewTrial:(BOOL)trialFinished {
	[lock lock];
	if (trialFinished) nRunningTrials --;
	if (jobQueue.count > 0 && nRunningTrials < maxTrialsAtSameTime) {
		[jobQueue[0] runNextTrial];
		nRunningTrials ++;
	}
	[lock unlock];
}
- (void)submitJob:(BatchJob *)job {
	[lock lock];
	theJobs[job.ID] = job;
	[jobQueue addObject:job];
	[lock unlock];
	[self tryNewTrial:NO];
}
- (void)jobDidComplete:(BatchJob *)job {
	[lock lock];
	[jobQueue removeObject:job];
	[lock unlock];
}
- (BatchJob *)jobFromID:(NSString *)jobID { return theJobs[jobID]; }
- (NSInteger)queueLength { return jobQueue.count; }
- (NSInteger)nRunningTrials { return nRunningTrials; }
- (NSInteger)indexOfJobInQueue:(BatchJob *)job {
	return [jobQueue indexOfObject:job];
}
@end
static NSString *batch_job_dir(void) {
	static NSString *batchJobDir = nil;
	if (batchJobDir == nil) batchJobDir =
		[dataDirectory stringByAppendingPathComponent:@"BatchJob"];
	return batchJobDir;
}
void schedule_job_expiration_check(void) { // called from AppDelegate
#ifdef DEBUG
	[NSTimer scheduledTimerWithTimeInterval:1 repeats:NO
#else
	[NSTimer scheduledTimerWithTimeInterval:3600 repeats:YES
#endif
	block:^(NSTimer * _Nonnull timer) {
		@try {
			NSFileManager *fm = NSFileManager.defaultManager;
			NSString *dirPath = batch_job_dir();
			NSDirectoryEnumerator *dirEnum = [fm enumeratorAtPath:dirPath];
			NSDate *pastDate = [NSDate dateWithTimeIntervalSinceNow:
				jobRecExpirationHours * -3600.];
			NSMutableArray<NSString *> *dirsTobeRemoved = NSMutableArray.new;
			for (NSString *path in dirEnum) {
				NSDictionary *attr = dirEnum.fileAttributes;
				if (attr == nil) {
					os_log_error(OS_LOG_DEFAULT,
						"Job record %@ failed to get attributes", path);
					continue;
				}
				if (![attr[NSFileType] isEqualTo:NSFileTypeDirectory]) continue;
				NSDate *modDate = attr[NSFileModificationDate];
				if (modDate == nil) os_log_error(OS_LOG_DEFAULT,
					"Job record %@ failed to get the content modification date.", path);
				else if ([pastDate compare:modDate] == NSOrderedDescending)
					[dirsTobeRemoved addObject:path];
				[dirEnum skipDescendents];
			}
			if (dirsTobeRemoved.count > 0) {
				NSMutableString *ms = NSMutableString.new;
				NSString *pnc = @"";
				for (NSString *name in dirsTobeRemoved)
					{ [ms appendFormat:@"%@%@", pnc, name]; pnc = @", "; }
				os_log(OS_LOG_DEFAULT, "Job records %@ are going to be removed.", ms);
			}
			NSError *error;
			for (NSString *path in dirsTobeRemoved)
				if (![fm removeItemAtPath:
					[dirPath stringByAppendingPathComponent:path] error:&error])
					os_log_error(OS_LOG_DEFAULT, "Job record %@ couldn't be removed. %@",
						path, error.localizedDescription);
		} @catch (NSException *excp) {
			os_log_error(OS_LOG_DEFAULT, "Job record expiration check: %@", excp.reason);
		}
	}];
}

@implementation BatchJob
- (instancetype)initWithInfo:(NSDictionary *)info browser:(NSString *)brwsID {
	if (!(self = [super init])) return nil;
	_ID = new_uniq_string();
	_parameters = info[@"params"];
	_scenario = info[@"scenario"];
	NSNumber *num;
	_stopAt = ((num = info[@"stopAt"]) == nil)? 0 : num.integerValue;
	_nIteration = ((num = info[@"n"]) == nil)? 1 : num.integerValue;
	if (_nIteration <= 1) _nIteration = 1;
	browserID = brwsID;
	NSArray<NSString *> *output = info[@"out"];
	NSInteger n = output.count, nn = 0, nd = 0, nD = 0;
	NSString *an[n], *ad[n], *aD[n];
	for (NSString *key in output) {
		if (indexNames[key] != nil) an[nn ++] = key;
		else if ([key hasPrefix:@"daily"]) {
			unichar uc = [key characterAtIndex:5];
			if (uc < 'A' || uc > 'Z') continue;
			NSString *newKey = [NSString stringWithFormat:@"%c%@",
				uc + 'a' - 'A', [key substringFromIndex:6]];
			if (indexNames[newKey] != nil) ad[nd ++] = newKey;
		} if ([distributionNames containsObject:key]) aD[nD ++] = key;
	}
	output_n = [NSArray arrayWithObjects:an count:nn];
	output_d = [NSArray arrayWithObjects:ad count:nd];
	output_D = [NSArray arrayWithObjects:aD count:nD];
	lock = NSLock.new;
	runningTrials = NSMutableDictionary.new;
	availableWorlds = NSMutableArray.new;
	return self;
}
- (void)makeDataFileWith:(NSNumber *)number type:(NSString *)type
	dir:(NSString *)bjDir names:(NSArray *)names
	makeObj:(NSObject * (^)(StatInfo *, NSArray *))makeObj {
	if (names.count <= 0) return;
	NSError *error;
	NSData *data = [NSJSONSerialization dataWithJSONObject:
		@{@"jobID":_ID, @"n":number, @"type":type, @"table":
			makeObj(runningTrials[number].statInfo, names)}
		options:0 error:&error];
	if (data == nil) @throw error;
	NSString *path = [bjDir stringByAppendingPathComponent:
		[NSString stringWithFormat:@"%@_%@", type, number]];
	if (![data writeToFile:path options:0 error:&error]) @throw error;
}
- (void)trialDidFinish:(NSNumber *)number mode:(LoopMode)mode {
// output the results
	os_log(OS_LOG_DEFAULT, "Trial %@/%ld of job %@ finished as %@.",
		number, _nIteration, _ID,
		(mode == LoopFinished)? @"no more infected individuals" :
		(mode == LoopEndByCondition)? @"condition in scenario" :
		(mode == LoopEndAsDaysPassed)? @"specified days passed" : @"unknown reason");
	@try {
		BOOL isDir;
		NSError *error;
		NSFileManager *fm = NSFileManager.defaultManager;
		NSString *bjDir = [batch_job_dir() stringByAppendingPathComponent:_ID];
		if (![fm fileExistsAtPath:bjDir isDirectory:&isDir]) {
			if (![fm createDirectoryAtPath:bjDir withIntermediateDirectories:YES
				attributes:@{NSFilePosixPermissions:@(0755)} error:&error])
				@throw error;
		} else if (!isDir) @throw @"exists but not a directory";
		[self makeDataFileWith:number type:@"indexes" dir:bjDir names:output_n
			makeObj:^(StatInfo *stInfo, NSArray *names)
				{ return [stInfo objectOfTimeEvoTableWithNames:names]; }];
		[self makeDataFileWith:number type:@"daily" dir:bjDir names:output_d
			makeObj:^(StatInfo *stInfo, NSArray *names)
				{ return [stInfo objectOfTransitTableWithNames:names]; }];
		[self makeDataFileWith:number type:@"distribution" dir:bjDir names:output_D
			makeObj:^(StatInfo *stInfo, NSArray *names)
				{ return [stInfo objectOfHistgramTableWithNames:names]; }];
	} @catch (NSString *msg) {
		os_log_error(OS_LOG_DEFAULT, "Data strage %@ %@.", dataDirectory, msg);
	} @catch (NSError *error) {
		os_log_error(OS_LOG_DEFAULT, "%@", error.localizedDescription);
	}
// check next trial
	if (nextTrialNumber >= _nIteration)
		[theJobController jobDidComplete:self];
	else {
		[lock lock];
		[availableWorlds addObject:runningTrials[number]];
		[runningTrials removeObjectForKey:number];
		[lock unlock];
	}
	[theJobController tryNewTrial:YES];
}
- (void)runNextTrial {
	Document *doc = nil;
	[lock lock];
	if (availableWorlds.count <= 0) {
		doc = make_new_world(@"Job", browserID);
		[doc setScenarioWithPList:_scenario];
		set_params_from_dict(doc.initParamsP, doc.worldParamsP, _parameters);
	} else {
		doc = [availableWorlds lastObject];
		[availableWorlds removeLastObject];
		[doc resetPop];
	}
	NSNumber *trialNumb = @(++ nextTrialNumber);
	[lock unlock];
	doc.stopCallBack = ^(LoopMode mode){
		[self trialDidFinish:trialNumb mode:mode];
	};
	[doc start:_stopAt];
	runningTrials[trialNumb] = doc;
	os_log(OS_LOG_DEFAULT, "Trial %@/%ld of job %@ started on world %@.",
		trialNumb, _nIteration, _ID, doc.ID);
}
- (NSDictionary *)jobStatus {
	NSInteger nowProcessed = runningTrials.count;
	return @{@"notYet":@(_nIteration - nextTrialNumber),
		@"nowProcessed":@(nowProcessed),
		@"finished":@(nextTrialNumber - nowProcessed) };
}
- (void)stop {
	for (Document *doc in runningTrials.objectEnumerator) [doc stop];
	[theJobController jobDidComplete:self];
}
@end

@implementation ProcContext (BatchJobExtension)
- (void)submitJob {
	if (theJobController != nil && theJobController.queueLength >= maxJobsInQueue)
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
	BatchJob *job = [BatchJob.alloc initWithInfo:jobInfo browser:browserID];
	if (job == nil) @throw @"500 Couldn't make a batch job.";
	if (theJobController == nil) theJobController = JobController.new;
	os_log(OS_LOG_DEFAULT, "Job %@ was submitted from %{network:in_addr}d.",
		job.ID, ip4addr);
	[theJobController submitJob:job];
	content = job.ID;
	type = @"text/plain";
	code = 200;
}
- (BatchJob *)targetJob {
	NSString *jobID = query[@"job"];
	if (jobID == nil) @throw @"500 Job ID is requied.";
	BatchJob *job = [theJobController jobFromID:jobID];
	if (job == nil) @throw [NSString stringWithFormat:
		@"500 Job with ID:%@ doesn't exist.", jobID];
	return job;
}
- (void)getJobStatus {
	[self setJSONDataAsResponse:self.targetJob.jobStatus];
}
- (void)getJobQueueStatus {
	NSMutableDictionary *md = NSMutableDictionary.new;
	md[@"length"] = @(theJobController.queueLength);
	for (NSString *jobID in query) {
		if (query[jobID].integerValue != 1) continue;
		BatchJob *job = [theJobController jobFromID:jobID];
		if (job == nil) continue;
		NSInteger index = [theJobController indexOfJobInQueue:job];
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
			[NSFileManager.defaultManager enumeratorAtPath:jobDir]) {
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
	if (jobID == nil) @throw @"500 Job ID is requied.";
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
			os_log_error(OS_LOG_DEFAULT, "Couldn't create directory %@.", myTmpDir);
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
			os_log_error(OS_LOG_DEFAULT, "%@", error.localizedDescription);
		moreHeader = [NSString stringWithFormat:
			@"Content-Disposition: attachment; filename=\"%@.zip\"\n", save];
		type = @"application/zip";
		code = 200;
	}
}
@end
