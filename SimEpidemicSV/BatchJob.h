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

extern void schedule_job_expiration_check(void);
extern void for_all_bacth_job_documents(void (^block)(Document *));

@interface BatchJob : NSObject {
	NSLock *lock;
	NSMutableDictionary<NSNumber *, Document *> *runningTrials;
	NSMutableArray<Document *> *availableWorlds;
	NSInteger nextTrialNumber;
	NSArray<NSString *> *output_n, *output_d, *output_D;
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
