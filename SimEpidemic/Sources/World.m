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

#define N_AGE_BANDS 21
NSInteger AgePopSize[N_AGE_BANDS] = {	// 2021/3/1 Tokyo
// https://www.toukei.metro.tokyo.lg.jp/juukiy/2021/jy21qf0001.pdf
	528572, 543911, 528135, 535275, 785544, 948618, 943157, 1003681,
	1056852, 1173805, 1061030, 895855, 700522, 679782, 807894, 627318,
	489137, 335982, 149459, 42354, 6641 };

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
- (void)addInfected:(NSInteger)n variant:(int)variantType {
	NSInteger nSusc = 0, nCells = worldParams.mesh * worldParams.mesh;
	for (NSInteger i = 0; i < nCells; i ++)
		for (Agent *a = _Pop[i]; a; a = a->next) if (a->health == Susceptible) nSusc ++;
	if (nSusc == 0) return;
	if (n >= nSusc) {
		n = nSusc;
		for (NSInteger i = 0; i < nCells; i ++) for (Agent *a = _Pop[i]; a; a = a->next)
			if (a->health == Susceptible) force_infect(a, variantType);
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
				force_infect(a, variantType);
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
- (NSString *)varNameFromKey:(NSString *)key vcnTypeReturn:(int *)vcnTypeP {
	NSScanner *scan = [NSScanner scannerWithString:key];
	NSString *varName;
	[scan scanUpToString:@" " intoString:&varName];
	*vcnTypeP = scan.atEnd? 0 :
		[self vcnTypeFromName:[key substringFromIndex:scan.scanLocation + 1]];
	return varName;
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
				NSInteger n = [arr[0] integerValue];
				switch (arr.count) {
					case 1: scenarioIndex = n; break;
					case 2: if ([(NSPredicate *)arr[1] evaluateWithObject:statInfo])
						scenarioIndex = n; break;
					case 3:	{ // add infected individuals of specified variant
						int varType = [self variantTypeFromName:arr[2]];
						if (varType >= 0) [self addInfected:n variant:varType];
				}}
			} else if ([arr[1] isKindOfClass:NSPredicate.class]) {	// continue until --
				predicateToStop = (NSPredicate *)arr[1];
				hasStopCond = YES;
				break;
			} else if (arr.count == 2) md[arr[0]] = arr[1];	// paramter assignment
			else {	// parameter assignment with delay
				NSObject *goal = [(NSString *)arr[0] hasPrefix:@"vaccine"]? arr[1] :
					(paramIndexFromKey[arr[0]].integerValue > IDX_D &&
					[arr[1] isKindOfClass:NSNumber.class])? @[arr[1], arr[1], arr[1]] : arr[1];
				paramChangers[arr[0]] = @[goal,
					@(runtimeParams.step / worldParams.stepsPerDay + [(arr[2]) doubleValue])];
			}
		} else if ([item isKindOfClass:NSDictionary.class]) {	// for upper compatibility
			[md addEntriesFromDictionary:(NSDictionary *)item];
		} else if ([item isKindOfClass:NSNumber.class]) {	// add infected individuals
			[self addInfected:((NSNumber *)item).integerValue variant:0];
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
	if (md.count > 0) {	// parameter change
		for (NSString *key in md) {
			if ([key hasPrefix:@"vaccine"]) {
				if ([key isEqualToString:@"vaccineAntiRate"]) {
					CGFloat newAntiRate = ((NSNumber *)md[key]).doubleValue;
					if (newAntiRate > worldParams.vcnAntiRate) {
						NSInteger nReg = nPop * (newAntiRate - worldParams.vcnAntiRate);
						for (NSInteger i = 0; i < nPop && nReg > 0; i ++)
							if (_agents[i].forVcn != VcnAccept)
								{ _agents[i].forVcn = VcnAccept; nReg --; }
					}
				} else {
					int vcnType;
					NSString *varName = [self varNameFromKey:key vcnTypeReturn:&vcnType];
					if (vcnType < 0) continue;
					VaccinationInfo *vInfo = &runtimeParams.vcnInfo[vcnType];
					NSNumber *num = (NSNumber *)md[key];
					if ([varName hasSuffix:@"Rate"]) vInfo->performRate = num.doubleValue;
					else if ([varName hasSuffix:@"Regularity"]) vInfo->regularity = num.doubleValue;
					else {
						vInfo->priority = num.intValue;
						if (vInfo->priority == VcnPrBooster) [self resetBoostQueue];
					}
				}
			} else {
				NSNumber *idxNum = paramIndexFromKey[key];
				if (idxNum == nil) continue;
				NSInteger idx = idxNum.integerValue;
				NSObject *value = md[key];
				if (idx < IDX_D)
					(&runtimeParams.PARAM_F1)[idx] = ((NSNumber *)md[key]).doubleValue;
				else if (idx < IDX_I) {
					if ([value isKindOfClass:NSArray.class] && ((NSArray *)value).count == 3)
						set_dist_values(&runtimeParams.PARAM_D1 + idx - IDX_D,
							(NSArray<NSNumber *> *)value, 1.);
				} else if (idx >= IDX_E && idx < IDX_H)
					(&runtimeParams.PARAM_E1)[idx - IDX_E] = ((NSNumber *)md[key]).intValue;
			}
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
		vcnQueue = realloc(vcnQueue, sizeof(NSInteger) * nPop * N_VCN_QUEQUE);
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
static NSPoint random_point_in_hospital(CGFloat worldSize) {
	return (NSPoint){
		(d_random() * .248 + 1.001) * worldSize,
		(d_random() * .458 + 0.501) * worldSize};
}
- (void)setupVaxenAndVarintsFromLists {
	NSInteger nVariants, nVaccines;
	if ((nVariants = _variantList.count) > MAX_N_VARIANTS) nVariants = MAX_N_VARIANTS;
	NSString *vrNames[nVariants];
	for (NSInteger i = 0; i < nVariants; i ++) vrNames[i] = _variantList[i][@"name"];
	VariantInfo *rInfo = variantInfo;
	for (NSInteger i = 0; i < nVariants; i ++) {
		NSDictionary *dict = _variantList[i];
		rInfo[i].reproductivity = [dict[@"reproductivity"] doubleValue];
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
			{ CGFloat fdd = a->firstDoseDate; return (fdd > 0.)? fdd : MAXFLOAT; }];
}
- (void)resetVaccineQueue {
	for (NSInteger i = 0; i < nPop; i ++) {
		_agents[i].vaccineType = -1;
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
		idx = 0, lstIdx = 0;
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
	NSInteger *avAgentIDs = malloc(sizeof(NSInteger) * nAntiVcnPop);
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
			NSInteger ID = members[i].distanceInfo.agent->ID;
			_agents[ID].forVcn = VcnReject;
			avAgentIDs[lstIdx ++] = ID;
		}
		idx += nAgents;
	}
	if (idx < nAntiVcnPop) {
		NSInteger nRestAgents = nPop - nAgentsInClstr;
		NSInteger *agentIDs = malloc(sizeof(NSInteger) * nRestAgents);
		for (NSInteger i = 0, j = 0; i < nPop && j < nRestAgents; i ++)
			if (_agents[i].forVcn != VcnReject) agentIDs[j ++] = i;
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
- (BOOL)resetPop {
	BOOL changed = NO;
	if (memcmp(&worldParams, &tmpWorldParams, sizeof(WorldParams)) != 0) {
		memcpy(&worldParams, &tmpWorldParams, sizeof(WorldParams));
		changed = YES;
	}
	memcpy(&runtimeParams, &initParams, sizeof(RuntimeParams));
	[popLock lock];
	[self allocateMemory];
	NSInteger nAgePop[N_AGE_BANDS], nASum = 0;
	for (NSInteger i = 0; i < N_AGE_BANDS; i ++) nASum += AgePopSize[i];
	for (NSInteger i = 0; i < N_AGE_BANDS; i ++)
		nAgePop[i] = nPop * AgePopSize[i] / nASum + ((i == 0)? 0 : nAgePop[i - 1]);
	NSInteger *ibuf = malloc(sizeof(NSInteger) * nPop);
	for (NSInteger i = 0; i < nPop; i ++) ibuf[i] = i;
	for (NSInteger i = 0, iS = 0; i < nPop; i ++) {
		NSInteger j = random() % (nPop - i) + i, k = ibuf[j];
		if (i != j) ibuf[j] = ibuf[i];
		_agents[k].age = (d_random() + iS) * 5.;
		if (i >= nAgePop[iS] && iS < N_AGE_BANDS - 1) iS ++;
	}
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
			a->virusVariant = 0;
		} else {
			a->health = Recovered;
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
	[self setupVaxenAndVarintsFromLists];
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
	_variantList = [NSMutableArray arrayWithObject:
		[NSMutableDictionary dictionaryWithDictionary:
		@{@"name":@"Original", @"reproductivity":@(1.),
			@"Original":@(1.)}]];
	_vaccineList = [NSMutableArray arrayWithObject:
		[NSMutableDictionary dictionaryWithDictionary:
		@{@"name":@"PfBNT", @"intervalOn":@YES, @"intervalDays":@(21),
			@"Original":@(1.)}]];
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
#ifdef NOGUI
static NSString *check_paramname_in_chng_prm_elm(NSArray *prop) {
	NSString *paramName = prop[0];
	if (![paramName isKindOfClass:NSString.class]) return nil;
	@try {
		NSNumber *idxNum = paramIndexFromKey[(NSString *)prop[0]];
		if (idxNum != nil) {
			NSInteger idx = idxNum.integerValue;
			if ((idx >= IDX_I && idx < IDX_E) || idx >= IDX_H) {
				if (![paramName isEqualToString:@"vaccineAntiRate"] || prop.count > 2)
					@throw @"invalid to modify in scenario.";
			}
		} else if ([paramName hasPrefix:@"vaccine"]) {
			NSString *suffix;
			NSScanner *scan = [NSScanner scannerWithString:paramName];
			[scan scanString:@"vaccine" intoString:NULL];
			[scan scanUpToString:@" " intoString:&suffix];
			if ([@[@"PerformRate", @"Priority", @"Regularity"] indexOfObject:suffix] == NSNotFound)
				@throw @"unknown parameter name";
		} else @throw @"unknown parameter name";
	} @catch (NSString *msg) {
		return [NSString stringWithFormat:@"\"%@\" is %@.", paramName, msg]; }
	return nil;
}
NSString *check_scenario_element_from_property(NSObject *prop) {
// returns nil when it looks OK, otherwise return a string of error message
	NSString *predForm = nil;
	if ([prop isKindOfClass:NSString.class]) predForm = (NSString *)prop;
	else if (![prop isKindOfClass:NSArray.class]) return nil;
	else if (((NSArray *)prop).count != 2) return check_paramname_in_chng_prm_elm((NSArray *)prop);
	else if (![((NSArray *)prop)[1] isKindOfClass:NSString.class])
		return check_paramname_in_chng_prm_elm((NSArray *)prop);
	else predForm = (NSString *)((NSArray *)prop)[1];
	if (predForm == nil || predForm.length == 0) return @"Null predicate";
	@try { return ([NSPredicate predicateWithFormat:predForm] == nil)? @"Null" : nil; }
	@catch (NSException *e) { return e.reason; }
}
#endif
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
static BOOL give_vcn_ticket_if_possible(Agent *a, int vcnType, VaccinePriority priority) {
	if ((a->health == Susceptible || (a->health == Asymptomatic && !a->isOutOfField)
		|| (a->health == Vaccinated && priority == VcnPrBooster))
		&& a->forVcn == VcnAccept && !a->vaccineTicket) {
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
	if (paramChangers != nil && paramChangers.count > 0) {
		NSMutableArray<NSString *> *keyToRemove = NSMutableArray.new;
		for (NSString *key in paramChangers) {
			NSArray<NSNumber *> *entry = paramChangers[key];
			CGFloat stepsLeft = entry[1].doubleValue * worldParams.stepsPerDay
				- runtimeParams.step;
			if ([key hasPrefix:@"vaccine"]) {
				int vcnType;
				NSString *varName = [self varNameFromKey:key vcnTypeReturn:&vcnType];
				if (vcnType < 0) continue;
				VaccinationInfo *vInfo = &runtimeParams.vcnInfo[vcnType];
				CGFloat goalValue = entry[0].doubleValue;
				if (stepsLeft <= 1.) {
					[keyToRemove addObject:key];
					if ([varName hasSuffix:@"Rate"]) vInfo->performRate = goalValue;
					else vInfo->regularity = goalValue;
				} else {
					CGFloat *vp = [varName hasSuffix:@"Rate"]?
						&vInfo->performRate : &vInfo->regularity;
					*vp += (goalValue - *vp) / stepsLeft;
				}
			} else {
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
		}}
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
		for (NSInteger cnt = 0, k = 0; cnt < n && k < nPop; ix = (ix + 1) % nPop, k ++)
			if (give_vcn_ticket_if_possible(_agents + vQue[ix], (int)idx, vp->priority)) cnt ++;
		vcnQueIdx[vp->priority] = ix;
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
