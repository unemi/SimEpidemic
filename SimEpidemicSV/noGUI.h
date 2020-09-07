//
//  noGUI.h
//  simepidemic
//
//  Created by Tatsuo Unemi on 2020/08/31.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>
#import "Document.h"

extern NSMutableArray<Document *> *theDocuments;
extern void connection_thread(void);
