//
//  Document.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <sys/sysctl.h>
#import <sys/resource.h>
#import "Document.h"
#import "Agent.h"
#import "MyView.h"
#import "Scenario.h"
#import "ParamPanel.h"
#import "StatPanel.h"
#import "DataPanel.h"
#import "Parameters.h"
#define ALLOC_UNIT 2048
typedef enum {
	LoopNone, LoopRunning, LoopFinished, LoopEndByUser,
	LoopEndByCondition, LoopEndAsDaysPassed
} LoopMode;
#define DYNAMIC_STRUCT(t,f,n,fm) static t *f = NULL;\
static t *n(void) {\
	if (f == NULL) {\
		f = malloc(sizeof(t) * ALLOC_UNIT);\
		for (NSInteger i = 0; i < ALLOC_UNIT - 1; i ++) f[i].next = f + i + 1;\
		f[ALLOC_UNIT - 1].next = NULL;\
	}\
	t *a = f; f = f->next; a->next = NULL; return a;\
}\
static void fm(t **ap) {\
	if (*ap == NULL) return;\
	for (t *p = *ap; ; p = p->next)\
		if (p->next == NULL) { p->next = f; break; }\
	f = *ap; *ap = NULL;\
}
DYNAMIC_STRUCT(Agent, freePop, new_agent, free_agent_mems)
DYNAMIC_STRUCT(TestEntry, freeTestEntries, new_testEntry, free_testEntry_mems)
DYNAMIC_STRUCT(ContactInfo, freeCInfo, new_cinfo, free_cinfo_mems)
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
	in_main_thread(^{ [NSApp terminate:nil]; });
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

@interface Document () {
	NSInteger scenarioIndex;
	Scenario *scenarioPanel;
	ParamPanel *paramPanel;
	DataPanel *dataPanel;
	LoopMode loopMode;
	NSInteger nPop, nMesh;
	Agent **pop;
	NSRange *pRange;
	CGFloat prevTime, stepsPerSec;
	NSMutableDictionary<NSNumber *, WarpInfo *> *newWarpF;
	NSMutableDictionary<NSNumber *, NSNumber *> *testees;
	NSLock *newWarpLock, *testeesLock;
	NSInteger animeSteps, stopAtNDays;
	NSArray *scenario;
	NSPredicate *predicateToStop;
	TestEntry *testQueHead, *testQueTail;
	dispatch_queue_t dispatchQueue;
	dispatch_group_t dispatchGroup;
	NSSize orgWindowSize, orgViewSize;
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
#endif
- (void)popLock { [popLock lock]; }
- (void)popUnlock { [popLock unlock]; }
- (NSMutableArray<MyCounter *> *)RecovPHist { return statInfo.RecovPHist; }
- (NSMutableArray<MyCounter *> *)IncubPHist { return statInfo.IncubPHist; }
- (NSMutableArray<MyCounter *> *)DeathPHist { return statInfo.DeathPHist; }
- (void)addOperation:(void (^)(void))block {
	dispatch_group_async(dispatchGroup, dispatchQueue, block);
}
- (void)waitAllOperations {
	dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
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
#endif
- (void)setInitialParameters:(NSData *)newParams {
	NSData *orgParams = [NSData dataWithBytes:&initParams length:sizeof(RuntimeParams)];
	[self.undoManager registerUndoWithTarget:self handler:
		^(Document *target) { [target setInitialParameters:orgParams]; }];
	memcpy(&initParams, newParams.bytes, sizeof(RuntimeParams));
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
	char visitFlags[scenario.count];
	memset(visitFlags, 0, scenario.count);
	predicateToStop = nil;
	if (scenario == nil) return;
	NSMutableDictionary *md = NSMutableDictionary.new;
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
			} else md[((NSArray *)item)[0]] = ((NSArray *)item)[1];	// paramter assignment
		} else if ([item isKindOfClass:NSDictionary.class]) {	// for upper compatibility
			[md addEntriesFromDictionary:(NSDictionary *)item];
		} else if ([item isKindOfClass:NSNumber.class]) {	// add infected individuals
			[self addInfected:((NSNumber *)item).integerValue];
		} else if ([item isKindOfClass:NSPredicate.class]) {	// predicate to stop
			predicateToStop = (NSPredicate *)item;
#ifndef NOGUI
			in_main_thread( ^{ [self adjustScenarioText]; });
#endif
			break;
		}
	}
	if (md.count > 0) {
		set_params_from_dict(&runtimeParams, &worldParams, md);
		in_main_thread( ^{ [self->paramPanel adjustControls]; });
	}
	if (predicateToStop == nil && scenarioIndex == scenario.count) scenarioIndex ++;
	[statInfo phaseChangedTo:scenarioIndex];
}
- (NSArray *)scenario { return scenario; }
static NSArray<NSNumber *> *phase_info(NSArray *scen) {
	NSMutableArray<NSNumber *> *ma = NSMutableArray.new;
	for (NSInteger i = 0; i < scen.count; i ++)
		if ([scen[i] isKindOfClass:NSPredicate.class])
			[ma addObject:@(i + 1)];
	// if the final item is not an unconditional jump then add finale phase.
	NSArray *item = scen.lastObject;
	if (![item isKindOfClass:NSArray.class] || item.count != 1 ||
		![item[0] isKindOfClass:NSNumber.class])
		[ma addObject:@(scen.count + 1)];
	return ma;
}
- (void)setScenario:(NSArray *)newScen {
	if (self.running) return;
	NSArray *orgScen = scenario;
	[self.undoManager registerUndoWithTarget:self handler:
		^(Document *target) { target.scenario = orgScen; }];
	scenario = newScen;
	scenarioIndex = 0;
	statInfo.phaseInfo = phase_info(scenario);
#ifndef NOGUI
	[self adjustScenarioText];
#endif
	if (runtimeParams.step == 0) [self execScenario];
#ifndef NOGUI
	[scenarioPanel adjustControls:
		self.undoManager.undoing || self.undoManager.redoing];
#endif
}
#ifndef NOGUI
- (void)showCurrentStatistics {
	StatData *stat = statInfo.statistics;
	for (NSInteger i = 0; i < NHealthTypes; i ++)
		lvViews[i].integerValue = stat->cnt[i];
	qNSNum.integerValue = stat->cnt[QuarantineAsym];
	qDSNum.integerValue = stat->cnt[QuarantineSymp];
	[statInfo flushPanels];
}
#endif
- (void)resetPop {
	if (memcmp(&worldParams, &tmpWorldParams, sizeof(WorldParams)) != 0) {
		memcpy(&worldParams, &tmpWorldParams, sizeof(WorldParams));
		[self updateChangeCount:NSChangeDone];
	}
	if (scenario != nil) {
		memcpy(&runtimeParams, &initParams, sizeof(RuntimeParams));
		[paramPanel adjustControls];
	}
	[popLock lock];
	for (NSInteger i = 0; i < nMesh * nMesh; i ++)
		for (Agent *a = _Pop[i]; a != NULL; a = a->next) {
			free_cinfo_mems(&a->contactInfoHead);
			a->contactInfoTail = NULL;
		}
	if (nMesh != worldParams.mesh) {
		nMesh = worldParams.mesh;
		NSInteger popMemSz = sizeof(void *) * nMesh * nMesh;
		_Pop = realloc(_Pop, popMemSz);
		pRange = realloc(pRange, sizeof(NSRange) * nMesh * nMesh);
		memset(_Pop, 0, popMemSz);
	} else for (NSInteger i = 0; i < nMesh * nMesh; i ++)
		free_agent_mems(_Pop + i);
	if (nPop != worldParams.initPop) {
		nPop = worldParams.initPop;
		pop = realloc(pop, sizeof(void *) * nPop);
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
		Agent *a = new_agent();
		a->ID = i;
		reset_agent(a, &runtimeParams, &worldParams);
		if (i < nDist) a->distancing = YES;
		if (iIdx < worldParams.nInitInfec && i == infecIdxs[iIdx]) {
			a->health = Asymptomatic; iIdx ++;
			a->nInfects = 0;
		}
		add_agent(a, &worldParams, _Pop);
	}
	free_agent_mems(&_QList);
	free_agent_mems(&_CList);
	_WarpList = NSMutableArray.new;
	free_testEntry_mems(&testQueHead);
	testQueTail = NULL;
	runtimeParams.step = 0;
	[statInfo reset:nPop infected:worldParams.nInitInfec];
	[popLock unlock];
	scenarioIndex = 0;
	[self execScenario];
#ifndef NOGUI
	daysNum.doubleValue = 0.;
	[self showCurrentStatistics];
#endif
	loopMode = LoopNone;
}
- (instancetype)init {
	if ((self = [super init]) == nil) return nil;
	if (cInfoLock == nil) cInfoLock = NSLock.new;
	dispatchGroup = dispatch_group_create();
	dispatchQueue = dispatch_queue_create(
		"jp.ac.soka.unemi.SimEpidemic.queue", DISPATCH_QUEUE_CONCURRENT);
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
	self.undoManager = NSUndoManager.new;
#ifdef NOGUI
	statInfo = StatInfo.new;
	statInfo.doc = self;
	[self resetPop];
#endif
	return self;
}
#ifndef NOGUI
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
	if (scenario != nil) statInfo.phaseInfo = phase_info(scenario);
	[self resetPop];
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
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)fSize {
	NSSize aSize = { fSize.width - orgWindowSize.width + orgViewSize.width,
		fSize.height - orgWindowSize.height + orgViewSize.height };
	if (aSize.width * orgViewSize.height > aSize.height * orgViewSize.width)
		aSize.width = aSize.height * orgViewSize.width / orgViewSize.height;
	else aSize.height = aSize.width * orgViewSize.height / orgViewSize.width;
	return (NSSize){ aSize.width + orgWindowSize.width - orgViewSize.width,
		aSize.height + orgWindowSize.height - orgViewSize.height };
}
#endif
NSString *keyParameters = @"parameters", *keyScenario = @"scenario";
static NSObject *property_from_element(NSObject *elm) {
	if ([elm isKindOfClass:NSPredicate.class]) return ((NSPredicate *)elm).predicateFormat;
	else if (![elm isKindOfClass:NSArray.class]) return elm;
	else if (![((NSArray *)elm)[0] isKindOfClass:NSNumber.class]) return elm;
	else if (((NSArray *)elm).count == 1) return elm;
	else return @[((NSArray *)elm)[0], ((NSPredicate *)((NSArray *)elm)[1]).predicateFormat];
}
static NSObject *element_from_property(NSObject *prop) {
	if ([prop isKindOfClass:NSString.class])
		return [NSPredicate predicateWithFormat:(NSString *)prop];
	else if (![prop isKindOfClass:NSArray.class]) return prop;
	else if (![((NSArray *)prop)[0] isKindOfClass:NSNumber.class]) return prop;
	else if (((NSArray *)prop).count == 1) return prop;
	else return @[((NSArray *)prop)[0],
		[NSPredicate predicateWithFormat:(NSString *)((NSArray *)prop)[1]]];
}
- (NSDictionary *)documentDictionary {
	NSMutableDictionary *dict = NSMutableDictionary.new;
	dict[keyAnimeSteps] = @(animeSteps);
	if (scenario != nil) {
		dict[keyParameters] = param_dict(&initParams, &worldParams);
		NSObject *items[scenario.count];
		for (NSInteger i = 0; i < scenario.count; i ++)
			items[i] = property_from_element(scenario[i]);
		dict[keyScenario] = [NSArray arrayWithObjects:items count:scenario.count];
	} else dict[keyParameters] = param_dict(&runtimeParams, &worldParams);
	return dict;
}
- (BOOL)readFromDictionary:(NSDictionary *)dict {
	NSNumber *num = dict[keyAnimeSteps];
	if (num != nil) animeSteps = num.integerValue;
	NSDictionary *pDict = dict[keyParameters];
	if (pDict != nil) {
		set_params_from_dict(&runtimeParams, &worldParams, pDict);
		memcpy(&tmpWorldParams, &worldParams, sizeof(WorldParams));
	}
	NSArray *seq = dict[keyScenario];
	if (seq != nil) {
		NSObject *items[seq.count];
		for (NSInteger i = 0; i < seq.count; i ++)
			items[i] = element_from_property(seq[i]);
		scenario = [NSArray arrayWithObjects:items count:seq.count];
		scenarioIndex = 0;
		if (statInfo != nil) {
			statInfo.phaseInfo = phase_info(scenario);
			[self execScenario];
		}
		memcpy(&initParams, &runtimeParams, sizeof(RuntimeParams));
	}
	return YES;
}
#ifdef NOGUI
- (NSData *)JSONdataWithOptions:(NSUInteger)options error:(NSError **)outError {
	return [NSJSONSerialization dataWithJSONObject:[self documentDictionary]
		options:options error:outError];
}
- (BOOL)readFromJSONData:(NSData *)data error:(NSError **)outError {
	NSDictionary *dict = [NSJSONSerialization
		JSONObjectWithData:data options:0 error:outError];
	if (dict == nil) return NO;
	return [self readFromDictionary:dict];
}
#else
- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
	NSDictionary *dict = [self documentDictionary];
	return [NSPropertyListSerialization dataWithPropertyList:dict
		format:NSPropertyListXMLFormat_v1_0 options:0 error:outError];
}
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
	NSDictionary *dict = [NSPropertyListSerialization
		propertyListWithData:data options:NSPropertyListImmutable
		format:NULL error:outError];
	if (dict == nil) return NO;
	return [self readFromDictionary:dict];
}
#endif
static NSLock *testEntriesLock = nil;
- (void)testInfectionOfAgent:(Agent *)agent reason:(TestType)reason {
	if (runtimeParams.step - agent->lastTested <
		runtimeParams.tstInterval * worldParams.stepsPerDay ||
		agent->isOutOfField) return;
	[testeesLock lock];
	testees[@((NSUInteger)agent)] = @(reason);
	[testeesLock unlock];
}
- (void)deliverTestResults:(NSUInteger *)testCount {
	// check the results of tests
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
			[self addNewWarp:[WarpInfo.alloc initWithAgent:a goal:newPt mode:WarpToHospital]];
			for (ContactInfo *c = a->contactInfoHead; c != NULL; c = c->next)
				[self testInfectionOfAgent:c->agent reason:TestAsContact];
			[cInfoLock lock];
			free_cinfo_mems(&a->contactInfoHead);
			[cInfoLock unlock];
			a->contactInfoTail = NULL;
		} else testCount[TestNegative] ++;
		testQueHead = entry->next;
		if (entry->next) entry->next->prev = NULL;
		else testQueTail = NULL;
		entry->next = freeTestEntries;
		freeTestEntries = entry;
	}

	// enqueue new tests
	if (testEntriesLock == nil) testEntriesLock = NSLock.new;
	[testEntriesLock lock];
	for (NSNumber *num in testees.keyEnumerator) {
		testCount[testees[num].integerValue] ++;
		Agent *agent = (Agent *)num.integerValue;
		TestEntry *entry = new_testEntry();
		entry->isPositive = is_infected(agent)?
			(random() < 0x7fffffff * runtimeParams.tstSens / 100.) :
			(random() > 0x7fffffff * runtimeParams.tstSpec / 100.);
		agent->lastTested = entry->timeStamp = runtimeParams.step;
		entry->agent = agent;
		if ((entry->prev = testQueTail) != NULL) testQueTail->next = entry;
		else testQueHead = entry;
		entry->next = NULL;
		testQueTail = entry;
	}
	[testEntriesLock unlock];
	[testees removeAllObjects];
	for (NSInteger i = TestAsSymptom; i < TestPositive; i ++)
		testCount[TestTotal] += testCount[i];
}
- (void)gridToGridA:(NSInteger)iA B:(NSInteger)iB {
	Agent **apA = pop + pRange[iA].location, **apB = pop + pRange[iB].location;
	for (NSInteger j = 0; j < pRange[iA].length; j ++)
	for (NSInteger k = 0; k < pRange[iB].length; k ++)
		interacts(apA[j], apB[k], &runtimeParams, &worldParams);
}
- (void)addNewWarp:(WarpInfo *)info {
	[newWarpLock lock];
	newWarpF[@((NSUInteger)info.agent)] = info;
	[newWarpLock unlock];
}
//#define MEASURE_TIME
#ifdef MEASURE_TIME
#define N_MTIME 6
static unsigned long mtime[N_MTIME] = {0,0,0,0,0,0};
static NSInteger mCount = 0, mCount2 = 0;
#endif
- (void)doOneStep {
	[popLock lock];
#ifdef MEASURE_TIME
	unsigned long tm0 = current_time_us(), tm1 = tm0, tm2;
	NSInteger tmIdx = 0;
	mCount ++;
#endif
	NSInteger nCells = worldParams.mesh * worldParams.mesh;
	memset(pRange, 0, sizeof(NSRange) * nCells);
	NSInteger nInField = 0;
	for (NSInteger i = 0; i < nCells; i ++) {
		if (i > 0) pRange[i - 1].length = nInField - pRange[i - 1].location;
		pRange[i].location = nInField;
		for (Agent *p = _Pop[i]; p; p = p->next) pop[nInField ++] = p;
	}
	pRange[nCells - 1].length = nInField - pRange[nCells - 1].location;
	NSInteger oldTimeStamp = runtimeParams.step - worldParams.stepsPerDay * 14;	// two weeks
	Agent **popL = pop;
	for (NSInteger j = 0; j < nCores; j ++) {
		NSInteger start = j * nInField / nCores;
		NSInteger end = (j < nCores - 1)? (j + 1) * nInField / nCores : nInField;
		[self addOperation:^{
			for (NSInteger i = start; i < end; i ++) {
				reset_for_step(popL[i]);
				remove_old_cinfo(popL[i], oldTimeStamp);
		}}];
	}
	[self waitAllOperations];
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif
	RuntimeParams *rp = &runtimeParams;
	WorldParams *wp = &worldParams;
	__weak typeof(self) weakSelf = self;
	for (NSInteger i = 0; i < nCells; i ++) {
		Agent **ap = popL + pRange[i].location;
		NSRange rng = pRange[i];
		[self addOperation:^{
			for (NSInteger j = 0; j < rng.length; j ++)
			for (NSInteger k = j + 1; k < rng.length; k ++)
				interacts(ap[j], ap[k], rp, wp);
		}];
	}
	[self waitAllOperations];
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif
	NSInteger mesh = worldParams.mesh;
	for (NSInteger x = 1; x < mesh; x += 2)
		for (NSInteger y = 0; y < mesh; y ++) [self addOperation:^{
			[weakSelf gridToGridA:y * mesh + x B:y * mesh + x - 1]; }];
	[self waitAllOperations];
	for (NSInteger x = 2; x < mesh; x += 2)
		for (NSInteger y = 0; y < mesh; y ++) [self addOperation:^{
			[weakSelf gridToGridA:y * mesh + x B:y * mesh + x - 1]; }];
	[self waitAllOperations];
	for (NSInteger y = 1; y < mesh; y += 2)
		for (NSInteger x = 0; x < mesh; x ++) [self addOperation:^{
			[weakSelf gridToGridA:y * mesh + x B:(y - 1) * mesh + x]; }];
	[self waitAllOperations];
	for (NSInteger y = 2; y < mesh; y += 2)
		for (NSInteger x = 0; x < mesh; x ++) [self addOperation:^{
			[weakSelf gridToGridA:y * mesh + x B:(y - 1) * mesh + x]; }];
	[self waitAllOperations];
	for (NSInteger y = 1; y < mesh; y += 2)
		for (NSInteger x = 1; x < mesh; x ++) [self addOperation:^{
			[weakSelf gridToGridA:y * mesh + x B:(y - 1) * mesh + x - 1]; }];
	[self waitAllOperations];
	for (NSInteger y = 2; y < mesh; y += 2)
		for (NSInteger x = 1; x < mesh; x ++) [self addOperation:^{
			[weakSelf gridToGridA:y * mesh + x B:(y - 1) * mesh + x - 1]; }];
	[self waitAllOperations];
	for (NSInteger y = 1; y < mesh; y += 2)
		for (NSInteger x = 1; x < mesh; x ++) [self addOperation:^{
			[weakSelf gridToGridA:y * mesh + x - 1 B:(y - 1) * mesh + x]; }];
	[self waitAllOperations];
	for (NSInteger y = 2; y < mesh; y += 2)
		for (NSInteger x = 1; x < mesh; x ++) [self addOperation:^{
			[weakSelf gridToGridA:y * mesh + x - 1 B:(y - 1) * mesh + x]; }];
	[self waitAllOperations];
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif
// Step
	NSMutableArray<NSValue *> *infectors[nCores];
	NSUInteger transitCnt[NHealthTypes][nCores];
	memset(transitCnt, 0, sizeof(transitCnt));
	for (NSInteger j = 0; j < nCores; j ++) {
		NSInteger start = j * nInField / nCores;
		NSInteger end = (j < nCores - 1)? (j + 1) * nInField / nCores : nInField;
		NSMutableArray<NSValue *> *infec = infectors[j] = NSMutableArray.new;
		[self addOperation:^{
			for (NSInteger i = start; i < end; i ++) {
				Agent *a = popL[i];
				step_agent(a, rp, wp, weakSelf);
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

//	BOOL finished = [statInfo calcStat:_Pop nCells:nCells
//		qlist:_QList clist:_CList warp:_WarpList
//		testCount:testCount stepsPerDay:worldParams.stepsPerDay];
	BOOL finished = [statInfo calcStatWithTestCount:testCount infects:
		[NSArray arrayWithObjects:infectors count:nCores]];
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
		if (mCount2 >= 10) {
			if (self.running) in_main_thread(^{ [self startStop:nil]; });
		} else mCount = 0;
	}
#endif
}
#ifndef NOGUI
- (void)showAllAfterStep {
	[self showCurrentStatistics];
	daysNum.doubleValue = floor(runtimeParams.step / worldParams.stepsPerDay);
	spsNum.doubleValue = self->stepsPerSec;
	view.needsDisplay = YES;
}
#endif
- (void)runningLoop {
	while (loopMode == LoopRunning) {
		[self doOneStep];
		if (loopMode == LoopEndByCondition && scenarioIndex < scenario.count) {
			[self execScenario];
			loopMode = LoopRunning;
		}
		if (stopAtNDays > 0 && stopAtNDays * worldParams.stepsPerDay == runtimeParams.step) {
			loopMode = LoopEndAsDaysPassed;
			break;
		}
		CGFloat newTime = get_uptime(), timePassed = newTime - prevTime;
		if (timePassed < 1.)
			stepsPerSec += (fmin(30., 1. / timePassed) - stepsPerSec) * 0.2;
		prevTime = newTime;
#ifndef NOGUI
		if (runtimeParams.step % animeSteps == 0) {
			in_main_thread(^{ [self showAllAfterStep]; });
			NSInteger usToWait = (1./30. - timePassed) * 1e6;
			usleep((unsigned int)((usToWait < 0)? 1 : usToWait));
		} else
#endif
		usleep(1);
	}
#ifndef NOGUI
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
- (void)start:(NSInteger)stopAt {
	if (loopMode == LoopRunning) return;
	if (stopAt > 0) stopAtNDays = stopAt;
	[self goAhead];
	loopMode = LoopRunning;
	[NSThread detachNewThreadSelector:@selector(runningLoop) toTarget:self withObject:nil];
}
- (void)step {
	switch (loopMode) {
		case LoopRunning: return;
		case LoopFinished: case LoopEndByCondition: [self goAhead];
		case LoopEndByUser: case LoopNone: case LoopEndAsDaysPassed:
		[self doOneStep];
	}
	loopMode = LoopEndByUser;
}
- (void)stop {
	if (loopMode == LoopRunning) loopMode = LoopEndByUser;
}
- (StatInfo *)statInfo { return statInfo; }
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
	}
}
- (IBAction)step:(id)sedner {
	switch (loopMode) {
		case LoopRunning: return;
		case LoopFinished: case LoopEndByCondition: [self goAhead];
		case LoopEndByUser: case LoopNone: case LoopEndAsDaysPassed:
		[self doOneStep];
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
