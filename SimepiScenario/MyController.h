//
//  MyView.h
//  SimepiScenario
//
//  Created by Tatsuo Unemi on 2022/07/12.
//  Copyright © 2022 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "TrendView.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct { CGFloat start, duration; } DayRange;
extern DayRange day_range_from_item(NSDictionary *item);
extern void in_main_thread(void (^block)(void));
extern void error_msg(NSObject *obj);

@interface MyController : NSObject <NSTableViewDelegate, NSTableViewDataSource> {
	IBOutlet NSTableView *nameView;
	IBOutlet NSTableView *prmView;
	NSString *header, *tail;
	NSMutableArray<NSDictionary *> *sequence;
	NSMutableArray *auxItems;
}
@property CGFloat lastDay;
- (void)setup;
@end

NS_ASSUME_NONNULL_END
