//
//  Statistics.h
//  simepiWorld
//
//  Created by Tatsuo Unemi on 2020/11/24.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "main.h"

NS_ASSUME_NONNULL_BEGIN

extern NSArray *make_history(StatData *stat, NSInteger nItems,
	NSNumber *(^getter)(StatData *));
extern void get_indexes(ComGetIndexes *c);
extern NSArray *dist_cnt_array(NSArray<MyCounter *> *hist);
extern void get_distribution(ComGetDistribution *c);
extern void get_population(ComGetPopulation *c);

NS_ASSUME_NONNULL_END
