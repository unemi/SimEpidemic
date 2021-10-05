//
//  Agent.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "Agent.h"
#import "StatPanel.h"
#define AVOIDANCE .2

CGFloat d_random(void) {
	return random() / (CGFloat)0x7fffffff;
}
// Random number of psuedo Gaussian distribution by Box-Müller method
static CGFloat random_guassian(void) {
	static CGFloat z = 0.;
	static BOOL secondTime = NO;
	if (secondTime) { secondTime = NO; return z; }
	else {
		secondTime = YES;
		CGFloat r = sqrt(-2. * log(d_random())), th = d_random() * M_PI * 2.;
		z = r * cos(th);
		return r * sin(th);
	}
}
#define EXP_BASE .02
static CGFloat random_exp(void) {
	return (pow(EXP_BASE, d_random()) - EXP_BASE) / (1. - EXP_BASE);
}
static CGFloat revise_prob(CGFloat x, CGFloat mode) {
// x is a sample from distribution [0,1] mode = 0.5;
	CGFloat a = mode / (1. - mode);
	return a * x / ((a - 1.) * x + 1.);
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
	return revise_prob((x + 1.) / 2., mode);
}
CGFloat modified_prob(CGFloat x, DistInfo *p) {
	CGFloat span = p->max - p->min;
	return revise_prob(x, (p->mode - p->min) / span) * span + p->min;
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
	y += (random_mk(y * .1 + mY * .9, 0.) - y) * (1. - fabs(c));
	if (c < 0.) y = 1. - y;
	return y * (p->max - p->min) + p->min;
}
BOOL was_hit(NSInteger stepsPerDay, CGFloat prob) {
	return (d_random() > pow(1. - prob, 1. / stepsPerDay));
}
BOOL is_infected(Agent *a) {
	return a->health == Asymptomatic || a->health == Symptomatic;
}
static CGFloat random_coord(WorldParams *wp) {
	return d_random() * (wp->worldSize - 6.) + 3.;
}
#define CENTERED_BIAS .25
CGFloat centered_bias(CGPoint p) {	// p.x and p.y are in [-1,1]
//	if p = (0, 0) then return a. if p = (1, 1) then return 1.
	CGFloat a = CENTERED_BIAS / (1. - CENTERED_BIAS);
	return a / (1. - (1. - a) * fmax(fabs(p.x), fabs(p.y)));
}
static CGPoint centered_point(WorldParams *wp) {
	CGPoint p = {d_random() * 2. - 1., d_random() * 2. - 1.};
	CGFloat v = centered_bias(p);
	p.x = (p.x * v + 1.) * .5 * (wp->worldSize - 6.) + 3.;
	p.y = (p.y * v + 1.) * .5 * (wp->worldSize - 6.) + 3.;
	return p;
}
static void setup_acquired_immunity(Agent *a, RuntimeParams *p) {
	CGFloat maxSeverity = a->daysToRecover * (1. - p->therapyEffc / 100.) / a->daysToDie;
	a->imExpr = fmin(1., maxSeverity / (p->imnMaxDurSv / 100.)) * p->imnMaxDur;
	a->agentImmunity = fmin(1., maxSeverity / (p->imnMaxEffcSv / 100.)) * p->imnMaxEffc / 100.;
}
static void reset_days(Agent *a, RuntimeParams *rp, WorldParams *wp) {
	struct ActivenessEffect ae = {a->activeness, rp->actMode/100.};
	a->daysToOnset = random_with_corr(&rp->incub, ae, rp->incubAct/100.);
	a->daysToDie = random_with_corr(&rp->fatal, ae, rp->fatalAct/100.) + a->daysToOnset;
	CGFloat mode = wp->rcvBias / 100. * exp((a->age - 105.) / wp->rcvTemp);
	CGFloat low = wp->rcvLower / 100. * mode, span = wp->rcvUpper / 100. * mode - low;
	a->daysToRecover = ((span == 0.)? mode : random_mk((mode - low) / span, 0.) * span + low)
		* (rp->incub.mode + rp->fatal.mode);
//if (a->ID < 50) printf("%.2f -> %.2f %.2f %.2f %c\n",
//	a->age, a->daysToOnset, a->daysToDie, a->daysToRecover,
//	(a->daysToRecover > a->daysToDie)? '*' : (a->daysToRecover > a->daysToOnset)? '+' : ' ');
}
#define ALT_RATE .1
static void alter_days(Agent *a, RuntimeParams *rp, WorldParams *wp) {
	Agent tmpA;
	reset_days(&tmpA, rp, wp);
	a->daysToRecover += (tmpA.daysToRecover - a->daysToRecover) * ALT_RATE;
	a->daysToOnset += (tmpA.daysToOnset - a->daysToOnset) * ALT_RATE;
	a->daysToDie += (tmpA.daysToDie - a->daysToDie) * ALT_RATE;
	a->imExpr += (tmpA.imExpr - a->imExpr) * ALT_RATE;
}
void reset_agent(Agent *a, CGFloat age, RuntimeParams *rp, WorldParams *wp) {
	memset(a, 0, sizeof(Agent));
	a->app = d_random();
	a->prf = d_random();
	switch (wp->wrkPlcMode) {
		case WrkPlcNone:
		a->x = random_coord(wp);
		a->y = random_coord(wp);
		break;
		case WrkPlcUniform:
		a->orgPt = (CGPoint){(a->x = random_coord(wp)), (a->y = random_coord(wp))};
		break;
		case WrkPlcCentered:
		a->orgPt = centered_point(wp);
		a->x = a->orgPt.x; a->y = a->orgPt.y;
		break;
		case WrkPlcPopDistImg: break;
	}
	CGFloat th = d_random() * M_PI * 2.;
	a->vx = cos(th);
	a->vy = sin(th);
	a->health = Susceptible;
	a->nInfects = a->virusVariant = a->vaccineType = -1;
	a->agentImmunity = 0.;
	a->isOutOfField = YES;
	a->lastTested = -999999;
	a->age = age;
	reset_days(a, rp, wp);
	a->daysToCompleteRecov = 0.;
	a->activeness = random_mk(rp->actMode / 100., rp->actKurt / 100.);
	a->gathering = NULL;
	a->mass = rp->mass * pow(rp->massAct, (.5 - a->activeness) / .5);
	struct ActivenessEffect ae = {a->activeness, rp->actMode/100.};
	DistInfo dInfo = {0., 1., .5};
	a->mobFreq = random_with_corr(&dInfo, ae, rp->mobAct/100.);
	a->gatFreq = random_with_corr(&dInfo, ae, rp->gatAct/100.);
}
static float pop_dist_sum(NSInteger x, NSInteger y, NSInteger w, float *pd) {
	float s = 0;
	for (int i = 0; i < w; i ++) for (int j = 0; j < w; j ++)
		s += pd[(y + i) * PopDistMapRes + x + j];
	return s;
}
static void pop_dist_alloc(NSInteger x, NSInteger y, NSInteger w,
	NSPoint *pts, NSInteger n, float *pd) {
	if (n <= 1) {
		pts[0] = (NSPoint){x + d_random() * w, y + d_random() * w};
	} else if (w <= 4) {
		for (NSInteger i = 0; i < n; i ++)
			pts[i] = (NSPoint){x + d_random() * w, y + d_random() * w};
	} else {
		NSInteger v = w / 2, m = 0;
		NSInteger xx[] = {x, x, x + v, x + v}, yy[] = {y, y + v, y, y + v}, nn[4];
		struct AAndIdx { float a; NSInteger idx; } aa[4];
		float s = 0.;
		for (NSInteger i = 0; i < 4; i ++)
			s += aa[i].a = pop_dist_sum(xx[i], yy[i], v, pd);
		for (NSInteger i = 0; i < 4; i ++) {
			aa[i].a = n * aa[i].a / s;
			m += nn[i] = aa[i].a;
			aa[i].a -= nn[i];
			aa[i].idx = i;
		}
		qsort_b(aa, 4, sizeof(struct AAndIdx), ^int(const void *a, const void *b) {
			struct AAndIdx *c = (struct AAndIdx *)a, *d = (struct AAndIdx *)b;
			return (c->a > d->a)? -1 : (c->a < d->a)? 1 : 0;
		});
		for (NSInteger i = 0; m < n; m ++, i = (i + 1) % 4) nn[aa[i].idx] ++;
		NSPoint *pt = pts;
		for (NSInteger i = 0; i < 4; i ++) if (nn[i] > 0) {
			pop_dist_alloc(xx[i], yy[i], v, pt, nn[i], pd);
			pt += nn[i];
		}
	}
}
NSBitmapImageRep *make_pop_dist_bm(void) {
	return [NSBitmapImageRep.alloc initWithBitmapDataPlanes:NULL
		pixelsWide:PopDistMapRes pixelsHigh:PopDistMapRes bitsPerSample:sizeof(float)*8
		samplesPerPixel:1 hasAlpha:NO isPlanar:NO colorSpaceName:NSCalibratedWhiteColorSpace
		bitmapFormat:NSBitmapFormatFloatingPointSamples
		bytesPerRow:sizeof(float) * PopDistMapRes bitsPerPixel:sizeof(float)*8];
}
NSBitmapImageRep *make_bm_with_image(NSImage *image) {
	NSBitmapImageRep *imgRep = make_pop_dist_bm();
	NSGraphicsContext *orgCtx = NSGraphicsContext.currentContext;
	NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:imgRep];
	NSRect rct = {NSZeroPoint, imgRep.size};
	if (image != nil) [image drawInRect:rct];
	else { [NSColor.grayColor setFill]; [NSBezierPath fillRect:rct]; }
	NSGraphicsContext.currentContext = orgCtx;
	return imgRep;
}
void setup_home_with_map(Agent *agents, WorldParams *wp, NSImage *image) {
	NSBitmapImageRep *imgRep = make_bm_with_image(image);
	float *pd = (float *)imgRep.bitmapData;
	NSPoint *pts = malloc(sizeof(NSPoint) * wp->initPop);
	pop_dist_alloc(0, 0, PopDistMapRes, pts, wp->initPop, pd);
	for (NSInteger i = 0; i < wp->initPop - 1; i ++) {
		NSInteger j = random() % (wp->initPop - i) + i;
		if (i != j) { NSPoint p = pts[i]; pts[i] = pts[j]; pts[j] = p; }
	}
	CGFloat a = (CGFloat)wp->worldSize / PopDistMapRes;
	for (NSInteger i = 0; i < wp->initPop; i ++) {
		NSPoint *pt = &agents[i].orgPt;
		agents[i].x = pt->x = pts[i].x * a;
		agents[i].y = pt->y = wp->worldSize - 1 - pts[i].y * a;
	}
	free(pts);
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
if (!a->isOutOfField) {
	printf("agent %ld is already in the field.\n", a->ID);
	my_exit();
}
#endif
	a->isOutOfField = NO;
	add_to_list(a, Pop + index_in_pop(a, wp));
}
void remove_agent(Agent *a, WorldParams *wp, Agent **Pop) {
#ifdef DEBUG
if (a->isOutOfField) {
	printf("agent %ld is already out of field.\n", a->ID);
	my_exit();
}
#endif
	a->isOutOfField = YES;
	remove_from_list(a, Pop + index_in_pop(a, wp));
}
@implementation World (AgentExtension)
static void attracted(Agent *a, Agent *b) {
	CGFloat x = fabs(b->app - a->prf);
	x = ((x < 0.5)? x : 1.0 - x) * 2.0;
	if (a->bestDist > x) {
		a->bestDist = x;
		a->best = b;
	}
}
static inline CGFloat exacerbation(CGFloat repro) { return pow(repro, 1./3.); }
- (void)checkInfectionA:(Agent *)a B:(Agent *)b dist:(CGFloat)d {
	if (d < runtimeParams.infecDst &&
		was_hit(worldParams.stepsPerDay, runtimeParams.cntctTrc / 100.))
		[self addNewCInfoA:a B:b tm:runtimeParams.step];
	if (a->newHealth != a->health || !is_infected(b)) return;
	CGFloat virusX = variantInfo[b->virusVariant].reproductivity,
		infecDMax = runtimeParams.infecDst * sqrt(virusX);
	if (d > infecDMax) return;
	CGFloat exacerbate = exacerbation(virusX),
		contagDelay = runtimeParams.contagDelay / exacerbate,
		contagPeak = runtimeParams.contagPeak / exacerbate;
	if (b->daysInfected <= contagDelay) return;
	CGFloat immuneFactor;
	switch (a->health) {
		case Susceptible: immuneFactor = 0.; break;
		case Recovered: immuneFactor = a->agentImmunity
			* variantInfo[a->virusVariant].efficacy[b->virusVariant]; break;
		case Vaccinated: immuneFactor = a->agentImmunity
			* vaccineInfo[a->vaccineType].efficacy[b->virusVariant]; break;
		default: return;
	}
	CGFloat timeFactor = (b->daysToCompleteRecov <= 0.)?
		fmin(1., (b->daysInfected - contagDelay) /
			(fmin(contagPeak, b->daysToOnset) - contagDelay)) :
		(b->daysToCompleteRecov - b->daysInfected) / (b->daysToCompleteRecov - b->daysToRecover);
	CGFloat distanceFactor = fmin(1., pow((infecDMax - d) / 2., 2.));
	CGFloat infecProb = (virusX < 1.)? runtimeParams.infec / 100. * virusX :
		1. - (1. - runtimeParams.infec / 100.) / virusX;
	if (was_hit(worldParams.stepsPerDay,
		infecProb * timeFactor * distanceFactor * (1. - immuneFactor))) {	// infected!
		a->newHealth = Asymptomatic;
		a->agentImmunity = immuneFactor;
		a->virusVariant = b->virusVariant;
		a->daysInfected = a->daysDiseased = 0;
		if (a->nInfects < 0) a->newNInfects = 1;
		b->newNInfects ++;
	}
}
- (void)interactsA:(Agent *)a Bs:(Agent **)b n:(NSInteger)n {
	CGFloat dx[n], dy[n], d2[n], d[n];
	Agent *bb[n];
	for (NSInteger i = 0; i < n; i ++) {
		dx[i] = b[i]->x - a->x; dy[i] = b[i]->y - a->y;
		d[i] = sqrt((d2[i] = fmax(1e-4, dx[i] * dx[i] + dy[i] * dy[i])));
	}
	CGFloat viewRange = worldParams.worldSize / worldParams.mesh;
	NSInteger j = 0;
	for (NSInteger i = 0; i < n; i ++) if (d[i] < viewRange) {
		if (i > j) { dx[j] = dx[i]; dy[j] = dy[i]; d2[j] = d2[i]; d[j] = d[i]; }
		bb[j] = b[i];
		j ++;
	}
	if (j <= 0) return;
	CGFloat dd[j], ax[j], ay[j];
	for (NSInteger i = 0; i < j; i ++) dd[i] = ((d[i] < viewRange * 0.8)? 1.0 :
		(1 - d[i] / viewRange) / 0.2) / d[i] / d2[i] * AVOIDANCE * runtimeParams.avoidance / 50.;
	for (NSInteger i = 0; i < j; i ++)
		{ ax[i] = dx[i] * dd[i]; ay[i] = dy[i] * dd[i]; }
	for (NSInteger i = 0; i < j; i ++) {
		a->fx -= ax[i]; a->fy -= ay[i];
		bb[i]->fx += ax[i]; bb[i]->fy += ay[i];
		attracted(a, bb[i]);
		attracted(bb[i], a);
		[self checkInfectionA:a B:bb[i] dist:d[i]];
		[self checkInfectionA:bb[i] B:a dist:d[i]];
	}
}
@end

#define SET_HIST(t,d) { info->histType = t; info->histDays = a->d; }
static BOOL patient_step(Agent *a, ParamsForStep prms, BOOL inQuarantine, StepInfo *info) {
	CGFloat exacerbate = exacerbation(prms.vrInfo[a->virusVariant].reproductivity);
	CGFloat daysToRecv = (1. - prms.rp->therapyEffc / 100.) * a->daysToRecover;
	if (a->daysToCompleteRecov > 0.) { // in the recovery phase
		if (a->daysInfected >= a->daysToCompleteRecov) {
			if (a->health == Symptomatic) SET_HIST(HistRecov, daysDiseased)
			a->newHealth = Recovered;
			a->daysInfected = a->daysToCompleteRecov = 0.;
			setup_acquired_immunity(a, prms.rp);
		}
	} else if (a->daysInfected > daysToRecv * (1. - a->agentImmunity)) { // starts recovery
		a->daysToCompleteRecov = daysToRecv * (1. - a->agentImmunity)
			* (1. + 10. / (a->daysToDie / exacerbate));
	} else if (a->daysInfected >= a->daysToDie / exacerbate) {
		SET_HIST(HistDeath, daysDiseased);
		a->newHealth = Died;
		info->warpType = inQuarantine? WarpToCemeteryH : WarpToCemeteryF;
		info->warpTo = (NSPoint){
			(d_random() * .248 + 1.001) * prms.wp->worldSize,
			(d_random() * .468 + 0.001) * prms.wp->worldSize};
		return YES;
	} else if (a->health == Asymptomatic && a->daysInfected >= a->daysToOnset / exacerbate) {
		a->newHealth = Symptomatic;
		SET_HIST(HistIncub, daysInfected);
	}
	return NO;
}
static CGFloat wall(CGFloat d) {
	if (d < .02) d = .02;
	return AVOIDANCE * 20. / d / d;
}
static void expire_immunity(Agent *a, RuntimeParams *rp, WorldParams *wp) {
	a->newHealth = Susceptible;
	a->daysInfected = a->daysDiseased = 0;
	alter_days(a, rp, wp);
}
static void go_warp(Agent *a, RuntimeParams *rp, WorldParams *wp, StepInfo *info) {
	CGFloat dst = my_random(&rp->mobDist) * wp->worldSize / 100.;
	CGFloat th = d_random() * M_PI * 2.;
	NSPoint newPt = {a->x + cos(th) * dst, a->y + sin(th) * dst};
	if (newPt.x < 3.) newPt.x = 3. - newPt.x;
	else if (newPt.x > wp->worldSize - 3.) newPt.x = (wp->worldSize - 3.) * 2. - newPt.x;
	if (newPt.y < 3.) newPt.y = 3. - newPt.y;
	else if (newPt.y > wp->worldSize - 3.) newPt.y = (wp->worldSize - 3.) * 2. - newPt.y;
	info->warpTo = newPt;
	info->warpType = WarpInside;
}
#define HOMING_FORCE .2
#define MAX_HOMING_FORCE 2.
#define MIN_AWAY_TO_HOME 50.
void going_back_home(Agent *a) {
	CGPoint f = {(a->orgPt.x - a->x) * HOMING_FORCE, (a->orgPt.y - a->y) * HOMING_FORCE};
	CGFloat fa = hypot(f.x, f.y);
	if (fa > MIN_AWAY_TO_HOME * HOMING_FORCE) return;
	if (fa > MAX_HOMING_FORCE) {
		f.x *= MAX_HOMING_FORCE / fa;
		f.y *= MAX_HOMING_FORCE / fa;
	}
	a->fx += f.x;
	a->fy += f.y;
}
static void vaccinate(Agent *a, ParamsForStep prms) {
	a->newHealth = Vaccinated;
	a->vaccineTicket = NO;
	CGFloat fdd = (CGFloat)prms.rp->step / prms.wp->stepsPerDay;
	if (a->firstDoseDate >= 0.) {
		a->firstDoseDate = fdd - prms.vxInfo[a->vaccineType].interval;
	} else {
		a->daysToRecover *= 1. - prms.wp->vcnEffcSymp / 100.;
		a->firstDoseDate = fdd;
	}
}
void step_agent(Agent *a, ParamsForStep prms, BOOL goHomeBack, StepInfo *info) {
	RuntimeParams *rp = prms.rp;
	WorldParams *wp = prms.wp;
	switch (a->health) {
		case Susceptible: if (a->vaccineTicket) vaccinate(a, prms); break;
		case Symptomatic: a->daysInfected += 1. / wp->stepsPerDay;
		a->daysDiseased += 1. / wp->stepsPerDay;
		if (patient_step(a, prms, NO, info)) return;
		else if (a->daysDiseased >= rp->tstDelay && was_hit(wp->stepsPerDay, rp->tstSbjSym / 100.))
			info->testType = TestAsSymptom;
		break;
		case Asymptomatic: if (a->vaccineTicket) vaccinate(a, prms);
		else {
			a->daysInfected += 1. / wp->stepsPerDay;
			if (patient_step(a, prms, NO, info)) return;
		} break;
		case Vaccinated: if (a->vaccineTicket) vaccinate(a, prms);
		else {
			CGFloat daysVaccinated = (CGFloat)rp->step / wp->stepsPerDay - a->firstDoseDate;
			NSInteger span = prms.vxInfo[a->vaccineType].interval;
			if (daysVaccinated < span)	// only the first dose
				a->agentImmunity = daysVaccinated * wp->vcn1stEffc / 100. / span;
			else if (daysVaccinated < wp->vcnEDelay + span)	// not fully vaccinated yet
				a->agentImmunity = ((daysVaccinated - span)
					* (wp->vcnMaxEffc - wp->vcn1stEffc) / wp->vcnEDelay + wp->vcn1stEffc) / 100.;
			else if (daysVaccinated < wp->vcnEDelay + span + wp->vcnEDecay) // full
				a->agentImmunity = wp->vcnMaxEffc / 100.;
			else if (daysVaccinated < wp->vcnEDelay + span + wp->vcnEPeriod) // Decay
				a->agentImmunity = (wp->vcnEDelay + span + wp->vcnEPeriod - daysVaccinated)
					/ (wp->vcnEPeriod - wp->vcnEDecay) * wp->vcnMaxEffc / 100.;
			else expire_immunity(a, rp, wp);
		} break;
		case Recovered: a->daysInfected += 1. / wp->stepsPerDay;
		if (a->daysInfected > a->imExpr) expire_immunity(a, rp, wp);
		break;
		default: break;
	}
	if (a->health != Symptomatic && was_hit(wp->stepsPerDay, rp->tstSbjAsy / 100.))
		info->testType = TestAsSuspected;
#define BACK_HOME_RATE_ON
#ifdef BACK_HOME_RATE_ON
	if (a->health != Symptomatic) {
		if (goHomeBack &&
			hypot(a->x - a->orgPt.x, a->y - a->orgPt.y) > fmax(rp->mobDist.min, MIN_AWAY_TO_HOME) &&
			was_hit(wp->stepsPerDay / 3, rp->backHmRt / 100.)) {
			info->warpTo = a->orgPt;
			info->warpType = WarpInside;
			return;
		}
		if (was_hit(wp->stepsPerDay, modified_prob(a->mobFreq, &rp->mobFreq) / 1000.)) {
			go_warp(a, rp, wp, info);
			return;
		}
	}
#else
	if (a->health != Symptomatic &&
		was_hit(wp->stepsPerDay, modified_prob(a->mobFreq, &rp->mobFreq) / 1000.)) {
		if (!goHomeBack) go_warp(a, rp, wp, info);
		else if (hypot(a->x - a->orgPt.x, a->y - a->orgPt.y)
			> fmax(rp->mobDist.min, MIN_AWAY_TO_HOME)) {
			info->warpTo = a->orgPt;
			info->warpType = WarpInside;
		} else go_warp(a, rp, wp, info);
		return;
	}
#endif
	NSInteger orgIdx = index_in_pop(a, wp);
	if (a->distancing) {
		CGFloat dst = 1.0 + rp->dstST / 5.0;
		a->fx *= dst;
		a->fy *= dst;
	}
	a->fx += wall(a->x) - wall(wp->worldSize - a->x);
	a->fy += wall(a->y) - wall(wp->worldSize - a->y);
	CGFloat mass = a->mass / 100.;
	if (a->health == Symptomatic) mass *= 20.; 
	if (a->best != NULL && !a->distancing) {
		CGFloat dx = a->best->x - a->x;
		CGFloat dy = a->best->y - a->y;
		CGFloat d = fmax(.01, hypot(dx, dy)) * 20.;
		a->fx += dx / d;
		a->fy += dy / d;
	}
	CGFloat fric = pow(.99 * (1. - rp->friction / 100.), 1. / wp->stepsPerDay);
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
	NSInteger newIdx = index_in_pop(a, wp);
	if (newIdx != orgIdx) { info->moveFrom = orgIdx; info->moveTo = newIdx; }
}
void step_agent_in_quarantine(Agent *a, ParamsForStep prms, StepInfo *info) {
	switch (a->health) {
		case Symptomatic: a->daysDiseased += 1. / prms.wp->stepsPerDay;
		case Asymptomatic: a->daysInfected += 1. / prms.wp->stepsPerDay;
		break;
		default: info->warpType = WarpBack; info->warpTo = a->orgPt;
		return;
	}
	if (!patient_step(a, prms, YES, info) && a->newHealth == Recovered)
		{ info->warpType = WarpBack; info->warpTo = a->orgPt; }
}
BOOL warp_step(Agent *a, WorldParams *wp, World *world, WarpType mode, NSPoint goal) {
	NSPoint dp = {goal.x - a->x, goal.y - a->y};
	CGFloat d = hypot(dp.y, dp.x), v = wp->worldSize / 5. / wp->stepsPerDay;
	if (d < v) {
		a->x = goal.x; a->y = goal.y;
		a->isWarping = NO;
		switch (mode) {
			case WarpInside: case WarpBack: add_agent(a, wp, world.Pop); break;
			case WarpToHospital:
				add_to_list(a, world.QListP); a->gotAtHospital = YES; break;
			case WarpToCemeteryF: case WarpToCemeteryH: add_to_list(a, world.CListP);
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
void warp_show(Agent *a, WarpType mode, NSPoint goal, NSRect dirtyRect, NSBezierPath *path) {
	NSPoint dp = {goal.x - a->x, goal.y - a->y};
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
		[path moveToPoint:vertex[0]];
		[path lineToPoint:vertex[1]];
		[path lineToPoint:vertex[2]];
		[path closePath];
	}
}
void show_agent(Agent *a, AgentDrawType type,
	NSRect dirtyRect, NSBezierPath *path) {
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
