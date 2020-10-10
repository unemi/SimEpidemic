//
//  PeriodicReporter.h
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/10/08.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@class Document;

@interface PeriodicReporter : NSObject
@property (readonly) NSString *ID;
- (BOOL)setupWithQuery:(NSDictionary *)query;
- (instancetype)initWithDocument:(Document *)doc desc:(int)dsc;
- (BOOL)sendReport;
- (void)sendReportPeriodic;
- (void)reset;
- (void)pause;
- (void)quit;
- (BOOL)connectionWillClose:(int)dsc;
@end
NS_ASSUME_NONNULL_END
