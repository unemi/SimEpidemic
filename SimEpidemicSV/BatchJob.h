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

@interface BatchJob : NSObject {
	NSLock *lock;
	NSMutableDictionary<NSNumber *, Document *> *runningTrials;
	NSMutableArray<Document *> *availableWorlds;
	NSInteger nextTrialNumber;
	NSString *browserID;
	NSArray<NSString *> *output_n, *output_d, *output_D;
}
@property (readonly) NSString *ID;
@property (readonly) NSDictionary<NSString *, NSNumber *> *parameters;
@property (readonly) NSArray *scenario;
@property (readonly) NSInteger stopAt, nIteration;
- (void)runNextTrial;
@end

@interface ProcContext (BatchJobExtension)
@end

@interface JobController : NSObject {
	NSLock *lock;
	NSMutableDictionary<NSString *, BatchJob *> *theJobs;
	NSMutableArray<BatchJob *> *jobQueue;
	NSInteger nRunningTrials;
}
@end
NS_ASSUME_NONNULL_END
