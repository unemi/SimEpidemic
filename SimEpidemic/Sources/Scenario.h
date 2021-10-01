//
//  Scenario.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2021/10/01.
//  Copyright © 2021 Tatsuo Unemi. All rights reserved.
//
#import <AppKit/AppKit.h>
#import "World.h"

NS_ASSUME_NONNULL_BEGIN
@interface World (Scenario)
- (void)execScenario;
- (NSArray *)scenario;
- (NSInteger)scenarioIndex;
- (void)setScenario:(NSArray *)newScen index:(NSInteger)idx;
- (NSArray *)scenarioPList;
#ifndef NOGUI
- (void)setupPhaseInfo;
#endif
- (void)setScenarioWithPList:(NSArray *)plist;
@end
NS_ASSUME_NONNULL_END
