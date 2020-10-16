//
//  noGUI.h
//  simepidemic
//
//  Created by Tatsuo Unemi on 2020/08/31.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>

#define MY_LOG(...) { os_log(OS_LOG_DEFAULT, __VA_ARGS__);\
	my_log(__VA_ARGS__);}
#ifdef DEBUG
#define MY_LOG_DEBUG(...) os_log_debug(OS_LOG_DEFAULT, __VA_ARGS__);
#else
#define MY_LOG_DEBUG(...)
#endif

@class Document;
extern NSMutableDictionary<NSString *, Document *> *defaultDocuments;
extern NSMutableDictionary<NSString *, Document *> *theDocuments;
extern NSUInteger JSONOptions;
extern NSInteger maxPopSize, maxNDocuments, maxRuntime,
	documentTimeout, maxJobsInQueue, maxTrialsAtSameTime,
	jobRecExpirationHours;
extern NSString *fileDirectory, *dataDirectory;
extern NSDictionary *extToMime, *codeMeaning, *indexNames;
extern NSArray *distributionNames;
extern NSDictionary *indexNameToIndex, *testINameToIdx;
extern NSDateFormatter *dateFormat;
extern NSString *new_uniq_string(void);
extern NSString *ip4_string(uint32 ip4addr);
extern void my_log(const char *, ...);
extern void connection_thread(void);
extern void terminateApp(int);
