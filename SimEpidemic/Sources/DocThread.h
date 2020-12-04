//
//  DocThread.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/11/30.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Foundation/Foundation.h>

extern void init_doc_threads(NSInteger nThreads);
extern void add_doc_task(void (^block)(void));
extern void wait_all_doc_tasks(void);
