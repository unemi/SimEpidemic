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

extern NSMutableDictionary<NSNumber *, Document *> *theDocuments;
extern NSUInteger JSONOptions;
extern NSString *fileDirectory;
extern NSDictionary *extToMime, *codeMeaning, *indexNames;
extern NSDateFormatter *dateFormat;
extern void connection_thread(void);
