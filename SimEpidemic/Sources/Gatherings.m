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

//a->gatActive = (1. - a->activeness) * rp->gatAct / 100.;

static inline CGFloat gat_act(Agent *a, RuntimeParams *rp) {
	return (1. - a->activeness) * rp->gatAct / 100.;
}
static void collect_participants(Gathering *gat, Agent **pop,
	NSMutableArray<NSNumber *> *agents, RuntimeParams *rp,
	NSInteger row, NSInteger left, NSInteger right) {
	for (NSInteger ix = left; ix < right; ix ++)
		for (Agent *a = pop[row + ix]; a; a = a->next)
			if (a->health != Symptomatic && random() / (CGFloat)0x7fffffff > gat_act(a, rp)) {
				[agents addObject:@((NSUInteger)a)];
				a->gathering = gat;
			}
}
static NSInteger ix_right(NSInteger wSize, NSInteger mesh, CGFloat x, CGFloat grid) {
	NSInteger right = ceil(fmin(wSize, x) / grid);
	return (right <= mesh)? right : mesh;
}
static void setup_gathering(Gathering *gat, Agent **pmap, WorldParams *wp, RuntimeParams *rp) {
	gat->size = my_random(&rp->gatSZ);
	gat->duration = my_random(&rp->gatDR);
	gat->strength = my_random(&rp->gatST);
	NSInteger wSize = wp->worldSize;
	gat->p = (NSPoint){ random() / (CGFloat)0x7fffffff * wSize,
		random() / (CGFloat)0x7fffffff * wSize };
	CGFloat grid = (CGFloat)wp->worldSize / wp->mesh, r = gat->size + SURROUND;
	NSInteger bottom = floor(fmax(0., gat->p.y - r) / grid),
		top = floor(fmin(wp->worldSize, gat->p.y + r) / grid),
		center = round(gat->p.y / grid);
	if (top >= wp->mesh) top = wp->mesh - 1;
	if (center >= wp->mesh) center = wp->mesh - 1;
	NSMutableArray<NSNumber *> *agents = NSMutableArray.new;
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
		gat->agents[i] = (Agent *)agents[i].integerValue;
}
static BOOL step_gathering(Gathering *gat, CGFloat stepsPerDay) {
	return (gat->duration -= 24./stepsPerDay) <= 0.;
}
void affect_to_agent(Gathering *gat, Agent *a) {
	if (a->isWarping || a->health == Symptomatic) {
		a->gathering = NULL;
	} else {
		CGFloat dx = gat->p.x - a->x, dy = gat->p.y - a->y, d = hypot(dx, dy);
		if (d > gat->size + SURROUND) return;
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

#ifdef VER_1_8
#define GAT_DENS 5e4
#else
#define GAT_DENS 1e5
#endif
Gathering *manage_gatherings(Gathering *gatherings,
	Agent **popmap, WorldParams *wp, RuntimeParams *rp) {
	Gathering *gatToFree = NULL, *freeTail = NULL, *nextGat;
	NSInteger nFree = 0;
	for (Gathering *gat = gatherings; gat != NULL; gat = nextGat) {
		nextGat = gat->next;
		if (step_gathering(gat, wp->stepsPerDay)) {
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
		* wp->worldSize * wp->worldSize / GAT_DENS *
		- log(random() / (CGFloat)0x7fffffff * .9999 + .0001));
	Gathering *newGats;
	if (nNewGat < nFree) {
		if (nNewGat <= 0) { free_gatherings(gatToFree); return gatherings; }
		newGats = gatToFree;
		for (NSInteger i = nNewGat - 1; i > 0; i --) gatToFree = gatToFree->next;
		free_gatherings(gatToFree->next);
		gatToFree->next = NULL;
	} else if (nNewGat > nFree) {
		newGats = new_n_gatherings(nNewGat - nFree);
		if (nFree > 0) {
			freeTail->next = newGats;
			newGats->prev = freeTail;
			newGats = gatToFree;
		}
	} else if (nNewGat <= 0) return gatherings;
	else newGats = gatToFree;
	Gathering *tail = NULL;
	for (Gathering *gat = newGats; gat != NULL; gat = gat->next) {
		setup_gathering(gat, popmap, wp, rp);
		if (gat->next == NULL) tail = gat;
	}
	tail->next = gatherings;
	if (gatherings != NULL) gatherings->prev = tail;
	return newGats;
}
