//
//  Gatherings.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/09/20.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "Gatherings.h"
#import "Document.h"
#import "Agent.h"
#define SURROUND 5
#define GATHERING_FORCE .5

@implementation Gathering
static void record_gat(Gathering *gat, GatheringMap *map,
	NSMutableArray<NSNumber *> *cellIdxs,
	NSInteger row, NSInteger left, NSInteger right) {
	for (NSInteger ix = left; ix < right; ix ++) {
		NSNumber *num = @(row + ix);
		if (map[num] == nil) map[num] = [NSMutableArray arrayWithObject:gat];
		else [map[num] addObject:gat];
		[cellIdxs addObject:num];
	}
}
static NSInteger ix_right(NSInteger wSize, NSInteger mesh, CGFloat x, CGFloat grid) {
	NSInteger right = ceil(fmin(wSize, x) / grid);
	return (right <= mesh)? right : mesh;
}
- (instancetype)initWithMap:(GatheringMap *)map
	world:(WorldParams *)wp runtime:(RuntimeParams *)rp {
	if (!(self = [super init])) return nil;
	size = my_random(&rp->gatSZ);
	duration = my_random(&rp->gatDR);
	strength = my_random(&rp->gatST);
	NSInteger wSize = wp->worldSize;
	p = (NSPoint){ random() / (CGFloat)0x7fffffff * wSize,
		random() / (CGFloat)0x7fffffff * wSize };
	cellIdxs = NSMutableArray.new;
	CGFloat grid = (CGFloat)wp->worldSize / wp->mesh, r = size + SURROUND;
	NSInteger bottom = floor(fmax(0., p.y - r) / grid),
		top = floor(fmin(wp->worldSize, p.y + r) / grid),
		center = round(p.y / grid);
	if (top >= wp->mesh) top = wp->mesh - 1;
	if (center >= wp->mesh) center = wp->mesh - 1;
	for (NSInteger iy = bottom; iy < center; iy ++) {
		CGFloat dy = p.y - (iy + 1) * grid, dx = sqrt(r * r - dy * dy);
		record_gat(self, map, cellIdxs, iy * wp->mesh,
			floor(fmax(0., p.x - dx) / grid),
			ix_right(wp->worldSize, wp->mesh, p.x + dx, grid));
	}
	for (NSInteger iy = top; iy >= center; iy --) {
		CGFloat dy = p.y - iy * grid,
			dx = sqrt(r * r - dy * dy);
		record_gat(self, map, cellIdxs, iy * wp->mesh,
			floor(fmax(0., p.x - dx) / grid),
			ix_right(wp->worldSize, wp->mesh, p.x + dx, grid));
	}
	return self;
}
- (BOOL)step:(CGFloat)stepsPerDay {
	return (duration -= 24./stepsPerDay) <= 0.;
}
- (void)removeFromMap:(GatheringMap *)gatMap {
	for (NSNumber *num in cellIdxs) {
		if (gatMap[num].count > 1) [gatMap[num] removeObject:self];
		else [gatMap removeObjectForKey:num];
	}
}
- (void)affectToAgent:(Agent *)a {
	CGFloat dx = p.x - a->x, dy = p.y - a->y, d = hypot(dx, dy);
	if (d > size + SURROUND || d < size - SURROUND) return;
	CGFloat f = strength / SURROUND * GATHERING_FORCE *
		((d > size)? size + SURROUND - d :
		 (size > SURROUND)? d - size + SURROUND : d * SURROUND / size);
	a->fx += dx / d * f;
	a->fy += dy / d * f;
}
#ifndef NOGUI
- (void)drawItWithRGB:(CGFloat *)rgb rect:(NSRect)dRect {
	NSRect rect = {p.x - size, p.y - size, size * 2., size * 2.};
	if (NSIntersectsRect(rect, dRect)) {
		[[NSColor colorWithCalibratedRed:rgb[0] green:rgb[1] blue:rgb[2]
			alpha:strength * .01] setFill];
		[[NSBezierPath bezierPathWithOvalInRect:rect] fill];
	}
}
#endif
#ifdef DEBUG
- (void)printInfo:(WorldParams *)wp {
	CGFloat s = 100. / wp->worldSize;
	NSInteger m = wp->mesh;
	printf("(%.1f, %.1f) %.1f; ", p.x * s, p.y * s, size * s);
	for (NSNumber *num in cellIdxs) {
		NSInteger idx = num.integerValue;
		printf("[%ld,%ld],", idx % m, idx / m);
	}
	printf("\n");
}
#endif
@end

void manage_gatherings(
	NSMutableArray<Gathering *> *gatherings, GatheringMap *gatMap,
	WorldParams *wp, RuntimeParams *rp) {
	for (NSInteger i = gatherings.count - 1; i >= 0; i --)
		if ([gatherings[i] step:wp->stepsPerDay]) {
			[gatherings[i] removeFromMap:gatMap];
			[gatherings removeObjectAtIndex:i];
		}
//	calculate the number of gathering circles
//	using random number in exponetial distribution.
	NSInteger nNewGat = round(rp->gatFr / wp->stepsPerDay
		* wp->worldSize * wp->worldSize / 1e5 *
		- log(random() / (CGFloat)0x7fffffff * .9999 + .0001));
	for (NSInteger i = 0; i < nNewGat; i ++)
		[gatherings addObject:[Gathering.alloc initWithMap:gatMap world:wp runtime:rp]];
}
