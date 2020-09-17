//
//  BatchJob.m
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/09/14.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "BatchJob.h"
#import "noGUI.h"
#import "Document.h"

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
- (NSInteger)queueLength { return jobQueue.count; }
- (NSInteger)nRunningTrials { return nRunningTrials; }
@end

@implementation BatchJob
- (instancetype)initWithInfo:(NSDictionary *)info addr:(NSNumber *)addr {
	if (!(self = [super init])) return nil;
	_ID = new_uniq_string();
	_parameters = info[@"params"];
	_scenario = info[@"scenario"];
	NSNumber *num = info[@"stopAt"];
	_stopAt = (num == nil)? 0 : num.integerValue;
	num = info[@"nIterates"];
	_nIteration = (num == nil)? 1 : num.integerValue;
	if (_nIteration <= 1) _nIteration = 1;
	ip4addr = addr;
	lock = NSLock.new;
	runningTrials = NSMutableDictionary.new;
	availableWorlds = NSMutableArray.new;
	return self;
}
- (void)trialDidFinish:(NSNumber *)number mode:(LoopMode)mode {
	Document *doc = runningTrials[number];
// here it should extract data for output
//
	if (nextTrialNumber >= _nIteration)
		[theJobController jobDidComplete:self];
	else {
		[lock lock];
		[availableWorlds addObject:doc];
		[runningTrials removeObjectForKey:number];
		[lock unlock];
	}
	[theJobController tryNewTrial:YES];
}
- (void)runNextTrial {
	Document *doc = nil;
	[lock lock];
	NSNumber *trialNumb = @(nextTrialNumber);
	if (availableWorlds.count <= 0) {
		doc = make_new_world(@"Job", ip4addr);
		[doc setScenarioWithPList:_scenario];
		set_params_from_dict(doc.initParamsP, doc.worldParamsP, _parameters);
		doc.stopCallBack = ^(LoopMode mode){
			[self trialDidFinish:trialNumb mode:mode];
		};
	} else {
		doc = [availableWorlds lastObject];
		[availableWorlds removeLastObject];
	}
	nextTrialNumber ++;
	[lock unlock];
	[doc start:_stopAt];
	runningTrials[trialNumb] = doc;
}
@end

@implementation ProcContext (BatchJobExtension)
- (void)submitJob {
	if (theJobController != nil && theJobController.queueLength >= maxJobsInQueue)
		@throw [NSString stringWithFormat:
			@"500 The job queue is full (%ld jobs).", maxJobsInQueue];
	NSString *jobStr = query[@"JSON"];
	if (jobStr == nil) jobStr = query[@"job"];
	if (jobStr == nil) @throw @"417 Job data is missing.";
	NSData *jobData = [jobStr dataUsingEncoding:NSUTF8StringEncoding];
	NSError *error;
	NSDictionary *jobInfo = [NSJSONSerialization JSONObjectWithData:
		jobData options:0 error:&error];
	if (jobInfo == nil)
		@throw [NSString stringWithFormat:@"417 %@", error.localizedDescription];
	BatchJob *job = [BatchJob.alloc initWithInfo:jobInfo addr:ip4addr];
	if (job == nil) @throw @"500 Couldn't make a batch job.";
	if (theJobController == nil) theJobController = JobController.new;
	[theJobController submitJob:job];
	content = job.ID;
	type = @"text/plain";
	code = 200;
}
- (void)getJobStatus { [self notImplementedYet]; }
- (void)getJobQueueStatus { [self notImplementedYet]; }
- (void)stopJob { [self notImplementedYet]; }
- (void)getJobResults { [self notImplementedYet]; }
@end
