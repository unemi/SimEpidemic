//
//  TrendView.m
//  SimepiScenario
//
//  Created by Tatsuo Unemi on 2022/07/14.
//  Copyright © 2022 Tatsuo Unemi. All rights reserved.
//

#import "TrendView.h"
#import "MyController.h"

@interface TrendView () {
	MyController *control;
	NSMutableArray<NSMutableDictionary *> *seq;
	NSArray<NSBezierPath *> *paths;
}
@end

@implementation TrendView
- (void)setupWithController:(MyController *)cnt seq:(NSMutableArray<NSMutableDictionary *> *)sq {
	if (cnt == control) return;
	control = cnt;
	seq = sq;
	@try {
	CGFloat value[3] = {0.,0.,0.}, day = 0.;
	for (NSDictionary *item in sq) {
		id valInfo = item[@"value"];
		DayRange rng = day_range_from_item(item);
		if ([valInfo isKindOfClass:NSArray.class]) {
			NSArray<NSNumber *> *dist = valInfo;
			if (dist.count < 3)
				@throw @"Value info is an array, but it has less than three elements.";
			CGFloat v[3];
			for (NSInteger i = 0; i < 3; i ++) v[i] = dist[i].doubleValue;
			if (paths == nil) {
				paths = @[NSBezierPath.new, NSBezierPath.new, NSBezierPath.new];
				for (NSInteger i = 0; i < 3; i ++)
					[paths[i] moveToPoint:(NSPoint){0, (value[i] = v[i])}];
			} else if (paths.count < 3) @throw @"Value info is an array, but 'paths' is singleton.";
			if (day != rng.start) for (NSInteger i = 0; i < 3; i ++)
				[paths[i] lineToPoint:(NSPoint){rng.start, value[i]}];
			day = rng.start + rng.duration;
			for (NSInteger i = 0; i < 3; i ++) {
				if (v[i] != value[i] || rng.duration != 0.)
					[paths[i] lineToPoint:(NSPoint){day, (value[i] = v[i])}];
			}
		} else {
			CGFloat v = ((NSNumber *)valInfo).doubleValue;
			if (paths == nil) {
				paths = @[NSBezierPath.new];
				[paths[0] moveToPoint:(NSPoint){0, (value[0] = v)}];
			}
			if (day != rng.start) [paths[0] lineToPoint:(NSPoint){rng.start, value[0]}];
			day = rng.start + rng.duration;
			if (v != value[0] || rng.duration != 0.)
				[paths[0] lineToPoint:(NSPoint){day, (value[0] = v)}];
		}
	}
	if (day < cnt.lastDay) for (NSInteger i = 0; i < paths.count; i ++)
		[paths[i] lineToPoint:(NSPoint){cnt.lastDay, value[i]}];
#define PAD_RATE .1
	NSRect bbox = NSZeroRect, bds = self.bounds;
	for (NSBezierPath *path in paths) bbox = NSUnionRect(bbox, path.bounds);
//	bbox.origin.y -= bbox.size.height * PAD_RATE;
//	if ((bbox.size.height *= 1. + PAD_RATE * 2.) <= 0.)
//		{ bbox.size.height = 1.; bbox.origin.y = minV - .5; }
	if (bbox.size.height <= 0.) bbox.size.height = 1.;
	NSAffineTransform *trans = NSAffineTransform.transform;
	[trans translateXBy:bds.origin.x - bbox.origin.x yBy:bds.origin.y - bbox.origin.y];
	[trans scaleXBy:bds.size.width / bbox.size.width yBy:bds.size.height / bbox.size.height];
	for (NSBezierPath *path in paths) [path transformUsingAffineTransform:trans];
NSRect bx = paths[0].bounds;
printf("pathBBox = %.2f,%.2f %.2fx%.2f, view = %.2f,%.2f %.2fx%.2f\n",
	bx.origin.x,bx.origin.y,bx.size.width,bx.size.height,
	bds.origin.x,bds.origin.y,bds.size.width,bds.size.height);
	} @catch (NSObject *obj) {
		in_main_thread( ^{ error_msg(obj); [NSApp terminate:nil]; } );
	}
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    for (NSBezierPath *path in paths) [path stroke];
}
@end
