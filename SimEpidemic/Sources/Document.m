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
#define ALLOC_UNIT 2048
typedef enum {
	LoopNone, LoopRunning, LoopFinished, LoopEndByUser, LoopEndByCondition
} LoopMode;
static Agent *freePop = NULL;
static Agent *new_agent(void) {
	if (freePop == NULL) {
		freePop = malloc(sizeof(Agent) * ALLOC_UNIT);
		for (NSInteger i = 0; i < ALLOC_UNIT - 1; i ++)
			freePop[i].next = freePop + i + 1;
		freePop[ALLOC_UNIT - 1].next = NULL;
	}
	Agent *a = freePop;
	freePop = freePop->next;
	a->next = NULL;
	return a;
}
static void free_agent_mems(Agent **ap) {
	if (*ap == NULL) return;
	for (Agent *p = *ap; ; p = p->next)
		if (p->next == NULL) { p->next = freePop; break; }
	freePop = *ap;
	*ap = NULL;
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

@implementation NSWindowController (ChildWindowExtension)
- (void)showWindowWithParent:(NSWindow *)parentWindow {
	if (self.window.parentWindow == nil)
		[parentWindow addChildWindow:self.window ordered:NSWindowAbove];
	[self showWindow:self];
}
@end

@interface Document () {
	NSInteger seqIndex;
	Scenario *scenarioPanel;
	ParamPanel *paramPanel;
	DataPanel *dataPanel;
	LoopMode loopMode;
	NSInteger nPop, nMesh;
	Agent **pop;
	NSRange *pRange;
	CGFloat prevTime, stepsPerSec;
	NSMutableArray<WarpInfo *> *newWarpF;
	NSLock *newWarpLock;
	NSInteger animeSteps;
	NSArray *scenario;
	NSPredicate *predicateToStop;
	dispatch_queue_t dispatchQueue;
	dispatch_group_t dispatchGroup;
	NSSize orgWindowSize, orgViewSize;
}
@end

@implementation Document
- (Agent **)QListP { return &_QList; }
- (Agent **)CListP { return &_CList; }
- (Params *)paramsP { return &params; }
- (Params *)initParamsP { return &initParams; }
- (BOOL)running { return loopMode == LoopRunning; }
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
	NSData *orgParams = [NSData dataWithBytes:&initParams length:sizeof(Params)];
	[self.undoManager registerUndoWithTarget:self handler:
		^(Document *target) { [target setInitialParameters:orgParams]; }];
	memcpy(&initParams, newParams.bytes, sizeof(Params));
}
- (void)showScenarioDesc {
	scenarioText.stringValue = (scenario == nil)? NSLocalizedString(@"None", nil) :
		[NSString stringWithFormat:@"%ld items", scenario.count];
}
- (void)setScenario:(NSArray *)newScen {
	NSArray *orgScen = scenario;
	[self.undoManager registerUndoWithTarget:self handler:
		^(Document *target) { target.scenario = orgScen; }];
	scenario = newScen;
	[self showScenarioDesc];
}
- (void)addInfected:(NSInteger)n {
	NSInteger nSusc = 0;
	for (NSInteger i = 0; i < params.mesh * params.mesh; i ++)
		for (Agent *a = _Pop[i]; a; a = a->next) if (a->health == Susceptible) nSusc ++;
	if (nSusc == 0) return;
	if (n >= nSusc) {
		n = nSusc;
		for (NSInteger i = 0; i < params.mesh * params.mesh; i ++)
			for (Agent *a = _Pop[i]; a; a = a->next) if (a->health == Susceptible)
				{ a->health = Asymptomatic; a->daysI = a->daysD = 0; }
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
		for (NSInteger i = 0, j = 0, k = 0; i < params.mesh * params.mesh && j < n; i ++)
		for (Agent *a = _Pop[i]; a; a = a->next) if (a->health == Susceptible) {
			if (k == idx) {
				a->health = Asymptomatic; a->daysI = a->daysD = 0;
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
	in_main_thread(^{
		[self showCurrentStatistics];
		self->view.needsDisplay = YES;
	});
}
- (void)setParamsAndConditionFromSequence {
	predicateToStop = nil;
	while (seqIndex < scenario.count) {
		NSObject *item = scenario[seqIndex ++];
		if ([item isKindOfClass:NSDictionary.class]) {
			set_params_from_dict(&params, (NSDictionary *)item);
			in_main_thread( ^{ [self->paramPanel adjustControls]; });
		} else if ([item isKindOfClass:NSNumber.class]) {
			[self addInfected:((NSNumber *)item).integerValue];
		} else if ([item isKindOfClass:NSPredicate.class]) {
			in_main_thread( ^{
				self->stopCond.stringValue = ((NSPredicate *)item).predicateFormat; });
			predicateToStop = (NSPredicate *)item;
			break;
		}
	}
	if (predicateToStop == nil)
		in_main_thread( ^{ self->stopCond.stringValue = NSLocalizedString(@"None", nil); });
}
- (void)showCurrentStatistics {
	StatData *stat = statInfo.statistics;
	for (NSInteger i = 0; i < NHealthTypes; i ++)
		lvViews[i].integerValue = stat->cnt[i];
	qNSNum.integerValue = stat->cnt[QuarantineAsym];
	qDSNum.integerValue = stat->cnt[QuarantineSymp];
	[statInfo flushPanels];
}
- (void)resetPop {
	if (initParams.initPop > 0) memcpy(&params, &initParams, sizeof(Params));
	[popLock lock];
	if (nMesh != params.mesh) {
		nMesh = params.mesh;
		NSInteger popMemSz = sizeof(void *) * nMesh * nMesh;
		_Pop = realloc(_Pop, popMemSz);
		pRange = realloc(pRange, sizeof(NSRange) * nMesh * nMesh);
		memset(_Pop, 0, popMemSz);
	} else for (NSInteger i = 0; i < nMesh * nMesh; i ++)
		free_agent_mems(_Pop + i);
	if (nPop != params.initPop) {
		nPop = params.initPop;
		pop = realloc(pop, sizeof(void *) * nPop);
	}
	NSInteger nDist = params.dstOB / 100. * nPop;
	NSInteger iIdx = 0, infecIdxs[params.nInitInfec];
	for (NSInteger i = 0; i < params.nInitInfec; i ++) {
		NSInteger k = (nPop - i - 1) * random() / 0x7fffffff;
		for (NSInteger j = 0; j < i; j ++) if (k >= infecIdxs[j]) k ++;
		infecIdxs[i] = k;
	}
	qsort_b(infecIdxs, params.nInitInfec, sizeof(NSInteger), ^int(const void *a, const void *b) {
		NSInteger *x = (NSInteger *)a, *y = (NSInteger *)b;
		return (*x < *y)? -1 : (*x > *y)? 1 : 0;
	});
// for (NSInteger i = 0; i < params.nInitInfec; i ++) printf("%ld,", infecIdxs[i]); printf("\n");
	for (NSInteger i = 0; i < nPop; i ++) {
		Agent *a = new_agent();
		a->ID = i;
		reset_agent(a, &params);
		if (i < nDist) a->distancing = YES;
		if (iIdx < params.nInitInfec && i == infecIdxs[iIdx])
			{ a->health = Asymptomatic; iIdx ++; }
		add_agent(a, &params, _Pop);
	}
	free_agent_mems(&_QList);
	free_agent_mems(&_CList);
	_WarpList = NSMutableArray.new;
	step = 0;
	[statInfo reset:nPop infected:params.nInitInfec];
	[popLock unlock];
	seqIndex = 0;
	[self setParamsAndConditionFromSequence];
	daysNum.doubleValue = 0.;
	[self showCurrentStatistics];
}
- (instancetype)init {
	if ((self = [super init]) == nil) return nil;
	dispatchGroup = dispatch_group_create();
	dispatchQueue = dispatch_queue_create(
		"jp.ac.soka.unemi.SimEpidemic.queue", DISPATCH_QUEUE_CONCURRENT);
	popLock = NSLock.new;
	newWarpF = NSMutableArray.new;
	newWarpLock = NSLock.new;
	animeSteps = defaultAnimeSteps;
	memcpy(&params, &userDefaultParams, sizeof(Params));
	self.undoManager = NSUndoManager.new;
	return self;
}
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
	[self resetPop];
	show_anime_steps(animeStepsTxt, animeSteps);
	if (scenario != nil) [self showScenarioDesc];
	orgWindowSize = windowController.window.frame.size;
	orgViewSize = view.frame.size;
	[self openStatPenel:self];
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
static NSString *keyInitialParameters = @"initialParameters", *keyScenario = @"scenario";
- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
	NSMutableDictionary *dict = NSMutableDictionary.new;
	dict[keyAnimeSteps] = @(animeSteps);
	if (initParams.initPop > 0) dict[keyInitialParameters] = param_dict(&initParams);
	if (scenario != nil) {
		NSObject *items[scenario.count];
		for (NSInteger i = 0; i < scenario.count; i ++)
			items[i] = [scenario[i] isKindOfClass:NSPredicate.class]?
				((NSPredicate *)scenario[i]).predicateFormat : scenario[i];
		dict[keyScenario] = [NSArray arrayWithObjects:items count:scenario.count];
	}
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
	NSDictionary *initPDict = dict[keyInitialParameters];
	if (initPDict != nil) set_params_from_dict(&initParams, initPDict);
	NSArray *seq = dict[keyScenario];
	if (seq != nil) {
		NSObject *items[seq.count];
		for (NSInteger i = 0; i < seq.count; i ++)
			items[i] = [seq[i] isKindOfClass:NSString.class]?
				[NSPredicate predicateWithFormat:(NSString *)seq[i]] : seq[i];
		scenario = [NSArray arrayWithObjects:items count:seq.count];
		if (scenarioText != nil) [self showScenarioDesc];
	}
	seqIndex = 0;
	[self setParamsAndConditionFromSequence];
	return YES;
}
- (void)gridToGridA:(NSInteger)iA B:(NSInteger)iB {
	Agent **apA = pop + pRange[iA].location, **apB = pop + pRange[iB].location;
	for (NSInteger j = 0; j < pRange[iA].length; j ++)
	for (NSInteger k = 0; k < pRange[iB].length; k ++)
		interacts(apA[j], apB[k], &params);
}
- (void)addNewWarp:(WarpInfo *)info {
	[newWarpLock lock];
	[newWarpF addObject:info];
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
	NSInteger nCells = params.mesh * params.mesh;
	memset(pRange, 0, sizeof(NSRange) * nCells);
	NSInteger nInField = 0;
	for (NSInteger i = 0; i < nCells; i ++) {
		if (i > 0) pRange[i - 1].length = nInField - pRange[i - 1].location;
		pRange[i].location = nInField;
		for (Agent *p = _Pop[i]; p; p = p->next) pop[nInField ++] = p;
	}
	pRange[nCells - 1].length = nInField - pRange[nCells - 1].location;
	for (NSInteger i = 0; i < nInField; i ++) reset_for_step(pop[i]);
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif

	Params *para = &params;
	Agent **popL = pop;
	__weak typeof(self) weakSelf = self;
	for (NSInteger i = 0; i < nCells; i ++) {
		Agent **ap = popL + pRange[i].location;
		NSRange rng = pRange[i];
		[self addOperation:^{
			for (NSInteger j = 0; j < rng.length; j ++)
			for (NSInteger k = j + 1; k < rng.length; k ++)
				interacts(ap[j], ap[k], para);
		}];
	}
	[self waitAllOperations];
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif
	NSInteger mesh = params.mesh;
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

	NSUInteger transitCnt[NHealthTypes][nCores];
	memset(transitCnt, 0, sizeof(transitCnt));
	for (NSInteger j = 0; j < nCores; j ++) {
		NSInteger start = j * nInField / nCores;
		NSInteger end = (j < nCores - 1)? (j + 1) * nInField / nCores : nInField;
		[self addOperation:^{
			for (NSInteger i = start; i < end; i ++)
				step_agent(popL[i], para, weakSelf);
		}];
	}
	for (Agent *a = _QList; a; a = a->next)
		step_agent_in_quarantine(a, &params, self);
	[self waitAllOperations];
#ifdef MEASURE_TIME
	tm2 = current_time_us();
	mtime[tmIdx ++] += tm2 - tm1;
	tm1 = tm2;
#endif

	for (WarpInfo *info in newWarpF) {
		Agent *a = info.agent;
		if (a->isWarping) {
			for (NSInteger i = _WarpList.count - 1; i >= 0; i --)
				if (_WarpList[i].agent == a)
					{ [_WarpList removeObjectAtIndex:i]; break; }
		} else a->isWarping = YES;
		switch (info.mode) {
			case WarpInside: case WarpToHospital: case WarpToCemeteryF:
			remove_agent(a, &params, _Pop); break;
			case WarpBack: case WarpToCemeteryH:
			remove_from_list(a, &_QList); break;
		}
	}
	[_WarpList addObjectsFromArray:newWarpF];
	[newWarpF removeAllObjects];
	for (NSInteger i = _WarpList.count - 1; i >= 0; i --) {
		WarpInfo *info = _WarpList[i];
		if (warp_step(info.agent, &params, self, info.mode, info.goal))
			[_WarpList removeObjectAtIndex:i];
	}

	BOOL finished = [statInfo calcStat:_Pop nCells:nCells
		qlist:_QList clist:_CList warp:_WarpList stepsPerDay:params.stepsPerDay];
	[popLock unlock];
	step ++;
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
			if (running) in_main_thread(^{ [self startStop:nil]; });
		} else mCount = 0;
	}
#endif
	CGFloat days = floor(step / params.stepsPerDay);
	in_main_thread(^{
		[self showCurrentStatistics];
		self->daysNum.doubleValue = days;
	});
}
- (void)runningLoop {
	while (loopMode == LoopRunning) {
		[self doOneStep];
		CGFloat newTime = get_uptime(), timePassed = newTime - prevTime;
		if (timePassed < 1.) {
			stepsPerSec += (fmin(30., 1. / timePassed) - stepsPerSec) * 0.2;
			in_main_thread(^{ self->spsNum.doubleValue = self->stepsPerSec; });
		}
		prevTime = newTime;
		if (step % animeSteps == 0) {
			in_main_thread(^{ self->view.needsDisplay = YES; });
			NSInteger usToWait = (1./30. - timePassed) * 1e6;
			usleep((unsigned int)((usToWait < 0)? 1 : usToWait));
		} else usleep(1);
		if (loopMode == LoopEndByCondition && seqIndex < scenario.count) {
			[self setParamsAndConditionFromSequence];
			loopMode = LoopRunning;
		}
	}
	in_main_thread(^{
		self->view.needsDisplay = YES;
		self->startBtn.title = NSLocalizedString(@"Start", nil);
		self->stepBtn.enabled = YES;
	});
}
- (void)goAhead {
	if (loopMode == LoopFinished) [self resetPop];
	else if (loopMode == LoopEndByCondition)
		[self setParamsAndConditionFromSequence];
}
- (IBAction)startStop:(id)sender {
	if (loopMode != LoopRunning) {
		[self goAhead];
		startBtn.title = NSLocalizedString(@"Stop", nil);
		stepBtn.enabled = NO;
		loopMode = LoopRunning;
		[NSThread detachNewThreadSelector:@selector(runningLoop) toTarget:self withObject:nil];
	} else {
		startBtn.title = NSLocalizedString(@"Start", nil);
		stepBtn.enabled = YES;
		loopMode = LoopEndByUser;
	}
}
- (IBAction)step:(id)sedner {
	switch (loopMode) {
		case LoopRunning: return;
		case LoopFinished: case LoopEndByCondition: [self goAhead];
		case LoopEndByUser: case LoopNone: [self doOneStep];
	}
	view.needsDisplay = YES;
	loopMode = LoopEndByUser;
}
- (IBAction)reset:(id)sender {
	[self resetPop];
	view.needsDisplay = YES;
}
- (IBAction)addOneInfected:(id)sender {
	[self addInfected:1];
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
		Params tmpParams;
		memcpy(&tmpParams, &params, sizeof(Params));
		set_params_from_dict(&tmpParams, (NSDictionary *)pList);
		[self openParamPanel:self];
		[paramPanel setParamsWithPointer:&tmpParams];
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
