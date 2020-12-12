//
//  Document.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

//#define MY_DOC_THREADS
//#define GCD_CONCURRENT_QUEUE

#import <sys/sysctl.h>
#import <sys/resource.h>
#import "Document.h"
#ifdef MY_DOC_THREADS
#import "DocThread.h"
#endif
#import "Agent.h"
#import "MyView.h"
#import "Scenario.h"
#import "ParamPanel.h"
#import "StatPanel.h"
#import "DataPanel.h"
#import "Parameters.h"
#import "Gatherings.h"
#ifdef NOGUI
#import "../../SimEpidemicSV/noGUI.h"
#import "../../SimEpidemicSV/PeriodicReporter.h"
#endif
#define ALLOC_UNIT 2048
#define DYNAMIC_STRUCT(t,f,n) static t *f = NULL;\
static t *n(void) {\
	if (f == NULL) {\
		f = malloc(sizeof(t) * ALLOC_UNIT);\
		for (NSInteger i = 0; i < ALLOC_UNIT - 1; i ++) f[i].next = f + i + 1;\
		f[ALLOC_UNIT - 1].next = NULL;\
	}\
	t *a = f; f = f->next; a->next = NULL; return a;\
}
DYNAMIC_STRUCT(TestEntry, freeTestEntries, new_testEntry)
DYNAMIC_STRUCT(ContactInfo, freeCInfo, new_cinfo)
static NSLock *cInfoLock = nil;
void add_new_cinfo(Agent *a, Agent *b, NSInteger tm) {
	[cInfoLock lock];
	ContactInfo *c = new_cinfo();
	[cInfoLock unlock];
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
static void remove_old_cinfo(Agent *a, NSInteger tm) {
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
	[cInfoLock lock];
	gbTail->next = freeCInfo; freeCInfo = gbHead;
	[cInfoLock unlock];
}

CGFloat get_uptime(void) {
	struct timespec ts;
	clock_gettime(CLOCK_UPTIME_RAW, &ts);
	return ts.tv_sec + ts.tv_nsec * 1e-9;
}
void in_main_thread(dispatch_block_t block) {
	if ([NSThread isMainThread]) block();
	else dispatch_async(dispatch_get_main_queue(), block);
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

#ifndef NOGUI
@implementation NSWindowController (ChildWindowExtension)
- (void)setupParentWindow:(NSWindow *)parentWindow {
	if (self.window.parentWindow == nil && makePanelChildWindow)
		[parentWindow addChildWindow:self.window ordered:NSWindowAbove];
}
- (void)showWindowWithParent:(NSWindow *)parentWindow {
	[self setupParentWindow:parentWindow];
	[self showWindow:self];
}
- (void)windowDidBecomeKey:(NSNotification *)notification {
	NSWindow *pWin = self.window.parentWindow;
	if (pWin != nil) {
		[pWin removeChildWindow:self.window];
		[pWin addChildWindow:self.window ordered:NSWindowAbove];
	}
}
@end
#endif

#ifdef MY_DOC_THREADS
#elif defined GCD_CONCURRENT_QUEUE
#else
NSInteger nQueues = 10;
#endif

@interface Document () {
	NSInteger scenarioIndex;
	LoopMode loopMode;
	NSInteger nPop, nMesh;
	Agent **pop, *agents;
	NSRange *pRange;
	CGFloat stepsPerSec;
	NSMutableArray<NSLock *> *cellLocks;
	NSMutableDictionary<NSNumber *, WarpInfo *> *newWarpF;
	NSMutableDictionary<NSNumber *, NSNumber *> *testees;
	NSLock *newWarpLock, *testeesLock;
	NSInteger animeSteps, stopAtNDays;
	NSArray *scenario;
	NSPredicate *predicateToStop;
	NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *paramChangers;
	TestEntry *testQueHead, *testQueTail;
	GatheringMap *gatheringsMap;
	NSMutableArray<Gathering *> *gatherings;
#ifdef MY_DOC_THREADS
#else
	dispatch_group_t dispatchGroup;
#ifdef GCD_CONCURRENT_QUEUE
	dispatch_queue_t dispatchQueue;
#else
	NSArray<dispatch_queue_t> *dispatchQueue;
	NSInteger queueIdx;
#endif
#endif
	NSSize orgWindowSize, orgViewSize;
#ifdef NOGUI
	__weak NSTimer *runtimeTimer;
	NSMutableArray<PeriodicReporter *> *reporters;
	NSLock *reportersLock;
	CGFloat maxSPS;
#else
	Scenario *scenarioPanel;
	ParamPanel *paramPanel;
	DataPanel *dataPanel;
	NSMutableDictionary *orgViewInfo;
	FillView *fillView;
#endif
}
@end

@implementation Document
- (Agent **)QListP { return &_QList; }
- (Agent **)CListP { return &_CList; }
- (RuntimeParams *)runtimeParamsP { return &runtimeParams; }
- (RuntimeParams *)initParamsP { return &initParams; }
- (WorldParams *)worldParamsP { return &worldParams; }
- (WorldParams *)tmpWorldParamsP { return &tmpWorldParams; }
- (BOOL)running { return loopMode == LoopRunning; }
#ifndef NOGUI
- (void)setRunning:(BOOL)newState {
	BOOL orgState = loopMode == LoopRunning;
	if (orgState != newState) [self startStop:nil];
}
- (NSArray<Gathering *> *)gatherings { return gatherings; }
#endif
- (void)popLock { [popLock lock]; }
- (void)popUnlock { [popLock unlock]; }
- (NSMutableArray<MyCounter *> *)RecovPHist { return statInfo.RecovPHist; }
- (NSMutableArray<MyCounter *> *)IncubPHist { return statInfo.IncubPHist; }
- (NSMutableArray<MyCounter *> *)DeathPHist { return statInfo.DeathPHist; }
- (void)addOperation:(void (^)(void))block {
#ifdef MY_DOC_THREADS
	add_doc_task(block);
#elif defined GCD_CONCURRENT_QUEUE
	dispatch_group_async(dispatchGroup, dispatchQueue, block);
#else
	queueIdx = (queueIdx + 1) % nQueues;
	dispatch_group_async(dispatchGroup, dispatchQueue[queueIdx], block);
#endif
}
- (void)waitAllOperations {
#ifdef MY_DOC_THREADS
	wait_all_doc_tasks();
#else
	dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
#endif
}
#ifndef NOGUI
- (void)setPanelTitle:(NSWindow *)panel {
	NSString *orgTitle = panel.title;
	NSScanner *scan = [NSScanner scannerWithString:orgTitle];
	[scan scanUpToString:@": " intoString:NULL];
	panel.title = [NSString stringWithFormat:@"%@: %@", self.displayName,
		scan.atEnd? orgTitle : [orgTitle substringFromIndex:scan.scanLocation + 2]];
}
- (void)setDisplayName:(NSString *)name {
	[super setDisplayName:name];
	NSWindowController *winCon[] = {scenarioPanel, paramPanel, dataPanel};
	for (NSInteger i = 0; i < 3; i ++)
		if (winCon[i] != nil) [self setPanelTitle:winCon[i].window];
	for (StatPanel *panel in statInfo.statPanels)
		[self setPanelTitle:panel.window];
}
- (void)reviseColors {
	view.needsDisplay = YES;
	for (NSInteger i = 0; i < NHealthTypes; i ++) {
		lvViews[i].color = stateColors[i];
		lvViews[i].needsDisplay = YES;
	}
	[statInfo reviseColors];
}
- (void)setInitialParameters:(NSData *)newParams {
	NSData *orgParams = [NSData dataWithBytes:&initParams length:sizeof(RuntimeParams)];
	[self.undoManager registerUndoWithTarget:self handler:
		^(Document *target) { [target setInitialParameters:orgParams]; }];
	memcpy(&initParams, newParams.bytes, sizeof(RuntimeParams));
}
#endif
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
#ifndef NOGUI
	in_main_thread(^{
		[self showCurrentStatistics];
		self->view.needsDisplay = YES;
	});
#endif
}
#ifndef NOGUI
- (void)adjustScenarioText {
	if (scenario != nil && scenario.count > 0)
		scenarioText.integerValue = scenarioIndex;
	else scenarioText.stringValue = NSLocalizedString(@"None", nil);
}
#endif
- (void)execScenario {
	predicateToStop = nil;
	if (scenario == nil) return;
	char visitFlags[scenario.count];
	memset(visitFlags, 0, scenario.count);
	BOOL hasStopCond = NO;
	NSMutableDictionary<NSString *, NSObject *> *md = NSMutableDictionary.new;
	while (scenarioIndex < scenario.count) {
		if (visitFlags[scenarioIndex] == YES) {
			error_msg([NSString stringWithFormat:@"%@: %ld",
				NSLocalizedString(@"Looping was found in the Scenario.", nil),
				scenarioIndex + 1],
#ifdef NOGUI
				nil,
#else
				scenarioPanel? scenarioPanel.window : view.window,
#endif
				NO);
			break;
		}
		visitFlags[scenarioIndex] = YES;
		NSObject *item = scenario[scenarioIndex ++];
		if ([item isKindOfClass:NSArray.class]) {
			if ([((NSArray *)item)[0] isKindOfClass:NSNumber.class]) {	// jump N if --
				NSInteger destIdx = [((NSArray *)item)[0] integerValue];
				if (((NSArray *)item).count == 1) scenarioIndex = destIdx;
				else if ([(NSPredicate *)((NSArray *)item)[1] evaluateWithObject:statInfo])
					scenarioIndex = destIdx;
			} else if ([((NSArray *)item)[1] isKindOfClass:NSPredicate.class]) {
				predicateToStop = (NSPredicate *)((NSArray *)item)[1];
				hasStopCond = YES;
				break;
			} else if (((NSArray *)item).count == 2)
				md[((NSArray *)item)[0]] = ((NSArray *)item)[1];	// paramter assignment
			else paramChangers[((NSArray *)item)[0]] = @[((NSArray *)item)[1],
				@(runtimeParams.step / worldParams.stepsPerDay +
					[(((NSArray *)item)[2]) doubleValue])];
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
	if (hasStopCond) in_main_thread( ^{ [self adjustScenarioText]; });
#endif
	if (md.count > 0) {
		for (NSString *key in md.keyEnumerator) {
			NSInteger idx = paramIndexFromKey[key].integerValue;
			NSObject *value = md[key];
			if (idx < IDX_D)
				(&runtimeParams.PARAM_F1)[idx] = ((NSNumber *)md[key]).doubleValue;
			else if ([value isKindOfClass:NSArray.class] && ((NSArray *)value).count == 3)
				set_dist_values(&runtimeParams.PARAM_D1 + idx - IDX_D,
					(NSArray<NSNumber *> *)value, 1.);
		}
#ifndef NOGUI
		NSArray<NSString *> *allKeys = md.allKeys;
		in_main_thread( ^{ [self->paramPanel adjustParamControls:allKeys]; });
#endif
	}
	if (predicateToStop == nil && scenarioIndex == scenario.count) scenarioIndex ++;
#ifndef NOGUI
	[statInfo phaseChangedTo:scenarioIndex];
#endif
}
- (NSArray *)scenario { return scenario; }
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
		if ([elm isKindOfClass:NSPredicate.class]) {
			[maPhase addObject:@(i + 1)];
			[maLabel addObject:@""];
		} else if (![elm isKindOfClass:NSArray.class]) continue;
		else if (((NSArray *)elm).count != 2) continue;
		else if ([((NSArray *)elm)[1] isKindOfClass:NSPredicate.class]) {
			[maPhase addObject:@(i + 1)];
			[maLabel addObject:((NSArray *)elm)[0]];
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
- (void)setScenario:(NSArray *)newScen {
	if (self.running) return;
	NSArray *orgScen = scenario;
	[self.undoManager registerUndoWithTarget:self handler:
		^(Document *target) { target.scenario = orgScen; }];
	scenario = newScen;
	scenarioIndex = 0;
	[self setupPhaseInfo];
	[self adjustScenarioText];
	paramChangers = NSMutableDictionary.new;
	if (runtimeParams.step == 0) [self execScenario];
	[scenarioPanel adjustControls:
		self.undoManager.undoing || self.undoManager.redoing];
}
- (void)showCurrentStatistics {
	StatData *stat = statInfo.statistics;
	for (NSInteger i = 0; i < NHealthTypes; i ++)
		lvViews[i].integerValue = stat->cnt[i];
	qNSNum.integerValue = stat->cnt[QuarantineAsym];
	qDSNum.integerValue = stat->cnt[QuarantineSymp];
	[statInfo flushPanels];
}
#else
- (void)forAllReporters:(void (^)(PeriodicReporter *))block {
	if (reporters == nil) return;
	[reportersLock lock];
	for (PeriodicReporter *rep in reporters) block(rep);
	[reportersLock unlock];
}
#endif
- (void)resetPop {
	if (memcmp(&worldParams, &tmpWorldParams, sizeof(WorldParams)) != 0) {
		memcpy(&worldParams, &tmpWorldParams, sizeof(WorldParams));
#ifndef NOGUI
		[self updateChangeCount:NSChangeDone];
#endif
	}
	if (scenario != nil) {
		memcpy(&runtimeParams, &initParams, sizeof(RuntimeParams));
#ifndef NOGUI
		[paramPanel adjustControls];
#endif
	}
	gatheringsMap = NSMutableDictionary.new;
	gatherings = NSMutableArray.new;
	[popLock lock];
	[cInfoLock lock];
	for (NSInteger i = 0; i < nPop; i ++)
		if (agents[i].contactInfoHead != NULL) {
			agents[i].contactInfoTail->next = freeCInfo;
			freeCInfo = agents[i].contactInfoHead;
			agents[i].contactInfoHead = agents[i].contactInfoTail = NULL;
	}
	[cInfoLock unlock];
	if (nMesh != worldParams.mesh) {
		NSInteger nCOrg = nMesh * nMesh, nCNew = worldParams.mesh * worldParams.mesh;
		if (nCOrg < nCNew) {
			if (cellLocks == nil) cellLocks = NSMutableArray.new;
			for (NSInteger i = nCOrg; i < nCNew; i ++)
				[cellLocks addObject:NSLock.new];
		} else [cellLocks removeObjectsInRange:(NSRange){nCNew, nCOrg - nCNew}];
		nMesh = worldParams.mesh;
		_Pop = realloc(_Pop, sizeof(void *) * nCNew);
		pRange = realloc(pRange, sizeof(NSRange) * nCNew);
	}
	memset(_Pop, 0, sizeof(void *) * nMesh * nMesh);
	if (nPop != worldParams.initPop) {
		nPop = worldParams.initPop;
		pop = realloc(pop, sizeof(void *) * nPop);
		agents = realloc(agents, sizeof(Agent) * nPop);
	}
	NSInteger nDist = runtimeParams.dstOB / 100. * nPop;
	NSInteger iIdx = 0, infecIdxs[worldParams.nInitInfec];
	for (NSInteger i = 0; i < worldParams.nInitInfec; i ++) {
		NSInteger k = (nPop - i - 1) * random() / 0x7fffffff;
		for (NSInteger j = 0; j < i; j ++) if (k >= infecIdxs[j]) k ++;
		infecIdxs[i] = k;
	}
	qsort_b(infecIdxs, worldParams.nInitInfec, sizeof(NSInteger),
		^int(const void *a, const void *b) {
			NSInteger *x = (NSInteger *)a, *y = (NSInteger *)b;
			return (*x < *y)? -1 : (*x > *y)? 1 : 0;
	});
// for (NSInteger i = 0; i < params.nInitInfec; i ++) printf("%ld,", infecIdxs[i]); printf("\n");
	for (NSInteger i = 0; i < nPop; i ++) {
		Agent *a = &agents[i];
		reset_agent(a, &runtimeParams, &worldParams);
		a->ID = i;
		a->distancing = (i < nDist);
		if (iIdx < worldParams.nInitInfec && i == infecIdxs[iIdx]) {
			a->health = Asymptomatic; iIdx ++;
			a->nInfects = 0;
		}
		add_agent(a, &worldParams, _Pop);
	}
	_QList = _CList = NULL;
	_WarpList = NSMutableArray.new;
	if (testQueTail != nil) {
		[testEntriesLock lock];
		testQueTail->next = freeTestEntries;
		freeTestEntries = testQueHead;
		[testEntriesLock unlock];
		testQueTail = testQueHead = NULL;
	}
	runtimeParams.step = 0;
	[statInfo reset:nPop infected:worldParams.nInitInfec];
	[popLock unlock];
	paramChangers = NSMutableDictionary.new;
	scenarioIndex = 0;
	[self execScenario];
#ifdef NOGUI
	[self forAllReporters:^(PeriodicReporter *rep) { [rep reset]; }];
#else
	daysNum.doubleValue = 0.;
	[self showCurrentStatistics];
#endif
	loopMode = LoopNone;
}
- (instancetype)init {
	if ((self = [super init]) == nil) return nil;
	if (cInfoLock == nil) cInfoLock = NSLock.new;
#ifdef MY_DOC_THREADS
	init_doc_threads(nCores/2);
#else
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
#endif
	popLock = NSLock.new;
	newWarpF = NSMutableDictionary.new;
	newWarpLock = NSLock.new;
	testees = NSMutableDictionary.new;
	testeesLock = NSLock.new;
	animeSteps = defaultAnimeSteps;
	stopAtNDays = -365;
	memcpy(&runtimeParams, &userDefaultRuntimeParams, sizeof(RuntimeParams));
	memcpy(&initParams, &userDefaultRuntimeParams, sizeof(RuntimeParams));
	memcpy(&worldParams, &userDefaultWorldParams, sizeof(WorldParams));
	memcpy(&tmpWorldParams, &userDefaultWorldParams, sizeof(WorldParams));
#ifdef NOGUI
	_ID = new_uniq_string();
	_lastTLock = NSLock.new;
	statInfo = StatInfo.new;
	statInfo.doc = self;
	[self resetPop];
#else
	self.undoManager = NSUndoManager.new;
#endif
	return self;
}
#ifdef NOGUI
- (void)discardMemory {	// called when this document got useless
	if (reporters != nil) {
		for (PeriodicReporter *rep in reporters) [rep quit];
		reporters = nil;
	}
	[statInfo discardMemory];	// cut the recursive reference
	[cInfoLock lock];
	for (NSInteger i = 0; i < nPop; i ++) if (agents[i].contactInfoHead != NULL) {
		agents[i].contactInfoTail->next = freeCInfo;
		freeCInfo = agents[i].contactInfoHead;
	}
	[cInfoLock unlock];
	if (testQueTail != nil) {
		[testEntriesLock lock];
		testQueTail->next = freeTestEntries;
		freeTestEntries = testQueHead;
		[testEntriesLock unlock];
	}
	free(_Pop);
	free(pop);
	free(agents);
}
#else
- (NSString *)windowNibName { return @"Document"; }
- (void)windowControllerDidLoadNib:(NSWindowController *)windowController {
	static NSString *lvNames[] = {
		@"Susceptible", @"Asymptomatic", @"Symptomatic", @"Recovered", @"Dead"
	};
	lvViews = @[lvSuc, lvAsy, lvSym, lvRec, lvDea];
	for (NSInteger i = 0; i < lvViews.count; i ++) {
		lvViews[i].color = stateColors[i];
		lvViews[i].name = NSLocalizedString(lvNames[i], nil);
		lvViews[i].integerValue = 0;
	}
	windowController.window.delegate = self;
	if (scenario != nil) [self setupPhaseInfo];
	[self resetPop];
	animeStepper.integerValue = log2(animeSteps);
	show_anime_steps(animeStepsTxt, animeSteps);
	stopAtNDaysDgt.integerValue = (stopAtNDays > 0)? stopAtNDays : - stopAtNDays;
	stopAtNDaysCBox.state = stopAtNDays > 0;
	[self adjustScenarioText];
	orgWindowSize = windowController.window.frame.size;
	orgViewSize = view.frame.size;
//	[self openStatPenel:self];
}
- (void)windowWillClose:(NSNotification *)notification {
	if (scenarioPanel != nil) [scenarioPanel close];
	if (paramPanel != nil) [paramPanel close];
	if (dataPanel != nil) [dataPanel close];
	if (statInfo.statPanels != nil)
		for (NSInteger i = statInfo.statPanels.count - 1; i >= 0; i --)
			[statInfo.statPanels[i] close];
}
- (void)windowWillEnterFullScreen:(NSNotification *)notification {
	orgViewInfo = NSMutableDictionary.new;
	orgViewInfo[@"windowFrame"] = [NSValue valueWithRect:view.window.frame];
	orgViewInfo[@"viewFrame"] = [NSValue valueWithRect:view.frame];
}
- (void)windowDidEnterFullScreen:(NSNotification *)notification {
	NSView *contentView = view.superview;
	NSSize contentSize = contentView.frame.size;
	NSRect newViewFrame = {0, 0, contentSize.height * 1.2, contentSize.height};
	newViewFrame.origin.x = contentSize.width - newViewFrame.size.width;
	NSRect panelRect = {0, stopAtNDaysDgt.frame.origin.y - 10., newViewFrame.origin.x,};
	[view setFrame:newViewFrame];
	panelRect.origin.y -= (panelRect.size.height = panelRect.size.width / 4.);
	if (statInfo.statPanels != nil) {
		NSMutableArray *ma = NSMutableArray.new;
		for (StatPanel *sp in statInfo.statPanels) {
			NSView *statView = sp.view;
			[ma addObject:@[statView, statView.superview,
				[NSValue valueWithRect:statView.frame]]];
			[contentView addSubview:statView];
			[statView setFrame:panelRect];
			if ((panelRect.origin.y -= panelRect.size.height) < 0.) break;
		}
		orgViewInfo[@"statViews"] = ma;
	}
	fillView = [FillView.alloc initWithFrame:(NSRect)
		{0, 0, panelRect.size.width, NSMaxY(panelRect)}];
	[contentView addSubview:fillView];
	for (NSButton *btn in @[scnBtn, prmBtn, sttBtn, datBtn]) btn.enabled = NO;
}
- (void)windowDidExitFullScreen:(NSNotification *)notification {
	[view.window setFrame:
		[(NSValue *)orgViewInfo[@"windowFrame"] rectValue] display:YES];
	[view setFrame:[(NSValue *)orgViewInfo[@"viewFrame"] rectValue]];
	NSArray *statViews = orgViewInfo[@"statViews"];
	if (statViews != nil) for (NSArray *info in statViews) {
		[(NSView *)info[1] addSubview:info[0]];
		[(NSView *)info[0] setFrame:[(NSValue *)info[2] rectValue]];
	}
	[fillView removeFromSuperview];
	fillView = nil;
	orgViewInfo = nil;
	for (NSButton *btn in @[scnBtn, prmBtn, sttBtn, datBtn]) btn.enabled = YES;
}
#endif
NSString *keyParameters = @"parameters", *keyScenario = @"scenario";
static NSString *keyDaysToStop = @"daysToStop";
static NSObject *property_from_element(NSObject *elm) {
	if ([elm isKindOfClass:NSPredicate.class]) return ((NSPredicate *)elm).predicateFormat;
	else if (![elm isKindOfClass:NSArray.class]) return elm;
	NSInteger n = ((NSArray *)elm).count;
	NSObject *elms[n];
	BOOL hasPredicate = NO;
	for (NSInteger i = 0; i < n; i ++) {
		NSObject *obj = ((NSArray *)elm)[i];
		if ([obj isKindOfClass:NSPredicate.class]) {
			elms[i] = ((NSPredicate *)obj).predicateFormat;
			hasPredicate = YES;
		} else elms[i] = obj;
	}
	return hasPredicate? [NSArray arrayWithObjects:elms count:n] : elm;
}
static NSObject *element_from_property(NSObject *prop) {
	if ([prop isKindOfClass:NSString.class])
		return [NSPredicate predicateWithFormat:(NSString *)prop];
	else if (![prop isKindOfClass:NSArray.class]) return prop;
	else if (((NSArray *)prop).count != 2) return prop;
	else if (![((NSArray *)prop)[1] isKindOfClass:NSString.class]) return prop;
	NSPredicate *pred =
		[NSPredicate predicateWithFormat:(NSString *)((NSArray *)prop)[1]];
	return (pred != nil)? @[((NSArray *)prop)[0], pred] : prop;
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
			items[i] = element_from_property(plist[i]);
			if (items[i] == nil) @throw [NSString stringWithFormat:
				@"Could not convert it to a scenario element: %@", plist[i]];
		}
		newScen = [NSArray arrayWithObjects:items count:plist.count];
	}
#ifndef NOGUI
	NSArray *orgScen = scenario;
#endif
	scenario = newScen;
	scenarioIndex = 0;
	if (statInfo != nil) {
#ifndef NOGUI
		[self setupPhaseInfo];
#endif
		[self execScenario];
	}
#ifndef NOGUI
	if (orgScen == nil)
#endif
		memcpy(&initParams, &runtimeParams, sizeof(RuntimeParams));
}
#ifndef NOGUI
- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
	NSMutableDictionary *dict = NSMutableDictionary.new;
	dict[keyAnimeSteps] = @(animeSteps);
	if (stopAtNDays > 0) dict[keyDaysToStop] = @(stopAtNDays);
	if (scenario != nil) {
		dict[keyParameters] = param_dict(&initParams, &worldParams);
		dict[keyScenario] = [self scenarioPList];
	} else dict[keyParameters] = param_dict(&runtimeParams, &worldParams);
	return [NSPropertyListSerialization dataWithPropertyList:dict
		format:NSPropertyListXMLFormat_v1_0 options:0 error:outError];
}
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
	NSDictionary *dict = [NSPropertyListSerialization
		propertyListWithData:data options:NSPropertyListImmutable
		format:NULL error:outError];
	if (dict == nil) return NO;
	NSNumber *num = dict[keyAnimeSteps];
	if (num != nil) animeSteps = num.integerValue;
	if ((num = dict[keyDaysToStop]) != nil) stopAtNDays = num.integerValue;
	NSDictionary *pDict = dict[keyParameters];
	if (pDict != nil) {
		set_params_from_dict(&runtimeParams, &worldParams, pDict);
		memcpy(&tmpWorldParams, &worldParams, sizeof(WorldParams));
	}
	NSArray *seq = dict[keyScenario];
	if (seq != nil) {
		@try { [self setScenarioWithPList:seq]; }
		@catch (NSString *msg) { error_msg(msg, nil, NO); }
	}
	return YES;
}
void copy_plist_as_JSON_text(NSObject *plist, NSWindow *window) {
	NSError *error;
	NSData *data = [NSJSONSerialization dataWithJSONObject:plist
		options:JSONFormat error:&error];
	if (data != nil) {
		NSPasteboard *pb = NSPasteboard.generalPasteboard;
		[pb declareTypes:@[NSPasteboardTypeString] owner:NSApp];
		[pb setData:data forType:NSPasteboardTypeString];
	} else if (window != nil) error_msg(error, window, NO);
}
- (IBAction)copy:(id)sender {
	NSMutableDictionary *dict = NSMutableDictionary.new;
	if (stopAtNDays > 0) dict[@"stopAt"] = @(stopAtNDays);
	if (scenario != nil) dict[keyScenario] = [self scenarioPList];
	dict[keyParameters] = param_dict(&initParams, &worldParams);
	copy_plist_as_JSON_text(dict, view.window);
}
#endif
static NSLock *testEntriesLock = nil;
- (void)testInfectionOfAgent:(Agent *)agent reason:(TestType)reason {
	if (runtimeParams.step - agent->lastTested <
		runtimeParams.tstInterval * worldParams.stepsPerDay ||
		agent->isOutOfField || agent->inTestQueue) return;
	[testeesLock lock];
	testees[@(agent->ID)] = @(reason);
	[testeesLock unlock];
}
- (void)deliverTestResults:(NSUInteger *)testCount {
	// check the results of tests
	if (testEntriesLock == nil) testEntriesLock = NSLock.new;
	NSInteger cTm = runtimeParams.step - runtimeParams.tstProc * worldParams.stepsPerDay;
	for (TestEntry *entry = testQueHead; entry != NULL; entry = testQueHead) {
		if (entry->timeStamp > cTm) break;
		if (entry->isPositive) {
			testCount[TestPositive] ++;
			Agent *a = entry->agent;
			a->orgPt = (CGPoint){a->x, a->y};
			NSPoint newPt = {
				(random() * .248 / 0x7fffffff + 1.001) * worldParams.worldSize,
				(random() * .458 / 0x7fffffff + .501) * worldParams.worldSize};
			[self addNewWarp:[WarpInfo.alloc initWithAgent:a
				goal:newPt mode:WarpToHospital]];
			if (a->contactInfoHead != NULL) {
				for (ContactInfo *c = a->contactInfoHead; c != NULL; c = c->next)
					[self testInfectionOfAgent:c->agent reason:TestAsContact];
				[cInfoLock lock];
				a->contactInfoTail->next = freeCInfo;
				freeCInfo = a->contactInfoHead;
				[cInfoLock unlock];
				a->contactInfoHead = a->contactInfoTail = NULL;
			}
		} else testCount[TestNegative] ++;
		entry->agent->inTestQueue = NO;
		testQueHead = entry->next;
		if (entry->next) entry->next->prev = NULL;
		else testQueTail = NULL;
		[testEntriesLock lock];
		entry->next = freeTestEntries;
		freeTestEntries = entry;
		[testEntriesLock unlock];
	}
	// enqueue new tests
	[testeesLock lock];
	for (NSNumber *num in testees) {
		testCount[testees[num].integerValue] ++;
		Agent *agent = &agents[num.integerValue];
		[testEntriesLock lock];
		TestEntry *entry = new_testEntry();
		[testEntriesLock unlock];
		entry->isPositive = is_infected(agent)?
			(random() < 0x7fffffff * runtimeParams.tstSens / 100.) :
			(random() > 0x7fffffff * runtimeParams.tstSpec / 100.);
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
		interacts(apA[j], apB, pRange[iB].length, &runtimeParams, &worldParams);
}
- (void)addNewWarp:(WarpInfo *)info {
	[newWarpLock lock];
	newWarpF[@(info.agent->ID)] = info;
	[newWarpLock unlock];
}
//#define MEASURE_TIME
#ifdef MEASURE_TIME
#define N_MTIME 7
static unsigned long mtime[N_MTIME] = {0,0,0,0,0,0,0};
static NSInteger mCount = 0, mCount2 = 0;
#endif
static void set_dist_values(DistInfo *dp, NSArray<NSNumber *> *arr, CGFloat steps) {
	dp->min += (arr[0].doubleValue - dp->min) / steps;
	dp->max += (arr[1].doubleValue - dp->max) / steps;
	dp->mode += (arr[2].doubleValue - dp->mode) / steps;
}
- (void)doOneStep {
	[popLock lock];
#ifdef MEASURE_TIME
	unsigned long tm0 = current_time_us(), tm1 = tm0, tm2;
	NSInteger tmIdx = 0;
	mCount ++;
#endif
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
		NSArray<NSString *> *allKeys = paramChangers.allKeys;
		in_main_thread(^{ [self->paramPanel adjustParamControls:allKeys]; });
#endif
		for (NSString *key in keyToRemove) [paramChangers removeObjectForKey:key];
	}
//
    NSInteger unitJ = 4;
	NSInteger nCells = worldParams.mesh * worldParams.mesh;
	memset(pRange, 0, sizeof(NSRange) * nCells);
	NSInteger nInField = 0;
	for (NSInteger i = 0; i < nCells; i ++) {
		pRange[i].location = nInField;
		for (Agent *p = _Pop[i]; p; p = p->next) pop[nInField ++] = p;
		pRange[i].length = nInField - pRange[i].location;
	}
	NSInteger oldTimeStamp = runtimeParams.step - worldParams.stepsPerDay * 14;	// two weeks
	Agent **popL = pop;
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * nInField / unitJ, end = (j + 1) * nInField / unitJ;
		[self addOperation:^{
			for (NSInteger i = start; i < end; i ++) {
				reset_for_step(popL[i]);
				remove_old_cinfo(popL[i], oldTimeStamp);
		}}];
	}
	RuntimeParams *rp = &runtimeParams;
	WorldParams *wp = &worldParams;
	manage_gatherings(gatherings, gatheringsMap, wp, rp);
	[self waitAllOperations];
//
	Agent **popMap = _Pop;
	__weak NSArray<NSNumber *> *keys = gatheringsMap.allKeys;
	__weak GatheringMap *gMap = gatheringsMap;
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * keys.count / unitJ, end = (j + 1) * keys.count / unitJ;
		[self addOperation:^{
		for (NSInteger i = start; i < end; i ++) {
			NSNumber *key = keys[i];
			NSMutableArray<Gathering *> *obj = gMap[key];
			for (Agent *a = popMap[key.integerValue]; a != NULL; a = a->next)
				if (a->health != Symptomatic)
					for (Gathering *gat in obj) [gat affectToAgent:a];
		}}]; }
	[self waitAllOperations];
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif
	unitJ = 6;
	__weak typeof(self) weakSelf = self;
    NSRange *pRng = pRange;
    for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * nCells / unitJ;
		NSInteger end = (j + 1) * nCells / unitJ;
		void (^block)(void) = ^{
			for (NSInteger i = start; i < end; i ++) {
				Agent **ap = popL + pRng[i].location;
				NSRange rng = pRng[i];
				for (NSInteger j = 1; j < rng.length; j ++)
					interacts(ap[j], ap, j, rp, wp);
			}
		};
		if (j < unitJ - 1) [self addOperation:block];
		else block();
	}
	[self waitAllOperations];
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif
	NSInteger mesh = worldParams.mesh;
    for (NSInteger x = 1; x < mesh; x += 2) [self addOperation:^{
		for (NSInteger y = 0; y < mesh; y ++)
			[weakSelf gridToGridA:y * mesh + x B:y * mesh + x - 1]; }];
	[self waitAllOperations];
    for (NSInteger x = 2; x < mesh; x += 2) [self addOperation:^{
		for (NSInteger y = 0; y < mesh; y ++)
			[weakSelf gridToGridA:y * mesh + x B:y * mesh + x - 1]; }];
	[self waitAllOperations];
    for (NSInteger y = 1; y < mesh; y += 2) [self addOperation:^{
		for (NSInteger x = 0; x < mesh; x ++)
			[weakSelf gridToGridA:y * mesh + x B:(y - 1) * mesh + x]; }];
	[self waitAllOperations];
    for (NSInteger y = 2; y < mesh; y += 2) [self addOperation:^{
		for (NSInteger x = 0; x < mesh; x ++)
			[weakSelf gridToGridA:y * mesh + x B:(y - 1) * mesh + x]; }];
	[self waitAllOperations];
    for (NSInteger y = 1; y < mesh; y += 2) [self addOperation:^{
		for (NSInteger x = 1; x < mesh; x ++)
			[weakSelf gridToGridA:y * mesh + x B:(y - 1) * mesh + x - 1]; }];
	[self waitAllOperations];
    for (NSInteger y = 2; y < mesh; y += 2) [self addOperation:^{
		for (NSInteger x = 1; x < mesh; x ++)
			[weakSelf gridToGridA:y * mesh + x B:(y - 1) * mesh + x - 1]; }];
	[self waitAllOperations];
    for (NSInteger y = 1; y < mesh; y += 2) [self addOperation:^{
		for (NSInteger x = 1; x < mesh; x ++)
			[weakSelf gridToGridA:y * mesh + x - 1 B:(y - 1) * mesh + x]; }];
	[self waitAllOperations];
    for (NSInteger y = 2; y < mesh; y += 2) [self addOperation:^{
		for (NSInteger x = 1; x < mesh; x ++)
			[weakSelf gridToGridA:y * mesh + x - 1 B:(y - 1) * mesh + x]; }];
	[self waitAllOperations];
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif
// Step
    unitJ = 2;
	NSMutableArray<NSValue *> *infectors[unitJ];
	NSMutableArray<NSLock *> *locks = cellLocks;
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * nInField / unitJ;
		NSInteger end = (j < unitJ - 1)? (j + 1) * nInField / unitJ : nInField;
		NSMutableArray<NSValue *> *infec = infectors[j] = NSMutableArray.new;
		[self addOperation:^{
			for (NSInteger i = start; i < end; i ++) {
				Agent *a = popL[i];
				step_agent(a, rp, wp, weakSelf, locks);
				if (a->newNInfects > 0) {
					[infec addObject:[NSValue valueWithInfect:
						(InfectionCntInfo){a->nInfects, a->nInfects + a->newNInfects}]];
					a->nInfects += a->newNInfects;
					a->newNInfects = 0;
				}
			}
		}];
	}
	for (Agent *a = _QList; a; a = a->next)
		step_agent_in_quarantine(a, &worldParams, self);
	[self waitAllOperations];
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif
	NSArray<WarpInfo *> *newInfos = newWarpF.allValues;
	for (WarpInfo *info in newInfos) {
		Agent *a = info.agent;
		if (a->isWarping) {
			for (NSInteger i = _WarpList.count - 1; i >= 0; i --)
				if (_WarpList[i].agent == a)
					{ [_WarpList removeObjectAtIndex:i]; break; }
		} else {
			a->isWarping = YES;
			switch (info.mode) {
				case WarpInside: case WarpToHospital: case WarpToCemeteryF:
				remove_agent(a, &worldParams, _Pop); break;
				case WarpBack: case WarpToCemeteryH:
				remove_from_list(a, &_QList); break;
			}
		}
	}
	[_WarpList addObjectsFromArray:newInfos];
	[newWarpF removeAllObjects];
	for (NSInteger i = _WarpList.count - 1; i >= 0; i --) {
		WarpInfo *info = _WarpList[i];
		if (warp_step(info.agent, &worldParams, self, info.mode, info.goal))
			[_WarpList removeObjectAtIndex:i];
	}
	
	NSUInteger testCount[NIntTestTypes];
	memset(testCount, 0, sizeof(testCount));
	[self deliverTestResults:testCount];
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
		printf("%ld\t", ++ mCount2);
		for (NSInteger i = 0; i <= tmIdx; i ++) {
			printf("%.3f%c", (double)mtime[i] / mCount, (i < tmIdx)? '\t' : '\n');
			mtime[i] = 0;
		}
#ifdef NOGUI
		mCount = 0;
#else
		if (mCount2 >= 10) {
			if (self.running) in_main_thread(^{ [self startStop:nil]; });
		} else mCount = 0;
#endif
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
#else
- (void)showAllAfterStep {
	[self showCurrentStatistics];
	daysNum.doubleValue = floor(runtimeParams.step / worldParams.stepsPerDay);
	spsNum.doubleValue = stepsPerSec;
	view.needsDisplay = YES;
}
#endif
- (void)runningLoop {
#ifdef NOGUI
	in_main_thread(^{ [self startTimeLimitTimer]; });
	[self forAllReporters:^(PeriodicReporter *rep) { [rep start]; }];
#endif
	while (loopMode == LoopRunning) {
		CGFloat startTime = get_uptime();
		[self doOneStep];
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
			in_main_thread(^{ [self showAllAfterStep]; });
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
#else
	in_main_thread(^{
		self->view.needsDisplay = YES;
		self->startBtn.title = NSLocalizedString(@"Start", nil);
		self->stepBtn.enabled = YES;
		[self->scenarioPanel adjustControls:NO];
	});
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
	if ((result = (_docKey != nil))) _lastTouch = NSDate.date;
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
- (StatInfo *)statInfo { return statInfo; }
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
#else
- (IBAction)startStop:(id)sender {
	if (loopMode != LoopRunning) {
		[self goAhead];
		startBtn.title = NSLocalizedString(@"Stop", nil);
		stepBtn.enabled = NO;
		loopMode = LoopRunning;
		[scenarioPanel adjustControls:NO];
		[NSThread detachNewThreadSelector:
			@selector(runningLoop) toTarget:self withObject:nil];
	} else {
		startBtn.title = NSLocalizedString(@"Start", nil);
		stepBtn.enabled = YES;
		loopMode = LoopEndByUser;
		[scenarioPanel adjustControls:NO];
#ifdef DEBUGx
printf("%ld gatherings, %ld cells\n", gatherings.count, gatheringsMap.count);
for (Gathering *g in gatherings) [g printInfo:&worldParams];
NSArray *keys = [gatheringsMap.allKeys sortedArrayUsingSelector:@selector(compare:)];
for (NSNumber *key in keys)
	printf("%ld:%ld, ", key.integerValue, gatheringsMap[key].count);
printf("\n");
#endif
	}
}
- (IBAction)step:(id)sedner {
	switch (loopMode) {
		case LoopRunning: return;
		case LoopFinished: case LoopEndByCondition: [self goAhead];
		default: [self doOneStep];
	}
	[self showAllAfterStep];
	loopMode = LoopEndByUser;
}
- (IBAction)reset:(id)sender {
	[self resetPop];
	view.needsDisplay = YES;
}
- (IBAction)addOneInfected:(id)sender {
	[self addInfected:1];
}
- (IBAction)switchDaysToStop:(id)sender {
	BOOL orgState = stopAtNDays > 0, newState = stopAtNDaysCBox.state;
	if (orgState == newState) return;
	[self.undoManager registerUndoWithTarget:stopAtNDaysCBox handler:^(NSButton *target) {
		target.state = orgState;
		[target sendAction:target.action to:target.target];
	}];
	stopAtNDays = - stopAtNDays;
}
- (IBAction)changeDaysToStop:(id)sender {
	NSInteger orgDays = stopAtNDays;
	[self.undoManager registerUndoWithTarget:stopAtNDaysDgt handler:^(NSTextField *target) {
		target.integerValue = orgDays;
		[target sendAction:target.action to:target.target];
	}];
	NSInteger days = stopAtNDaysDgt.integerValue;	
	stopAtNDays = stopAtNDaysCBox.state? days : - days;
}
- (IBAction)switchShowGatherings:(id)sender {
	BOOL newValue = showGatheringsCBox.state == NSControlStateValueOn;
	if (newValue == view.showGatherings) return;
	[self.undoManager registerUndoWithTarget:showGatheringsCBox
		handler:^(NSButton *target) {
		target.state = 1 - target.state;
		[target sendAction:target.action to:target.target];
	}];
	view.showGatherings = newValue;
	view.needsDisplay = YES;
}
- (IBAction)changeAnimeSteps:(id)sender {
	NSInteger newSteps = 1 << animeStepper.integerValue;
	if (newSteps == animeSteps) return;
	NSInteger orgExp = 0;
	for (NSInteger i = 1; i < animeSteps; i <<= 1) orgExp ++;
	[self.undoManager registerUndoWithTarget:animeStepper handler:^(NSStepper *target) {
		target.integerValue = orgExp;
		[target sendAction:target.action to:target.target];
	}];
	animeSteps = newSteps;
	show_anime_steps(animeStepsTxt, animeSteps);
}
- (IBAction)animeStepsDouble:(id)sender {
	animeStepper.integerValue = animeStepper.integerValue + 1;
	[self changeAnimeSteps:sender];
}
- (IBAction)animeStepsHalf:(id)sender {
	animeStepper.integerValue = animeStepper.integerValue - 1;
	[self changeAnimeSteps:sender];
}
- (IBAction)openScenarioPanel:(id)sender {
	if (scenarioPanel == nil) scenarioPanel =
		[Scenario.alloc initWithDoc:self];
	[scenarioPanel showWindowWithParent:view.window];
}
- (IBAction)openParamPanel:(id)sender {
	if (paramPanel == nil) paramPanel =
		[ParamPanel.alloc initWithDoc:self];
	[paramPanel showWindowWithParent:view.window];
}
- (IBAction)openDataPanel:(id)sender {
	if (dataPanel == nil) dataPanel =
		[DataPanel.alloc initWithInfo:statInfo];
	[dataPanel showWindowWithParent:view.window];
}
- (IBAction)openStatPenel:(id)sender { [statInfo openStatPanel:view.window]; }
//
- (void)openScenarioFromURL:(NSURL *)url {
	NSObject *pList = get_propertyList_from_url(url, NSArray.class, view.window);
	if (pList != nil) {
		[self openScenarioPanel:self];
		[scenarioPanel setScenarioWithArray:(NSArray *)pList];
	}
}
- (void)openParamsFromURL:(NSURL *)url {
	NSObject *pList = get_propertyList_from_url(url, NSDictionary.class, view.window);
	if (pList != nil) {
		RuntimeParams tmpRParams;
		WorldParams tmpWParams;
		memcpy(&tmpRParams, &runtimeParams, sizeof(RuntimeParams));
		memcpy(&tmpWParams, &worldParams, sizeof(WorldParams));
		set_params_from_dict(&tmpRParams, &tmpWParams, (NSDictionary *)pList);
		[self openParamPanel:self];
		[paramPanel setParamsOfRuntime:&tmpRParams world:&tmpWParams];
	}
}
- (void)revisePanelsAlpha {
	if (paramPanel != nil) paramPanel.window.alphaValue = panelsAlpha;
	if (scenarioPanel != nil) scenarioPanel.window.alphaValue = panelsAlpha;
}
- (void)revisePanelChildhood {
	NSArray<NSWindow *> *children = view.window.childWindows;
	if (!makePanelChildWindow) {
		for (NSWindow *child in children)
			[view.window removeChildWindow:child];
	} else if (children == nil || children.count == 0) {
		if (paramPanel != nil) [paramPanel setupParentWindow:view.window];
		if (scenarioPanel != nil) [scenarioPanel setupParentWindow:view.window];
		if (dataPanel != nil) [dataPanel setupParentWindow:view.window];
		for (StatPanel *stp in statInfo.statPanels)
			[stp setupParentWindow:view.window];
	}
}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = menuItem.action;
	if (action == @selector(startStop:))
		menuItem.title = NSLocalizedString((loopMode == LoopRunning)? @"Stop" : @"Start", nil);
	else if (action == @selector(step:)) return (loopMode != LoopRunning);
	else if (action == @selector(animeStepsDouble:))
		return animeStepper.integerValue < animeStepper.maxValue;
	else if (action == @selector(animeStepsHalf:))
		return animeStepper.integerValue > animeStepper.minValue;
	return YES;
}
#endif
@end

@implementation WarpInfo
- (instancetype)initWithAgent:(Agent *)a goal:(CGPoint)p mode:(WarpType)md {
	if ((self = [super init]) == nil) return nil;
	_agent = a;
	_goal = p;
	_mode = md;
	return self;
}
@end 
