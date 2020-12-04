//
//  DocThread.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/11/30.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "DocThread.h"

enum { QUEUE_EMPTY, QUEUE_HAS_TASK };
@interface DocThread : NSObject
@end
static NSMutableArray<void (^)(void)> *theTaskQueue;
static NSMutableArray<DocThread *> *theThreads;
static NSConditionLock *docTaskQueLock, *runningTaskLock;

@implementation DocThread
- (instancetype)initWithIndex:(NSInteger)index {
	if (!(self = [super init])) return nil;
	NSThread *thread = [NSThread.alloc initWithTarget:self
		selector:@selector(myThread:) object:@(index)];
	thread.name = [NSString stringWithFormat:@"Doc%ld", index];
	thread.threadPriority = thread.threadPriority * .9;
	[thread start];
	return self;
}
- (void)myThread:(NSNumber *)number {
	for (;;) @autoreleasepool {
		[docTaskQueLock lockWhenCondition:QUEUE_HAS_TASK];
		void (^block)(void) = theTaskQueue[0];
		[theTaskQueue removeObjectAtIndex:0];
		[runningTaskLock lock];
		[runningTaskLock unlockWithCondition:runningTaskLock.condition + 1];
		[docTaskQueLock unlockWithCondition:
			(theTaskQueue.count > 0)? QUEUE_HAS_TASK : QUEUE_EMPTY];
		block();
		[runningTaskLock lock];
		[runningTaskLock unlockWithCondition:runningTaskLock.condition - 1];
	}
}
@end

void init_doc_threads(NSInteger nThreads) {
	theTaskQueue = NSMutableArray.new;
	theThreads = NSMutableArray.new;
	docTaskQueLock = NSConditionLock.new;
	runningTaskLock = NSConditionLock.new;
	for (NSInteger i = 0; i < nThreads; i ++)
		[theThreads addObject:[DocThread.alloc initWithIndex:i]];
}
void add_doc_task(void (^block)(void)) {
	[docTaskQueLock lock];
	[theTaskQueue addObject:block];
	[docTaskQueLock unlockWithCondition:QUEUE_HAS_TASK];
}
void wait_all_doc_tasks(void) {
	[docTaskQueLock lockWhenCondition:QUEUE_EMPTY];
	[runningTaskLock lockWhenCondition:0];
	[runningTaskLock unlock];
	[docTaskQueLock unlock];
}
