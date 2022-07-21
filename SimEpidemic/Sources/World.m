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
#import "Gatherings.h"
#ifdef NOGUI
#import "../../SimEpidemicSV/noGUI.h"
#import "../../SimEpidemicSV/PeriodicReporter.h"
#else
#import "Document.h"
#import "ScenPanel.h"
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

NSString *keyParameters = @"parameters", *keyScenario = @"scenario",
	*keyDaysToStop = @"daysToStop";

@interface World () {
#ifdef MEASURE_TIME
	unsigned long mtime[N_MTIME];
	NSInteger mCount, mCount2;
#endif
	NSInteger nPop, nMesh;
	Agent **pop;
	NSRange *pRange;
	CGFloat stepsPerSec;
	NSMutableDictionary<NSNumber *, NSValue *> *newWarpF;
	NSMutableDictionary<NSNumber *, NSNumber *> *testees;
	NSMutableSet *trcVcnSet;	// tracing vaccination subjects
	NSLock *newWarpLock, *testeesLock;
	NSLock *memPoolLock, *tmemLock, *cmemLock, *gmemLock;
	NSMutableArray<NSMutableData *> *memPool;
	TestEntry *freeTMem;
	ContactInfo *freeCMem;
	Gathering *freeGMem;
	int ctxVariantType, ctxVaccineType;
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
- (VariantInfo *)variantInfoP { return variantInfo; }
- (CGFloat)stepsPerSec { return stepsPerSec; }
- (BOOL)running { return loopMode == LoopRunning || loopMode == LoopPauseByCondition; }
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
- (int)variantTypeFromName:(NSString *)varName {
	for (int idx = 0; idx < _variantList.count; idx ++)
		if ([varName isEqualToString:_variantList[idx][@"name"]]) return idx;
	return -1;
}
- (int)vcnTypeFromName:(NSString *)vcnName {
	for (int idx = 0; idx < _vaccineList.count; idx ++)
		if ([vcnName isEqualToString:_vaccineList[idx][@"name"]]) return idx;
	return -1;
}
static void force_infect(Agent *a, int vType) {
	a->health = Asymptomatic; a->daysInfected = a->daysDiseased = 0;
	a->virusVariant = vType;
}
- (void)addInfected:(NSInteger)n location:(InfecLocation)loc variant:(int)variantType {
	if (n <= 0) return;
	Agent **cdd = malloc(sizeof(void *) * nPop);
	NSInteger k = 0;
	for (NSInteger i = 0; i < nPop; i ++) {
		Agent *a = _agents + i;
		if (!a->isOutOfField && a->health == Susceptible) cdd[k ++] = a;
	}
	if (k == 0) return;
	if (n > k) n = k;
	if (loc == IfcLocScattered) {
		for (NSInteger i = 0; i < n; i ++) {
			NSInteger j = (random() % (k - i)) + i;
			if (j != i) { Agent *a = cdd[i]; cdd[i] = cdd[j]; cdd[j] = a; }
		}
	} else {
		NSPoint pt = (loc == IfcLocRandomCluster)?
			(NSPoint){d_random(), d_random()} : (NSPoint){.5, .5};
		pt.x *= worldParams.worldSize;
		pt.y *= worldParams.worldSize;
		CGFloat *ds = malloc(sizeof(CGFloat) * n);
		NSInteger kk = 0, jj;
		for (NSInteger i = 0; i < k; i ++) {
			Agent *a = cdd[i];
			CGFloat d = hypot(a->x - pt.x, a->y - pt.y);
			for (jj = kk; jj > 0; jj --) if (d > ds[jj - 1]) break;
			if (jj < n) {
				for (NSInteger j = (kk < n)? kk : n - 1; j > jj; j --) {
					cdd[j] = cdd[j - 1];
					ds[j] = ds[j - 1];
				}
				cdd[jj] = a;
				ds[jj] = d;
				if (kk < n) kk ++;
			}
		}
		free(ds);
	}
	for (NSInteger i = 0; i < n; i ++) force_infect(cdd[i], variantType);
	free(cdd);
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
- (NSString *)varNameFromKey:(NSString *)key vcnTypeReturn:(int *)vcnTypeP {
	NSArray<NSString *> *words = [key componentsSeparatedByString:@" "];
	*vcnTypeP = (words.count < 2)? 0 : [self vcnTypeFromName:words[1]];
	return (words.count > 0)? words[0] : nil;
}
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
		vcnQueue = realloc(vcnQueue, sizeof(NSInteger) * nPop * N_VCN_QUEQUE);
		ageSpanIDs = realloc(ageSpanIDs, sizeof(NSInteger) * nPop);
		agentsRnd = realloc(agentsRnd, sizeof(CGFloat) * nPop);
	}
	memset(_agents, 0, sizeof(Agent) * nPop);
	if (testQueTail != nil) {
		[tmemLock lock];
		testQueTail->next = freeTMem;
		freeTMem = testQueHead;
		[tmemLock unlock];
		testQueTail = testQueHead = NULL;
	}
	_QList = _CList = NULL;
	[_WarpList removeAllObjects];
}
#ifdef NOGUI
- (void)forAllReporters:(void (^)(PeriodicReporter *))block {
	if (reporters == nil) return;
	[reportersLock lock];
	for (PeriodicReporter *rep in reporters) block(rep);
	[reportersLock unlock];
}
#endif
static NSPoint random_point_in_hospital(CGFloat worldSize) {
	return (NSPoint){
		(d_random() * .248 + 1.001) * worldSize,
		(d_random() * .458 + 0.501) * worldSize};
}
- (void)setupVaxenAndVariantsFromLists {
	NSInteger nVariants, nVaccines;
	if ((nVariants = _variantList.count) > MAX_N_VARIANTS) nVariants = MAX_N_VARIANTS;
	NSString *vrNames[nVariants];
	for (NSInteger i = 0; i < nVariants; i ++) vrNames[i] = _variantList[i][@"name"];
	VariantInfo *rInfo = variantInfo;
	for (NSInteger i = 0; i < nVariants; i ++) {
		NSDictionary *dict = _variantList[i];
		NSNumber *num;
		rInfo[i].reproductivity = ((num = dict[@"reproductivity"]))? num.doubleValue : 1.;
		rInfo[i].toxicity = ((num = dict[@"toxicity"]))? num.doubleValue : 1.;
		for (NSInteger j = 0; j < nVariants; j ++)
			rInfo[i].efficacy[j] = [dict[vrNames[j]] doubleValue];
	}
	if ((nVaccines = _vaccineList.count) > MAX_N_VAXEN) nVaccines = MAX_N_VAXEN;
	VaccineInfo *xInfo = vaccineInfo;
	for (NSInteger i = 0; i < nVaccines; i ++) {
		NSDictionary *dict = _vaccineList[i];
		xInfo[i].interval = [dict[@"intervalOn"] boolValue]?
			[dict[@"intervalDays"] integerValue] : 0;
		for (NSInteger j = 0; j < nVariants; j ++)
			xInfo[i].efficacy[j] = [dict[vrNames[j]] doubleValue];
	}
}
- (void)sortVaccineQueue:(NSInteger *)que comp:(CGFloat (^)(Agent *a))getValue {
	CGFloat *d = malloc(sizeof(CGFloat) * nPop);
	for (NSInteger i = 0; i < nPop; i ++) { que[i] = i; d[i] = getValue(_agents + i); }
	qsort_b(que, nPop, sizeof(NSInteger),
		^int(const void *p1, const void *p2) {
			CGFloat v1 = d[*((NSInteger *)p1)], v2 = d[*((NSInteger *)p2)]; 
			return (v1 < v2)? -1 : (v1 > v2)? 1 : 0;
	});
	free(d);
}
- (void)vcnQueueRandom:(NSInteger *)queue {
	for (NSInteger i = 0; i < nPop; i ++) queue[i] = i;
	for (NSInteger i = 0; i < nPop - 1; i ++) {
		NSInteger j = (random() % (nPop - i)) + i, k;
		if (j != i) { k = queue[i]; queue[i] = queue[j]; queue[j] = k; }
	}
}
- (void)vcnQueueFromCenter:(NSInteger *)queue {
	CGFloat cx = worldParams.worldSize / 2.;
	[self sortVaccineQueue:queue comp:(worldParams.wrkPlcMode == WrkPlcNone)?
		^(Agent *a) { return hypot(a->x - cx, a->y - cx); } :
		^(Agent *a) { return hypot(a->orgPt.x - cx, a->orgPt.y - cx); }];
}
- (void)vcnQueuePopDens:(NSInteger *)queue {
	NSBitmapImageRep *imgRep = make_bm_with_image(_popDistImage);
	float *pd = (float *)imgRep.bitmapData;
	CGFloat aa = (CGFloat)PopDistMapRes / worldParams.worldSize;
	[self sortVaccineQueue:queue comp:^(Agent *a) {
		NSInteger ix = a->orgPt.x * aa, iy = a->orgPt.y * aa;
		return 1. - (CGFloat)pd[iy * PopDistMapRes + ix]; }];
}
- (void)resetBoostQueue {
	if (vcnQueIdx[VcnPrBooster] == 0)
		[self sortVaccineQueue:vcnQueue + VcnPrBooster * nPop comp:^CGFloat(Agent *a)
			{ CGFloat fdd = a->firstDoseDate; return (fdd >= 0.)? fdd : MAXFLOAT; }];
}
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
- (void)resetVaccineQueue {
	WorldParams *wp = &worldParams;
	RuntimeParams *rp = &runtimeParams;
	for (NSInteger i = 0; i < nPop; i ++) {
		_agents[i].vaccineType = -1;
		_agents[i].vaccineTicket = NO;
		_agents[i].forVcn = VcnAccept;
	}
	NSInteger nAntiVcnPopTotal = 0, antiVcnNPop[nAgeSpans];
	for (NSInteger i = 0; i < nAgeSpans; i ++)
		nAntiVcnPopTotal += antiVcnNPop[i] = round(spanNPop[i] * (1. - rp->vcnFnlRt[i].rate));
	NSInteger nClstrs = pow(nAntiVcnPopTotal / 2, wp->avClstrGran / 100.);
	for (NSInteger spanIdx = 0; spanIdx < nAgeSpans; spanIdx ++) {
		NSInteger nAntiVcnPop = antiVcnNPop[spanIdx];
		if (nAntiVcnPop <= 0) continue;
		NSInteger nNoVcnNorTest = round(nAntiVcnPop * (1. - wp->avTestRate / 100.));
		NSInteger nAgentsInClstr = nAntiVcnPop * wp->avClstrRate / 100.;
		NSInteger nClstrCols = ceil(sqrt(nClstrs)),
			nClstrRows = (nClstrs + nClstrCols - 1) / nClstrCols,
			idx = 0, lstIdx = 0;
		NSInteger *avAgentIDs = malloc(sizeof(NSInteger) * nAntiVcnPop);
		for (NSInteger i = 0; i < nClstrs; i ++) {
			NSInteger nAgents = (nAgentsInClstr - idx) / (nClstrs - i);
			if (nAgents <= 0) continue;
			NSPoint pt = {
				(i % nClstrCols + .5) * worldParams.worldSize / nClstrCols,
				(i / nClstrCols + .5) * worldParams.worldSize / nClstrRows
			};
			CGFloat ay = pt.y * wp->mesh / wp->worldSize, ax = pt.x * wp->mesh / wp->worldSize;
			NSInteger iy = floor(ay), ix = floor(ax);
			if (iy < 0) iy = 0; else if (iy >= wp->mesh) iy = wp->mesh - 1;
			if (ix < 0) ix = 0; else if (ix >= wp->mesh) ix = wp->mesh - 1;
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
				for (Agent *a = _Pop[(ky + v) * wp->mesh + kx + u]; a != NULL; a = a->next)
					if (a->ageSpanIndex == spanIdx && a->forVcn != VcnReject)
						[candidates addObject:[NSValue valueWithDistanceInfo:
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
						case IdxDown: if (jy < wp->mesh - 1) 
							{ ky = ++ jy; kx = ix; ih = 1; iw = jx - ix + 1; doItMore = YES; } break;
						case IdxUp: if (iy > 0)
							{ ky = -- iy; kx = ix; ih = 1; iw = jx - ix + 1; doItMore = YES; } break;
						case IdxRight: if (jx < wp->mesh - 1)
							{ kx = ++ jx; ky = iy; iw = 1; ih = jy - iy + 1; doItMore = YES; } break;
						case IdxLeft: if (ix > 0)
							{ kx = -- ix; ky = iy; iw = 1; ih = jy - iy + 1; doItMore = YES; }
					}
					orderIdx = (orderIdx + 1) % 4;
				}
			}
			for (NSInteger i = 0; i < nAgents && i < members.count; i ++) {
				NSInteger ID = members[i].distanceInfo.agent->ID;
				_agents[ID].forVcn = VcnReject;
				avAgentIDs[lstIdx ++] = ID;
			}
			idx += nAgents;
		}
		if (idx < nAntiVcnPop) {
			NSInteger nRestAgents = spanNPop[spanIdx] - nAgentsInClstr;
			NSInteger *agentIDs = malloc(sizeof(NSInteger) * nRestAgents);
			for (NSInteger i = 0, j = 0; i < nPop && j < nRestAgents; i ++)
				if (_agents[i].ageSpanIndex == spanIdx && _agents[i].forVcn != VcnReject)
					agentIDs[j ++] = i;
			for (NSInteger i = 0; i < nAntiVcnPop - idx; i ++) {
				NSInteger j = random() % (nRestAgents - i);
				_agents[agentIDs[j]].forVcn = VcnReject;
				avAgentIDs[lstIdx ++] = agentIDs[j];
				if (j < nRestAgents - i - 1) agentIDs[j] = agentIDs[nRestAgents - i - 1];
			}
			free(agentIDs);
		}
		if (nNoVcnNorTest >= nAntiVcnPop) {
			for (NSInteger i = 0; i < nAntiVcnPop; i ++)
				_agents[avAgentIDs[i]].forVcn = VcnNoTest;
		} else if (nNoVcnNorTest > 0) {
			for (NSInteger i = 0; i < nNoVcnNorTest; i ++) {
				NSInteger j = random() % (nAntiVcnPop - i);
				_agents[avAgentIDs[j]].forVcn = VcnNoTest;
				if (j < nAntiVcnPop - i - 1) avAgentIDs[j] = avAgentIDs[nAntiVcnPop - i - 1];
			}
		}
		free(avAgentIDs);
	}
	NSInteger *queue = vcnQueue + VcnPrRandom * nPop;
	for (NSInteger i = 0; i < nPop; i ++) queue[i] = i;
	for (NSInteger i = 0; i < nPop - 1; i ++) {
		NSInteger j = (random() % (nPop - 1 - i)) + i;
		if (j != i) { NSInteger k = queue[i]; queue[i] = queue[j]; queue[j] = k; }
	}
	[self sortVaccineQueue:vcnQueue + VcnPrOlder * nPop
		comp:^(Agent *a) { return - a->age; }];
	[self vcnQueueFromCenter:vcnQueue + VcnPrCentral * nPop];
	queue = vcnQueue + VcnPrPopDens * nPop;
	switch (worldParams.wrkPlcMode) {
		case WrkPlcCentered: [self vcnQueueFromCenter:queue]; break;
		case WrkPlcPopDistImg: [self vcnQueuePopDens:queue]; break;
		default: [self vcnQueueRandom:queue];
	}
	memcpy(vcnQueue + VcnPrBooster * nPop, vcnQueue + VcnPrRandom * nPop,
		sizeof(NSInteger) * nPop);
	memset(vcnQueIdx, 0, sizeof(vcnQueIdx));
	memset(vcnSubjRem, 0, sizeof(vcnSubjRem));
}
- (void)organizeAgeSpanInfo {
	memset(spanNPop, 0, sizeof(spanNPop));
	for (nAgeSpans = 0; nAgeSpans < MAX_N_AGE_SPANS; nAgeSpans ++)
		if (initParams.vcnFnlRt[nAgeSpans].upperAge >= 150) { nAgeSpans ++; break; }
	for (NSInteger i = 0; i < nPop; i ++) {
		Agent *a = &_agents[i];
		int sIdx = 0;
		for (; sIdx < nAgeSpans; sIdx ++)
			if (a->age < initParams.vcnFnlRt[sIdx].upperAge + 1) break;
		if (sIdx >= nAgeSpans) sIdx = nAgeSpans - 1;
		a->ageSpanIndex = sIdx;
		spanNPop[sIdx] ++;
	}
	ageSpanIdxs[0] = 0;
	for (NSInteger i = 0; i < nAgeSpans - 1; i ++)
		ageSpanIdxs[i + 1] = ageSpanIdxs[i] + spanNPop[i];
	NSInteger idx[nAgeSpans];
	memset(idx, 0, sizeof(idx));
	for (NSInteger i = 0; i < nPop; i ++) {
		int span = _agents[i].ageSpanIndex;
		ageSpanIDs[ageSpanIdxs[span] + (idx[span] ++)] = i;
	}
}
#define N_AGE_BANDS 104
static NSInteger AgePopSize[N_AGE_BANDS] = {	// 2021/3/1 Tokyo
// https://www.toukei.metro.tokyo.lg.jp/juukiy/2021/jy21q10601.htm
	95975, 99101, 103773, 104797, 107163, 108487, 105920, 106118, 103586, 102899,
	104775, 103597, 103591, 102340, 100832, 96638, 100756, 100955, 105038, 112672,
	120006, 127282, 140154, 159382, 166432, 168263, 178101, 170612, 173084, 172862,
	168955, 168514, 175146, 177028, 178665, 183927, 190680, 190906, 189606, 189371,
	192704, 198755, 203002, 205724, 210132, 214166, 227010, 235031, 231145, 228018,
	221382, 217032, 213949, 217545, 157671, 200787, 185100, 171046, 160955, 152337,
	148371, 141566, 138486, 127619, 127979, 129708, 128497, 130110, 138327, 142374,
	153823, 176341, 174508, 176877, 119524, 105249, 127560, 135271, 128519, 126580,
	113767, 96597, 90751, 96408, 88884, 86876, 71570, 66662, 59730, 49570, 41908,
	35028, 29471, 23645, 18724, 14969, 10446, 7535, 5301, 3867, 2614, 1586, 962, 1448 
};
static void random_ages(CGFloat *ages, NSInteger n) {
	NSInteger sum = 0, nn = n, agePop[N_AGE_BANDS];
	for (NSInteger i = 0; i < N_AGE_BANDS; i ++) sum += AgePopSize[i];
	for (NSInteger i = 0; i < N_AGE_BANDS; i ++) {
		agePop[i] = (sum > 0)? (nn * AgePopSize[i] + sum / 2) / sum : 0;
		sum -= AgePopSize[i];
		nn -= agePop[i];
	}
//#ifdef DEBUG
//	sum = 0;
//	for (NSInteger i = 0; i < N_AGE_BANDS; i ++) {
//		printf("%ld,", agePop[i]);
//		sum += agePop[i];
//	}
//	printf("\n%ld\n", sum);
//#endif
	for (NSInteger i = 1; i < N_AGE_BANDS; i ++) agePop[i] += agePop[i - 1];
	for (NSInteger i = 0, j = 0; i < n; i ++) {
		while (i >= agePop[j] && j < N_AGE_BANDS - 1) j ++;
		ages[i] = j + d_random();
	}
	for (NSInteger i = 0; i < n - 1; i ++) {
		NSInteger j = (random() % (n - i)) + i;
		if (j != i) { CGFloat v = ages[i]; ages[i] = ages[j]; ages[j] = v; }
	}
}
- (void)setupPopDistMapData {
	NSBitmapImageRep *imgRep = make_bm_with_image(_popDistImage);
	float *pd = (float *)imgRep.bitmapData;
	if (popDistMapData == NULL)
		popDistMapData = (float *)malloc(sizeof(float) * PopDistMapRes * PopDistMapRes);
	if (worldParams.popDistMapLog2Gamma != 0.) {
		float gamma = powf(2., worldParams.popDistMapLog2Gamma);
		for (NSInteger i = 0; i < PopDistMapRes * PopDistMapRes; i ++)
			popDistMapData[i] = powf(pd[i], gamma);
	} else memcpy(popDistMapData, pd, sizeof(float) * PopDistMapRes * PopDistMapRes);
}
- (void)makeDistribution:(NSPoint *)pts n:(NSInteger)n {
	pop_dist_alloc(0, 0, PopDistMapRes, pts, n, popDistMapData);
	CGFloat a = (CGFloat)worldParams.worldSize / PopDistMapRes;
	for (NSInteger i = 0; i < n; i ++) {
		pts[i].x = pts[i].x * a + .5;
		pts[i].y = (worldParams.worldSize - 1. - pts[i].y * a) + .5;
	}
}
- (void)setupHomeWithMap {
	NSPoint *pts = malloc(sizeof(NSPoint) * worldParams.initPop);
	[self makeDistribution:pts n:worldParams.initPop];
	for (NSInteger i = 0; i < worldParams.initPop; i ++) {
		NSInteger j = random() % (worldParams.initPop - i) + i;
		_agents[i].orgPt = pts[j];
		_agents[i].x = pts[j].x;
		_agents[i].y = pts[j].y;
		if (i != j) pts[j] = pts[i];
	}
	free(pts);
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
	if (worldParams.wrkPlcMode == WrkPlcPopDistImg) [self setupPopDistMapData];

	CGFloat *ages = malloc(sizeof(CGFloat) * nPop);
	random_ages(ages, nPop);
	NSInteger nDist = runtimeParams.dstOB / 100. * nPop;
	for (NSInteger i = 0; i < nPop; i ++) {
		Agent *a = &_agents[i];
		reset_agent(a, ages[i], &runtimeParams, &worldParams);
		a->ID = i;
		a->distancing = (i < nDist);
		agentsRnd[i] = d_random();
	}
	free(ages);
	[self organizeAgeSpanInfo];
	if (worldParams.wrkPlcMode == WrkPlcPopDistImg) [self setupHomeWithMap];
	[self resetRegGatInfo];

	NSInteger nn = nPop * worldParams.gatSpotFixed / 1000.;
	Agent *ags = _agents;
	if (nn > 0) {
		NSPoint *pp = malloc(sizeof(NSPoint) * nn);
		if (worldParams.wrkPlcMode == WrkPlcPopDistImg)
			[self makeDistribution:pp n:nn];
		else for (NSInteger i = 0; i < nn; i ++) pp[i] =
			(NSPoint){d_random() * worldParams.worldSize, d_random() * worldParams.worldSize};
		gatSpotsFixed = [NSData dataWithBytesNoCopy:pp
			length:sizeof(NSPoint) * nn freeWhenDone:YES];
	} else gatSpotsFixed = nil;
#ifdef DEBUG
	printf("Fixed gathering spots = %ld\n", nn);
#endif

	PopulationHConf pconf = { 0,
		nPop * worldParams.infected / 100, 0,
		nPop * worldParams.recovered / 100, 0,
	}, *pconfp = &pconf;
	nn = pconf.asym + pconf.recv;
	if (nn > nPop) pconf.recv = (nn = nPop) - pconf.asym;
	pconf.susc = nPop - nn;
	NSInteger *ibuf = malloc(sizeof(NSInteger) * nPop);
	for (NSInteger i = 0; i < nPop; i ++) ibuf[i] = i;
	for (NSInteger i = 0; i < nn; i ++) {
		NSInteger j = random() % (nPop - i) + i, idx = ibuf[j];
		if (j != i) ibuf[j] = ibuf[i];
		Agent *a = &ags[idx];
		if (i < pconfp->asym) {
			a->daysInfected = d_random() * fmin(a->daysToRecover, a->daysToDie);
			if (a->daysInfected < a->daysToOnset) a->health = Asymptomatic;
			else {
				a->health = Symptomatic;
				a->daysDiseased = a->daysInfected - a->daysToOnset;
				pconfp->symp ++;
			}
			a->virusVariant = 0;
		} else {
			a->health = Recovered;
			a->imExpr = d_random() * runtimeParams.imnMaxDur;
			a->daysInfected = d_random() * a->imExpr;
			a->virusVariant = 0;
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
	[self setupVaxenAndVariantsFromLists];
	[self resetVaccineQueue];
	runtimeParams.step = 0;
	[statInfo reset:pconf];
	[popLock unlock];
	scenarioIndex = 0;
	paramChangers = NSMutableDictionary.new;
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
- (void)applyWorldSize {
	WorldParams *orgP = &worldParams, *newP = &tmpWorldParams;
	if (orgP->worldSize == newP->worldSize) return;
	[popLock lock];
	CGFloat mag = (CGFloat)newP->worldSize / orgP->worldSize;
	NSInteger nPop = orgP->initPop, unitJ = nCores; if (unitJ > 20) unitJ = 20;
	Agent *agents = _agents;
	NSMutableArray *maa = NSMutableArray.new;
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * nPop / unitJ, end = (j + 1) * nPop / unitJ;
		NSMutableArray *ma = NSMutableArray.new;
		[maa addObject:ma];
		[self addOperation:^{ for (NSInteger i = start; i < end; i ++) {
			Agent *a = &agents[i];
			NSInteger orgIdx = index_in_pop(a->x, a->y, orgP);
			a->x *= mag; a->y *= mag; a->vx *= mag; a->vy *= mag;
			a->orgPt.x *= mag; a->orgPt.y *= mag;
			if (!a->isOutOfField) {
				NSInteger newIdx = index_in_pop(a->x, a->y, newP);
				if (orgIdx != newIdx) [ma addObject:@[@(i), @(orgIdx), @(newIdx)]];
		}}}];
	}
	for (Gathering *gat = gatherings; gat; gat = gat->next) {
		gat->p.x *= mag; gat->p.y *= mag; gat->size *= mag;
	}
	for (NSNumber *key in _WarpList.allKeys) {
		WarpInfo info = _WarpList[key].warpInfoValue;
		info.goal.x *= mag; info.goal.y *= mag;
		_WarpList[key] = [NSValue valueWithWarpInfo:info];
	}
	if (gatSpotsFixed != nil) {
		NSInteger len = gatSpotsFixed.length;
		NSPoint *pt = malloc(len);
		memcpy(pt, gatSpotsFixed.bytes, len);
		for (NSInteger i = 0; i < len / sizeof(NSPoint); i ++) {
			pt[i].x *= mag; pt[i].y *= mag;
		}
		gatSpotsFixed = [NSData dataWithBytesNoCopy:pt length:len freeWhenDone:YES];
	}
	for (NSMutableArray *gatList in regGatInfo.objectEnumerator)
	for (NSInteger i = 0; i < gatList.count; i ++) {
		NSDictionary *item = gatList[i];
		NSPoint pt = ((NSValue *)item[@"point"]).pointValue;
		pt.x = mag; pt.y *= mag;
		[gatList replaceObjectAtIndex:i withObject:
			@{@"point":[NSValue valueWithPoint:pt], @"member":item[@"member"]}];
	}
	[self waitAllOperations];
	for (NSArray *arr in maa) for (NSArray<NSNumber *> *vec in arr) {
		Agent *a = &agents[vec[0].integerValue];
		remove_from_list(a, &_Pop[vec[1].integerValue]);
		add_to_list(a, &_Pop[vec[2].integerValue]);
	}
	worldParams.worldSize = tmpWorldParams.worldSize;
	[popLock unlock];
}
MutableDictArray default_variants(void) {
	return [NSMutableArray arrayWithObject:
		[NSMutableDictionary dictionaryWithDictionary:
		@{@"name":@"Original", @"reproductivity":@(1.),
			@"toxicity":@(1.),@"Original":@(1.)}]];
}
MutableDictArray default_vaccines(void) {
	return [NSMutableArray arrayWithObject:
		[NSMutableDictionary dictionaryWithDictionary:
		@{@"name":@"PfBNT", @"intervalOn":@YES, @"intervalDays":@(21),@"Original":@(1.)}]];
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
	_variantList = default_variants();
	_vaccineList = default_vaccines();
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
	free(vcnQueue);
	free(ageSpanIDs);
	self.popDistImage = nil;
	if (popDistMapData != NULL) free(popDistMapData);
//	MY_LOG("Memory for world %@ was discarded.", _ID)
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
#define TEST_DUMPER 0.9
- (void)deliverTestResults:(NSUInteger *)testCount {
	// check the results of tests
	CGFloat maxT = worldParams.initPop
		* runtimeParams.tstCapa / 1000. / worldParams.stepsPerDay;
	NSInteger cTmLatest = runtimeParams.step - runtimeParams.tstProc * worldParams.stepsPerDay,
		cTmOldest = cTmLatest - runtimeParams.tstDlyLim * worldParams.stepsPerDay, 
		maxTests = maxT;
	if (maxT - maxTests > d_random()) maxTests ++;
	if (runtimeParams.trcOpe != TrcTst) trcVcnSet = NSMutableSet.new;
	for (TestEntry *entry = testQueHead; entry != NULL; entry = testQueHead) {
		if (entry->timeStamp > cTmLatest || maxTests <= 0) break;
		Agent *a = entry->agent;
		if (entry->timeStamp > cTmOldest && a->x < worldParams.worldSize) {
			maxTests --;
			if (entry->isPositive) {
				testCount[TestPositive] ++;
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
		}
		entry->agent->inTestQueue = NO;
		if ((testQueHead = entry->next) != NULL) testQueHead->prev = NULL;
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
			(d_random() < 1. - pow(1. - runtimeParams.tstSens / 100.,
				variantInfo[agent->virusVariant].reproductivity)) :
			(d_random() > runtimeParams.tstSpec / 100.);
		agent->lastTested = entry->timeStamp = runtimeParams.step;
		entry->agent = agent;
		if ((entry->prev = testQueTail) != NULL) testQueTail->next = entry;
		else testQueHead = entry;
		entry->next = NULL;
		testQueTail = entry;
		agent->inTestQueue = YES;
	}
	[testees removeAllObjects];
	[testeesLock unlock];
	for (NSInteger i = TestAsSymptom; i < TestPositive; i ++)
		testCount[TestTotal] += testCount[i];
}
- (void)gridToGridA:(NSInteger)iA B:(NSInteger)iB {
	Agent **apA = pop + pRange[iA].location, **apB = pop + pRange[iB].location;
	for (NSInteger j = 0; j < pRange[iA].length; j ++)
		[self interactsA:apA[j] Bs:apB n:pRange[iB].length];
	[self avoidGatherings:iB agents:apA n:pRange[iA].length];
	[self avoidGatherings:iA agents:apB n:pRange[iB].length];
}
void set_dist_values(DistInfo *dp, NSArray<NSNumber *> *arr, CGFloat steps) {
	dp->min += (arr[0].doubleValue - dp->min) / steps;
	dp->max += (arr[1].doubleValue - dp->max) / steps;
	dp->mode += (arr[2].doubleValue - dp->mode) / steps;
}
void set_reg_gat_value(MutableDictArray gatInfo, NSString *key, NSNumber *goal, CGFloat steps) {
//NSLog(@"SRGV %@ %@ %.2f", key, goal, steps);
	NSArray<NSString *> *words = [key componentsSeparatedByString:@" "];
	if (words.count < 3) return;
	NSString *attr = words[1], *name = words[2];
	NSMutableDictionary *item = nil;
	if ([name hasPrefix:@"__"]) {
		NSInteger idx = [name substringFromIndex:2].integerValue;
		if (idx >= 0 && idx < gatInfo.count) item = gatInfo[idx];
	} else for (NSMutableDictionary *elm in gatInfo)
		if ([name isEqualToString:elm[@"name"]]) { item = elm; break; }
	if (item == nil) return;
	CGFloat value = [item[attr] doubleValue];
	value += (goal.doubleValue - value) / steps;
	item[attr] = @(value);
//NSLog(@"SRGV %@ %@ <- %.2f", name, attr, value);
}
static BOOL give_vcn_ticket_if_possible(Agent *a, int vcnType, VaccinePriority priority) {
	if ((a->health == Susceptible || (a->health == Asymptomatic && !a->isOutOfField)
		|| (a->health == Vaccinated && priority == VcnPrBooster))
		&& a->forVcn == VcnAccept && !a->vaccineTicket
		&& (priority == VcnPrBooster || a->firstDoseDate < 0)) {
		a->vaccineTicket = YES; a->vaccineType = vcnType; return YES;
	} else return NO;
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

//	Apply parameter changers as in Scenario
	if (paramChangers != nil && paramChangers.count > 0) {
		NSMutableArray<NSString *> *keyToRemove = NSMutableArray.new;
		for (NSString *key in paramChangers) {
			NSArray<NSNumber *> *entry = paramChangers[key];
			DistInfo *targetDist = NULL;
			CGFloat *targetVar = NULL,
				stepsLeft = entry[1].doubleValue * worldParams.stepsPerDay - runtimeParams.step;
			NSNumber *idxNum;
			BOOL isRegGat = NO;
			if (![key hasPrefix:@"vaccine"]) {
				if (!(isRegGat = [key hasPrefix:@"regGat "])) {
					NSInteger idx = paramIndexFromKey[key].integerValue;
					if (idx < IDX_D) targetVar = &runtimeParams.PARAM_F1 + idx;
					else targetDist = &runtimeParams.PARAM_D1 + idx - IDX_D;
				}
			} else if ((idxNum = paramIndexFromKey[key]) != nil) {
				NSInteger idx = idxNum.integerValue;
				if (idx >= IDX_R && idx < IDX_E)
					targetVar = &worldParams.PARAM_R1 + idx - IDX_R;
			} else {
				int vcnType;
				NSString *varName = [self varNameFromKey:key vcnTypeReturn:&vcnType];
				if (vcnType < 0) continue;
				VaccinationInfo *vInfo = &runtimeParams.vcnInfo[vcnType];
				if ([varName hasSuffix:@"Rate"]) targetVar = &vInfo->performRate;
				else if ([varName hasSuffix:@"Regularity"]) targetVar = &vInfo->regularity;
			}
			if (stepsLeft <= 1.) {
				[keyToRemove addObject:key];
				stepsLeft = 1.;
			}
			if (targetVar != NULL)
				*targetVar += (entry[0].doubleValue - *targetVar) / stepsLeft;
			else if (targetDist != NULL)
				set_dist_values(targetDist, (NSArray<NSNumber *> *)entry[0], stepsLeft);
			else if (isRegGat)
				set_reg_gat_value(_gatheringsList, key, entry[0], stepsLeft);
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
	if (!goHomeBack) [self manageGatherings];
	ParamsForStep prms = { &runtimeParams, &worldParams, variantInfo, vaccineInfo };

//	Vaccination
	for (NSInteger idx = 0; idx < _vaccineList.count; idx ++) {
		VaccinationInfo *vp = &prms.rp->vcnInfo[idx];
		if (vp->performRate <= 0. || vp->priority == VcnPrNone) continue;
		vcnSubjRem[idx] += nPop * vp->performRate / 1000. / prms.wp->stepsPerDay;
		NSInteger n = vcnSubjRem[idx];
		if (n == 0) continue;
		vcnSubjRem[idx] -= n;
		if (trcVcnSet != nil && idx == prms.rp->trcVcnType) for (NSNumber *num in trcVcnSet)
			if (give_vcn_ticket_if_possible(_agents + num.integerValue, (int)idx, VcnPrNone))
				if ((-- n) < 0) break;
		NSInteger *vQue = vcnQueue + vp->priority * nPop, ix = vcnQueIdx[vp->priority];
		for (NSInteger cnt = 0, k = 0; cnt < n && k < nPop; ix = (ix + 1) % nPop, k ++) {
			NSInteger jx = (vp->priority == VcnPrRandom || vp->regularity >= 100. ||
				d_random() < vp->regularity / 100.)? ix : (ix + 1 + random() % (nPop / 2)) % nPop;
			if (give_vcn_ticket_if_possible(_agents + vQue[jx], (int)idx, vp->priority)) cnt ++;
		}
		vcnQueIdx[vp->priority] = ix;
	}
	[self waitAllOperations];
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif

// Interaction among agents
	unitJ = isARM? 4 : (nCores <= 8)? nCores - 1 : 8;
    NSRange *pRng = pRange;
    for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * nCells / unitJ;
		NSInteger end = (j + 1) * nCells / unitJ;
		void (^block)(void) = ^{
			for (NSInteger i = start; i < end; i ++) {
				NSRange rng = pRng[i];
				Agent **ap = popL + rng.location;
				for (NSInteger j = 1; j < rng.length; j ++)
					[self interactsA:ap[j] Bs:ap n:j];
				[self avoidGatherings:i agents:ap n:rng.length];
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
	NSMutableArray<NSValue *> *infectors[unitJ], *movers[unitJ], *warps[unitJ],
		*hists[unitJ], *tests[unitJ];
	NSInteger vcnNows[unitJ][N_ELMS_VCN_REC];
	memset(vcnNows[0], 0, sizeof(vcnNows));
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * nCells / unitJ;
		NSInteger end = (j + 1) * nCells / unitJ;
		NSMutableArray<NSValue *> *infec = infectors[j] = NSMutableArray.new;
		NSMutableArray<NSValue *> *move = movers[j] = NSMutableArray.new;
		NSMutableArray<NSValue *> *warp = warps[j] = NSMutableArray.new;
		NSMutableArray<NSValue *> *hist = hists[j] = NSMutableArray.new;
		NSMutableArray<NSValue *> *test = tests[j] = NSMutableArray.new;
		NSInteger *vcnNow = vcnNows[j];
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
					step_agent(a, prms, goHomeBack, &info);
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
					if (info.vcnNowType != VcnNowNone) {
						NSInteger ageRk = a->age / (100 / (N_AGE_RANKS - 1));
						if (ageRk >= N_AGE_RANKS) ageRk = N_AGE_RANKS - 1;
						vcnNow[(info.vcnNowType - VcnNowFirst) * N_AGE_RANKS + ageRk] ++;
					}
					if (a->newNInfects > 0) {
						[infec addObject:[NSValue valueWithInfect:
							(InfectionCntInfo){a->nInfects, a->nInfects + a->newNInfects}]];
						a->nInfects += a->newNInfects;
		}}}};
		if (j < unitJ - 1) [self addOperation:block];
		else block();
	}
	[self waitAllOperations];
	NSArray<NSArray <NSValue *> *> *histArray = [NSArray arrayWithObjects:hists count:unitJ];
	__weak StatInfo *weakStatInfo = statInfo;
	[self addOperation: ^{ for (NSInteger i = 0; i < unitJ; i ++)
		for (NSValue *v in histArray[i]) {
			HistInfo info = v.histInfoValue;
			[weakStatInfo cummulateHistgrm:info.type days:info.days];
		}}];
	for (NSInteger i = 1; i < unitJ; i ++)
		for (NSInteger j = 0; j < N_ELMS_VCN_REC; j ++) vcnNows[0][j] += vcnNows[i][j];
	[statInfo cummulateVcnRecord:vcnNows[0]];
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
		step_agent_in_quarantine(a, prms, &info);
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
			loopMode = LoopPauseByCondition;
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
		if (loopMode == LoopPauseByCondition) {
			if (scenarioIndex < scenario.count) {
				[self execScenario];
				loopMode = LoopRunning;
			} else loopMode = LoopEndByCondition;
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
DEF_VAL(VcnNowInfo, valueWithVcnNowInfo, vcnNowInfoValue)		
DEF_VAL(DistanceInfo, valueWithDistanceInfo, distanceInfo)
@end
