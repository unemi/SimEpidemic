//
//  BatchJob.h
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/09/14.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>
#import "ProcContext.h"

NS_ASSUME_NONNULL_BEGIN

@class Document;

extern NSString *batch_job_dir(void);
extern void for_all_bacth_job_documents(void (^block)(Document *));
extern void check_batch_jobs_to_restart(void);

@interface BatchJob : NSObject {
	NSLock *lock;
	NSMutableDictionary<NSNumber *, Document *> *runningTrials;
	NSMutableArray<Document *> *availableWorlds;
	NSInteger nextTrialNumber;
	NSArray<NSString *> *output_n, *output_d, *output_D;
	NSString *jobDirPath;
	NSString *loadState;
	BOOL shouldSaveState;
}
@property (readonly) NSString *ID;
@property (readonly) NSDictionary<NSString *, NSNumber *> *parameters;
@property (readonly) NSArray *scenario;
@property (readonly) NSInteger stopAt, nIteration;
- (void)runNextTrial;
- (void)forAllLiveDocuments:(void (^)(Document *))block;
@end

@interface JobController : NSObject {
	NSLock *lock;
	NSMutableDictionary<NSString *, BatchJob *> *theJobs;
	NSMutableArray<BatchJob *> *jobQueue;
	NSInteger nRunningTrials;
	NSMutableArray *unfinishedJobIDs;
}
@end

@interface ProcContext (BatchJobExtension)
- (void)submitJob;
- (void)getJobStatus;
- (void)getJobQueueStatus;
- (void)stopJob;
- (void)getJobResults;
@end

NS_ASSUME_NONNULL_END
