//
//  BlockingInfo.h
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/10/17.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BlockingInfo : NSObject
@end

extern BOOL check_blocking(int code, uint32 ipaddr, NSString *request);
extern BOOL should_block_it(uint32 ipaddr);
extern void schedule_clean_up_blocking_info(void);
extern void block_list_from_plist(NSArray *plist);
extern NSArray *block_list(void);
extern BOOL unblock(uint32 ipaddr);

NS_ASSUME_NONNULL_END
