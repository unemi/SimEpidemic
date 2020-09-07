//
//  Agent.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "Agent.h"
#import "Document.h"
#import "StatPanel.h"
#define BIG_NUM 1e10
#define AVOIDANCE .2
// Random number of psuedo Gaussian distribution by Box-Müller method
static CGFloat random_guassian(CGFloat mu, CGFloat sigma) {
	static CGFloat z = 0.;
	static BOOL secondTime = NO;
	CGFloat x;
	if (secondTime) { secondTime = NO; x = z; }
	else {
		secondTime = YES;
		CGFloat r = sqrt(-2. * log(random() / (CGFloat)0x7fffffff)),
			th = random() / (CGFloat)0x7fffffff * M_PI * 2.;
		x = r * sin(th);
		z = r * cos(th);
	}
	return x * sigma + mu;
}
#define EXP_BASE .02
static CGFloat my_random(DistInfo *p) {
	if (p->mode == p->min) return (pow(EXP_BASE, random() / (CGFloat)0x7fffffff) - EXP_BASE)
		/ (1. - EXP_BASE) * (p->max - p->min) + p->min;
	else if (p->mode == p->max) return (1. - pow(EXP_BASE, random() / (CGFloat)0x7fffffff))
		/ (1. - EXP_BASE) * (p->max - p->min) + p->min;
	CGFloat x = random_guassian(.5, .166667);
	if (x < 0.) x += floor(1. - x);
	else if (x > 1.) x -= floor(x);
//	if (kurtosis != 0.) {
//		CGFloat b = pow(2., -kurtosis);
//		/* x = (x < .5)? b * x / ((b - 1) * x * 2. + 1.) :
//			(x - .5) / ((x + b - b * x) * 2. - 1.) + .5;  */
//		x = (x < .5)? pow(x * 2., b) * .5 : 1. - pow(2. - x * 2., b) * .5;
//	}
//	if (x < 0.) x = 0.; else if (x > 1.) x = 1.;
	CGFloat a = (p->mode - p->min) / (p->max - p->mode);
	return a * x / ((a - 1.) * x + 1.) * (p->max - p->min) + p->min;
}
BOOL was_hit(WorldParams *wp, CGFloat prob) {
	return (random() > pow(1. - prob, 1. / wp->stepsPerDay) * 0x7fffffff);
}
BOOL is_infected(Agent *a) {
	return a->health == Asymptomatic || a->health == Symptomatic;
}
static void reset_days(Agent *a, RuntimeParams *p) {
	a->daysInfected = a->daysDiseased = 0;
	a->daysToRecover = my_random(&p->recov);
	a->daysToOnset = my_random(&p->incub);
	a->daysToDie = my_random(&p->fatal) + a->daysToOnset;
	a->imExpr = my_random(&p->immun);
}
void reset_agent(Agent *a, RuntimeParams *rp, WorldParams *wp) {
	a->app = random() / (CGFloat)0x7fffffff;
	a->prf = random() / (CGFloat)0x7fffffff;
	a->x = random() / (CGFloat)0x7fffffff * (wp->worldSize - 6.) + 3.;
	a->y = random() / (CGFloat)0x7fffffff * (wp->worldSize - 6.) + 3.;
	CGFloat th = random() / (CGFloat)0x7fffffff * M_PI * 2.;
	a->vx = cos(th);
	a->vy = sin(th);
	a->health = Susceptible;
	a->nInfects = -1;
	a->newNInfects = 0;
	a->distancing = a->isWarping = NO;
	a->isOutOfField = YES;
	reset_days(a, rp);
	a->contactInfoHead = a->contactInfoTail = NULL;
	a->lastTested = -999999;
}
void reset_for_step(Agent *a) {
	a->fx = a->fy = 0.;
	a->best = NULL;
	a->bestDist = BIG_NUM;
	a->newHealth = a->health;
}
static NSInteger index_in_pop(Agent *a, WorldParams *p) {
	NSInteger iy = floor(a->y * p->mesh / p->worldSize);
	NSInteger ix = floor(a->x * p->mesh / p->worldSize);
	if (iy < 0) iy = 0; else if (iy >= p->mesh) iy = p->mesh - 1;
	if (ix < 0) ix = 0; else if (ix >= p->mesh) ix = p->mesh - 1;
	return iy * p->mesh + ix;
}
static void add_to_list(Agent *a, Agent **list) {
#ifdef DEBUG
for (Agent *b = *list; b != NULL; b = b->next) if (a == b)
	{ printf("agent %ld is already in the list.\n", a->ID); my_exit(); }
#endif
	a->next = *list;
	a->prev = NULL;
	if (*list != NULL) (*list)->prev = a;
	*list = a;
}
void remove_from_list(Agent *a, Agent **list) {
	if (a->prev != NULL) a->prev->next = a->next;
	else *list = a->next;
	if (a->next != NULL) a->next->prev = a->prev;
}
void add_agent(Agent *a, WorldParams *wp, Agent **Pop) {
#ifdef DEBUG
if (!a->isOutOfField)
	{ printf("agent %ld is already in the field.\n", a->ID); my_exit(); }
#endif
	a->isOutOfField = NO;
	add_to_list(a, Pop + index_in_pop(a, wp));
}
void remove_agent(Agent *a, WorldParams *wp, Agent **Pop) {
#ifdef DEBUG
if (a->isOutOfField)
	{ printf("agent %ld is already out of field.\n", a->ID); my_exit(); }
#endif
	a->isOutOfField = YES;
	remove_from_list(a, Pop + index_in_pop(a, wp));
}
static void attracted(Agent *a, Agent *b, RuntimeParams *rp, WorldParams *wp, CGFloat d) {
	CGFloat x = fabs(b->app - a->prf);
	x = ((x < 0.5)? x : 1.0 - x) * 2.0;
	if (a->bestDist > x) {
		a->bestDist = x;
		a->best = b;
	}
	// check contact and infection
	if (d < rp->infecDst) {
		if (was_hit(wp, rp->cntctTrc / 100.)) add_new_cinfo(a, b, rp->step);
		if (a->health == Susceptible && is_infected(b)) {
			CGFloat timeFactor = fmin(1., b->daysInfected / b->daysToOnset * 2.);
			CGFloat distanceFactor = fmin(1., pow((rp->infecDst - d) / 2., 2.));
			if (was_hit(wp, rp->infec / 100. * timeFactor * distanceFactor)) {
				a->newHealth = Asymptomatic;
				if (a->nInfects < 0) a->newNInfects = 1;
				b->newNInfects ++;
	}}}
}
void interacts(Agent *a, Agent *b, RuntimeParams *rp, WorldParams *wp) {
	CGFloat dx = b->x - a->x;
	CGFloat dy = b->y - a->y;
	CGFloat d2 = fmax(1e-4, dx * dx + dy * dy);
	CGFloat d = sqrt(d2);
	CGFloat viewRange = wp->worldSize / wp->mesh;
	if (d >= viewRange) { return; }
	CGFloat dd = ((d < viewRange * 0.8)? 1.0 : (1 - d / viewRange) / 0.2) / d / d2;
	CGFloat ax = dx * dd * AVOIDANCE;
	CGFloat ay = dy * dd * AVOIDANCE;
	a->fx -= ax;
	a->fy -= ay;
	b->fx += ax;
	b->fy += ay;
	attracted(a, b, rp, wp, d);
	attracted(b, a, rp, wp, d);
}
static void starts_warping(Agent *a, WarpType mode, CGPoint newPt, Document *doc) {
	[doc addNewWarp:[WarpInfo.alloc initWithAgent:a goal:newPt mode:mode]];
}
static void died(Agent *a, WarpType mode, WorldParams *p, Document *doc) {
	a->newHealth = Died;
	starts_warping(a, mode, (CGPoint){
		(random() * .248 / 0x7fffffff + 1.001) * p->worldSize,
		(random() * .468 / 0x7fffffff + .001) * p->worldSize}, doc);
}
static void cummulate_histgrm(NSMutableArray<MyCounter *> *h, CGFloat d) {
  NSInteger ds = floor(d);
  if (h.count <= d) {
    NSInteger n = ds - h.count;
    for (NSInteger i = 0; i <= n; i ++) [h addObject:MyCounter.new];
  }
  [h[ds] inc];
}
static BOOL patient_step(Agent *a, WorldParams *p, BOOL inQuarantine, Document *doc) {
  if (a->daysToDie == BIG_NUM) { // in the recovery phase
	if (a->daysInfected >= a->daysToRecover) {
		if (a->health == Symptomatic) cummulate_histgrm(doc.RecovPHist, a->daysDiseased);
		a->newHealth = Recovered;
		a->daysInfected = 0;
	}
  } else if (a->daysInfected > a->daysToRecover) { // starts recovery
	a->daysToRecover *= 1. + 10. / a->daysToDie;
	a->daysToDie = BIG_NUM;
  } else if (a->daysInfected >= a->daysToDie) {
	cummulate_histgrm(doc.DeathPHist, a->daysDiseased);
	died(a, inQuarantine? WarpToCemeteryH : WarpToCemeteryF, p, doc);
	return YES;
  } else if (a->health == Asymptomatic && a->daysInfected >= a->daysToOnset) {
	a->newHealth = Symptomatic;
	cummulate_histgrm(doc.IncubPHist, a->daysInfected);
  }
  return NO;
}
static CGFloat wall(CGFloat d) {
	if (d < .02) d = .02;
	return AVOIDANCE / d / d;
}
void step_agent(Agent *a, RuntimeParams *rp, WorldParams *wp, Document *doc) {
	switch (a->health) {
		case Symptomatic: a->daysInfected += 1. / wp->stepsPerDay;
		a->daysDiseased += 1. / wp->stepsPerDay;
		if (patient_step(a, wp, NO, doc)) return;
		else if (a->daysDiseased >= rp->tstDelay && was_hit(wp, rp->tstSbjSym / 100.))
			[doc testInfectionOfAgent:a reason:TestAsSymptom];
		break;
		case Asymptomatic: a->daysInfected += 1. / wp->stepsPerDay;
		if (patient_step(a, wp, NO, doc)) return;
		break;
		case Recovered: a->daysInfected += 1. / wp->stepsPerDay;
		if (a->daysInfected > a->imExpr) {
			a->newHealth = Susceptible;
			a->daysInfected = a->daysDiseased = 0;
			reset_days(a, rp);
		} break;
		default: break;
	}
	if (a->health != Symptomatic && was_hit(wp, rp->tstSbjAsy / 100.))
		[doc testInfectionOfAgent:a reason:TestAsSuspected];
	NSInteger orgIdx = index_in_pop(a, wp);
	if (a->health != Symptomatic && was_hit(wp, rp->mobFr / 1000.)) {
		CGFloat dst = my_random(&rp->mobDist) * wp->worldSize / 100.;
		CGFloat th = random() * M_PI * 2. / 0x7fffffff;
		CGPoint newPt = {a->x + cos(th) * dst, a->y + sin(th) * dst};
		if (newPt.x < 3.) newPt.x = 3. - newPt.x;
		else if (newPt.x > wp->worldSize - 3.) newPt.x = (wp->worldSize - 3.) * 2. - newPt.x;
		if (newPt.y < 3.) newPt.y = 3. - newPt.y;
		else if (newPt.y > wp->worldSize - 3.) newPt.y = (wp->worldSize - 3.) * 2. - newPt.y;
		starts_warping(a, WarpInside, newPt, doc);
		return;
	} else {
		if (a->distancing) {
			CGFloat dst = 1.0 + rp->dstST / 5.0;
			a->fx *= dst;
			a->fy *= dst;
		}
		a->fx += wall(a->x) - wall(wp->worldSize - a->x);
		a->fy += wall(a->y) - wall(wp->worldSize - a->y);
		CGFloat speed = ((a->health == Symptomatic)? .01 : .05) / wp->stepsPerDay;
		if (a->best != NULL && !a->distancing) {
			CGFloat dx = a->best->x - a->x;
			CGFloat dy = a->best->y - a->y;
			CGFloat d = fmax(.01, hypot(dx, dy)) * 20.;
			a->fx += dx / d;
			a->fy += dy / d;
		}
		CGFloat frac = pow(0.96, 1.0 / wp->stepsPerDay);
		a->vx = a->vx * frac + a->fx / wp->stepsPerDay;
		a->vy = a->vy * frac + a->fy / wp->stepsPerDay;
		CGFloat v = hypot(a->vx, a->vy);
		CGFloat maxV = 20.0;
		if (v > maxV) { 
			a->vx *= maxV / v; 
			a->vy *= maxV / v;
		}
		a->x += a->vx * speed;
		a->y += a->vy * speed;
		if (a->x < AGENT_RADIUS) a->x = AGENT_RADIUS * 2 - a->x;
		else if (a->x > wp->worldSize - AGENT_RADIUS)
			a->x = (wp->worldSize - AGENT_RADIUS) * 2 - a->x;
		if (a->y < AGENT_RADIUS) a->y = AGENT_RADIUS * 2 - a->y;
		else if (a->y > wp->worldSize - AGENT_RADIUS)
			a->y = (wp->worldSize - AGENT_RADIUS) * 2 - a->y;
	}
	NSInteger newIdx = index_in_pop(a, wp);
	if (newIdx != orgIdx) {
		remove_from_list(a, doc.Pop + orgIdx);
		add_to_list(a, doc.Pop + newIdx);
	}
}
void step_agent_in_quarantine(Agent *a, WorldParams *p, Document *doc) {
	switch (a->health) {
		case Symptomatic: a->daysDiseased += 1. / p->stepsPerDay;
		case Asymptomatic: a->daysInfected += 1. / p->stepsPerDay;
		break;
		default: starts_warping(a, WarpBack, a->orgPt, doc);
		return;
	}
	if (!patient_step(a, p, YES, doc) && a->health == Recovered)
		starts_warping(a, WarpBack, a->orgPt, doc);
}
BOOL warp_step(Agent *a, WorldParams *wp, Document *doc, WarpType mode, CGPoint goal) {
	CGPoint dp = {goal.x - a->x, goal.y - a->y};
	CGFloat d = hypot(dp.y, dp.x), v = wp->worldSize / 5. / wp->stepsPerDay;
	if (d < v) {
		a->x = goal.x; a->y = goal.y;
		a->isWarping = NO;
		switch (mode) {
			case WarpInside: case WarpBack: add_agent(a, wp, doc.Pop); break;
			case WarpToHospital:
				add_to_list(a, doc.QListP); a->gotAtHospital = YES; break;
			case WarpToCemeteryF: case WarpToCemeteryH: add_to_list(a, doc.CListP);
		}
		return YES;
	} else {
		CGFloat th = atan2(dp.y, dp.x);
		a->x += v * cos(th);
		a->y += v * sin(th);
		return NO;
	}
}
void warp_show(Agent *a, WarpType mode, CGPoint goal,
	NSRect dirtyRect, NSArray<NSBezierPath *> *paths) {
	CGPoint dp = {goal.x - a->x, goal.y - a->y};
	CGFloat d = fmin(hypot(dp.x, dp.y), 30.), th = atan2(dp.y, dp.x);
	CGFloat wx = .25 * cos(th + M_PI/2), wy = .25 * sin(th + M_PI/2);
	NSPoint vertex[3] = {
		{a->x + d * cos(th), a->y + d * sin(th)},
		{a->x + wx, a->y + wy},
		{a->x - wx, a->y - wy}
	};
	NSRect bounds = {vertex[0], vertex[0].x, vertex[0].y};
	for (NSInteger i = 1; i < 3; i ++) {
		if (bounds.origin.x > vertex[i].x) bounds.origin.x = vertex[i].x;
		else if (bounds.size.width < vertex[i].x) bounds.size.width = vertex[i].x;
		if (bounds.origin.y > vertex[i].y) bounds.origin.y = vertex[i].y;
		else if (bounds.size.height < vertex[i].y) bounds.size.height = vertex[i].y;
	}
	bounds.size.width -= bounds.origin.x;
	bounds.size.height -= bounds.origin.y;
	if (NSIntersectsRect(bounds, dirtyRect)) {
		NSBezierPath *path = paths[a->health];
		[path moveToPoint:vertex[0]];
		[path lineToPoint:vertex[1]];
		[path lineToPoint:vertex[2]];
		[path closePath];
	}
}
void show_agent(Agent *a, AgentDrawType type,
	NSRect dirtyRect, NSArray<NSBezierPath *> *paths) {
	NSBezierPath *path = paths[a->health];
	CGFloat r = (type == AgntDrwCircle)? AGENT_RADIUS : AGENT_SIZE;
	NSRect aBounds = {a->x - r, a->y - r, r * 2, r * 2};
	if (NSIntersectsRect(aBounds, dirtyRect)) switch (type) {
		case AgntDrwCircle:
		[path appendBezierPathWithOvalInRect:aBounds]; break;
		case AgntDrwOctagon:
		case AgntDrwSquire:
		[path appendBezierPathWithRect:aBounds]; break;
		case AgntDrwPoint: break;
	}
}
