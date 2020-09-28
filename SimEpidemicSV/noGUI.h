//
//  noGUI.h
//  simepidemic
//
//  Created by Tatsuo Unemi on 2020/08/31.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>
#import "Document.h"
#define MAX_INT32 0x7fffffff

extern NSMutableDictionary<NSString *, Document *> *defaultDocuments;
extern NSMutableDictionary<NSString *, Document *> *theDocuments;
extern NSUInteger JSONOptions;
extern NSInteger maxPopSize, maxNDocuments, maxRuntime,
	documentTimeout, maxJobsInQueue, maxTrialsAtSameTime;
extern NSString *fileDirectory, *dataDirectory;
extern NSDictionary *extToMime, *codeMeaning, *indexNames;
extern NSArray *distributionNames;
extern NSDateFormatter *dateFormat;
extern NSString *new_uniq_string(void);
extern void connection_thread(void);
