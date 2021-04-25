//
//  Gatherings.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/09/20.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>
#import "World.h"

NS_ASSUME_NONNULL_BEGIN

extern void affect_to_agent(Gathering *gat, Agent *a);
#ifndef NOGUI
extern void draw_gathering(Gathering *gat, CGFloat *rgb, NSRect dRect);
#endif

@interface World (GatheringExtantion)
- (void)manageGatherings;
@end

NS_ASSUME_NONNULL_END
