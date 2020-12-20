//
//  StatPanel.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/09.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "StatPanel.h"
#import "Document.h"
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
#ifndef NOGUI
	imgBm = malloc(IMG_WIDTH * IMG_HEIGHT * 4);
	scenarioPhases = NSMutableArray.new;
#endif
	return self;
}
- (Document *)doc { return doc; }
#ifdef NOGUI
- (NSInteger)skipSteps { return skip; }
- (NSInteger)skipDays { return skipDays; }
- (void)setDoc:(Document *)docu { doc = docu; }
- (void)discardMemory {
	doc = nil;
	[statLock lock];
	free_stat_mem(&_statistics);
	free_stat_mem(&_transit);
	[statLock unlock];
}
#else
- (void)fillImageForOneStep:(StatData *)stat atX:(NSInteger)ix {
	static HealthType typeOrder[] =
		{Died, Susceptible, Recovered, Asymptomatic, Symptomatic};
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
- (void)reset:(NSInteger)nPop infected:(NSInteger)nInitInfec {
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
	pRateCumm = maxStepPRate = maxDailyPRate = 0.;
	_testResultCnt = (TestResultCount){0, 0};
	_statistics->cnt[Susceptible] = maxCounts[Susceptible] = nPop - nInitInfec;
	_statistics->cnt[Asymptomatic] = maxCounts[Asymptomatic] = nInitInfec;
	steps = days = 0;
	skip = skipDays = 1;
	popSize = nPop;
	[_IncubPHist removeAllObjects];
	[_RecovPHist removeAllObjects];
	[_DeathPHist removeAllObjects];
	[_NInfectsHist removeAllObjects];
	[_NInfectsHist addObject:MyCounter.new];
	_NInfectsHist[0].cnt = nInitInfec;
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
static CGFloat calc_positive_rate(NSUInteger *count) {
	NSUInteger tt = count[TestPositive] + count[TestNegative];
	return (tt == 0)? 0. : (CGFloat)count[TestPositive] / tt;
}
- (BOOL)calcStatWithTestCount:(NSUInteger *)testCount
	infects:(NSArray<NSArray<NSValue *> *> *)infects {
	Agent *agents = doc.agents;
	WorldParams *wp = doc.worldParamsP;
	NSInteger nPop = wp->initPop;
	Agent *qlist = doc.QList;
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
		if (j < unitJ - 1) [doc addOperation:block]; else block();
	}
	[doc waitAllOperations];
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

	for (NSInteger i = 0; i < NIntIndexes; i ++)
		if (maxCounts[i] < tmpStat.cnt[i]) maxCounts[i] = tmpStat.cnt[i];
	if (maxStepPRate < tmpStat.pRate) maxStepPRate = tmpStat.pRate;

	NSInteger idxInCum = steps % skip;
	if (idxInCum == 0) memset(&statCumm, 0, sizeof(StatData));
	for (NSInteger i = 0; i < NIntIndexes; i ++) statCumm.cnt[i] += tmpStat.cnt[i];
	statCumm.pRate += tmpStat.pRate;
	if (idxInCum + 1 >= skip) {
		StatData *newStat = new_stat();
		for (NSInteger i = 0; i < NIntIndexes; i ++)
			newStat->cnt[i] = statCumm.cnt[i] / skip;
		newStat->pRate = statCumm.pRate / skip;
		newStat->next = _statistics;
		_statistics = newStat;
		if (steps / skip > MAX_N_REC) {
			[statLock lock];
			for (StatData *p = newStat; p; p = p->next) {
				StatData *q = p->next;
				for (NSInteger i = 0; i < NIntIndexes; i ++)
					p->cnt[i] = (p->cnt[i] + q->cnt[i]) / 2;
				p->pRate = (p->pRate + q->pRate) / 2.;
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
- (void)openStatPanel:(NSWindow *)parentWindow {
	StatPanel *statPnl = [StatPanel.alloc initWithInfo:self];
	if (_statPanels == nil) _statPanels = NSMutableArray.new;
	[_statPanels addObject:statPnl];
	[statPnl showWindowWithParent:parentWindow];
}
- (void)statPanelDidClose:(StatPanel *)panel {
	[_statPanels removeObject:panel];
}
- (void)flushPanels {
	for (StatPanel *panel in _statPanels) [panel flushView:self];
}
- (NSArray *)fillPhaseBackground:(NSSize)size {
	NSInteger n = scenarioPhases.count;
	if (n < 2) return nil;
	NSMutableSet<NSNumber *> *ms = NSMutableSet.new;
	for (NSInteger i = 1; i < n; i += 2) [ms addObject:scenarioPhases[i]];
	NSInteger nPhases = ms.count, idx = 0;
	NSNumber *phs[nPhases];
	for (NSNumber *num in ms) phs[idx ++] = num;
	NSArray<NSNumber *> *phases = [NSArray arrayWithObjects:phs count:nPhases];
	NSRect rect = {0., 0.,
		scenarioPhases[0].integerValue * size.width / steps, size.height};
	NSMutableArray *labels = NSMutableArray.new;
	for (NSInteger i = 1; i < n; i += 2) {
		NSInteger phase = [phases indexOfObject:scenarioPhases[i]],
			step = (i < n - 1)? scenarioPhases[i + 1].integerValue : steps;
		rect.origin.x += rect.size.width;
		rect.size.width = step * size.width / steps - rect.origin.x;
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
typedef struct { NSUInteger maxCnt; CGFloat maxRate; } TimeEvoMax;
static TimeEvoMax show_time_evo(StatData *stData, TimeEvoInfo *info, NSUInteger maxV[],
	NSInteger steps, NSInteger skip, CGFloat maxPRate, NSRect rect) {
	TimeEvoMax teMax = {0, 0};
	NSUInteger nPoints = 0, k = 0;
	NSInteger winSz = (info->idxBits & MskTransit)? info->windowSize : 1;
	for (NSInteger i = 0; i < NIntIndexes; i ++) if ((info->idxBits & 1 << i) != 0)
		if (teMax.maxCnt < maxV[i]) teMax.maxCnt = maxV[i];
	BOOL drawPRate = (info->idxBits & MskTestPRate) != 0;
	for (StatData *tran = stData; tran != NULL; tran = tran->next) nPoints ++;
	NSPoint *pts = malloc(sizeof(NSPoint) * nPoints);
	void (^block)(CGFloat (^)(StatData *), CGFloat, NSUInteger) =
	^(CGFloat (^getter)(StatData *), CGFloat maxv, NSUInteger k) {
		StatData *tran = stData;
		for (NSInteger j = nPoints - 1; tran && j >= 0; tran = tran->next, j --)
			pts[j] = (NSPoint){
				j * (rect.size.width - 1.) / steps * skip + rect.origin.x,
				getter(tran) * rect.size.height / maxv + rect.origin.y};
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
		[[NSColor colorWithHue:(CGFloat)k / info->nIndexes
			saturation:1. brightness:1. alpha:1.] setStroke];
		[path stroke];
	};
	if (steps > 0 && teMax.maxCnt > 0) for (NSInteger i = 0; i < NIntIndexes; i ++)
	if ((info->idxBits & 1 << i) != 0 && maxV[i] > 0)
		block(^(StatData *tran) { return (CGFloat)tran->cnt[i]; }, teMax.maxCnt, k ++);
	if (drawPRate && maxPRate > 0) {
		block(^(StatData *tran) { return tran->pRate; }, maxPRate, k);
		teMax.maxRate = maxPRate;
	}
	free(pts);
	return teMax;
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
			[self fillPhaseBackground:(NSSize){bounds.size.width, dRect.origin.y}];
		NSBitmapImageRep *imgRep = [NSBitmapImageRep.alloc
			initWithBitmapDataPlanes:(unsigned char *[]){imgBm}
			pixelsWide:IMG_WIDTH pixelsHigh:IMG_HEIGHT bitsPerSample:8 samplesPerPixel:3
			hasAlpha:NO isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
			bytesPerRow:IMG_WIDTH * 4 bitsPerPixel:32];
		[imgRep drawInRect:dRect
			fromRect:(NSRect){0, 0, ((steps == 0)? 1 : steps) / skip, IMG_HEIGHT}
			operation:NSCompositingOperationCopy fraction:1. respectFlipped:NO hints:nil];
		[self drawLabels:labels y:NSMaxY(bounds)];
		draw_tics(bounds, (CGFloat)steps/doc.worldParamsP->stepsPerDay);
		} break;
		case StatTimeEvo: {
		[self drawLabels:[self fillPhaseBackground:bounds.size] y:NSMaxY(bounds)];
		NSRect dRect = drawing_area(bounds);
		TimeEvoMax teMax = ((info->idxBits & MskTransit) != 0)?
			show_time_evo(_transit, info, maxTransit, days, skipDays, maxDailyPRate, dRect) :
			show_time_evo(_statistics, info, maxCounts, steps, skip, maxStepPRate, dRect);
		NSMutableString *ms = NSMutableString.new;
		if (teMax.maxCnt > 0) [ms appendFormat:@"%@ %@ (%.2f%%)",
			NSLocalizedString(@"max count", nil),
			[decFormat stringFromNumber:@(teMax.maxCnt)], teMax.maxCnt * 100. / popSize];
		if (teMax.maxRate > 0.) [ms appendFormat:@"%s%@ %.3f%%",
			(ms.length > 0)? "\n" : "", NSLocalizedString(@"max rate", nil), teMax.maxRate * 100.];
		if (ms.length > 0) [ms
			drawAtPoint:(NSPoint){6., (bounds.size.height - NSFont.systemFontSize) / 2.}
			withAttributes:textAttributes];
		draw_tics(bounds, (CGFloat)steps/doc.worldParamsP->stepsPerDay);
		} break;
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
		cbox.underLineColor = cbox.state?
			[NSColor colorWithHue:((CGFloat)(k ++)) / timeEvoInfo.nIndexes
				saturation:1. brightness:1. alpha:1.] : nil;
		cbox.needsDisplay = YES;
	}
}
- (NSInteger)setupIndexCbox:(NSArray<NSView *> *)list tag:(NSInteger)tag {
	for (NSInteger i = 0; i < list.count; i ++) {
		NSView *view = list[i];
		if ([view isKindOfClass:NSButton.class]) {
			((NSButton *)view).target = self;
			((NSButton *)view).action = @selector(switchIndexSelection:);
			if ([view isKindOfClass:ULinedButton.class]) {
				((NSButton *)view).tag = tag;
				if (((NSButton *)view).state) {
					timeEvoInfo.idxBits |= tag; timeEvoInfo.nIndexes ++;
				}
				[indexCBoxes addObject:(ULinedButton *)view];
				tag <<= 1;
			} else {
				((NSButton *)view).tag = MskTransit;
				if (((NSButton *)view).state) timeEvoInfo.idxBits |= MskTransit;
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
	} else mvAvrgView.hidden = !getOn;
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
