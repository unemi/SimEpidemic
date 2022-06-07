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
NSArray *variable_gat_params(void) {
	static NSArray *params = nil;
	if (params == nil) params = @[@"freq", @"duration", @"strength", @"participation"];
	return params;
}
void correct_gathering_names(MutableDictArray list) {
	NSMutableDictionary *nameIdx = NSMutableDictionary.new;
	NSInteger index = 0;
	for (NSMutableDictionary *item in list) {
		NSString *name = item[@"name"];
		if (name == nil) item[@"name"] = [NSString stringWithFormat:@"__%04ld", index++];
		else {
			NSNumber *num = nameIdx[name];
			if (num != nil) {
				NSInteger nmIdx = num.integerValue + 1;
				item[@"name"] = [name stringByAppendingFormat:@"_%ld", nmIdx];
				nameIdx[name] = @(nmIdx);
			} else nameIdx[name] = @0;
} } }
void correct_gathering_list(MutableDictArray list) {
	NSDictionary *temp = item_template();
	for (NSMutableDictionary *item in list) {
		NSMutableDictionary *initPrm = item[@"initParams"];
		if (initPrm == nil) initPrm = item[@"initParams"] = NSMutableDictionary.new;
		for (NSString *key in temp) {
			NSObject *obj = item[key];
			if ([variable_gat_params() containsObject:key]) {
				NSObject *objI = initPrm[key];
				if (obj == nil && objI == nil)
					item[key] = initPrm[key] = temp[key];
				else if (obj == nil) item[key] = objI;
				else if (objI == nil) initPrm[key] = obj;
			} else if (obj == nil) item[key] = temp[key];
	} }
	correct_gathering_names(list);
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
	regGatInfo = NSMutableDictionary.new;
	for (NSMutableDictionary *item in self.gatheringsList) {
		NSString *name = item[@"name"]; if (name == nil) continue;
		NSDictionary *initParams = item[@"initParams"];
		if (initParams != nil) for (NSString *key in initParams) item[key] = initParams[key];
		NSInteger nPoints = [item[@"npp"] doubleValue] * worldParams.initPop / 1e5;
		if (nPoints > 0) {
			NSPoint *pts = malloc(sizeof(NSPoint) * nPoints);
			switch (worldParams.wrkPlcMode) {
				case WrkPlcPopDistImg:
					[self makeDistribution:pts n:nPoints]; break;
				default: {
					NSInteger nx = ceil(sqrt(nPoints));
					for (NSInteger i = 0; i < nPoints; i ++) {
						pts[i].x = worldParams.worldSize * (i % nx + .5) / nx;
						pts[i].y = worldParams.worldSize * (i / nx + .5) / nx;
				}}
			}
			CGFloat minAge = [item[@"minAge"] doubleValue];
			CGFloat maxAge = [item[@"maxAge"] doubleValue];
			Agent *agents = self.agents;
			NSMutableArray<NSNumber *> *plcList[nPoints];
			for (NSInteger i = 0; i < nPoints; i ++) plcList[i] = NSMutableArray.new;
			for (NSInteger i = 0; i < worldParams.initPop; i ++)
				if (agents[i].age >= minAge && agents[i].age < maxAge) {
					NSPoint pt = agents[i].orgPt;
					CGFloat minD = 1e10; NSInteger nearestPlc = -1;
					for (NSInteger j = 0; j < nPoints; j ++) {
						CGFloat d = pow(pt.x - pts[j].x, 2.) + pow(pt.y - pts[j].y, 2.);
						if (minD > d) { minD = d; nearestPlc = j; }
					}
					if (nearestPlc >= 0) [plcList[nearestPlc] addObject:@(i)];
			}
			CGFloat exceptionRate = 1. - [item[@"participation"] doubleValue] / 100.;
			NSMutableArray *gatInfo = NSMutableArray.new;
			for (NSInteger i = 0; i < nPoints; i ++) {
				NSMutableArray<NSNumber *> *candidates = plcList[i];
				NSInteger nException = round(candidates.count * exceptionRate);
				if (nException == candidates.count) continue;
				for (NSInteger j = 0; j < nException; j ++)
					[candidates removeObjectAtIndex:random() % candidates.count];
				if (candidates.count > 0) {
					NSMutableData *idData =
						[NSMutableData dataWithLength:sizeof(NSInteger) * candidates.count];
					for (NSInteger j = 0; j < candidates.count; j ++)
						((NSInteger *)idData.mutableBytes)[j] = candidates[j].integerValue;
					[gatInfo addObject:
						@{@"point":[NSValue valueWithPoint:pts[i]], @"member":idData}];
				}
			}
			free(pts);
			if (gatInfo.count > 0) regGatInfo[name] = gatInfo;
		}
	}
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
/*	CGFloat size = [info[@"size"] doubleValue],
		duration = [info[@"duration"] doubleValue],
		strength = [info[@"strength"] doubleValue],
		joinRate = [info[@"participation"] doubleValue] / 100.,
		minAge, maxAge;
	NSInteger n = [info[@"n"] integerValue];
	NSNumber *num;
	minAge = ((num = info[@"minAge"]) == nil)? 0. : num.doubleValue;
	maxAge = ((num = info[@"maxAge"]) == nil)? 200. : num.doubleValue;
	NSPoint *pts = (NSPoint *)regGatInfo[info[@"name"]].bytes;
#ifndef NOGUI
	NSInteger gatType = [self.gatheringsList indexOfObject:info] + 1;
#endif
	for (NSInteger i = 0; i < n && gat != NULL; i ++, gat = gat->next) {
		gat->size = size;
		gat->duration = duration;
		gat->strength = strength;
		gat->p = pts[i];
		CGFloat *rndP = agentsRnd;
		[self collectParticipants:gat test:^BOOL(Agent *a) {
			return a->age >= minAge && a->age < maxAge && rndP[a->ID] < joinRate; }];
#ifdef DEBUG
	printf("%ld %s(%.1f,%.1f)%s", gat->nAgents,
		[(NSString *)info[@"name"] UTF8String], gat->p.x, gat->p.y,
		(i<n)? ", " : "\n");
#endif
#ifndef NOGUI
		gat->type = gatType;
#endif
	}
	info[@"n"] = nil;
*/
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
