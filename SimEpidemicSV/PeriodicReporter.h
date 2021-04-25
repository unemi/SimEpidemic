//
//  PeriodicReporter.h
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/10/08.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ProcContext.h"

NS_ASSUME_NONNULL_BEGIN
@class World;

@interface PeriodicReporter : NSObject
@property (readonly) NSString *ID;
- (instancetype)initWithWorld:(World *)wd addr:(uint32)addr desc:(int)dsc;
- (BOOL)sendReport;
- (void)sendReportPeriodic;
- (void)reset;
- (void)start;
- (void)pause;
- (void)quit;
- (BOOL)connectionWillClose:(int)dsc;
@end

@interface ProcContext (PeriodicReportExtension)
- (void)periodicReport;
- (void)quitReport;
- (void)changeReport;
@end

NS_ASSUME_NONNULL_END
