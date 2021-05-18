//
//  World.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#define GCD_CONCURRENT_QUEUE

#import <sys/sysctl.h>
#import <sys/resource.h>
#import "World.h"
#import "Agent.h"
#import "Scenario.h"
#import "StatPanel.h"
#import "Parameters.h"
#import "Gatherings.h"
#ifdef NOGUI
#import "../../SimEpidemicSV/noGUI.h"
#import "../../SimEpidemicSV/PeriodicReporter.h"
#else
#import "Document.h"
#endif

#ifdef GCD_CONCURRENT_QUEUE
#else
NSInteger nQueues = 10;
#endif
//#define MEASURE_TIME
#ifdef MEASURE_TIME
#define N_MTIME 8
#endif

static CGFloat get_uptime(void) {
	struct timespec ts;
	clock_gettime(CLOCK_UPTIME_RAW, &ts);
	return ts.tv_sec + ts.tv_nsec * 1e-9;
}
void in_main_thread(dispatch_block_t block) {
	if ([NSThread isMainThread]) block();
	else dispatch_async(dispatch_get_main_queue(), block);
}
static BOOL is_daytime(WorldParams *wp, RuntimeParams *rp) {
	return (wp->stepsPerDay < 3)? (rp->step % 2) == 0 :
		(rp->step % wp->stepsPerDay) < wp->stepsPerDay * 2 / 3;
}
#ifdef DEBUG
void my_exit(void) {
#ifdef NOGUI
	in_main_thread(^{ terminateApp(-2); });
#else
	in_main_thread(^{ [NSApp terminate:nil]; });
#endif
}
#endif

@interface World () {
#ifdef MEASURE_TIME
	unsigned long mtime[N_MTIME];
	NSInteger mCount, mCount2;
#endif
	NSInteger nPop, nMesh, nVcnPop;
	Agent **pop;
	NSRange *pRange;
	CGFloat stepsPerSec;
	NSMutableDictionary<NSNumber *, NSValue *> *newWarpF;
	NSMutableDictionary<NSNumber *, NSNumber *> *testees;
	NSInteger *vcnInvList;	// map from agent ID to list position
	NSLock *newWarpLock, *testeesLock;
	NSLock *memPoolLock, *tmemLock, *cmemLock, *gmemLock;
	NSMutableArray<NSMutableData *> *memPool;
	TestEntry *freeTMem;
	ContactInfo *freeCMem;
	Gathering *freeGMem;
	dispatch_group_t dispatchGroup;
#ifdef GCD_CONCURRENT_QUEUE
	dispatch_queue_t dispatchQueue;
#else
	NSArray<dispatch_queue_t> *dispatchQueue;
	NSInteger queueIdx;
#endif
#ifdef NOGUI
	__weak NSTimer *runtimeTimer;
	NSMutableArray<PeriodicReporter *> *reporters;
	NSLock *reportersLock;
	CGFloat maxSPS;
#endif
}
@end

@implementation World
@synthesize loopMode, stopAtNDays;
- (Agent **)QListP { return &_QList; }
- (Agent **)CListP { return &_CList; }
- (RuntimeParams *)runtimeParamsP { return &runtimeParams; }
- (RuntimeParams *)initParamsP { return &initParams; }
- (WorldParams *)worldParamsP { return &worldParams; }
- (WorldParams *)tmpWorldParamsP { return &tmpWorldParams; }
- (CGFloat)stepsPerSec { return stepsPerSec; }
- (BOOL)running { return loopMode == LoopRunning; }
- (Gathering *)gatherings { return gatherings; }
- (void)popLock { [popLock lock]; }
- (void)popUnlock { [popLock unlock]; }
- (StatInfo *)statInfo { return statInfo; }
- (NSMutableArray<MyCounter *> *)RecovPHist { return statInfo.RecovPHist; }
- (NSMutableArray<MyCounter *> *)IncubPHist { return statInfo.IncubPHist; }
- (NSMutableArray<MyCounter *> *)DeathPHist { return statInfo.DeathPHist; }
- (void)addOperation:(void (^)(void))block {
#ifdef GCD_CONCURRENT_QUEUE
	dispatch_group_async(dispatchGroup, dispatchQueue, block);
#else
	queueIdx = (queueIdx + 1) % nQueues;
	dispatch_group_async(dispatchGroup, dispatchQueue[queueIdx], block);
#endif
}
- (void)waitAllOperations {
	dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
}
#define ALLOC_UNIT 2048
#define DYNAMIC_MEM(t,f,n) -(t *)n {\
	if (f == NULL) {\
		NSMutableData *md = [NSMutableData.alloc initWithLength:sizeof(t) * ALLOC_UNIT];\
		f = md.mutableBytes;\
		for (NSInteger i = 0; i < ALLOC_UNIT - 1; i ++) f[i].next = f + i + 1;\
		f[ALLOC_UNIT - 1].next = NULL;\
		[memPoolLock lock]; [memPool addObject:md]; [memPoolLock unlock];\
	}\
	t *a = f; f = f->next; a->next = NULL; return a;\
}
DYNAMIC_MEM(TestEntry, freeTMem, newTestEntry0)
DYNAMIC_MEM(ContactInfo, freeCMem, newCInfo0)
DYNAMIC_MEM(Gathering, freeGMem, newGathering0)
#define NEW_DYMEM(t,m0,m1,lk) -(t *)m1 {\
	[lk lock];\
	t *a = [self m0];\
	[lk unlock];\
	return a;\
}
NEW_DYMEM(TestEntry, newTestEntry0, newTestEntry, tmemLock)
NEW_DYMEM(ContactInfo, newCInfo0, newCInfo, cmemLock)
- (void)addNewCInfoA:(Agent *)a B:(Agent *)b tm:(NSInteger)tm {
	ContactInfo *c = [self newCInfo];
	c->agent = b; c->timeStamp = tm;
	c->prev = NULL;
	if (a->contactInfoHead == NULL) {
		a->contactInfoHead = a->contactInfoTail = c;
	} else {
		c->next = a->contactInfoHead;
		a->contactInfoHead = c;
		c->next->prev = c;
	}
}
- (void)removeOldCInfo:(Agent *)a tm:(NSInteger)tm {
	ContactInfo *p = a->contactInfoTail;
	if (p == NULL) return;
	for ( ; p != NULL; p = p->prev) if (p->timeStamp > tm) break;
	ContactInfo *gbHead, *gbTail = a->contactInfoTail;
	if (p == NULL) {
		gbHead = a->contactInfoHead;
		a->contactInfoHead = a->contactInfoTail = NULL;
	} else if (p->next != NULL) {
		gbHead = p->next;
		a->contactInfoTail = p;
		p->next = NULL;
	} else return;
	[cmemLock lock];
	gbTail->next = freeCMem; freeCMem = gbHead;
	[cmemLock unlock];
}
- (void)freeGatherings:(Gathering *)gats {
	if (gats == NULL) return;
	[gmemLock lock];
	Gathering *g = gats;
	while(g->next) {
		free(g->agents);
		g = g->next;
	}
	free(g->agents);
	g->next = freeGMem; freeGMem = gats;
	[gmemLock unlock];
}
- (Gathering *)newNGatherings:(NSInteger)n {
	if (n <= 0) return NULL;
	[gmemLock lock];
	Gathering *gat = [self newGathering0], *p = gat;
	gat->prev = NULL;
	for (NSInteger i = 1; i < n; i ++, p = p->next)
		(p->next = [self newGathering0])->prev = p;
	[gmemLock unlock];
	for (Gathering *g = gat; g != NULL; g = g->next)
		{ g->nAgents = 0; g->agents = NULL; }
	return gat;
}
- (void)addInfected:(NSInteger)n {
	NSInteger nSusc = 0, nCells = worldParams.mesh * worldParams.mesh;
	for (NSInteger i = 0; i < nCells; i ++)
		for (Agent *a = _Pop[i]; a; a = a->next) if (a->health == Susceptible) nSusc ++;
	if (nSusc == 0) return;
	if (n >= nSusc) {
		n = nSusc;
		for (NSInteger i = 0; i < nCells; i ++)
			for (Agent *a = _Pop[i]; a; a = a->next) if (a->health == Susceptible)
				{ a->health = Asymptomatic; a->daysInfected = a->daysDiseased = 0; }
	} else if (n > 0) {
		NSInteger *idxs = malloc(nSusc * sizeof(NSInteger));
		for (NSInteger i = 0; i < nSusc; i ++) idxs[i] = i;
		for (NSInteger i = 0; i < n; i ++) {
			NSInteger j = (random() % (nSusc - i)) + i;
			NSInteger k = idxs[j]; idxs[j] = idxs[i]; idxs[i] = k;
		}
		qsort_b(idxs, n, sizeof(NSInteger), ^int(const void *a, const void *b) {
			NSInteger c = *((NSInteger *)a), d = *((NSInteger *)b);
			return (c < d)? -1 : (c > d)? 1 : 0;
		});
		NSInteger idx = idxs[0];
		for (NSInteger i = 0, j = 0, k = 0; i < nCells && j < n; i ++)
		for (Agent *a = _Pop[i]; a; a = a->next) if (a->health == Susceptible) {
			if (k == idx) {
				a->health = Asymptomatic; a->daysInfected = a->daysDiseased = 0;
				if ((++ j) >= n) break;
				else idx = idxs[j];
			}
			k ++;
		}
		free(idxs);
	} else return;
	if (loopMode == LoopFinished) loopMode = LoopEndByUser;
	statInfo.statistics->cnt[Susceptible] -= n;
	statInfo.statistics->cnt[Asymptomatic] += n;
}
NSPredicate *predicate_in_item(NSObject *item, NSString **comment) {
	if ([item isKindOfClass:NSPredicate.class]) {
		if (comment) *comment = @""; return (NSPredicate *)item;
	} else if ([item isKindOfClass:NSArray.class] && ((NSArray *)item).count > 1
		&& [((NSArray *)item)[1] isKindOfClass:NSPredicate.class]) {
		if (comment) *comment = [((NSArray *)item)[0] isKindOfClass:NSString.class]?
			(NSString *)((NSArray *)item)[0] : @"";
		return (NSPredicate *)((NSArray *)item)[1];
	} else return nil;
}
- (void)execScenario {
	predicateToStop = nil;
	if (scenario == nil) return;
	char visitFlags[scenario.count];
	memset(visitFlags, 0, scenario.count);
	BOOL hasStopCond = NO;
	NSMutableDictionary<NSString *, NSObject *> *md = NSMutableDictionary.new;
	while (scenarioIndex < scenario.count) {
		if (visitFlags[scenarioIndex] == YES) {
			NSString *message = [NSString stringWithFormat:@"%@: %ld",
				NSLocalizedString(@"Looping was found in the Scenario.", nil),
				scenarioIndex + 1];
#ifdef NOGUI
			fprintf(stderr, "%s\n", message.UTF8String);
			break;
#else
			@throw message;
#endif
		}
		visitFlags[scenarioIndex] = YES;
		NSObject *item = scenario[scenarioIndex ++];
		if ([item isKindOfClass:NSArray.class]) {
			NSArray *arr = (NSArray *)item;
			if ([arr[0] isKindOfClass:NSNumber.class]) {	// jump N if --
				NSInteger destIdx = [arr[0] integerValue];
				if (arr.count == 1) scenarioIndex = destIdx;
				else if ([(NSPredicate *)arr[1] evaluateWithObject:statInfo]) scenarioIndex = destIdx;
			} else if ([arr[1] isKindOfClass:NSPredicate.class]) {	// continue until --
				predicateToStop = (NSPredicate *)arr[1];
				hasStopCond = YES;
				break;
			} else if (arr.count == 2) md[arr[0]] = arr[1];	// paramter assignment
			else {	// parameter assignment with delay
				NSObject *goal = (paramIndexFromKey[arr[0]].integerValue > IDX_D &&
				  [arr[1] isKindOfClass:NSNumber.class])? @[arr[1], arr[1], arr[1]] : arr[1];
				paramChangers[arr[0]] = @[goal,
					@(runtimeParams.step / worldParams.stepsPerDay + [(arr[2]) doubleValue])];
			}
		} else if ([item isKindOfClass:NSDictionary.class]) {	// for upper compatibility
			[md addEntriesFromDictionary:(NSDictionary *)item];
		} else if ([item isKindOfClass:NSNumber.class]) {	// add infected individuals
			[self addInfected:((NSNumber *)item).integerValue];
		} else if ([item isKindOfClass:NSPredicate.class]) {	// predicate to stop
			predicateToStop = (NSPredicate *)item;
			hasStopCond = YES;
			break;
		}
	}
#ifndef NOGUI
	if (hasStopCond)
		[NSNotificationCenter.defaultCenter postNotificationName:nnScenarioText object:self];
#endif
	if (md.count > 0) {
		for (NSString *key in md.keyEnumerator) {
			NSNumber *idxNum = paramIndexFromKey[key];
			if (idxNum == nil) continue;
			NSInteger idx = idxNum.integerValue;
			NSObject *value = md[key];
			if (idx < IDX_D)
				(&runtimeParams.PARAM_F1)[idx] = ((NSNumber *)md[key]).doubleValue;
			else if ([value isKindOfClass:NSArray.class] && ((NSArray *)value).count == 3)
				set_dist_values(&runtimeParams.PARAM_D1 + idx - IDX_D,
					(NSArray<NSNumber *> *)value, 1.);
		}
#ifndef NOGUI
		[NSNotificationCenter.defaultCenter
			postNotificationName:nnParamChanged object:self
			userInfo:@{@"keys":md.allKeys}];
//		NSArray<NSString *> *allKeys = md.allKeys;
//		in_main_thread( ^{ [self->paramPanel adjustParamControls:allKeys]; });
#endif
	}
	if (predicateToStop == nil && scenarioIndex == scenario.count) scenarioIndex ++;
#ifndef NOGUI
	[statInfo phaseChangedTo:scenarioIndex];
#endif
}
- (NSArray *)scenario { return scenario; }
- (NSInteger)scenarioIndex { return scenarioIndex; }
- (void)setScenario:(NSArray *)newScen index:(NSInteger)idx {
	scenario = newScen;
	scenarioIndex = 0;
	paramChangers = NSMutableDictionary.new;
	if (runtimeParams.step == 0) [self execScenario];
}
#ifndef NOGUI
- (void)setupPhaseInfo {
	if (scenario.count == 0) {
		statInfo.phaseInfo = @[];
		statInfo.labelInfo = @[];
		return;
	}
	NSMutableArray<NSNumber *> *maPhase = NSMutableArray.new;
	NSMutableArray<NSString *> *maLabel = NSMutableArray.new;
	for (NSInteger i = 0; i < scenario.count; i ++) {
		NSObject *elm = scenario[i];
		NSString *label;
		NSPredicate *pred = predicate_in_item(elm, &label);
		if (pred != nil) {
			[maPhase addObject:@(i + 1)];
			[maLabel addObject:label];
		}
	}
	// if the final item is not an unconditional jump then add finale phase.
	NSArray *item = scenario.lastObject;
	if (![item isKindOfClass:NSArray.class] || item.count != 1 ||
		![item[0] isKindOfClass:NSNumber.class])
		[maPhase addObject:@(scenario.count + 1)];
	statInfo.phaseInfo = maPhase;
	statInfo.labelInfo = maLabel;
}
#else
- (void)forAllReporters:(void (^)(PeriodicReporter *))block {
	if (reporters == nil) return;
	[reportersLock lock];
	for (PeriodicReporter *rep in reporters) block(rep);
	[reportersLock unlock];
}
#endif
- (void)allocateMemory {
	[self freeGatherings:gatherings];
	gatherings = NULL;
	[cmemLock lock];
	for (NSInteger i = 0; i < nPop; i ++)
		if (_agents[i].contactInfoHead != NULL) {
			_agents[i].contactInfoTail->next = freeCMem;
			freeCMem = _agents[i].contactInfoHead;
			_agents[i].contactInfoHead = _agents[i].contactInfoTail = NULL;
	}
	[cmemLock unlock];
	if (nMesh != worldParams.mesh) {
		NSInteger nCNew = worldParams.mesh * worldParams.mesh;
		nMesh = worldParams.mesh;
		_Pop = realloc(_Pop, sizeof(void *) * nCNew);
		pRange = realloc(pRange, sizeof(NSRange) * nCNew);
	}
	memset(_Pop, 0, sizeof(void *) * nMesh * nMesh);
	if (nPop != worldParams.initPop) {
		nPop = worldParams.initPop;
		pop = realloc(pop, sizeof(void *) * nPop);
		_agents = realloc(_agents, sizeof(Agent) * nPop);
		vaccineList = realloc(vaccineList, sizeof(NSInteger) * nPop * 2);
		vcnInvList = vaccineList + nPop;
	}
	memset(_agents, 0, sizeof(Agent) * nPop);
	if (testQueTail != nil) {
		[tmemLock lock];
		testQueTail->next = freeTMem;
		freeTMem = testQueHead;
		[tmemLock unlock];
		testQueTail = testQueHead = NULL;
	}
	paramChangers = NSMutableDictionary.new;
	_QList = _CList = NULL;
	[_WarpList removeAllObjects];
}
static NSPoint random_point_in_hospital(CGFloat worldSize) {
	return (NSPoint){
		(d_random() * .248 + 1.001) * worldSize,
		(d_random() * .458 + 0.501) * worldSize};
}
- (void)sortVaccineListByActiveness:(int)order {
	Agent *amem = _agents;
	qsort_b(vaccineList + vcnListIndex, nVcnPop - vcnListIndex, sizeof(NSInteger),
		^int(const void *p1, const void *p2) {
			Agent *a1 = amem + *((NSInteger *)p1), *a2 = amem + *((NSInteger *)p2);
			return (a1->activeness > a2->activeness)? -order :
				(a1->activeness < a2->activeness)? order : 0;
	});
}
- (void)reorganizeVcnInvList {
	for (NSInteger i = vcnListIndex; i < nPop; i ++)
		vcnInvList[vaccineList[i]] = i;
}
- (void)sortVaccineList:(CGFloat (^)(Agent *a))getValue {
	NSInteger n = nVcnPop - vcnListIndex;
	CGFloat *d = malloc(sizeof(CGFloat) * nPop);
	for (NSInteger i = 0; i < n; i ++) {
		NSInteger idx = vaccineList[i + vcnListIndex];
		d[idx] = getValue(_agents + idx);
	}
	qsort_b(vaccineList + vcnListIndex, n, sizeof(NSInteger),
		^int(const void *p1, const void *p2) {
			CGFloat v1 = d[*((NSInteger *)p1)], v2 = d[*((NSInteger *)p2)]; 
			return (v1 < v2)? -1 : (v1 > v2)? 1 : 0;
	});
	free(d);
	[self reorganizeVcnInvList];
}
- (void)vcnListRandom {
	for (NSInteger i = vcnListIndex; i < nVcnPop - 1; i ++) {
		NSInteger j = random() % (nPop - i) + i;
		if (i != j) {
			NSInteger k = vaccineList[i];
			vaccineList[i] = vaccineList[j];
			vaccineList[j] = k;
		}
	}
	[self reorganizeVcnInvList];
}
- (void)vcnListFromCenter {
	CGFloat cx = worldParams.worldSize / 2.;
	[self sortVaccineList:(worldParams.wrkPlcMode == WrkPlcNone)?
		^(Agent *a) { return hypot(a->x - cx, a->y - cx); } :
		^(Agent *a) { return hypot(a->orgPt.x - cx, a->orgPt.y - cx); }];
}
- (void)vcnListPopDens {
	NSBitmapImageRep *imgRep = make_bm_with_image(_popDistImage);
	float *pd = (float *)imgRep.bitmapData;
	CGFloat aa = (CGFloat)PopDistMapRes / worldParams.worldSize;
	[self sortVaccineList:^(Agent *a) {
		NSInteger ix = a->orgPt.x * aa, iy = a->orgPt.y * aa;
		return 1. - (CGFloat)pd[iy * PopDistMapRes + ix]; }];
}
- (void)reconfigureVaccineList {
	switch (runtimeParams.vcnPri) {
		case VcnPrRandom: [self vcnListRandom]; break;
		case VcnPrActive:
			[self sortVaccineList:^(Agent *a) { return 1. - a->activeness; }]; break;
		case VcnPrInactive:
			[self sortVaccineList:^(Agent *a) { return a->activeness; }]; break;
		case VcnPrCentral: [self vcnListFromCenter]; break;
		case VcnPrPopDens: switch (worldParams.wrkPlcMode) {
			case WrkPlcCentered: [self vcnListFromCenter]; break;
			case WrkPlcPopDistImg: [self vcnListPopDens]; break;
			default: [self vcnListRandom];
		} break;
		case VcnPrActAndCntr: {
			CGFloat cx = worldParams.worldSize / 2.;
			NSPoint (^dist)(Agent *a) = (worldParams.wrkPlcMode == WrkPlcNone)?
				^(Agent *a) { return (NSPoint){a->x, a->y}; } :
				^(Agent *a) { return a->orgPt; };
			[self sortVaccineList:^(Agent *a) {
				NSPoint p = dist(a);
				return fmax(hypot(p.x - cx, p.y - cx) / cx / M_SQRT2, 1. - a->activeness);
			}];
		}
		default: break;
	}
#ifdef DEBUG
#ifdef NOGUI
	CGFloat ac[3]; CGPoint pt[3];
	for (NSInteger i = 0; i < 3; i ++) {
		Agent *a = _agents + vaccineList[i + vcnListIndex];
		ac[i] = a->activeness;
		pt[i] = (worldParams.wrkPlcMode == WrkPlcNone)? (CGPoint){a->x, a->y} : a->orgPt;
	}
	MY_LOG("Vcn list (%d) %.6f(%.1f,%.1f),%.6f(%.1f,%.1f),%.6f(%.1f,%.1f)", runtimeParams.vcnPri,
		ac[0], pt[0].x, pt[0].y, ac[1], pt[1].x, pt[1].y, ac[2], pt[2].x, pt[2].y);
#endif
#endif
}
- (void)setVaccinePriority:(VaccinePriority)newValue toInit:(BOOL)isInit {
	RuntimeParams *rp = isInit? &initParams : &runtimeParams;
	if (rp->vcnPri == newValue) return;
	rp->vcnPri = newValue;
	if (isInit) {
		if (runtimeParams.step == 0) {
			runtimeParams.vcnPri = newValue;
			[self reconfigureVaccineList];
	}} else [self reconfigureVaccineList];
}
- (void)resetVaccineList {
	for (NSInteger i = 0; i < nPop; i ++) {
		vaccineList[i] = vcnInvList[i] = i;
		_agents[i].vaccineTicket = NO;
		_agents[i].forVcn = VcnAccept;
	}
	WorldParams *p = &worldParams;
	NSInteger nAntiVcnPop = nPop * p->vcnAntiRate / 100.;
	NSInteger nNoVcnNorTest = nAntiVcnPop * (1. - p->avTestRate / 100.);
	NSInteger nClstrs = pow(nAntiVcnPop / 2, p->avClstrGran / 100.);
	NSInteger nAgentsInClstr = nAntiVcnPop * p->avClstrRate / 100.;
	NSInteger nClstrCols = ceil(sqrt(nClstrs)),
		nClstrRows = (nClstrs + nClstrCols - 1) / nClstrCols,
		idx = 0;
	typedef enum { IdxDown, IdxUp, IdxLeft, IdxRight } ExIdxOrder;
	static ExIdxOrder exIdxOrder[8][4] = {
		{ IdxDown, IdxLeft, IdxUp, IdxRight },
		{ IdxDown, IdxRight, IdxLeft, IdxUp },
		{ IdxLeft, IdxUp, IdxDown, IdxRight },
		{ IdxRight, IdxUp, IdxDown, IdxLeft },
		{ IdxLeft, IdxDown, IdxUp, IdxRight },
		{ IdxRight, IdxDown, IdxUp, IdxLeft },
		{ IdxUp, IdxLeft, IdxRight, IdxDown },
		{ IdxUp, IdxRight, IdxLeft, IdxDown }
	};
	for (NSInteger i = 0; i < nClstrs; i ++) {
		NSInteger nAgents = (nAgentsInClstr - idx) / (nClstrs - i);
		if (nAgents <= 0) continue;
		NSPoint pt = {
			(i % nClstrCols + .5) * worldParams.worldSize / nClstrCols,
			(i / nClstrCols + .5) * worldParams.worldSize / nClstrRows
		};
		CGFloat ay = pt.y * p->mesh / p->worldSize, ax = pt.x * p->mesh / p->worldSize;
		NSInteger iy = floor(ay), ix = floor(ax);
		if (iy < 0) iy = 0; else if (iy >= p->mesh) iy = p->mesh - 1;
		if (ix < 0) ix = 0; else if (ix >= p->mesh) ix = p->mesh - 1;
		NSInteger iw = 1, ih = 1, kx = ix, ky = iy, jx = ix, jy = iy,
			exOrder = 0, orderIdx = 0, noChangeCount = 0;
		if (ax - ix > .5) exOrder |= 1;
		if (ay - iy > .5) exOrder |= 2;
		if (exOrder == 0 || exOrder == 3) {
			if (ax - ix < ay - iy) exOrder |= 4;
		} else if (ax - ix > 1 - ay + iy) exOrder |= 4;
		ExIdxOrder *idxOrder = exIdxOrder[exOrder];
		NSMutableArray<NSValue *> *members = nil;
		for (BOOL doItMore = YES; doItMore; ) {
			NSMutableArray<NSValue *> *candidates = NSMutableArray.new;
			for (NSInteger v = 0; v < ih; v ++) for (NSInteger u = 0; u < iw; u ++)
			for (Agent *a = _Pop[(ky + v) * p->mesh + kx + u]; a != NULL; a = a->next)
				if (a->forVcn != VcnReject) [candidates addObject:[NSValue valueWithDistanceInfo:
					(DistanceInfo){a, hypot(a->x - pt.x, a->y - pt.y)}]];
			[candidates sortUsingComparator:^NSComparisonResult(NSValue *v1, NSValue *v2) {
				CGFloat d1 = v1.distanceInfo.dist, d2 = v2.distanceInfo.dist;
				return (d1 < d2)? NSOrderedAscending : (d1 > d2)? NSOrderedDescending : NSOrderedSame;
			}];
			if (members == nil) { if (candidates.count > 0) members = candidates; }
			else if (candidates.count > 0) {
				BOOL changed = NO;
				NSMutableArray<NSValue *> *newMem = NSMutableArray.new;
				NSInteger mIdx = 0, cIdx = 0;
				CGFloat mDist = members[0].distanceInfo.dist, cDist = candidates[0].distanceInfo.dist;
				while (newMem.count < nAgents && (mDist < MAXFLOAT || cDist < MAXFLOAT)) {
					if (mDist < cDist) {
						[newMem addObject:members[mIdx ++]];
						mDist = (mIdx < members.count)? members[mIdx].distanceInfo.dist : MAXFLOAT;
					} else {
						[newMem addObject:candidates[cIdx ++]];
						cDist = (cIdx < candidates.count)?
							candidates[cIdx].distanceInfo.dist : MAXFLOAT;
						changed = YES;
					}
				}
				members = newMem;
				if (changed) noChangeCount = 0;
				else if ((++ noChangeCount) >= 4) { doItMore = NO; break; }
			} else if (members.count >= nAgents)
				if ((++ noChangeCount) >= 4) { doItMore = NO; break; }
			doItMore = NO;
			for (NSInteger i = 0; !doItMore && i < 4; i ++) {
				switch (idxOrder[orderIdx]) {
					case IdxDown: if (jy < p->mesh - 1) 
						{ ky = ++ jy; kx = ix; ih = 1; iw = jx - ix + 1; doItMore = YES; } break;
					case IdxUp: if (iy > 0)
						{ ky = -- iy; kx = ix; ih = 1; iw = jx - ix + 1; doItMore = YES; } break;
					case IdxRight: if (jx < p->mesh - 1)
						{ kx = ++ jx; ky = iy; iw = 1; ih = jy - iy + 1; doItMore = YES; } break;
					case IdxLeft: if (ix > 0)
						{ kx = -- ix; ky = iy; iw = 1; ih = jy - iy + 1; doItMore = YES; }
				}
				orderIdx = (orderIdx + 1) % 4;
			}
		}
		for (NSInteger i = 0; i < nAgents && i < members.count; i ++) {
			NSInteger ID = members[i].distanceInfo.agent->ID,
				kIdx = nPop - 1 - idx - i, k = vaccineList[kIdx];
			vaccineList[kIdx] = ID; vaccineList[vcnInvList[ID]] = k;
			vcnInvList[k] = vcnInvList[ID]; vcnInvList[ID] = kIdx;
			_agents[ID].forVcn = VcnReject;
		}
		idx += nAgents;
	}
	for ( ; idx < nAntiVcnPop; idx ++) {
		NSInteger j = random() % (nPop - idx);
		if (j != idx) {
			NSInteger jIdx = nPop - 1 - j, kIdx = nPop - 1 - idx, k = vaccineList[kIdx];
			vaccineList[kIdx] = vaccineList[jIdx]; vaccineList[jIdx] = k;
			vcnInvList[k] = jIdx; vcnInvList[vaccineList[kIdx]] = kIdx;
		}
		_agents[vaccineList[nPop - idx - 1]].forVcn = VcnReject;
//			= (idx < nNoVcnButTest)? VcnReject : VcnNoTest;
	}
	if (nNoVcnNorTest >= nAntiVcnPop) {
		for (NSInteger i = 0; i < nAntiVcnPop; i ++)
			_agents[vaccineList[nPop - 1 - i]].forVcn = VcnNoTest;
	} else if (nNoVcnNorTest > 0) {
		NSInteger *b = malloc(sizeof(NSInteger) * nAntiVcnPop);
		for (NSInteger i = 0; i < nAntiVcnPop; i ++) b[i] = i;
		for (NSInteger i = 0; i < nNoVcnNorTest; i ++) {
			NSInteger k = random() % (nAntiVcnPop - i) + i;
			if (k != i) { NSInteger j = b[k]; b[k] = b[i]; b[i] = j; }
			_agents[vaccineList[nPop - 1 - b[i]]].forVcn = VcnNoTest; 
		}
		free(b);
	}
	nVcnPop = nPop - nAntiVcnPop;
	vcnListIndex = vcnLateIdx = 0;
	vcnSubjectsRem = 0.;
	[self reconfigureVaccineList];
}
- (BOOL)resetPop {
	BOOL changed = NO;
	if (memcmp(&worldParams, &tmpWorldParams, sizeof(WorldParams)) != 0) {
		memcpy(&worldParams, &tmpWorldParams, sizeof(WorldParams));
		changed = YES;
	}
	memcpy(&runtimeParams, &initParams, sizeof(RuntimeParams));
	[popLock lock];
	[self allocateMemory];
	NSInteger nDist = runtimeParams.dstOB / 100. * nPop;
	for (NSInteger i = 0; i < nPop; i ++) {
		Agent *a = &_agents[i];
		reset_agent(a, &runtimeParams, &worldParams);
		a->ID = i;
		a->distancing = (i < nDist);
	}
	if (worldParams.wrkPlcMode == WrkPlcPopDistImg)
		setup_home_with_map(_agents, &worldParams, _popDistImage);
	PopulationHConf pconf = { 0,
		nPop * worldParams.infected / 100, 0,
		nPop * worldParams.recovered / 100, 0,
	};
	NSInteger nn = pconf.asym + pconf.recv;
	if (nn > nPop) pconf.recv = (nn = nPop) - pconf.asym;
	pconf.susc = nPop - nn;
	NSInteger *ibuf = malloc(sizeof(NSInteger) * nPop);
	for (NSInteger i = 0; i < nPop; i ++) ibuf[i] = i;
	for (NSInteger i = 0; i < nn; i ++) {
		NSInteger j = random() % (nPop - i) + i, k = ibuf[j];
		if (i != j) ibuf[j] = ibuf[i];
		Agent *a = &_agents[k];
		if (i < pconf.asym) {
			a->daysInfected = d_random() * fmin(a->daysToRecover, a->daysToDie);
			if (a->daysInfected < a->daysToOnset) a->health = Asymptomatic;
			else {
				a->health = Symptomatic;
				a->daysDiseased = a->daysInfected - a->daysToOnset;
				pconf.symp ++;
			}
		} else {
			a->health = Recovered;
			a->daysInfected = d_random() * a->imExpr;
		}
	}
	free(ibuf);
	pconf.qAsym = (pconf.asym -= pconf.symp) * worldParams.qAsymp / 100;
	pconf.qSymp = pconf.symp * worldParams.qSymp / 100;
	NSInteger qaCnt = 0, qsCnt = 0;
	for (NSInteger i = 0; i < nPop; i ++) {
		Agent *a = &_agents[i];
		BOOL inQ = NO;
		switch (a->health) {
			case Asymptomatic:
				if (qaCnt < pconf.qAsym) { qaCnt ++; inQ = YES; } break;
			case Symptomatic:
				if (qsCnt < pconf.qSymp) { qsCnt ++; inQ = YES; }
			default: break;
		}
		if (inQ) {
			a->newHealth = a->health;
			if (worldParams.wrkPlcMode == WrkPlcNone) a->orgPt = (NSPoint){a->x, a->y};
			NSPoint pt = random_point_in_hospital(worldParams.worldSize);
			a->x = pt.x; a->y = pt.y;
			add_to_list(a, &_QList);
		} else add_agent(a, &worldParams, _Pop);
	}
	[self resetVaccineList];
	runtimeParams.step = 0;
	[statInfo reset:pconf];
	[popLock unlock];
	scenarioIndex = 0;
	[self execScenario];
#ifdef NOGUI
	[self forAllReporters:^(PeriodicReporter *rep) { [rep reset]; }];
#endif
	loopMode = LoopNone;
#ifdef MEASURE_TIME
	mCount = mCount2 = 0;
	memset(mtime, 0, sizeof(mtime));
#endif
	return changed;
}
- (instancetype)init {
	if ((self = [super init]) == nil) return nil;
	dispatchGroup = dispatch_group_create();
#ifdef GCD_CONCURRENT_QUEUE
	dispatchQueue = dispatch_queue_create(
		"jp.ac.soka.unemi.SimEpidemic.queue", DISPATCH_QUEUE_CONCURRENT);
#else
	dispatch_queue_t ques[nQueues];
	for (NSInteger i = 0; i < nQueues; i ++)
		ques[i] = dispatch_queue_create(
		"jp.ac.soka.unemi.SimEpidemic.queue", DISPATCH_QUEUE_SERIAL);
	dispatchQueue = [NSArray arrayWithObjects:ques count:nQueues];
#endif
	popLock = NSLock.new;
	newWarpF = NSMutableDictionary.new;
	newWarpLock = NSLock.new;
	_WarpList = NSMutableDictionary.new;
	testees = NSMutableDictionary.new;
	testeesLock = NSLock.new;
	memPool = NSMutableArray.new;
	memPoolLock = NSLock.new;
	tmemLock = NSLock.new;
	cmemLock = NSLock.new;
	gmemLock = NSLock.new;
	stopAtNDays = -365;
	memcpy(&runtimeParams, &userDefaultRuntimeParams, sizeof(RuntimeParams));
	memcpy(&initParams, &userDefaultRuntimeParams, sizeof(RuntimeParams));
	memcpy(&worldParams, &userDefaultWorldParams, sizeof(WorldParams));
	memcpy(&tmpWorldParams, &userDefaultWorldParams, sizeof(WorldParams));
	statInfo = StatInfo.new;
	statInfo.world = self;
#ifdef NOGUI
	_ID = new_uniq_string();
	_lastTLock = NSLock.new;
	[self resetPop];
#endif
	return self;
}
- (void)discardMemory {	// called when this document got useless
#ifdef NOGUI
	if (reporters != nil) {
		for (PeriodicReporter *rep in reporters) [rep quit];
		reporters = nil;
	}
	[statInfo discardMemory];	// cut the recursive reference
#endif
	[memPool removeAllObjects];
	free(_Pop);
	free(pop);
	free(_agents);
	self.popDistImage = nil;
}
NSString *keyParameters = @"parameters", *keyScenario = @"scenario",
	*keyDaysToStop = @"daysToStop";
static NSObject *property_from_element(NSObject *elm) {
	NSString *label;
	NSPredicate *pred = predicate_in_item(elm, &label);
	if (pred == nil) return elm;
	if (label.length == 0) return pred.predicateFormat;
	return @[label, pred.predicateFormat];
}
NSObject *scenario_element_from_property(NSObject *prop) {
	if ([prop isKindOfClass:NSString.class])
		return [NSPredicate predicateWithFormat:(NSString *)prop];
	else if (![prop isKindOfClass:NSArray.class]) return prop;
	else if (((NSArray *)prop).count != 2) return prop;
	else if (![((NSArray *)prop)[1] isKindOfClass:NSString.class]) return prop;
	NSPredicate *pred =
		[NSPredicate predicateWithFormat:(NSString *)((NSArray *)prop)[1]];
	return (pred != nil)? @[((NSArray *)prop)[0], pred] : nil;
}
NSString *check_scenario_element_from_property(NSObject *prop) {
// returns nil when it looks OK, otherwise return a string of error message
	NSString *predForm = nil;
	if ([prop isKindOfClass:NSString.class]) predForm = (NSString *)prop;
	else if (![prop isKindOfClass:NSArray.class]) return nil;
	else if (((NSArray *)prop).count != 2) return nil;
	else if (![((NSArray *)prop)[1] isKindOfClass:NSString.class]) return nil;
	else predForm = (NSString *)((NSArray *)prop)[1];
	if (predForm == nil || predForm.length == 0) return @"Null predicate";
	@try { return ([NSPredicate predicateWithFormat:predForm] == nil)? @"Null" : nil; }
	@catch (NSException *e) { return e.reason; }
}
- (NSArray *)scenarioPList {
	if (scenario == nil || scenario.count == 0) return @[];
	NSObject *items[scenario.count];
	for (NSInteger i = 0; i < scenario.count; i ++)
		items[i] = property_from_element(scenario[i]);
	return [NSArray arrayWithObjects:items count:scenario.count];
}
- (void)setScenarioWithPList:(NSArray *)plist {
	NSArray *newScen;
	if (plist.count == 0) newScen = plist;
	else {
		NSObject *items[plist.count];
		for (NSInteger i = 0; i < plist.count; i ++) {
			NSString *errmsg = nil;
			@try {
				items[i] = scenario_element_from_property(plist[i]);
				if (items[i] == nil) errmsg = [NSString stringWithFormat:
					@"Could not convert it to a scenario element: %@", plist[i]];
			} @catch (NSException *exc) { errmsg = exc.reason; }
			if (errmsg != nil) @throw errmsg;
		}
		newScen = [NSArray arrayWithObjects:items count:plist.count];
	}
	scenario = newScen;
	scenarioIndex = 0;
	if (statInfo != nil) {
#ifndef NOGUI
		[self setupPhaseInfo];
#endif
		if (runtimeParams.step == 0) [self execScenario];
	}
}
- (void)testInfectionOfAgent:(Agent *)agent reason:(TestType)reason {
	if (runtimeParams.step - agent->lastTested <
		runtimeParams.tstInterval * worldParams.stepsPerDay ||
		agent->isOutOfField || agent->inTestQueue || agent->forVcn == VcnNoTest) return;
	[testeesLock lock];
	testees[@(agent->ID)] = @(reason);
	[testeesLock unlock];
}
- (void)addNewWarp:(WarpInfo)info {
	newWarpF[@(info.agent->ID)] = [NSValue valueWithWarpInfo:info];
}
- (void)deliverTestResults:(NSUInteger *)testCount {
	// check the results of tests
	NSInteger cTm = runtimeParams.step - runtimeParams.tstProc * worldParams.stepsPerDay;
	NSMutableSet *trcVcnSet = nil;
	if (runtimeParams.trcOpe != TrcTst) trcVcnSet = NSMutableSet.new;
	for (TestEntry *entry = testQueHead; entry != NULL; entry = testQueHead) {
		if (entry->timeStamp > cTm) break;
		if (entry->isPositive) {
			testCount[TestPositive] ++;
			Agent *a = entry->agent;
			if (worldParams.wrkPlcMode == WrkPlcNone) a->orgPt = (NSPoint){a->x, a->y};
			[self addNewWarp:(WarpInfo){a, WarpToHospital,
				random_point_in_hospital(worldParams.worldSize)}];
			if (a->contactInfoHead != NULL) {
				switch (runtimeParams.trcOpe) {
					case TrcTst:
					for (ContactInfo *c = a->contactInfoHead; c != NULL; c = c->next)
						[self testInfectionOfAgent:c->agent reason:TestAsContact];
					break;
					case TrcVcn:
					for (ContactInfo *c = a->contactInfoHead; c != NULL; c = c->next)
						[trcVcnSet addObject:@(c->agent->ID)];
					break;
					case TrcBoth:
					for (ContactInfo *c = a->contactInfoHead; c != NULL; c = c->next) {
						[self testInfectionOfAgent:c->agent reason:TestAsContact];
						[trcVcnSet addObject:@(c->agent->ID)];
					}
				}
				[cmemLock lock];
				a->contactInfoTail->next = freeCMem;
				freeCMem = a->contactInfoHead;
				[cmemLock unlock];
				a->contactInfoHead = a->contactInfoTail = NULL;
			}
		} else testCount[TestNegative] ++;
		entry->agent->inTestQueue = NO;
		testQueHead = entry->next;
		if (entry->next) entry->next->prev = NULL;
		else testQueTail = NULL;
		[tmemLock lock];
		entry->next = freeTMem;
		freeTMem = entry;
		[tmemLock unlock];
	}
	// enqueue new tests
	[testeesLock lock];
	for (NSNumber *num in testees) {
		testCount[testees[num].integerValue] ++;
		Agent *agent = &_agents[num.integerValue];
		TestEntry *entry = [self newTestEntry];
		entry->isPositive = is_infected(agent)?
			(d_random() < runtimeParams.tstSens / 100.) :
			(d_random() > runtimeParams.tstSpec / 100.);
		agent->lastTested = entry->timeStamp = runtimeParams.step;
		entry->agent = agent;
		if ((entry->prev = testQueTail) != NULL) testQueTail->next = entry;
		else testQueHead = entry;
		entry->next = NULL;
		testQueTail = entry;
		agent->inTestQueue = YES;
	}
	[testeesLock unlock];
	[testees removeAllObjects];
	for (NSInteger i = TestAsSymptom; i < TestPositive; i ++)
		testCount[TestTotal] += testCount[i];
//
	if (trcVcnSet == nil) return;
	for (NSNumber *num in trcVcnSet) {
		NSInteger aID = num.integerValue, idx = vcnInvList[aID];
		if (idx <= vcnLateIdx) continue;
		if (idx >= nPop) {
			NSString *msg = [NSString stringWithFormat:
				#ifdef NOGUI
				@"In %@, vcnInvList[%ld] = %ld", _ID,
				#else
				@"vcnInvList[%ld] = %ld",
				#endif
				aID, idx];
			ERROR_MSG(msg);
			return;
		}
		for (NSInteger i = idx; i > vcnLateIdx; i --)
			vcnInvList[vaccineList[i] = vaccineList[i - 1]] = i;
		vaccineList[vcnLateIdx] = aID;
		vcnInvList[aID] = vcnLateIdx ++;
	}
}
- (void)gridToGridA:(NSInteger)iA B:(NSInteger)iB {
	Agent **apA = pop + pRange[iA].location, **apB = pop + pRange[iB].location;
	for (NSInteger j = 0; j < pRange[iA].length; j ++)
		[self interactsA:apA[j] Bs:apB n:pRange[iB].length];
}
static void set_dist_values(DistInfo *dp, NSArray<NSNumber *> *arr, CGFloat steps) {
	dp->min += (arr[0].doubleValue - dp->min) / steps;
	dp->max += (arr[1].doubleValue - dp->max) / steps;
	dp->mode += (arr[2].doubleValue - dp->mode) / steps;
}
#ifdef DEBUGz
#define INC_PHASE _phaseInStep ++; [self checkMemLoop];
- (void)checkMemLoop {
	for (NSInteger i = 0; i < worldParams.mesh * worldParams.mesh; i ++) {
		NSInteger n = 0;
		for (Agent *a = _Pop[i]; a; a = a->next) if ((++ n) > worldParams.initPop) {
			printf("LOOP! idx=%ld,phase=%ld\n", i, _phaseInStep);
			in_main_thread(^{ terminateApp(-2); });
			break;
		}
	}
}
#else
#define INC_PHASE ;
#endif
- (void)doOneStep {
	[popLock lock];
#ifdef DEBUGz
	_phaseInStep = 0;
#endif
#ifdef MEASURE_TIME
	unsigned long tm0 = current_time_us(), tm1 = tm0, tm2;
	NSInteger tmIdx = 0;
	mCount ++;
#endif
	BOOL goHomeBack = worldParams.wrkPlcMode != WrkPlcNone && is_daytime(&worldParams, &runtimeParams);
	if (paramChangers != nil && paramChangers.count > 0) {
		NSMutableArray<NSString *> *keyToRemove = NSMutableArray.new;
		for (NSString *key in paramChangers.keyEnumerator) {
			NSArray<NSNumber *> *entry = paramChangers[key];
			CGFloat stepsLeft = entry[1].doubleValue * worldParams.stepsPerDay
				- runtimeParams.step;
			NSInteger idx = paramIndexFromKey[key].integerValue;
			if (stepsLeft <= 1.) {
				[keyToRemove addObject:key];
				if (idx < IDX_D) (&runtimeParams.PARAM_F1)[idx] = entry[0].doubleValue;
				else set_dist_values(&runtimeParams.PARAM_D1 + idx - IDX_D,
					(NSArray<NSNumber *> *)entry[0], 1.);
			} else if (idx < IDX_D) {
				CGFloat *vp = &runtimeParams.PARAM_F1 + idx;
				*vp += (entry[0].doubleValue - *vp) / stepsLeft;
			} else set_dist_values(&runtimeParams.PARAM_D1 + idx - IDX_D,
				(NSArray<NSNumber *> *)entry[0], stepsLeft);
		}
#ifndef NOGUI
		[NSNotificationCenter.defaultCenter postNotificationName:nnParamChanged
			object:self userInfo:@{@"keys":paramChangers.allKeys}];
#endif
		for (NSString *key in keyToRemove) [paramChangers removeObjectForKey:key];
	}
//
    NSInteger unitJ = 4;
	NSInteger nCells = worldParams.mesh * worldParams.mesh;
//#define PARTIAL_CALC
#ifdef PARTIAL_CALC
	unsigned char IMap[nCells], *IMapP = IMap;
	memset(IMap, 0, nCells);
	Agent **PopL = _Pop;
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * nCells / unitJ, end = (j + 1) * nCells / unitJ;
		void (^block)(void) = ^{
			for (NSInteger i = start; i < end; i ++) {
				for (Agent *a = PopL[i]; a; a = a->next)
					if (a->health != Susceptible) { IMapP[i] = '\001'; break; }
		}};
		if (j < unitJ - 1) [self addOperation:block]; else block();
	}
	[self waitAllOperations];
	for (NSInteger i = 0; i < nMesh; i ++) {
		NSInteger aFrom = (i == 0)? 0 : -1, aTo = (i == nMesh - 1)? 0 : 1;
		for (NSInteger j = 0; j < nMesh; j ++) if (IMap[i * nMesh + j] & '\001') {
			NSInteger bFrom = (j == 0)? 0 : -1, bTo = (j == nMesh - 1)? 0 : 1;
			for (NSInteger a = aFrom; a <= aTo; a ++) for (NSInteger b = bFrom; b <= bTo; b ++)
				IMap[(i + a) * nMesh + j + b] |= '\002';
	}}
#endif
	memset(pRange, 0, sizeof(NSRange) * nCells);
	NSInteger nInField = 0;
	for (NSInteger i = 0; i < nCells; i ++) {
		pRange[i].location = nInField;
#ifdef PARTIAL_CALC
		if (IMap[i])
#endif
		for (Agent *p = _Pop[i]; p; p = p->next) pop[nInField ++] = p;
		pRange[i].length = nInField - pRange[i].location;
	}
	NSInteger oldTimeStamp = runtimeParams.step - worldParams.stepsPerDay * 14;	// two weeks
	Agent **popL = pop;
	__weak World *weakSelf = self;
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * nInField / unitJ, end = (j + 1) * nInField / unitJ;
		[self addOperation:^{
			for (NSInteger i = start; i < end; i ++) {
				reset_for_step(popL[i]);
				[weakSelf removeOldCInfo:popL[i] tm:oldTimeStamp];
		}}];
	}
	RuntimeParams *rp = &runtimeParams;
	WorldParams *wp = &worldParams;
	if (!goHomeBack) [self manageGatherings];
	if (rp->vcnPRate > 0 && vcnListIndex < nVcnPop) {
		vcnSubjectsRem += wp->initPop * rp->vcnPRate / 1000. / wp->stepsPerDay;
		NSInteger n = vcnSubjectsRem;
		vcnSubjectsRem -= n;
		for (NSInteger i = 0; i < wp->initPop && n > 0 && vcnListIndex < wp->initPop; i ++) {
			Agent *a = _agents + vaccineList[vcnListIndex];
			if (a->health == Susceptible || (a->health == Asymptomatic && !a->isOutOfField))
				{ a->vaccineTicket = YES; n --; }
			vcnListIndex ++;
		}
		if (vcnLateIdx < vcnListIndex) vcnLateIdx = vcnListIndex;
	}
	[self waitAllOperations];
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif
	unitJ = isARM? 4 : (nCores <= 8)? nCores - 1 : 8;
    NSRange *pRng = pRange;
    for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * nCells / unitJ;
		NSInteger end = (j + 1) * nCells / unitJ;
		void (^block)(void) = ^{
			for (NSInteger i = start; i < end; i ++) {
				Agent **ap = popL + pRng[i].location;
				NSRange rng = pRng[i];
				for (NSInteger j = 1; j < rng.length; j ++)
					[self interactsA:ap[j] Bs:ap n:j];
			}
		};
		if (j < unitJ - 1) [self addOperation:block]; else block();
	}
	[self waitAllOperations];
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif
	if (nCores > 20) unitJ = 20;
	NSInteger mesh = worldParams.mesh;
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * mesh / unitJ, end = (j + 1) * mesh / unitJ;
		void (^block)(void) = ^{ for (NSInteger y = start; y < end; y ++)
			for (NSInteger x = 1; x < mesh; x += 2) 
				[weakSelf gridToGridA:y * mesh + x B:y * mesh + x - 1]; };
		if (j < unitJ - 1) [self addOperation:block]; else block();
	}
	[self waitAllOperations];
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * mesh / unitJ, end = (j + 1) * mesh / unitJ;
		void (^block)(void) = ^{ for (NSInteger y = start; y < end; y ++)
			for (NSInteger x = 2; x < mesh; x += 2)
				[weakSelf gridToGridA:y * mesh + x B:y * mesh + x - 1]; };
		if (j < unitJ - 1) [self addOperation:block]; else block();
	}
	[self waitAllOperations];
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * mesh / unitJ, end = (j + 1) * mesh / unitJ;
		void (^block)(void) = ^{ for (NSInteger x = start; x < end; x ++)
			for (NSInteger y = 1; y < mesh; y += 2) 
				[weakSelf gridToGridA:y * mesh + x B:(y - 1) * mesh + x]; };
		if (j < unitJ - 1) [self addOperation:block]; else block();
	}
	[self waitAllOperations];
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * mesh / unitJ, end = (j + 1) * mesh / unitJ;
		void (^block)(void) = ^{ for (NSInteger x = start; x < end; x ++)
			for (NSInteger y = 2; y < mesh; y += 2) 
				[weakSelf gridToGridA:y * mesh + x B:(y - 1) * mesh + x]; };
		if (j < unitJ - 1) [self addOperation:block]; else block();
	}
	[self waitAllOperations];
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * (mesh - 1) / unitJ, end = (j + 1) * (mesh - 1) / unitJ;
		void (^block)(void) = ^{ for (NSInteger x = start; x < end; x ++)
			for (NSInteger y = 1; y < mesh; y += 2)
				[weakSelf gridToGridA:y * mesh + x + 1 B:(y - 1) * mesh + x]; };
		if (j < unitJ - 1) [self addOperation:block]; else block();
	}
	[self waitAllOperations];
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * (mesh - 1) / unitJ, end = (j + 1) * (mesh - 1) / unitJ;
		void (^block)(void) = ^{ for (NSInteger x = start; x < end; x ++)
			for (NSInteger y = 2; y < mesh; y += 2)
				[weakSelf gridToGridA:y * mesh + x + 1 B:(y - 1) * mesh + x]; };
		if (j < unitJ - 1) [self addOperation:block]; else block();
	}
	[self waitAllOperations];
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * (mesh - 1) / unitJ, end = (j + 1) * (mesh - 1) / unitJ;
		void (^block)(void) = ^{ for (NSInteger x = start; x < end; x ++)
			for (NSInteger y = 1; y < mesh; y += 2)
				[weakSelf gridToGridA:y * mesh + x B:(y - 1) * mesh + x + 1]; };
		if (j < unitJ - 1) [self addOperation:block]; else block();
	}
	[self waitAllOperations];
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * (mesh - 1) / unitJ, end = (j + 1) * (mesh - 1) / unitJ;
		void (^block)(void) = ^{ for (NSInteger x = start; x < end; x ++)
			for (NSInteger y = 2; y < mesh; y += 2)
				[weakSelf gridToGridA:y * mesh + x B:(y - 1) * mesh + x + 1]; };
		if (j < unitJ - 1) [self addOperation:block]; else block();
	}
	[self waitAllOperations];
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif
// Step
	INC_PHASE
	unitJ = 8;
	Agent **popMap = _Pop;
	CGFloat vcnPRateOrg = runtimeParams.vcnPRate;
	NSUInteger *stCnt = statInfo.statistics->cnt,
		nSusc = stCnt[Susceptible] + stCnt[Asymptomatic] - stCnt[QuarantineAsym];
	if (nSusc > 0) runtimeParams.vcnPRate *= (CGFloat)worldParams.initPop / nSusc;
	NSMutableArray<NSValue *> *infectors[unitJ];
	NSMutableArray<NSValue *> *movers[unitJ];
	NSMutableArray<NSValue *> *warps[unitJ];
	NSMutableArray<NSValue *> *hists[unitJ];
	NSMutableArray<NSValue *> *tests[unitJ];
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * nCells / unitJ;
		NSInteger end = (j + 1) * nCells / unitJ;
		NSMutableArray<NSValue *> *infec = infectors[j] = NSMutableArray.new;
		NSMutableArray<NSValue *> *move = movers[j] = NSMutableArray.new;
		NSMutableArray<NSValue *> *warp = warps[j] = NSMutableArray.new;
		NSMutableArray<NSValue *> *hist = hists[j] = NSMutableArray.new;
		NSMutableArray<NSValue *> *test = tests[j] = NSMutableArray.new;
		void (^block)(void) = ^{
			StepInfo info;
			for (NSInteger i = start; i < end; i ++) {
				Agent **ap = popL + pRng[i].location;
				NSRange rng = pRng[i];
				for (NSInteger j = 0; j < rng.length; j ++) {
					Agent *a = ap[j];
					memset(&info, 0, sizeof(info));
					if (goHomeBack) going_back_home(a);
					else if (a->gathering != NULL) affect_to_agent(a->gathering, a);
					step_agent(a, rp, wp, goHomeBack, &info);
					if (info.moveFrom != info.moveTo) {
						[move addObject:
							[NSValue valueWithMoveToIdxInfo:(MoveToIdxInfo){a, info.moveTo}]];
						remove_from_list(a, popMap + info.moveFrom);
					}
					if (info.warpType != WarpNone) [warp addObject:[NSValue
						valueWithWarpInfo:(WarpInfo){a, info.warpType, info.warpTo}]];
					if (info.histType != HistNone) [hist addObject:[NSValue
						valueWithHistInfo:(HistInfo){a, info.histType, info.histDays}]];
					if (info.testType != TestNone) [test addObject:[NSValue
						valueWithTestInfo:(TestInfo){a, info.testType}]];
					if (a->newNInfects > 0) {
						[infec addObject:[NSValue valueWithInfect:
							(InfectionCntInfo){a->nInfects, a->nInfects + a->newNInfects}]];
						a->nInfects += a->newNInfects;
		}}}};
		if (j < unitJ - 1) [self addOperation:block];
		else block();
	}
	[self waitAllOperations];
	runtimeParams.vcnPRate = vcnPRateOrg;
	NSArray<NSArray <NSValue *> *> *histArray = [NSArray arrayWithObjects:hists count:unitJ];
	__weak StatInfo *weakStatInfo = statInfo;
	[self addOperation: ^{ for (NSInteger i = 0; i < unitJ; i ++)
		for (NSValue *v in histArray[i]) {
			HistInfo info = v.histInfoValue;
			[weakStatInfo cummulateHistgrm:info.type days:info.days];
		} }];
	for (NSInteger i = 0; i < unitJ; i ++) {
		for (NSValue *v in warps[i]) [self addNewWarp:v.warpInfoValue];
		for (NSValue *v in tests[i]) {
			TestInfo info = v.testInfoValue;
			[self testInfectionOfAgent:info.agent reason:info.reason];
		}
	}
	[self waitAllOperations];
	StepInfo info;
	for (Agent *a = _QList; a; a = a->next) {
		memset(&info, 0, sizeof(info));
		step_agent_in_quarantine(a, &worldParams, &info);
		if (info.warpType != WarpNone) [self addNewWarp:(WarpInfo){a, info.warpType, info.warpTo}];
		if (info.histType != HistNone) [statInfo cummulateHistgrm:info.histType days:info.histDays];
	}
	INC_PHASE
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif
	NSInteger nMoves = 0;
	for (NSInteger i = 0; i < unitJ; i ++) for (NSValue *value in movers[i]) {
		MoveToIdxInfo info = value.moveToIdxInfoValue;
		add_to_list(info.agent, _Pop + info.newIdx);
		nMoves ++;
	}
	NSUInteger testCount[NIntTestTypes];
	memset(testCount, 0, sizeof(testCount));
	[self deliverTestResults:testCount];
	for (NSValue *value in newWarpF.objectEnumerator) {
		WarpInfo info = value.warpInfoValue;
		Agent *a = info.agent;
		if (!a->isWarping) {
			a->isWarping = YES;
			switch (info.mode) {
				case WarpInside: case WarpToHospital: case WarpToCemeteryF:
				remove_agent(a, &worldParams, _Pop); break;
				case WarpBack: case WarpToCemeteryH:
				remove_from_list(a, &_QList); break;
				default: break;
			}
		}
		_WarpList[@(a->ID)] = value;
	}
	[newWarpF removeAllObjects];
	for (NSNumber *num in _WarpList.allKeys) {
		WarpInfo info = _WarpList[num].warpInfoValue;
		if (warp_step(info.agent, &worldParams, self, info.mode, info.goal))
			[_WarpList removeObjectForKey:num];
	}
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif
	BOOL finished = [statInfo calcStatWithTestCount:testCount infects:
		[NSArray arrayWithObjects:infectors count:unitJ]];
	[popLock unlock];
	runtimeParams.step ++;
	if (loopMode == LoopRunning) {
		if (finished) loopMode = LoopFinished;
		else if ([predicateToStop evaluateWithObject:statInfo])
			loopMode = LoopEndByCondition;
	}
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	mtime[tmIdx] += tm2 - tm0;
	if (mCount >= 500) {
		printf("%ld, ", ++ mCount2);
		for (NSInteger i = 0; i <= tmIdx; i ++) {
			printf("%8.2f%c", (double)mtime[i] / mCount, (i < tmIdx)? ',' : '\n');
			mtime[i] = 0;
		}
		mCount = 0;
	}
#endif
}
#ifdef NOGUI
- (void)startTimeLimitTimer {
	runtimeTimer = [NSTimer scheduledTimerWithTimeInterval:maxRuntime repeats:NO
		block:^(NSTimer * _Nonnull timer) { [self stop:LoopEndByTimeLimit]; }];
}
- (void)stopTimeLimitTimer {
	if (runtimeTimer != nil) {
		if (runtimeTimer.valid) [runtimeTimer invalidate];
		runtimeTimer = nil;
	}
}
#endif
#ifdef NOGUI
- (void)runningLoop {
	in_main_thread(^{ [self startTimeLimitTimer]; });
	[self forAllReporters:^(PeriodicReporter *rep) { [rep start]; }];
#else
- (void)runningLoopWithAnimeSteps:(NSInteger)animeSteps postProc:(void (^)(void))stepPostProc {
#endif
	while (loopMode == LoopRunning) {
		CGFloat startTime = get_uptime();
		@autoreleasepool{ [self doOneStep]; }
		CGFloat timePassed = get_uptime() - startTime;
		if (timePassed < 1.)
			stepsPerSec += (1. / timePassed - stepsPerSec) * 0.2;
		if (loopMode == LoopEndByCondition && scenarioIndex < scenario.count) {
			[self execScenario];
			loopMode = LoopRunning;
		}
		if (stopAtNDays > 0 && runtimeParams.step
			== stopAtNDays * worldParams.stepsPerDay - 1) {
			loopMode = LoopEndAsDaysPassed;
			break;
		}
#ifdef NOGUI
//		if (runtimeParams.step % 100 == 0) NSLog(@"%ld", runtimeParams.step);
		[self forAllReporters:^(PeriodicReporter *rep) { [rep sendReportPeriodic]; }];
		if (maxSPS > 0) {
			NSInteger usToWait = (1./maxSPS - timePassed) * 1e6;
#else
		if (runtimeParams.step % animeSteps == 0) {
			in_main_thread(stepPostProc);
			NSInteger usToWait = (1./30. - timePassed) * 1e6;
#endif
			usleep((uint32)((usToWait < 0)? 1 : usToWait));
		} else usleep(1);
	}
#ifdef NOGUI
//NSLog(@"runningLoop will stop %d.", loopMode);
	in_main_thread(^{ [self stopTimeLimitTimer]; });
	if (loopMode != LoopEndByUser) [self touch];
	[self forAllReporters:^(PeriodicReporter *rep) { [rep pause]; }];
	if (_stopCallBack != nil) _stopCallBack(loopMode);
#endif
}
- (void)goAhead {
	if (loopMode == LoopFinished) [self resetPop];
	else if (loopMode == LoopEndByCondition)
		[self execScenario];
}
#ifdef NOGUI
- (CGFloat)howMuchBusy {
	return (loopMode != LoopRunning)? 0. :
		(stepsPerSec < 1e-6)? 1e6 : 1. / stepsPerSec;
}
- (BOOL)touch {
	BOOL result;
	[_lastTLock lock];
	if ((result = (_worldKey != nil))) _lastTouch = NSDate.date;
	[_lastTLock unlock];
	return result;
}
- (void)start:(NSInteger)stopAt maxSPS:(CGFloat)maxSps priority:(CGFloat)prio {
	if (loopMode == LoopRunning) return;
	if (stopAt > 0) stopAtNDays = stopAt;
	maxSPS = maxSps;
	[self goAhead];
	loopMode = LoopRunning;
	NSThread *thread = [NSThread.alloc initWithTarget:self
		selector:@selector(runningLoop) object:nil];
	thread.threadPriority = fmax(0., NSThread.mainThread.threadPriority + prio);
	[thread start];
}
- (void)step {
	switch (loopMode) {
		case LoopRunning: return;
		case LoopFinished: case LoopEndByCondition: [self goAhead];
		default: [self doOneStep];
	}
	loopMode = LoopEndByUser;
	[self forAllReporters:^(PeriodicReporter *rep) { [rep sendReport]; }];
}
- (void)stop:(LoopMode)mode {
	if (loopMode == LoopRunning) loopMode = mode;
}
- (void)addReporter:(PeriodicReporter *)rep {
	if (reportersLock == nil) reportersLock = NSLock.new;
	[reportersLock lock];
	if (reporters == nil) {
		reporters = [NSMutableArray arrayWithObject:rep];
	} else [reporters addObject:rep];
	[reportersLock unlock];
}
- (void)removeReporter:(PeriodicReporter *)rep {
	[reportersLock lock];
	for (NSInteger i = reporters.count - 1; i >= 0; i --)
		if (reporters[i] == rep) { [reporters removeObjectAtIndex:i]; break; }
	[reportersLock unlock];
}
- (void)reporterConnectionWillClose:(int)desc {
	[reportersLock lock];
	for (NSInteger i = reporters.count - 1; i >= 0; i --)
		if ([reporters[i] connectionWillClose:desc])
			{ [reporters removeObjectAtIndex:i]; break; }
	[reportersLock unlock];
}
#endif
@end

@implementation NSValue (WorldExtension)
#define DEF_VAL(t,b,g) + (NSValue *)b:(t)info {\
	return [NSValue valueWithBytes:&info objCType:@encode(t)]; }\
- (t)g { t info; [self getValue:&info]; return info; }
DEF_VAL(MoveToIdxInfo, valueWithMoveToIdxInfo, moveToIdxInfoValue)
DEF_VAL(WarpInfo, valueWithWarpInfo, warpInfoValue)
DEF_VAL(HistInfo, valueWithHistInfo, histInfoValue)
DEF_VAL(TestInfo, valueWithTestInfo, testInfoValue)					
DEF_VAL(DistanceInfo, valueWithDistanceInfo, distanceInfo)			
@end