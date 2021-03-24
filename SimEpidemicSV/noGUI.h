//
//  noGUI.h
//  simepidemic
//
//  Created by Tatsuo Unemi on 2020/08/31.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>
#import <os/log.h>

#define MY_LOG(...) { os_log(OS_LOG_DEFAULT, __VA_ARGS__);\
	my_log(__VA_ARGS__);}
#ifdef DEBUG
#define MY_LOG_DEBUG(...) os_log_debug(OS_LOG_DEFAULT, __VA_ARGS__);
#else
#define MY_LOG_DEBUG(...)
#endif

enum {
	EXIT_NORMAL,
	EXIT_SOCKET, EXIT_BIND, EXIT_LISTEN, EXIT_PID_FILE,
	EXIT_FATAL_ERROR, EXIT_FAILED_REGEXP, EXIT_FAILED_DEFLATER,
	EXIT_FAILED_IDCNT, EXIT_SENDING,
	EXIT_INVALID_ARGS
};
@class Document;
extern NSMutableDictionary<NSString *, Document *> *defaultDocuments;
extern NSMutableDictionary<NSString *, Document *> *theDocuments;
extern NSUInteger JSONOptions;
extern NSInteger maxPopSize, maxNDocuments, maxRuntime,
	documentTimeout, maxJobsInQueue, maxTrialsAtSameTime;
extern NSString *fileDirectory, *dataDirectory;
extern NSDictionary *extToMime, *codeMeaning, *indexNames;
extern NSArray *distributionNames;
extern NSDictionary *indexNameToIndex, *testINameToIdx;
extern NSDateFormatter *dateFormat;
extern void unix_error_msg(NSString *msg, int code);
extern NSString *new_uniq_string(void);
extern NSString *ip4_string(uint32 ip4addr);
extern void my_log(const char *, ...);
extern void connection_thread(void);
extern void terminateApp(int);
