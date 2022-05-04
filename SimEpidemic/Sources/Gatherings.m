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

NSDictionary *item_template(void) {
	static NSDictionary *template = nil;
	if (template == nil) template = @{@"minAge":@(0), @"maxAge":@(130),
		@"npp":@(100), @"freq":@(5), @"duration":@(2), @"size":@(8),@"strength":@(80),
		@"participation":@(50)};
	return template;
}
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
		CGFloat RGB[3]; memcpy(RGB, rgb, sizeof(RGB));
		if (gat->type > 0) for (NSInteger i = 0; i < 3; i ++) RGB[i] = 1.;
		[[NSColor colorWithCalibratedRed:RGB[0] green:RGB[1] blue:RGB[2]
			alpha:gat->strength * .005] setFill];
		[[NSBezierPath bezierPathWithOvalInRect:rect] fill];
	}
}
#endif

@implementation World (GatheringExtantion)
- (void)resetRegGatInfo {
	Agent *agents = self.agents;
	NSInteger nPop = worldParams.initPop;
	regGatInfo = NSMutableDictionary.new;
	for (NSMutableDictionary *item in self.gatheringsList) {
		NSString *name = item[@"name"]; if (name == nil) continue;
		NSDictionary *initParams = item[@"initParams"];
		if (initParams != nil) for (NSString *key in initParams) item[key] = initParams[key];
		NSInteger n = [item[@"npp"] doubleValue] * nPop / 1e5;
		NSMutableArray *p = [NSMutableArray arrayWithCapacity:n];
		[self doItExclusivelyForRandomIndexes:NULL n:n block:^(NSInteger i, NSInteger k) {
			Agent *a = &agents[k];
			[p addObject:[NSValue valueWithPoint:(NSPoint){a->x, a->y}]];
		}];
		regGatInfo[name] = p;
		rndPopOffset = (rndPopOffset + n) % nPop;
	}
}
- (void)reviseRegGatNppOfName:(NSString *)name npp:(CGFloat)npp {
	NSInteger nPop = worldParams.initPop;
	NSInteger n = npp * nPop / 1e5;
	NSMutableArray *info = regGatInfo[name];
	if (info == nil) regGatInfo[name] = [NSMutableArray arrayWithCapacity:n];
	else if (info.count >= n) return;
	else n -= info.count;
	Agent *agents = self.agents;
	[self doItExclusivelyForRandomIndexes:NULL n:n block:^(NSInteger i, NSInteger k) {
		[info addObject:[NSValue valueWithPoint:agents[k].orgPt]];
	}];
	rndPopOffset = (rndPopOffset + n) % nPop;
}
- (void)collectParticipants:(Gathering *)gat
	agentsIDs:(NSMutableArray<NSNumber *> *)agents
	row:(NSInteger)row left:(NSInteger)left right:(NSInteger)right test:(BOOL (^)(Agent *))test {
	Agent **pmap = self.Pop;
	for (NSInteger ix = left; ix < right; ix ++)
		for (Agent *a = pmap[row + ix]; a; a = a->next)
			if (a->health != Symptomatic && test(a)) {
				[agents addObject:@(a->ID)];
				a->gathering = gat;
			}
}
static NSInteger ix_right(NSInteger wSize, NSInteger mesh, CGFloat x, CGFloat grid) {
	NSInteger right = ceil(fmin(wSize, x) / grid);
	return (right <= mesh)? right : mesh;
}
- (void)collectParticipants:(Gathering *)gat test:(BOOL (^)(Agent *))test {
	WorldParams *wp = &worldParams;
	CGFloat grid = (CGFloat)wp->worldSize / wp->mesh, r = gat->size + SURROUND;
	NSInteger bottom = floor(fmax(0., gat->p.y - r) / grid),
		top = floor(fmin(wp->worldSize, gat->p.y + r) / grid),
		center = round(gat->p.y / grid);
	if (top >= wp->mesh) top = wp->mesh - 1;
	if (center >= wp->mesh) center = wp->mesh - 1;
	NSMutableArray<NSNumber *> *agents = NSMutableArray.new;
	for (NSInteger iy = bottom; iy < center; iy ++) {
		CGFloat dy = gat->p.y - (iy + 1) * grid, dx = sqrt(r * r - dy * dy);
		[self collectParticipants:gat agentsIDs:agents row:iy * wp->mesh
			left:floor(fmax(0., gat->p.x - dx) / grid)
			right:ix_right(wp->worldSize, wp->mesh, gat->p.x + dx, grid) test:test];
	}
	for (NSInteger iy = top; iy >= center; iy --) {
		CGFloat dy = gat->p.y - iy * grid, dx = sqrt(r * r - dy * dy);
		[self collectParticipants:gat agentsIDs:agents row:iy * wp->mesh
			left:floor(fmax(0., gat->p.x - dx) / grid)
			right:ix_right(wp->worldSize, wp->mesh, gat->p.x + dx, grid) test:test];
	}
	gat->nAgents = agents.count;
	gat->agents = realloc(gat->agents, sizeof(void *) * gat->nAgents);
	for (NSInteger i = 0; i < gat->nAgents; i ++)
		gat->agents[i] = self.agents + agents[i].integerValue;
}
- (void)setupGathering:(Gathering *)gat {
	WorldParams *wp = &worldParams;
	RuntimeParams *rp = &runtimeParams;
	gat->size = my_random(&rp->gatSZ);
	gat->duration = my_random(&rp->gatDR);
	gat->strength = my_random(&rp->gatST);
	NSInteger wSize = wp->worldSize;
	gat->p = (gatSpotsFixed != nil && rp->gatRndRt / 100. < d_random())?
		((NSPoint *)(gatSpotsFixed.bytes))[random() % (gatSpotsFixed.length / sizeof(NSPoint))] :
		(wp->wrkPlcMode == WrkPlcNone)?
			(NSPoint){ d_random() * wSize, d_random() * wSize } :
			self.agents[random() % wp->initPop].orgPt;
	if (wp->wrkPlcMode == WrkPlcCentered) gat->size *= centered_bias((CGPoint){
		gat->p.x / wSize * 2. - 1., gat->p.y / wSize * 2. - 1. }) * M_SQRT2;
	DistInfo *prmGatFreq = &runtimeParams.gatFreq;
	[self collectParticipants:gat test:^BOOL(Agent *a)
		{ return d_random() < modified_prob(a->gatFreq, prmGatFreq) / 100.; }];
#ifndef NOGUI
	gat->type = 0;
#endif
}
- (Gathering *)setupRegGathering:(Gathering *)gat info:(NSMutableDictionary *)info {
	CGFloat size = [info[@"size"] doubleValue],
		duration = [info[@"duration"] doubleValue],
		strength = [info[@"strength"] doubleValue],
		joinRate = [info[@"participation"] doubleValue] / 100.,
		minAge, maxAge;
	NSInteger n = [info[@"n"] integerValue];
	NSNumber *num;
	minAge = ((num = info[@"minAge"]) == nil)? 0. : num.doubleValue;
	maxAge = ((num = info[@"maxAge"]) == nil)? 200. : num.doubleValue;
	NSEnumerator<NSValue *> *ptEnm = regGatInfo[info[@"name"]].objectEnumerator;
#ifndef NOGUI
	NSInteger gatType = [self.gatheringsList indexOfObject:info] + 1;
#endif
	for (NSInteger i = 0; i < n && gat != NULL; i ++, gat = gat->next) {
		gat->size = size;
		gat->duration = duration;
		gat->strength = strength;
		gat->p = ptEnm.nextObject.pointValue;
		CGFloat *rndP = agentsRnd;
		[self collectParticipants:gat test:^BOOL(Agent *a) {
			return a->age >= minAge && a->age <= maxAge && rndP[a->ID] < joinRate; }];
#ifdef DEBUG
	printf("%s %ld\n", [(NSString *)info[@"name"] UTF8String], gat->nAgents);
#endif
#ifndef NOGUI
		gat->type = gatType;
#endif
	}
	info[@"n"] = nil;
	return gat;
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

	NSInteger nRegGat = 0;
	MutableDictArray regGatToBeFired = NSMutableArray.new;
	for (NSMutableDictionary *gatItem in self.gatheringsList) {
		CGFloat stpCnt = [gatItem[@"stpCnt"] doubleValue],
			freq = [gatItem[@"freq"] doubleValue];
		if (freq <= 0.) continue;
		if ((stpCnt -= 1.) <= 0.) {
			[regGatToBeFired addObject:gatItem];
			stpCnt += 7 * worldParams.stepsPerDay / freq;
			NSInteger nGats = [gatItem[@"npp"] doubleValue] * worldParams.initPop / 1e5;
			gatItem[@"n"] = @(nGats);
			nRegGat += nGats;
		}
		gatItem[@"stpCnt"] = @(stpCnt);
	}

//	calculate the number of gathering circles
//	using random number in exponetial distribution.
	NSInteger nRndGat = round(rp->gatFr / wp->stepsPerDay
		* wp->worldSize * wp->worldSize / GAT_DENS * - log(d_random() * .9999 + .0001)),
		nNewGat = nRndGat + nRegGat;
//	if (rp->step % wp->stepsPerDay == wp->stepsPerDay - 1)
//		printf("%ld %.2f %ld\n", rp->step / wp->stepsPerDay, rp->gatFr, nNewGat);
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
	Gathering *tail = NULL, *gat = newGats;
	for (NSInteger i = 0; i < nRndGat && gat != NULL; i ++, gat = gat->next)
		[self setupGathering:gat];
	for (NSMutableDictionary *gatItem in regGatToBeFired)
		gat = [self setupRegGathering:gat info:gatItem];
	for (tail = newGats; tail->next != NULL; tail = tail->next) ;
	tail->next = gatherings;
	if (gatherings != NULL) gatherings->prev = tail;
	gatherings = newGats;
}
@end
