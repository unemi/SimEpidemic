//
//  StatPanel.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/09.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "StatPanel.h"
#import "Agent.h"
#import "World.h"
#ifndef NOGUI
#import "Document.h"
#endif
#define ALLOC_UNIT 512

static NSLock *statLock = nil;
static StatData *freeStat = NULL;
StatData *new_stat(void) {
	[statLock lock];
	if (freeStat == NULL) {
		freeStat = malloc(sizeof(StatData) * ALLOC_UNIT);
		for (NSInteger i = 0; i < ALLOC_UNIT - 1; i ++)
			freeStat[i].next = freeStat + i + 1;
		freeStat[ALLOC_UNIT - 1].next = NULL;
	}
	StatData *a = freeStat;
	freeStat = freeStat->next;
	[statLock unlock];
	memset(a, 0, sizeof(StatData));
	return a;
}
static void free_stat_mem(StatData **memp) {
	if (*memp == NULL) return;
	StatData **p = memp;
	while ((*p)->next) p = &((*p)->next);
	*p = freeStat;
	freeStat = *memp;
	*memp = NULL;
}
@implementation MyCounter
- (instancetype)initWithCount:(NSInteger)count {
	if ((self = [super init]) == nil) return nil;
	_cnt = count;
	return self;
}
- (instancetype)init { return [self initWithCount:0]; }
- (void)inc { _cnt ++; }
- (void)dec { _cnt --; }
- (NSString *)description
	{ return [NSString stringWithFormat:@"<MyCounter: cnt=%ld>", _cnt]; }
@end

#ifndef NOGUI
@implementation ULinedButton
- (void)drawRect:(NSRect)dirtyRect {
	[super drawRect:dirtyRect];
	if (_underLineColor == nil) return;
	NSRect rct = self.bounds;
	CGFloat y = NSMaxY(rct) - 2.;
	[_underLineColor setStroke];
	[NSBezierPath strokeLineFromPoint:(NSPoint){rct.origin.x, y}
		toPoint:(NSPoint){NSMaxX(rct), y}];
}
@end
#endif

@implementation NSValue (InfectionExtension)
+ (NSValue *)valueWithInfect:(InfectionCntInfo)info {
	return [NSValue valueWithBytes:&info objCType:@encode(InfectionCntInfo)];
}
- (InfectionCntInfo)infectValue {
	InfectionCntInfo info;
	[self getValue:&info];
	return info;
}
@end

@implementation StatInfo
- (instancetype)init {
	if (!(self = [super init])) return nil;
	_IncubPHist = NSMutableArray.new;
	_RecovPHist = NSMutableArray.new;
	_DeathPHist = NSMutableArray.new;
	_NInfectsHist = NSMutableArray.new;
	_sspData = [NSMutableData dataWithLength:sizeof(NSInteger) * SSP_MaxSteps * SSP_NRanks];
	_variantsData = [NSMutableData dataWithLength:sizeof(NSInteger) * MAX_N_REC * MAX_N_VARIANTS];
#ifndef NOGUI
	imgBm = malloc(IMG_WIDTH * IMG_HEIGHT * 4);
	scenarioPhases = NSMutableArray.new;
#endif
	return self;
}
#ifdef NOGUI
- (NSInteger)skipSteps { return skip; }
- (NSInteger)skipDays { return skipDays; }
- (void)discardMemory {
	_world = nil;
	[statLock lock];
	_sspData = _variantsData = nil;
	free_stat_mem(&_statistics);
	free_stat_mem(&_transit);
	[statLock unlock];
}
#else
- (void)fillImageForOneStep:(StatData *)stat atX:(NSInteger)ix {
	static HealthType typeOrder[] =
		{Died, Susceptible, Vaccinated, Recovered, Asymptomatic, Symptomatic};
	unsigned char *pm = imgBm + ((ix > 0)? ix - 1 : ix) * 4;
	for (NSInteger i = 0, y = 0; i < NHealthTypes; i ++) {
		NSInteger ii = typeOrder[i], ynext = y + stat->cnt[ii];
		NSInteger n = ynext * IMG_HEIGHT / popSize - y * IMG_HEIGHT / popSize;
		for (NSInteger j = 0; j < n; j ++, pm += IMG_WIDTH * 4) {
			for (NSInteger k = 0; k < 3; k ++)
				pm[k] = (stateRGB[ii] >> (8 * (2 - k))) & 0xff;
			pm[3] = 255;
		}
		y = ynext;
	}
}
- (void)reviseColors {
	StatData *p = _statistics;
	memset(imgBm, 0, IMG_WIDTH * IMG_HEIGHT * 4);
	for (NSInteger x = steps / skip; x >= 0 && p; x --, p = p->next)
		[self fillImageForOneStep:p atX:x];
	[self flushPanels];
}
#endif
- (void)reset:(PopulationHConf)popConf {
	if (statLock == nil) statLock = NSLock.new;
	[statLock lock];
	free_stat_mem(&_statistics);
	free_stat_mem(&_transit);
	[statLock unlock];
	_statistics = new_stat();
	memset(&statCumm, 0, sizeof(StatData));
	memset(&transDaily, 0, sizeof(StatData));
	memset(&transCumm, 0, sizeof(StatData));
	memset(testCumm, 0, sizeof(testCumm));
	memset(testResultsW, 0, sizeof(testResultsW));
	memset(maxCounts, 0, sizeof(maxCounts));
	memset(maxTransit, 0, sizeof(maxTransit));
	maxStepPRate = maxDailyPRate = 0.;
	infectedSeq.len = _world.worldParamsP->stepsPerDay * 3;
	infectedSeq.rec = realloc(infectedSeq.rec, sizeof(CGFloat) * infectedSeq.len);
	infectedSeq.n = infectedSeq.tail = 0;
	minReproRate = maxReproRate = 1.;
	_testResultCnt = (TestResultCount){0, 0};
	_statistics->cnt[Susceptible] = maxCounts[Susceptible] = popConf.susc;
	_statistics->cnt[Asymptomatic] = maxCounts[Asymptomatic] = popConf.asym;
	_statistics->cnt[Symptomatic] = maxCounts[Symptomatic] = popConf.symp;
	_statistics->cnt[Recovered] = maxCounts[Recovered] = popConf.recv;
	_statistics->cnt[QuarantineAsym] = maxCounts[QuarantineAsym] = popConf.qAsym;
	_statistics->cnt[QuarantineSymp] = maxCounts[QuarantineSymp] = popConf.qSymp;
	_statistics->reproRate = 1.;
	steps = days = 0;
	skip = skipDays = 1;
	popSize = popConf.susc + popConf.asym + popConf.symp + popConf.recv;
	[_IncubPHist removeAllObjects];
	[_RecovPHist removeAllObjects];
	[_DeathPHist removeAllObjects];
	[_NInfectsHist removeAllObjects];
//	[_NInfectsHist addObject:MyCounter.new];
//	_NInfectsHist[0].cnt = nInitInfec;
	memset(_sspData.mutableBytes, 0, _sspData.length);
	memset(_variantsData.mutableBytes, 0, _variantsData.length);
#ifndef NOGUI
	memset(imgBm, 0, IMG_WIDTH * IMG_HEIGHT * 4);
	[scenarioPhases removeAllObjects];
	[self fillImageForOneStep:_statistics atX:0];
#endif
}
- (void)cummulateHistgrm:(HistogramType)type days:(CGFloat)d {
	NSMutableArray<MyCounter *> *h = (type == HistIncub)? _IncubPHist :
		(type == HistRecov)? _RecovPHist :
		(type == HistDeath)? _DeathPHist : nil;
	if (h == nil) return;
	NSInteger ds = floor(d);
	if (h.count <= d) {
		NSInteger n = ds - h.count;
		for (NSInteger i = 0; i <= n; i ++) [h addObject:MyCounter.new];
	}
	[h[ds] inc];
}
#ifndef NOGUI
- (void)setPhaseInfo:(NSArray<NSNumber *> *)info {
	phaseInfo = info;
#ifdef DEBUG
if (phaseInfo.count > 0) {
	char *s = "PI:";
	for (NSNumber *num in phaseInfo) { printf("%s%ld", s, num.integerValue); s = ", "; }
	printf("\n");
}
#endif
}
- (void)setLabelInfo:(NSArray<NSString *> *)info {
	labelInfo = info;
#ifdef DEBUG
if (labelInfo.count > 0) {
	char *s = "LI:";
	for (NSString *str in labelInfo) { printf("%s%s", s, str.UTF8String); s = ", "; }
	printf("\n");
}
#endif
}
- (void)phaseChangedTo:(NSInteger)lineNumber {
	NSInteger idx = [phaseInfo indexOfObject:@(lineNumber)];
	if (idx != NSNotFound) {
		[scenarioPhases addObject:@(steps)];
		[scenarioPhases addObject:@(idx + 1)];
	}
#ifdef DEBUG
if (scenarioPhases.count > 0) {
	char *s = "SP:";
	for (NSNumber *num in scenarioPhases)
		{ printf("%s%ld", s, num.integerValue); s = ", "; }
	printf("\n");
}
#endif
}
#endif
static void count_health(Agent *a, StatData *stat, StatData *tran) {
	if (a->health != a->newHealth) {
		a->health = a->newHealth;
		tran->cnt[a->health] ++;
	}
	stat->cnt[a->health] ++;
}
static void count_severity(Agent *a, VariantInfo *vp, NSInteger *cnt) {
	NSInteger rank;
	if (a->health != Symptomatic) rank = 0;
	else {
		vp += a->virusVariant;
		CGFloat exc = exacerbation(vp->reproductivity) * vp->toxicity;
		rank = (a->daysInfected - a->daysToOnset) / (a->daysToDie / exc) * SSP_NRanks;
		if (rank < 0) rank = 0; else if (rank >= SSP_NRanks) rank = SSP_NRanks - 1;
	}
	cnt[rank] ++;
}
static void count_infected_variants(Agent *a, NSInteger *cnt) {
	if (is_infected(a)) cnt[a->virusVariant] ++;
}
static CGFloat calc_positive_rate(NSUInteger *count) {
	NSUInteger tt = count[TestPositive] + count[TestNegative];
	return (tt == 0)? 0. : (CGFloat)count[TestPositive] / tt;
}
static CGFloat calc_reproduct_rate(NSInteger nInfec, InfecQueInfo *info) {
	if (nInfec <= 0) return 0.;
	info->rec[info->tail] = log(nInfec);
	info->tail = (info->tail + 1) % info->len;
	if (info->n < info->len) if ((++ info->n) < info->len) return 0.;
	NSInteger n = info->len;
	CGFloat sumX = n * (n - 1) / 2, sumY = 0, sumX2 = 0, sumXY = 0;
	for (NSInteger i = 0; i < n; i ++) {
		CGFloat y = info->rec[(info->tail + i) % n];
		sumY += y;
		sumX2 += i * i;
		sumXY += i * y;
	}
	CGFloat denomi = n * sumX2 - sumX * sumX;
	return (fabs(denomi) < 1e-6)? 0. :
		(n * sumXY - sumX * sumY) / denomi;
}
static void shrink_data_in_half(NSMutableData *data, NSInteger unit) {
	NSInteger *dt = (NSInteger *)data.mutableBytes;
	for (NSInteger i = 0; i < MAX_N_REC; i += 2)
		memcpy(dt + i / 2 * unit, dt + (i + 1) * unit, sizeof(NSInteger) * unit);
	NSInteger nItemsHalf = MAX_N_REC / 2 * unit;
	memset(dt + nItemsHalf, 0, sizeof(NSInteger) * nItemsHalf);
}
- (BOOL)calcStatWithTestCount:(NSUInteger *)testCount
	infects:(NSArray<NSArray<NSValue *> *> *)infects {
	Agent *agents = _world.agents;
	WorldParams *wp = _world.worldParamsP;
	NSInteger nPop = wp->initPop;
	Agent *qlist = _world.QList;
	NSInteger stepsPerDay = wp->stepsPerDay;

	if (steps % stepsPerDay == 0) memset(&transDaily, 0, sizeof(StatData));
	steps ++;
	NSInteger unitJ = 8;
	StatData *tmpStats, *tmpTrans;
	tmpStats = malloc(sizeof(StatData) * unitJ * 2);
	memset(tmpStats, 0, sizeof(StatData) * unitJ * 2);
	tmpTrans = tmpStats + unitJ;
	for (NSInteger j = 0; j < unitJ; j ++) {
		NSInteger start = j * nPop / unitJ, end = (j + 1) * nPop / unitJ;
		void (^block)(void) = ^{ for (NSInteger i = start; i < end; i ++)
			count_health(agents + i, tmpStats + j, tmpTrans + j); };
		if (j < unitJ - 1) [_world addOperation:block]; else block();
	}
	[_world waitAllOperations];
	StatData tmpStat;
	memset(&tmpStat, 0, sizeof(StatData));
	for (NSInteger j = 0; j < unitJ; j ++) for (NSInteger i = 0; i < NIntIndexes; i ++) {
		tmpStat.cnt[i] += tmpStats[j].cnt[i];
		transDaily.cnt[i] += tmpTrans[j].cnt[i];
	}
	free(tmpStats);
	for (Agent *a = qlist; a; a = a->next) {
		NSInteger qIdx = (a->health == Symptomatic)? QuarantineSymp : QuarantineAsym;
		if (a->gotAtHospital) {
			transDaily.cnt[qIdx] ++;
			a->gotAtHospital = NO;
		} else if (a->health == Asymptomatic && a->newHealth == Symptomatic)
			transDaily.cnt[QuarantineSymp] ++;
		tmpStat.cnt[qIdx] ++;
	}

	for (NSInteger i = 0; i < NIntTestTypes; i ++) {
		transDaily.cnt[i + NStateIndexes] += testCount[i];
		tmpStat.cnt[i + NStateIndexes] = testCumm[i] += testCount[i];
	}
	tmpStat.pRate = calc_positive_rate(testCount);
	tmpStat.reproRate = exp(calc_reproduct_rate(
		tmpStat.cnt[Asymptomatic] + tmpStat.cnt[Symptomatic], &infectedSeq)
		* stepsPerDay);

	for (NSInteger i = 0; i < NIntIndexes; i ++)
		if (maxCounts[i] < tmpStat.cnt[i]) maxCounts[i] = tmpStat.cnt[i];
	if (maxStepPRate < tmpStat.pRate) maxStepPRate = tmpStat.pRate;
	if (minReproRate > tmpStat.reproRate) minReproRate = tmpStat.reproRate;
	if (maxReproRate < tmpStat.reproRate) maxReproRate = tmpStat.reproRate;

	NSInteger idxInCum = steps % skip;
	if (idxInCum == 0) memset(&statCumm, 0, sizeof(StatData));
	for (NSInteger i = 0; i < NIntIndexes; i ++) statCumm.cnt[i] += tmpStat.cnt[i];
	statCumm.pRate += tmpStat.pRate;
	statCumm.reproRate += tmpStat.reproRate;
	if (idxInCum + 1 >= skip) {
		StatData *newStat = new_stat();
		for (NSInteger i = 0; i < NIntIndexes; i ++)
			newStat->cnt[i] = statCumm.cnt[i] / skip;
		newStat->pRate = statCumm.pRate / skip;
		newStat->reproRate = statCumm.reproRate / skip;
		newStat->next = _statistics;
		_statistics = newStat;
		if (steps / skip > MAX_N_REC) {
			[statLock lock];
			for (StatData *p = newStat; p; p = p->next) {
				StatData *q = p->next;
				for (NSInteger i = 0; i < NIntIndexes; i ++)
					p->cnt[i] = (p->cnt[i] + q->cnt[i]) / 2;
				p->pRate = (p->pRate + q->pRate) / 2.;
				p->reproRate = (p->reproRate + q->reproRate) / 2.;
				p->next = q->next;
				q->next = freeStat;
				freeStat = q;
			}
			[statLock unlock];
			skip *= 2;
#ifdef NOGUI
		}
#else
			StatData *p = newStat;
			memset(imgBm, 0, IMG_WIDTH * IMG_HEIGHT * 4);
			for (NSInteger x = steps / skip; x >= 0 && p; x --, p = p->next)
				[self fillImageForOneStep:p atX:x];
		} else [self fillImageForOneStep:newStat atX:steps / skip];
#endif
	}
	if (steps % stepsPerDay == stepsPerDay - 1) {
		NSUInteger *dailyTests = transDaily.cnt + NStateIndexes;
		transDaily.pRate = calc_positive_rate(dailyTests);
		if (days < 7) {
			_testResultCnt.positive += testResultsW[days].positive = dailyTests[TestPositive];
			_testResultCnt.negative += testResultsW[days].negative = dailyTests[TestNegative];
		} else {
			NSInteger idx = days % 7;
			_testResultCnt.positive += dailyTests[TestPositive] - testResultsW[idx].positive;
			testResultsW[idx].positive = dailyTests[TestPositive];
			_testResultCnt.negative += dailyTests[TestNegative] - testResultsW[idx].negative;
			testResultsW[idx].negative = dailyTests[TestNegative];
		}
		if (days % skipDays == 0) {
			NSInteger idx = days / skipDays;
			NSInteger *cntS = (NSInteger *)_sspData.mutableBytes + SSP_NRanks * idx;
			NSInteger *cntV = (NSInteger *)_variantsData.mutableBytes + MAX_N_VARIANTS * idx;
			for (Agent *a = _world.QList; a != NULL; a = a->next) {
				count_severity(a, _world.variantInfoP, cntS);
				count_infected_variants(a, cntV);
			}
		}
		days ++;
		if (maxDailyPRate < transDaily.pRate) maxDailyPRate = transDaily.pRate;
		for (NSInteger i = 0; i < NIntIndexes; i ++)
			if (maxTransit[i] < transDaily.cnt[i]) maxTransit[i] = transDaily.cnt[i];
		idxInCum = days % skipDays;
		if (idxInCum == 0) memset(&transCumm, 0, sizeof(StatData));
		for (NSInteger i = 0; i < NIntIndexes; i ++)
			transCumm.cnt[i] += transDaily.cnt[i];
		transCumm.pRate += transDaily.pRate;
		if (idxInCum + 1 >= skipDays) {
			StatData *newTran = new_stat();
			for (NSInteger i = 0; i < NIntIndexes; i ++)
				newTran->cnt[i] = transCumm.cnt[i] / skipDays;
			newTran->pRate = transCumm.pRate / skipDays;
			newTran->next = _transit;
			_transit = newTran;
			if (days / skipDays >= MAX_N_REC) {
				[statLock lock];
				for (StatData *p = newTran; p; p = p->next) {
					StatData *q = p->next;
					for (NSInteger i = 0; i < NIntIndexes; i ++)
						p->cnt[i] = (p->cnt[i] + q->cnt[i]) / 2;
					p->pRate = (p->pRate + q->pRate) / 2.;
					p->next = q->next;
					q->next = freeStat;
					freeStat = q;
				}
				shrink_data_in_half(_sspData, SSP_NRanks);
				shrink_data_in_half(_variantsData, MAX_N_VARIANTS);
				[statLock unlock];
				skipDays *= 2;
	}}}
	for (NSArray<NSValue *> *arr in infects) for (NSValue *val in arr) {
		InfectionCntInfo info = val.infectValue;
		if (_NInfectsHist.count < info.newV + 1) {
			NSInteger n = info.newV + 1 - _NInfectsHist.count;
			for (NSInteger j = 0; j < n; j ++)
				[_NInfectsHist addObject:MyCounter.new];
		}
		if (info.orgV >= 0) [_NInfectsHist[info.orgV] dec];
		[_NInfectsHist[info.newV] inc];
	}
	return _statistics->cnt[Asymptomatic] + _statistics->cnt[Symptomatic] == 0;
}
#ifndef NOGUI
- (StatPanel *)openStatPanel:(NSWindow *)parentWindow {
	StatPanel *statPnl = [StatPanel.alloc initWithInfo:self];
	if (_statPanels == nil) _statPanels = NSMutableArray.new;
	[_statPanels addObject:statPnl];
	[statPnl showWindowWithParent:parentWindow];
	return statPnl;
}
- (void)statPanelDidClose:(StatPanel *)panel {
	[_statPanels removeObject:panel];
}
- (void)flushPanels {
	for (StatPanel *panel in _statPanels) [panel flushView:self];
}
- (NSArray *)fillPhaseBackground:(NSSize)size xMax:(NSInteger)xMax {
	NSInteger n = scenarioPhases.count;
	if (n < 2) return nil;
	NSMutableSet<NSNumber *> *ms = NSMutableSet.new;
	for (NSInteger i = 1; i < n; i += 2) [ms addObject:scenarioPhases[i]];
	NSInteger nPhases = ms.count, idx = 0;
	NSNumber *phs[nPhases];
	for (NSNumber *num in ms) phs[idx ++] = num;
	NSArray<NSNumber *> *phases = [NSArray arrayWithObjects:phs count:nPhases];
	NSRect rect = {0., 0.,
		scenarioPhases[0].integerValue * size.width / xMax, size.height};
	NSMutableArray *labels = NSMutableArray.new;
	for (NSInteger i = 1; i < n; i += 2) {
		NSInteger phase = [phases indexOfObject:scenarioPhases[i]],
			step = (i < n - 1)? scenarioPhases[i + 1].integerValue : xMax;
		rect.origin.x += rect.size.width;
		rect.size.width = step * size.width / xMax - rect.origin.x;
		[[NSColor colorWithHue:((CGFloat)phase) / nPhases
			saturation:1. brightness:1. alpha:.15] setFill];
		[NSBezierPath fillRect:rect];
		if (i == n - 1) break;
		NSInteger lblIdx = scenarioPhases[i].integerValue;
		NSString *label = (lblIdx <= 0 || lblIdx > labelInfo.count)?
			@"" : labelInfo[lblIdx - 1];
		if (label.length > 0) {
			[labels addObject:label];
			[labels addObject:@(NSMaxX(rect))];
		}
	}
	return labels;
}
static NSRect drawing_area(NSRect area) {
	CGFloat ticsHeight = NSFont.systemFontSize * 1.4;
	return (NSRect){area.origin.x, area.origin.y + ticsHeight,
		area.size.width, area.size.height - ticsHeight};
}
static NSMutableDictionary *textAttributes = nil, *labelTxtAttr;
static void draw_tics(NSRect area, CGFloat xMax) {
	CGFloat exp = pow(10., floor(log10(xMax))), mts = xMax / exp;
	NSInteger intvl = ((mts < 2.)? .2 : (mts < 5.)? .5 : 1.) * exp;
	CGFloat baseY = NSMinY(area) + NSFont.systemFontSize * 1.4;
	[stateColors[ColText] setStroke];
	[NSBezierPath strokeLineFromPoint:
		(NSPoint){NSMinX(area), baseY} toPoint:(NSPoint){NSMaxX(area), baseY}];
	if (intvl > 0) for (NSInteger ix = 0; ix < xMax; ix += intvl) {
		CGFloat x = ix * area.size.width / xMax + area.origin.x;
		[NSBezierPath strokeLineFromPoint:
			(NSPoint){x, baseY} toPoint:(NSPoint){x, baseY * 1.2/1.4}];
		NSString *dgts = @(ix).stringValue;
		[dgts drawAtPoint:(NSPoint){x - [dgts sizeWithAttributes:textAttributes].width / 2.}
			withAttributes:textAttributes];
	}
}
typedef struct { NSUInteger maxCnt; CGFloat maxPRate, maxRRate; } TimeEvoMax;
static NSColor *color_for_index(NSUInteger k, TimeEvoInfo *info) {
	static struct RGBA { CGFloat r, g, b; } L = {0.2126, 0.7152, 0.0722};
	if (k >= info->nIndexes) return nil;
	CGFloat H = k * 6. / info->nIndexes, X = 1 - fabs(fmod(H, 2.) - 1.);
	struct RGBA c =
		(H < 1.)? (struct RGBA){1., X, 0.} : (H < 2.)? (struct RGBA){X, 1., 0.} :
		(H < 3.)? (struct RGBA){0., 1., X} : (H < 4.)? (struct RGBA){0., X, 1.} :
		(H < 5.)? (struct RGBA){X, 0., 1.} : (struct RGBA){1., 0., X};
	CGFloat d = (L.r + L.g - (c.r * L.r + c.g * L.g * c.b * L.b)) / (L.r + L.g) * .667;
	c.r += (1. - c.r) * d * (1. - L.r);
	c.g += (1. - c.g) * d * (1. - L.g);
	c.b += (1. - c.b) * d * (1. - L.b);
	if (!bgIsDark) { c.r *= .5; c.g *= .5; c.b *= .5; }
	return [NSColor colorWithRed:c.r green:c.g blue:c.b alpha:1.];
}
static TimeEvoMax show_time_evo(StatData *stData, TimeEvoInfo *info,
	NSUInteger maxV[], NSInteger steps, NSInteger skip,
	CGFloat maxPRate, CGFloat minReproRate, CGFloat maxReproRate, NSRect rect) {
	TimeEvoMax teMax = {0, 0., 0.};
	NSUInteger nPoints = 0, k = 0;
	NSInteger winSz = (info->idxBits & MskTransit)? info->windowSize : 1;
	for (NSInteger i = 0; i < NIntIndexes; i ++) if ((info->idxBits & 1 << i) != 0)
		if (teMax.maxCnt < maxV[i]) teMax.maxCnt = maxV[i];
	for (StatData *tran = stData; tran != NULL; tran = tran->next) nPoints ++;
	NSPoint *pts = malloc(sizeof(NSPoint) * nPoints);
	void (^block)(CGFloat (^)(StatData *), CGFloat, CGFloat, NSUInteger) =
	^(CGFloat (^getter)(StatData *), CGFloat minv, CGFloat maxv, NSUInteger k) {
		StatData *tran = stData;
		CGFloat span = maxv - minv;
		for (NSInteger j = nPoints - 1; tran && j >= 0; tran = tran->next, j --)
			pts[j] = (NSPoint){
				j * (rect.size.width - 1.) / steps * skip + rect.origin.x,
				(getter(tran) - minv) / span * rect.size.height + rect.origin.y};
		if (winSz > 1) {
			CGFloat sum = 0, buf[winSz];
			for (NSInteger j = 0; j < nPoints; j ++) {
				if (j < winSz) sum += pts[j].y;
				else sum += pts[j].y - buf[j % winSz];
				buf[j % winSz] = pts[j].y;
				pts[j].y = sum / ((j < winSz)? j + 1 : winSz);
			}
		}
		NSBezierPath *path = NSBezierPath.new;
		[path appendBezierPathWithPoints:pts count:nPoints];
		[color_for_index(k, info) setStroke];
		[path stroke];
	};
	if (steps > 0 && teMax.maxCnt > 0) for (NSInteger i = 0; i < NIntIndexes; i ++)
	if ((info->idxBits & 1 << i) != 0) {
		if (maxV[i] > 0)
			block(^(StatData *tran) { return (CGFloat)tran->cnt[i]; }, 0., teMax.maxCnt, k);
		k ++;
	}
	if ((info->idxBits & MskTestPRate) != 0 && maxPRate > 0) {
		block(^(StatData *tran) { return tran->pRate; }, 0., maxPRate, k);
		teMax.maxPRate = maxPRate;
	}
	if ((info->idxBits & MskReproRate) != 0 && minReproRate < maxReproRate) {
		block(^(StatData *tran) { return tran->reproRate; }, minReproRate, maxReproRate, k);
		CGFloat span = maxReproRate - minReproRate;
		if (minReproRate < 1.) {
			NSBezierPath *path = NSBezierPath.new;
			[path moveToPoint:(NSPoint){rect.origin.x,
				rect.size.height * (1. - minReproRate) / span + rect.origin.y}];
			[path relativeLineToPoint:(NSPoint){rect.size.width, 0.}];
			[path setLineDash:(CGFloat []){5., 2.} count:2 phase:0.];
			[path stroke];
		}
		teMax.maxRRate = maxReproRate;
	}
	free(pts);
	return teMax;
}
static NSArray<NSString *> *indexCBoxTitles = nil;
#define LEGEND_LINE_LENGTH 20
#define LEGEND_PADDING 4
static void draw_legend(TimeEvoInfo *info, NSRect rect) {
	if (indexCBoxTitles == nil) return;
	NSInteger n = 0, k = 0, m = indexCBoxTitles.count;
	NSMutableString *ms = NSMutableString.new;
	if ((info->idxBits & MskTransit) != 0) m --;
	for (NSInteger i = 0; i < m; i ++) if ((info->idxBits & 1 << i) != 0)
		{ [ms appendFormat:@"%@\n", indexCBoxTitles[i]]; n ++; }
	if (n == 0) return;
	[ms deleteCharactersInRange:(NSRange){ms.length - 1, 1}];
	NSSize lgSize = [ms sizeWithAttributes:textAttributes];
	NSPoint p1 = {NSMaxX(rect) - LEGEND_PADDING*2 - lgSize.width,
		NSMaxY(rect) - lgSize.height / n / 2 - LEGEND_PADDING},
		p2 = {p1.x - LEGEND_LINE_LENGTH, p1.y};
	for (NSInteger i = 0; i < m; i ++) if ((info->idxBits & 1 << i) != 0) {
		[color_for_index(k, info) setStroke];
		[NSBezierPath strokeLineFromPoint:p1 toPoint:p2];
		p1.y = p2.y -= lgSize.height / n;
		k ++;
	}
	[ms drawAtPoint:(NSPoint){
		NSMaxX(rect) - LEGEND_PADDING - lgSize.width,
		NSMaxY(rect) - LEGEND_PADDING - lgSize.height} withAttributes:textAttributes];
}
static void show_histogram(NSMutableArray<MyCounter *> *hist,
	NSRect area, NSColor *color, NSString *title) {
	NSInteger n = hist.count;
	if (n == 0) return;
	NSInteger max = 0, ns = 0, st = -1, sum = 0;
	for (NSInteger i = 0; i < n; i ++) {
		NSInteger cnt = hist[i].cnt;
		if (max < cnt) max = cnt;
		ns += cnt;
		if (st == -1 && cnt > 0) st = i;
		sum += i * cnt;
	}
	NSInteger m = 0, md = 0;
	for (NSInteger i = st; i < n; i ++)
		if ((m += hist[i].cnt) > ns / 2) { md = i; break; }
	[color setFill];
	CGFloat w = area.size.width / (n - st);
	for (NSInteger i = st; i < n; i ++)
		[NSBezierPath fillRect:(NSRect){(i - st) * w + area.origin.x, area.origin.y,
			w, hist[i].cnt * area.size.height / max}];
	[[NSString stringWithFormat:NSLocalizedString(@"HistogramFormat", nil),
		NSLocalizedString(title, nil), ns, st, n - 1, md, ((CGFloat)sum) / ns]
		drawAtPoint:(NSPoint){area.origin.x + 4., 10.}
		withAttributes:textAttributes];
}
static void show_period_hist(NSMutableArray<MyCounter *> *hist,
	NSInteger idx, NSSize size, NSString *title) {
	static HealthType colIdx[] = {Asymptomatic, Recovered, Died};
	NSRect area = {size.width * idx / 3., 0., size.width / 3., size.height};
	show_histogram(hist, area, stateColors[colIdx[idx]], title);
}
- (void)drawLabels:(NSArray *)labels y:(CGFloat)y {
	if (labels == nil) return;
	NSGraphicsContext *ctx = NSGraphicsContext.currentContext;
	[ctx saveGraphicsState];
	NSAffineTransform *mtrx = NSAffineTransform.transform;
	[mtrx rotateByDegrees:90];
	[mtrx concat];
	for (NSInteger i = 0; i < labels.count; i += 2) {
		NSString *label = labels[i];
		NSSize sz = [label sizeWithAttributes:labelTxtAttr];
		[label drawAtPoint:(NSPoint){y - sz.width - 6.,
			-((NSNumber *)labels[i + 1]).doubleValue} withAttributes:labelTxtAttr];
	}
	[ctx restoreGraphicsState];
}
- (void)drawCompositionData:(NSData *)data title:(NSString *)title
	ranks:(NSInteger)nRanks drawRanks:(NSInteger)drawRanks bounds:(NSRect)bounds {
	NSRect dRect = drawing_area(bounds);
	NSArray *labels = [self fillPhaseBackground:(NSSize){bounds.size.width, dRect.origin.y}
		xMax:days * _world.worldParamsP->stepsPerDay];
	NSInteger nPts = days / skipDays, nCnks = nRanks / drawRanks, maxSymp = 0;
	if (nPts > 1) {
		NSInteger *sspDt = (NSInteger *)data.bytes,
			*sspTbl = malloc(sizeof(NSInteger) * drawRanks * nPts),
			*dtP = sspDt, *tblP = sspTbl;
	  for (NSInteger j = 0; j < nPts; j ++, dtP += nRanks, tblP += drawRanks) {
		  NSInteger s = 0;
		  for (NSInteger i = 0; i < drawRanks; i ++) {
			  NSInteger ss = 0;
			  for (NSInteger k = 0; k < nCnks; k ++)
				  ss += dtP[(drawRanks - 1 - i) * nCnks + k];
			  tblP[i] = (s += ss);
		  }
		  if (maxSymp < s) maxSymp = s;
	  }
	  NSPoint *pts = malloc(sizeof(NSPoint) * nPts * 2);
	  for (NSInteger j = 0; j < nPts; j ++)
		  pts[j].x = dRect.origin.x + dRect.size.width * j / (nPts - 1);
	  pts[nPts].x = NSMaxX(dRect); pts[nPts + 1].x = dRect.origin.x;
	  pts[nPts].y = pts[nPts + 1].y = dRect.origin.y;
	  for (NSInteger i = 0; i < drawRanks; i ++) {
		  tblP = sspTbl + i;
		  for (NSInteger j = 0; j < nPts; j ++, tblP += drawRanks)
			  pts[j].y = dRect.origin.y + dRect.size.height * tblP[0] / maxSymp;
		  NSBezierPath *path = NSBezierPath.new;
		  [path appendBezierPathWithPoints:pts count:(i==0)? nPts + 2 : nPts * 2];
		  RainbowColorHB hb = rainbow_color(i, drawRanks);
		  [[NSColor colorWithHue:hb.hue saturation:.75 brightness:hb.brightness alpha:1.] setFill];
		  [path fill];
		  if (i < nRanks - 1)
			  for (NSInteger j = 0; j < nPts; j ++)
				  pts[nPts * 2 - 1 - j] = pts[j];
	  }
	  free(pts);
	  free(sspTbl);
	}
	[self drawLabels:labels y:NSMaxY(bounds)];
	draw_tics(bounds, days);
	[[NSString stringWithFormat:@"%@\n%@ %ld", NSLocalizedString(title, nil),
		NSLocalizedString(@"max count", nil), maxSymp]
		drawAtPoint:(NSPoint){6., (bounds.size.height + NSFont.systemFontSize) / 2.}
		withAttributes:textAttributes];
}
- (void)drawWithType:(StatType)type info:(TimeEvoInfo *)info bounds:(NSRect)bounds {
	static NSNumberFormatter *decFormat = nil;
	if (textAttributes == nil) {
		textAttributes = NSMutableDictionary.new;
		textAttributes[NSFontAttributeName] = [NSFont userFontOfSize:NSFont.systemFontSize];
		labelTxtAttr = [NSMutableDictionary dictionaryWithDictionary:textAttributes];
		decFormat = NSNumberFormatter.new;
		decFormat.numberStyle = NSNumberFormatterDecimalStyle;
	}
	textAttributes[NSForegroundColorAttributeName] = stateColors[ColText];
	labelTxtAttr[NSForegroundColorAttributeName] =
		[stateColors[ColText] colorWithAlphaComponent:0.667];
	[stateColors[ColBackground] setFill];
	[NSBezierPath fillRect:bounds];
	switch (type) {
		case StatWhole: {
		NSRect dRect = drawing_area(bounds);
		NSArray *labels =
			[self fillPhaseBackground:(NSSize){bounds.size.width, dRect.origin.y} xMax:steps];
		NSBitmapImageRep *imgRep = [NSBitmapImageRep.alloc
			initWithBitmapDataPlanes:(unsigned char *[]){imgBm}
			pixelsWide:IMG_WIDTH pixelsHigh:IMG_HEIGHT bitsPerSample:8 samplesPerPixel:3
			hasAlpha:NO isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
			bytesPerRow:IMG_WIDTH * 4 bitsPerPixel:32];
		[imgRep drawInRect:dRect
			fromRect:(NSRect){0, 0, ((steps == 0)? 1 : steps) / skip, IMG_HEIGHT}
			operation:NSCompositingOperationCopy fraction:1. respectFlipped:NO hints:nil];
		[self drawLabels:labels y:NSMaxY(bounds)];
		draw_tics(bounds, (CGFloat)steps/_world.worldParamsP->stepsPerDay);
		} break;
		case StatTimeEvo: {
		BOOL isTransit = (info->idxBits & MskTransit) != 0;
		[self drawLabels:[self fillPhaseBackground:bounds.size xMax:
			isTransit? days * _world.worldParamsP->stepsPerDay : steps] y:NSMaxY(bounds)];
		NSRect dRect = drawing_area(bounds);
		TimeEvoMax teMax = isTransit?
			show_time_evo(_transit, info, maxTransit, days, skipDays,
				maxDailyPRate, 1., 1., dRect) :
			show_time_evo(_statistics, info, maxCounts, steps, skip,
				maxStepPRate, minReproRate, maxReproRate, dRect);
		NSMutableString *ms = NSMutableString.new;
		if (teMax.maxCnt > 0) [ms appendFormat:@"%@ %@ (%.2f%%)",
			NSLocalizedString(@"max count", nil),
			[decFormat stringFromNumber:@(teMax.maxCnt)], teMax.maxCnt * 100. / popSize];
		if (teMax.maxPRate > 0.) [ms appendFormat:@"%s%@ %.3f%%", (ms.length > 0)? "\n" : "",
			NSLocalizedString(@"max test positive rate", nil), teMax.maxPRate * 100.];
		if (teMax.maxRRate > 0.) [ms appendFormat:@"%s%@ %.4f", (ms.length > 0)? "\n" : "",
			NSLocalizedString(@"max reproductive rate", nil), teMax.maxRRate];
		if (ms.length > 0) [ms
			drawAtPoint:(NSPoint){6., (bounds.size.height - NSFont.systemFontSize) / 2.}
			withAttributes:textAttributes];
		draw_legend(info, dRect);
		draw_tics(bounds, isTransit? days : (CGFloat)steps/_world.worldParamsP->stepsPerDay);
		} break;
		case StatSeverity:
		[self drawCompositionData:_sspData title:@"Symptom severity"
			ranks:SSP_NRanks drawRanks:SSP_NDrawRanks bounds:bounds];
		break;
		case StatVariants:
		[self drawCompositionData:_variantsData title:@"Virus variants"
			ranks:MAX_N_VARIANTS drawRanks:MAX_N_VARIANTS bounds:bounds];
		break;
		case StatPeriods:
		show_period_hist(_IncubPHist, 0, bounds.size, @"Incubation Period");
		show_period_hist(_RecovPHist, 1, bounds.size, @"Recovery Period");
		show_period_hist(_DeathPHist, 2, bounds.size, @"Fatal Period");
		break;
		case StatSpreaders:
		show_histogram(_NInfectsHist, bounds, NSColor.grayColor, @"Spreaders");
	}
}
#endif
@end

#ifndef NOGUI
@implementation StatPanel
- (instancetype)initWithInfo:(StatInfo *)info {
	if (!(self = [super initWithWindowNibName:@"StatPanel"])) return nil;
	statInfo = info;
	return self;
}
- (void)setupColorForCBoxes {
	NSInteger k = 0;
	for (ULinedButton *cbox in indexCBoxes) {
		cbox.underLineColor = cbox.state? color_for_index(k ++, &timeEvoInfo) : nil;
		cbox.needsDisplay = YES;
	}
}
- (NSInteger)setupIndexCbox:(NSArray<NSView *> *)list tag:(NSInteger)tag {
	for (NSInteger i = 0; i < list.count; i ++) {
		NSView *view = list[i];
		if ([view isKindOfClass:NSButton.class]) {
			NSButton *btn = (NSButton *)view;
			btn.target = self;
			btn.action = @selector(switchIndexSelection:);
			if ([btn isKindOfClass:ULinedButton.class]) {
				btn.tag = tag;
				if (btn.state) { timeEvoInfo.idxBits |= tag; timeEvoInfo.nIndexes ++; }
				[indexCBoxes addObject:(ULinedButton *)btn];
				if (tag == MskReproRate)
					if (!((reproRateCBox = btn).enabled =
						(timeEvoInfo.idxBits & MskTransit) == 0) && btn.state)
						timeEvoInfo.nIndexes --;
				tag <<= 1;
			} else {
				(transitCBox = btn).tag = MskTransit;
				if (btn.state) timeEvoInfo.idxBits |= MskTransit;
			}
		} else if ([view isKindOfClass:NSBox.class])
			if (((NSBox *)view).boxType == NSBoxPrimary)
				tag = [self setupIndexCbox:((NSBox *)view).contentView.subviews tag:tag];
	}
	return tag;
}
- (void)windowDidLoad {
	[super windowDidLoad];
	[statInfo.doc setPanelTitle:self.window];
	indexCBoxes = NSMutableArray.new;
	[self setupIndexCbox:idxSelectionSheet.contentView.subviews tag:1];
	[self setupColorForCBoxes];
	[idxSelectionSheet setFrameOrigin:self.window.frame.origin];
	timeEvoInfo.windowSize = mvAvrgDgt.integerValue = 1;
	mvAvrgUnit.stringValue = NSLocalizedString(@"day", nil);
	if (indexCBoxTitles == nil) {
		NSInteger n = indexCBoxes.count;
		NSString *titles[n];
		for (NSInteger i = 0; i < n; i ++) titles[i] = indexCBoxes[i].title;
		indexCBoxTitles = [NSArray.alloc initWithObjects:titles count:n];
	}
}
- (void)windowDidMove:(NSNotification *)notification {
	if (notification.object == self.window && !idxSelectionSheet.isVisible)
		[idxSelectionSheet setFrameOrigin:self.window.frame.origin];
}
- (void)windowDidResize:(NSNotification *)notification {
	if (notification.object == self.window) {
		if (idxSelectionSheet.isVisible) {
			NSRect mFrm = self.window.frame;
			NSSize size = idxSelectionSheet.contentView.frame.size;
			[idxSelectionSheet setFrameOrigin:(NSPoint){
				mFrm.origin.x + (mFrm.size.width - size.width) / 2.,
				mFrm.origin.y - size.height }];
		} else [idxSelectionSheet setFrameOrigin:self.window.frame.origin];
	}
}
- (void)windowWillClose:(NSNotification *)notification {
	if (notification.object == self.window) {
		[statInfo statPanelDidClose:self];
		isClosing = YES;
		[idxSelectionSheet close];
	} else if (notification.object == idxSelectionSheet && !isClosing) {
		[idxSelectionSheet resignKeyWindow];
		NSRect pFrm = idxSelectionSheet.frame;
		pFrm.origin.y = self.window.frame.origin.y;
		[idxSelectionSheet setFrame:pFrm display:NO animate:YES];
	}
}
- (void)windowDidBecomeKey:(NSNotification *)notification {
	if (notification.object == idxSelectionSheet) {
		NSRect mFrm = self.window.frame, pFrm = idxSelectionSheet.frame;
		if (mFrm.origin.y > pFrm.origin.y) return;
		[self.window addChildWindow:idxSelectionSheet ordered:NSWindowBelow];
		pFrm.origin.x = mFrm.origin.x + (mFrm.size.width - pFrm.size.width) / 2.;
		[idxSelectionSheet setFrameOrigin:pFrm.origin];
		pFrm.origin.y = mFrm.origin.y - idxSelectionSheet.contentView.frame.size.height;
		[idxSelectionSheet setFrame:pFrm display:YES animate:YES];
	} else if (self.window.parentWindow != nil) {
		NSWindow *pWin = self.window.parentWindow;
		[pWin removeChildWindow:self.window];
		[pWin addChildWindow:self.window ordered:NSWindowAbove];
	}
}
- (void)switchIndexSelection:(NSButton *)sender {
	BOOL getOn = (sender.state == NSControlStateValueOn);
	if (getOn) timeEvoInfo.idxBits |= sender.tag;
	else timeEvoInfo.idxBits &= ~ sender.tag;
	if (sender.tag < MskTransit) {
		if (getOn) timeEvoInfo.nIndexes ++; else timeEvoInfo.nIndexes --;
		[self setupColorForCBoxes];
	} else {
		mvAvrgView.hidden = !getOn;
		reproRateCBox.enabled = !getOn;
		if (reproRateCBox.state) {
			if (getOn) timeEvoInfo.nIndexes --; else timeEvoInfo.nIndexes ++;
			[self setupColorForCBoxes];
		}
	}
	view.needsDisplay = YES;
}
- (IBAction)stepMvAvrg:(id)sender {
	timeEvoInfo.windowSize = mvAvrgDgt.integerValue = 1 << mvAvrgStp.integerValue;
	mvAvrgUnit.stringValue =
		NSLocalizedString((timeEvoInfo.windowSize > 1)? @"days" : @"day", nil);
	view.needsDisplay = YES;
}
- (void)drawView:(NSRect)bounds {
	[statInfo drawWithType:(StatType)typePopUp.indexOfSelectedItem
		info:&timeEvoInfo bounds:bounds];
}
- (IBAction)flushView:(id)sender {
	if (sender == typePopUp) {
		NSInteger idx = typePopUp.indexOfSelectedItem;
		if ((idxSelectionBtn.enabled = (idx == StatTimeEvo))) {
			if (idxSelectionBtn.state) [idxSelectionSheet makeKeyAndOrderFront:nil];
		} else if (idxSelectionBtn.state) [idxSelectionSheet close];
	}
	view.needsDisplay = YES;
}
- (IBAction)openCloseIdxSheet:(id)sender {
	if (idxSelectionSheet.isVisible) [idxSelectionSheet close];
	else [idxSelectionSheet makeKeyAndOrderFront:sender];
}
- (NSView *)view { return view; }
@end

@implementation StatView
- (void)drawRect:(NSRect)dirtyRect {
	[super drawRect:dirtyRect];
	[statPanel drawView:self.bounds];
}
@end
#endif
