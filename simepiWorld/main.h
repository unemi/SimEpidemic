//
//  main.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/11/24.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#ifndef main_h
#define main_h

#import <Foundation/Foundation.h>
#import "../SimEpidemic/Sources/Document.h"
#import "../SimEpidemic/Sources/StatPanel.h"
#import "../simepiBackend/backend.h"

extern Document *document;
extern void respond_ok(void);
extern void respond_err(NSString *msg);
extern void respond_JSON(NSObject *plist);
extern NSObject *object_from_JSON(ComWithData *c);

#endif /* main_h */
