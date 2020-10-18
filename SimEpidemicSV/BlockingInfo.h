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

extern BOOL check_blocking(int code, uint32 ipaddr);
extern BOOL should_block_it(uint32 ipaddr);

NS_ASSUME_NONNULL_END
