//
//  Gatherings.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/09/20.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>
#import "CommonTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface Gathering : NSObject {
	CGFloat size, duration, strength;
	NSPoint p;
	NSMutableArray<NSNumber *> *cellIdxs;
}
- (void)affectToAgent:(Agent *)a;
#ifndef NOGUI
- (void)drawItWithRGB:(CGFloat *)rgb rect:(NSRect)dRect;
#endif
#ifdef DEBUG
- (void)printInfo:(WorldParams *)wp;
#endif
@end

extern void manage_gatherings(
	NSMutableArray<Gathering *> *gatherings,
	GatheringMap *gatMap,
	WorldParams *wp, RuntimeParams *rp);

NS_ASSUME_NONNULL_END
