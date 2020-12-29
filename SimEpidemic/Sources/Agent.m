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
static CGFloat random_guassian(void) {
	static CGFloat z = 0.;
	static BOOL secondTime = NO;
	if (secondTime) { secondTime = NO; return z; }
	else {
		secondTime = YES;
		CGFloat r = sqrt(-2. * log(random() / (CGFloat)0x7fffffff)),
			th = random() / (CGFloat)0x7fffffff * M_PI * 2.;
		z = r * cos(th);
		return r * sin(th);
	}
}
#define EXP_BASE .02
static CGFloat random_exp(void) {
	return (pow(EXP_BASE, random() / (CGFloat)0x7fffffff) - EXP_BASE) / (1. - EXP_BASE);
}
static CGFloat random_mk(CGFloat mode, CGFloat kurt) {
	CGFloat x =
		(mode <= 0.)? random_exp() * 2. - 1. :
		(mode >= 1.)? 1. - random_exp() * 2. :
		random_guassian() / 3.;
	if (x < -2.) x = -1.;
	else if (x < -1.) x = -2. - x;
	else if (x > 2.) x = 1.;
	else if (x > 1.) x = 2. - x;
	if (kurt != 0.) {
		CGFloat b = pow(2., -kurt);
		x = (x < 0.)? pow(x + 1., b) - 1. : 1. - pow(1. - x, b);
	}
	x = (x + 1.) / 2.;
	CGFloat a = mode / (1. - mode);
	return a * x / ((a - 1.) * x + 1.);
}
CGFloat my_random(DistInfo *p) {
	return (p->max == p->min)? p->min :
		random_mk((p->mode - p->min) / (p->max - p->min), 0.) * (p->max - p->min) + p->min;
}
struct ActivenessEffect { CGFloat x, mX; };
static CGFloat random_with_corr(DistInfo *p, struct ActivenessEffect a, CGFloat c) {
	if (c == 0.) return my_random(p);
	CGFloat m = (p->mode - p->min) / (p->max - p->min), mY = (c < 0.)? 1. - m : m;
	CGFloat y = mY * (1. - a.mX) * a.x / (a.mX * (1. - mY) - (a.mX - mY) * a.x);
	y = (random_mk(y * .1 + mY * .9, 0.) - y) * (1. - fabs(c));
	if (c < 0.) y = 1. - y;
	return y * (p->max - p->min) + p->min;
}
BOOL was_hit(WorldParams *wp, CGFloat prob) {
	return (random() > pow(1. - prob, 1. / wp->stepsPerDay) * 0x7fffffff);
}
BOOL is_infected(Agent *a) {
	return a->health == Asymptomatic || a->health == Symptomatic;
}
static void reset_days(Agent *a, RuntimeParams *p) {
	struct ActivenessEffect ae = {a->activeness, p->actMode/100.};
	a->daysToRecover = random_with_corr(&p->recov, ae, p->recovAct/100.);
	a->daysToOnset = random_with_corr(&p->incub, ae, p->incubAct/100.);
	a->daysToDie = random_with_corr(&p->fatal, ae, p->fatalAct/100.) + a->daysToOnset;
	a->imExpr = random_with_corr(&p->immun, ae, p->immuneAct/100.);
}
#define ALT_RATE .1
static void alter_days(Agent *a, RuntimeParams *p) {
	Agent tmpA;
	reset_days(&tmpA, p);
	a->daysToRecover += (tmpA.daysToRecover - a->daysToRecover) * ALT_RATE;
	a->daysToOnset += (tmpA.daysToOnset - a->daysToOnset) * ALT_RATE;
	a->daysToDie += (tmpA.daysToDie - a->daysToDie) * ALT_RATE;
	a->imExpr += (tmpA.imExpr - a->imExpr) * ALT_RATE;
}
void reset_agent(Agent *a, RuntimeParams *rp, WorldParams *wp) {
	memset(a, 0, sizeof(Agent));
	a->app = random() / (CGFloat)0x7fffffff;
	a->prf = random() / (CGFloat)0x7fffffff;
	a->x = random() / (CGFloat)0x7fffffff * (wp->worldSize - 6.) + 3.;
	a->y = random() / (CGFloat)0x7fffffff * (wp->worldSize - 6.) + 3.;
	CGFloat th = random() / (CGFloat)0x7fffffff * M_PI * 2.;
	a->vx = cos(th);
	a->vy = sin(th);
	a->health = Susceptible;
	a->nInfects = -1;
	a->isOutOfField = YES;
	reset_days(a, rp);
	a->lastTested = -999999;
	a->activeness = random_mk(rp->actMode / 100., rp->actKurt / 100.);
	a->gathering = NULL;
}
void reset_for_step(Agent *a) {
	a->fx = a->fy = 0.;
	a->best = NULL;
	a->bestDist = a->gatDist = BIG_NUM;
	a->newHealth = a->health;
	a->newNInfects = 0;
}
static NSInteger index_in_pop(Agent *a, WorldParams *p) {
	NSInteger iy = floor(a->y * p->mesh / p->worldSize);
	NSInteger ix = floor(a->x * p->mesh / p->worldSize);
	if (iy < 0) iy = 0; else if (iy >= p->mesh) iy = p->mesh - 1;
	if (ix < 0) ix = 0; else if (ix >= p->mesh) ix = p->mesh - 1;
	return iy * p->mesh + ix;
}
void add_to_list(Agent *a, Agent **list) {
#ifdef DEBUG
for (Agent *b = *list; b != NULL; b = b->next) if (a == b) {
	printf("agent %ld is already in the list.\n", a->ID);
	my_exit();
}
#endif
	a->prev = NULL;
	if ((a->next = *list) != NULL) a->next->prev = a;
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
}
static void infects(Agent *a, Agent *b, RuntimeParams *rp, WorldParams *wp, CGFloat d) {
	// b infects a
	CGFloat timeFactor = fmin(1., (b->daysInfected - rp->contagDelay) /
		(b->daysInfected - fmin(rp->contagPeak, b->daysToOnset)));
	CGFloat distanceFactor = fmin(1., pow((rp->infecDst - d) / 2., 2.));
	if (was_hit(wp, rp->infec / 100. * timeFactor * distanceFactor)) {
		a->newHealth = Asymptomatic;
		if (a->nInfects < 0) a->newNInfects = 1;
		b->newNInfects ++;
	}
}
static void check_infection(Agent *a, Agent *b,
	RuntimeParams *rp, WorldParams *wp, CGFloat d) {
	if (d >= rp->infecDst) return;
	if (was_hit(wp, rp->cntctTrc / 100.)) add_new_cinfo(a, b, rp->step);
	if (was_hit(wp, rp->cntctTrc / 100.)) add_new_cinfo(b, a, rp->step);
	if (a->health == Susceptible) {
		if (is_infected(b) && b->daysInfected > rp->contagDelay)
			infects(a, b, rp, wp, d);
	} else if (b->health == Susceptible &&
		is_infected(a) && a->daysInfected > rp->contagDelay)
		infects(b, a, rp, wp, d);
}
void interacts(Agent *a, Agent **b, NSInteger n, RuntimeParams *rp, WorldParams *wp) {
	CGFloat dx[n], dy[n], d2[n], d[n];
	Agent *bb[n];
	for (NSInteger i = 0; i < n; i ++) {
		dx[i] = b[i]->x - a->x; dy[i] = b[i]->y - a->y;
		d[i] = sqrt((d2[i] = fmax(1e-4, dx[i] * dx[i] + dy[i] * dy[i])));
	}
	CGFloat viewRange = wp->worldSize / wp->mesh;
	NSInteger j = 0;
	for (NSInteger i = 0; i < n; i ++) if (d[i] < viewRange) {
		if (i > j) { dx[j] = dx[i]; dy[j] = dy[i]; d2[j] = d2[i]; d[j] = d[i]; }
		bb[j] = b[i];
		j ++;
	}
	if (j <= 0) return;
	CGFloat dd[j], ax[j], ay[j];
	for (NSInteger i = 0; i < j; i ++) dd[i] = ((d[i] < viewRange * 0.8)? 1.0 :
		(1 - d[i] / viewRange) / 0.2) / d[i] / d2[i] * AVOIDANCE * rp->avoidance / 50.;
	for (NSInteger i = 0; i < j; i ++)
		{ ax[i] = dx[i] * dd[i]; ay[i] = dy[i] * dd[i]; }
	for (NSInteger i = 0; i < j; i ++) {
		a->fx -= ax[i]; a->fy -= ay[i];
		bb[i]->fx += ax[i]; bb[i]->fy += ay[i];
		attracted(a, bb[i], rp, wp, d[i]);
		attracted(bb[i], a, rp, wp, d[i]);
		check_infection(a, bb[i], rp, wp, d[i]);
	}
}
#define SET_HIST(t,d) { info->histType = t; info->histDays = a->d; }
static BOOL patient_step(Agent *a, WorldParams *p, BOOL inQuarantine, StepInfo *info) {
	if (a->daysToDie == BIG_NUM) { // in the recovery phase
		if (a->daysInfected >= a->daysToRecover) {
			if (a->health == Symptomatic) SET_HIST(HistRecov, daysDiseased)
			a->newHealth = Recovered;
			a->daysInfected = 0;
		}
	} else if (a->daysInfected > a->daysToRecover) { // starts recovery
		a->daysToRecover *= 1. + 10. / a->daysToDie;
		a->daysToDie = BIG_NUM;
	} else if (a->daysInfected >= a->daysToDie) {
		SET_HIST(HistDeath, daysDiseased);
		a->newHealth = Died;
		info->warpType = inQuarantine? WarpToCemeteryH : WarpToCemeteryF;
		info->warpTo = (CGPoint){
			(random() * .248 / 0x7fffffff + 1.001) * p->worldSize,
			(random() * .468 / 0x7fffffff + .001) * p->worldSize};
		return YES;
	} else if (a->health == Asymptomatic && a->daysInfected >= a->daysToOnset) {
		a->newHealth = Symptomatic;
		SET_HIST(HistIncub, daysInfected);
	}
	return NO;
}
static CGFloat wall(CGFloat d) {
	if (d < .02) d = .02;
	return AVOIDANCE * 20. / d / d;
}
static inline CGFloat mov_act(Agent *a, RuntimeParams *rp) {
	return pow(pow(10., rp->mobAct / 100.), (a->activeness - .5) / .5);
}
static inline CGFloat mass_bias(Agent *a) { return pow(4., (a->activeness - .5) / .5); }
void step_agent(Agent *a, RuntimeParams *rp, WorldParams *wp, StepInfo *info) {
	switch (a->health) {
		case Symptomatic: a->daysInfected += 1. / wp->stepsPerDay;
		a->daysDiseased += 1. / wp->stepsPerDay;
		if (patient_step(a, wp, NO, info)) return;
		else if (a->daysDiseased >= rp->tstDelay && was_hit(wp, rp->tstSbjSym / 100.))
			info->testType = TestAsSymptom;
		break;
		case Asymptomatic: a->daysInfected += 1. / wp->stepsPerDay;
		if (patient_step(a, wp, NO, info)) return;
		break;
		case Recovered: a->daysInfected += 1. / wp->stepsPerDay;
		if (a->daysInfected > a->imExpr) {
			a->newHealth = Susceptible;
			a->daysInfected = a->daysDiseased = 0;
			alter_days(a, rp);
		} break;
		default: break;
	}
	if (a->health != Symptomatic && was_hit(wp, rp->tstSbjAsy / 100.))
		info->testType = TestAsSuspected;
	NSInteger orgIdx = index_in_pop(a, wp);
	if (a->health != Symptomatic && was_hit(wp, rp->mobFr / 1000. * mov_act(a, rp))) {
		CGFloat dst = my_random(&rp->mobDist) * wp->worldSize / 100.;
		CGFloat th = random() * M_PI * 2. / 0x7fffffff;
		CGPoint newPt = {a->x + cos(th) * dst, a->y + sin(th) * dst};
		if (newPt.x < 3.) newPt.x = 3. - newPt.x;
		else if (newPt.x > wp->worldSize - 3.) newPt.x = (wp->worldSize - 3.) * 2. - newPt.x;
		if (newPt.y < 3.) newPt.y = 3. - newPt.y;
		else if (newPt.y > wp->worldSize - 3.) newPt.y = (wp->worldSize - 3.) * 2. - newPt.y;
		info->warpType = WarpInside;
		info->warpTo = newPt;
		return;
	} else {
		if (a->distancing) {
			CGFloat dst = 1.0 + rp->dstST / 5.0;
			a->fx *= dst;
			a->fy *= dst;
		}
		a->fx += wall(a->x) - wall(wp->worldSize - a->x);
		a->fy += wall(a->y) - wall(wp->worldSize - a->y);
#ifdef VER_1_8
		CGFloat mass = rp->mass / 100. * mass_bias(a);
#else
		CGFloat mass = rp->mass / 10.;
#endif
		if (a->health == Symptomatic) mass *= 20.; 
		if (a->best != NULL && !a->distancing) {
			CGFloat dx = a->best->x - a->x;
			CGFloat dy = a->best->y - a->y;
			CGFloat d = fmax(.01, hypot(dx, dy)) * 20.;
			a->fx += dx / d;
			a->fy += dy / d;
		}
#ifdef VER_1_8
		CGFloat fric = pow(.99 * (1. - rp->friction / 100.), 1. / wp->stepsPerDay);
#else
		CGFloat fric = pow(1. - rp->friction / 100., 1. / wp->stepsPerDay);
#endif
		if (a->gatDist < 1.) fric *= a->gatDist * .5 + .5;
		a->vx = a->vx * fric + a->fx / mass / wp->stepsPerDay;
		a->vy = a->vy * fric + a->fy / mass / wp->stepsPerDay;
		CGFloat v = hypot(a->vx, a->vy);
		CGFloat maxV = rp->maxSpeed * 20. / wp->stepsPerDay;
		if (v > maxV) { 
			a->vx *= maxV / v; 
			a->vy *= maxV / v;
		}
		a->x += a->vx / wp->stepsPerDay;
		a->y += a->vy / wp->stepsPerDay;
		if (a->x < AGENT_RADIUS)
			{ a->x = AGENT_RADIUS * 2 - a->x; a->vx = - a->vx; }
		else if (a->x > wp->worldSize - AGENT_RADIUS)
			{ a->x = (wp->worldSize - AGENT_RADIUS) * 2 - a->x; a->vx = - a->vx; }
		if (a->y < AGENT_RADIUS)
			{ a->y = AGENT_RADIUS * 2 - a->y; a->vy = - a->vy; }
		else if (a->y > wp->worldSize - AGENT_RADIUS)
			{ a->y = (wp->worldSize - AGENT_RADIUS) * 2 - a->y; a->vy = - a->vy; }
	}
	NSInteger newIdx = index_in_pop(a, wp);
	if (newIdx != orgIdx) { info->moveFrom = orgIdx; info->moveTo = newIdx; }
}
void step_agent_in_quarantine(Agent *a, WorldParams *p, StepInfo *info) {
	switch (a->health) {
		case Symptomatic: a->daysDiseased += 1. / p->stepsPerDay;
		case Asymptomatic: a->daysInfected += 1. / p->stepsPerDay;
		break;
		default: info->warpType = WarpBack; info->warpTo = a->orgPt;
		return;
	}
	if (!patient_step(a, p, YES, info) && a->newHealth == Recovered)
		{ info->warpType = WarpBack; info->warpTo = a->orgPt; }
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
			default: break;
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
