//
//  Gatherings.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/09/20.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "Gatherings.h"
#import "Agent.h"
#define SURROUND 5
#define GATHERING_FORCE .5

void affect_to_agent(Gathering *gat, Agent *a) {
	if (a->isWarping || a->health == Symptomatic) {
		a->gathering = NULL;
	} else {
		CGFloat dx = gat->p.x - a->x, dy = gat->p.y - a->y, d = hypot(dx, dy);
		if (d > gat->size + SURROUND || d < .01) return;
		CGFloat f = gat->strength / SURROUND * GATHERING_FORCE *
			((d > gat->size)? gat->size + SURROUND - d : d * SURROUND / gat->size);
		a->fx += dx / d * f;
		a->fy += dy / d * f;
		if (d < gat->size && a->gatDist > d / gat->size) a->gatDist = d / gat->size;
	}
}
#ifndef NOGUI
void draw_gathering(Gathering *gat, CGFloat *rgb, NSRect dRect) {
	NSRect rect = {gat->p.x - gat->size, gat->p.y - gat->size, gat->size * 2., gat->size * 2.};
	if (NSIntersectsRect(rect, dRect)) {
		[[NSColor colorWithCalibratedRed:rgb[0] green:rgb[1] blue:rgb[2]
			alpha:gat->strength * .01] setFill];
		[[NSBezierPath bezierPathWithOvalInRect:rect] fill];
	}
}
#endif

static void collect_participants(Gathering *gat, Agent **pop,
	NSMutableArray<NSNumber *> *agents, RuntimeParams *rp,
	NSInteger row, NSInteger left, NSInteger right) {
	for (NSInteger ix = left; ix < right; ix ++)
		for (Agent *a = pop[row + ix]; a; a = a->next)
			if (a->health != Symptomatic &&
				d_random() < modified_prob(a->gatFreq, &rp->gatFreq) / 100.) {
				[agents addObject:@(a->ID)];
				a->gathering = gat;
			}
}
static NSInteger ix_right(NSInteger wSize, NSInteger mesh, CGFloat x, CGFloat grid) {
	NSInteger right = ceil(fmin(wSize, x) / grid);
	return (right <= mesh)? right : mesh;
}

@implementation World (GatheringExtantion)
- (void)setupGathering:(Gathering *)gat {
	WorldParams *wp = &worldParams;
	RuntimeParams *rp = &runtimeParams;
	gat->size = my_random(&rp->gatSZ);
	gat->duration = my_random(&rp->gatDR);
	gat->strength = my_random(&rp->gatST);
	NSInteger wSize = wp->worldSize;
	gat->p = (wp->wrkPlcMode == WrkPlcNone)?
		(NSPoint){ d_random() * wSize, d_random() * wSize } :
		self.agents[random() % wp->initPop].orgPt;
	if (wp->wrkPlcMode == WrkPlcCentered) gat->size *= centered_bias((CGPoint){
		gat->p.x / wSize * 2. - 1., gat->p.y / wSize * 2. - 1. }) * M_SQRT2;
	CGFloat grid = (CGFloat)wSize / wp->mesh, r = gat->size + SURROUND;
	NSInteger bottom = floor(fmax(0., gat->p.y - r) / grid),
		top = floor(fmin(wp->worldSize, gat->p.y + r) / grid),
		center = round(gat->p.y / grid);
	if (top >= wp->mesh) top = wp->mesh - 1;
	if (center >= wp->mesh) center = wp->mesh - 1;
	NSMutableArray<NSNumber *> *agents = NSMutableArray.new;
	Agent **pmap = self.Pop;
	for (NSInteger iy = bottom; iy < center; iy ++) {
		CGFloat dy = gat->p.y - (iy + 1) * grid, dx = sqrt(r * r - dy * dy);
		collect_participants(gat, pmap, agents, rp, iy * wp->mesh,
			floor(fmax(0., gat->p.x - dx) / grid),
			ix_right(wp->worldSize, wp->mesh, gat->p.x + dx, grid));
	}
	for (NSInteger iy = top; iy >= center; iy --) {
		CGFloat dy = gat->p.y - iy * grid,
			dx = sqrt(r * r - dy * dy);
		collect_participants(gat, pmap, agents, rp, iy * wp->mesh,
			floor(fmax(0., gat->p.x - dx) / grid),
			ix_right(wp->worldSize, wp->mesh, gat->p.x + dx, grid));
	}
	gat->nAgents = agents.count;
	gat->agents = realloc(gat->agents, sizeof(void *) * gat->nAgents);
	for (NSInteger i = 0; i < gat->nAgents; i ++)
		gat->agents[i] = self.agents + agents[i].integerValue;
}
static BOOL step_gathering(Gathering *gat, CGFloat stepsPerDay) {
	return (gat->duration -= 24./stepsPerDay) <= 0.;
}
#ifdef VER_1_8
#define GAT_DENS 5e4
#else
#define GAT_DENS 1e5
#endif
- (void)manageGatherings {
	Gathering *gatToFree = NULL, *freeTail = NULL, *nextGat;
	NSInteger nFree = 0;
	WorldParams *wp = &worldParams;
	RuntimeParams *rp = &runtimeParams;
	for (Gathering *gat = gatherings; gat != NULL; gat = nextGat) {
		nextGat = gat->next;
		if (step_gathering(gat, wp->stepsPerDay)) {	// if the gathering was expired ...
			if (gatherings == gat) gatherings = nextGat;
			for (NSInteger i = 0; i < gat->nAgents; i ++) {
				Agent *a = gat->agents[i];
				if (a != NULL && a->gathering == gat) a->gathering = NULL;
			}
			if (nextGat != NULL) nextGat->prev = gat->prev;
			if (gat->prev != NULL) gat->prev->next = nextGat;
			gat->next = gatToFree;
			if (gatToFree != NULL) gatToFree->prev = gat;
			gatToFree = gat;
			if ((nFree ++) == 0) freeTail = gat;
		}
	}
	if (gatToFree != NULL) gatToFree->prev = NULL;
//	calculate the number of gathering circles
//	using random number in exponetial distribution.
	NSInteger nNewGat = round(rp->gatFr / wp->stepsPerDay
		* wp->worldSize * wp->worldSize / GAT_DENS * - log(d_random() * .9999 + .0001));
//	if (rp->step % 32 == 31) printf("%ld %ld\n", rp->step / 16, nNewGat);
	Gathering *newGats;
	if (nNewGat < nFree) {
		if (nNewGat <= 0) { [self freeGatherings:gatToFree]; return; }
		newGats = gatToFree;
		for (NSInteger i = nNewGat - 1; i > 0; i --) gatToFree = gatToFree->next;
		[self freeGatherings:gatToFree->next];
		gatToFree->next = NULL;
	} else if (nNewGat > nFree) {
		newGats = [self newNGatherings:nNewGat - nFree];
		if (nFree > 0) {
			freeTail->next = newGats;
			newGats->prev = freeTail;
			newGats = gatToFree;
		}
	} else if (nNewGat <= 0) return;
	else newGats = gatToFree;
	Gathering *tail = NULL;
	for (Gathering *gat = newGats; gat != NULL; gat = gat->next) {
		[self setupGathering:gat];
		if (gat->next == NULL) tail = gat;
	}
	tail->next = gatherings;
	if (gatherings != NULL) gatherings->prev = tail;
	gatherings = newGats;
}
@end
