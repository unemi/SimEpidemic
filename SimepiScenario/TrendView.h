//
//  TrendView.h
//  SimepiScenario
//
//  Created by Tatsuo Unemi on 2022/07/14.
//  Copyright © 2022 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MyController;

@interface TrendView : NSTableCellView
- (void)setupWithController:(MyController *)cnt seq:(NSMutableArray<NSMutableDictionary *> *)sq;
@end

NS_ASSUME_NONNULL_END
