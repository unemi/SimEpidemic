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
static StatData *new_stat(void) {
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

@implementation MyCounter
- (instancetype)init {
	if ((self = [super init]) == nil) return nil;
	_cnt = 0;
	return self;
}
- (void)inc { _cnt ++; }
@end

#define IMG_WIDTH (320*4)
#define IMG_HEIGHT	320
#define MAX_N_REC	IMG_WIDTH
@implementation StatInfo
- (instancetype)init {
	if (!(self = [super init])) return nil;
	_IncubPHist = NSMutableArray.new;
	_RecovPHist = NSMutableArray.new;
	_DeathPHist = NSMutableArray.new;
	imgBm = malloc(IMG_WIDTH * IMG_HEIGHT * 4);
	return self;
}
- (Document *)doc { return doc; }
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
- (void)reset:(NSInteger)nPop infected:(NSInteger)nInitInfec {
	if (statLock == nil) statLock = NSLock.new;
	[statLock lock];
	if (_statistics != NULL) {
		StatData **p = &_statistics;
		while ((*p)->next) p = &((*p)->next);
		*p = freeStat;
		freeStat = _statistics;
	}
	if (_transit != NULL) {
		StatData **p = &_transit;
		while ((*p)->next) p = &((*p)->next);
		*p = freeStat;
		freeStat = _transit;
		_transit = NULL;
	}
	[statLock unlock];
	_statistics = new_stat();
	memset(&statCumm, 0, sizeof(StatData));
	memset(&transDaily, 0, sizeof(StatData));
	memset(&transCumm, 0, sizeof(StatData));
	memset(maxCounts, 0, sizeof(maxCounts));
	memset(maxTransit, 0, sizeof(maxTransit));
	_statistics->cnt[Susceptible] = maxCounts[Susceptible] = nPop - nInitInfec;
	_statistics->cnt[Asymptomatic] = maxCounts[Asymptomatic] = nInitInfec;
	steps = days = 0;
	skip = skipDays = 1;
	popSize = nPop;
	[_IncubPHist removeAllObjects];
	[_RecovPHist removeAllObjects];
	[_DeathPHist removeAllObjects];
	memset(imgBm, 0, IMG_WIDTH * IMG_HEIGHT * 4);
	[self fillImageForOneStep:_statistics atX:0];
}
static void count_health(Agent *a, StatData *stat, StatData *tran) {
	if (a->health != a->newHealth) {
		a->health = a->newHealth;
		tran->cnt[a->health] ++;
	}
	stat->cnt[a->health] ++;
}
- (BOOL)calcStat:(Agent *_Nullable *_Nonnull)Pop nCells:(NSInteger)nCells
	qlist:(Agent *)qlist clist:(Agent *)clist warp:(NSArray<WarpInfo *> *)warp
	stepsPerDay:(NSInteger)stepsPerDay {
	StatData tmpStat;
	memset(&tmpStat, 0, sizeof(StatData));
	if (steps % stepsPerDay == 0) memset(&transDaily, 0, sizeof(StatData));
	steps ++;
	for (NSInteger i = 0; i < nCells; i ++)
		for (Agent *a = Pop[i]; a; a = a->next) count_health(a, &tmpStat, &transDaily);
	for (Agent *a = qlist; a; a = a->next) {
		if (a->gotAtHospital) {
			transDaily.cnt[a->health - Asymptomatic + QuarantineAsym] ++;
			a->gotAtHospital = NO;
		} else if (a->health == Asymptomatic && a->newHealth == Symptomatic)
			transDaily.cnt[QuarantineSymp] ++;
		count_health(a, &tmpStat, &transDaily);
		if (a->health == Asymptomatic || a->health == Symptomatic)
			tmpStat.cnt[a->health - Asymptomatic + QuarantineAsym] ++;
	}
	for (WarpInfo *info in warp)
		count_health(info.agent, &tmpStat, &transDaily);
	for (Agent *a = clist; a; a = a->next) count_health(a, &tmpStat, &transDaily);
	for (NSInteger i = 0; i < NIndexes; i ++)
		if (maxCounts[i] < tmpStat.cnt[i]) maxCounts[i] = tmpStat.cnt[i];

	NSInteger idxInCum = steps % skip;
	if (idxInCum == 0) memset(&statCumm, 0, sizeof(StatData));
	for (NSInteger i = 0; i < NIndexes; i ++) statCumm.cnt[i] += tmpStat.cnt[i];
	if (idxInCum + 1 >= skip) {
		StatData *newStat = new_stat();
		for (NSInteger i = 0; i < NIndexes; i ++)
			newStat->cnt[i] = statCumm.cnt[i] / skip;
		newStat->next = _statistics;
		_statistics = newStat;
		if (steps / skip > MAX_N_REC) {
			[statLock lock];
			for (StatData *p = newStat; p; p = p->next) {
				StatData *q = p->next;
				for (NSInteger i = 0; i < NIndexes; i ++)
					p->cnt[i] = (p->cnt[i] + q->cnt[i]) / 2;
				p->next = q->next;
				q->next = freeStat;
				freeStat = q;
			}
			[statLock unlock];
			skip *= 2;
			StatData *p = newStat;
			memset(imgBm, 0, IMG_WIDTH * IMG_HEIGHT * 4);
			for (NSInteger x = steps / skip; x >= 0 && p; x --, p = p->next)
				[self fillImageForOneStep:p atX:x];
		} else [self fillImageForOneStep:newStat atX:steps / skip];
	}
	if (steps % stepsPerDay == stepsPerDay - 1) {
		days ++;
		for (NSInteger i = 0; i < NIndexes; i ++)
			if (maxTransit[i] < transDaily.cnt[i]) maxTransit[i] = transDaily.cnt[i];
		idxInCum = days % skipDays;
		if (idxInCum == 0) memset(&transCumm, 0, sizeof(StatData));
		for (NSInteger i = 0; i < NIndexes; i ++)
			transCumm.cnt[i] += transDaily.cnt[i];
		if (idxInCum + 1 >= skipDays) {
			StatData *newTran = new_stat();
			for (NSInteger i = 0; i < NIndexes; i ++)
				newTran->cnt[i] = transCumm.cnt[i] / skipDays;
			newTran->next = _transit;
			_transit = newTran;
			if (days / skipDays >= MAX_N_REC) {
				[statLock lock];
				for (StatData *p = newTran; p; p = p->next) {
					StatData *q = p->next;
					for (NSInteger i = 0; i < NIndexes; i ++)
						p->cnt[i] = (p->cnt[i] + q->cnt[i]) / 2;
					p->next = q->next;
					q->next = freeStat;
					freeStat = q;
				}
				[statLock unlock];
				skipDays *= 2;
	}}}
	return _statistics->cnt[Asymptomatic] + _statistics->cnt[Symptomatic] == 0;
}
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
static NSRect drawing_area(NSRect area) {
	CGFloat ticsHeight = NSFont.systemFontSize * 1.4;
	return (NSRect){area.origin.x, area.origin.y + ticsHeight,
		area.size.width, area.size.height - ticsHeight};
}
static NSMutableDictionary *textAttributes = nil;
static void draw_tics(NSRect area, NSInteger xMax) {
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
static NSUInteger show_time_evo(StatData *stData, NSInteger idxBits, NSUInteger maxV[],
	NSInteger steps, NSInteger skip, NSRect rect) {
	NSUInteger maxValue = 0;
	for (NSInteger i = 0; i < NIndexes; i ++) if ((idxBits & 1 << i) != 0)
		if (maxValue < maxV[i]) maxValue = maxV[i];
	if (steps > 0 && maxValue > 0) for (NSInteger i = 0; i < NIndexes; i ++)
	if ((idxBits & 1 << i) != 0 && maxV[i] > 0) {
		NSBezierPath *path = NSBezierPath.new;
		StatData *tran = stData;
		[path moveToPoint:(NSPoint){NSMaxX(rect) - 1.,
			tran->cnt[i] * rect.size.height / maxValue + rect.origin.y}];
		tran = tran->next;
		for (NSInteger j = steps / skip - 1; tran; tran = tran->next, j --)
			[path lineToPoint:(NSPoint){
				j * (rect.size.width - 1.) / steps * skip + rect.origin.x,
				tran->cnt[i] * rect.size.height / maxValue + rect.origin.y}];
		NSColor *col = (i < NHealthTypes)? stateColors[i] :
			warpColors[i - NHealthTypes + Asymptomatic];
		[col  setStroke];
		[path stroke];
	}
	return maxValue;
}
static void show_histogram(NSArray<MyCounter *> *hist,
	NSInteger idx, NSSize size, NSString *title) {
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
	static HealthType colIdx[] = {Asymptomatic, Recovered, Died};
	[stateColors[colIdx[idx]] setFill];
	CGFloat w = size.width / 3. / (n - st);
	for (NSInteger i = st; i < n; i ++)
		[NSBezierPath fillRect:(NSRect){(i - st) * w + idx * size.width / 3., 0.,
			w, hist[i].cnt * size.height / max}];
	[[NSString stringWithFormat:NSLocalizedString(@"HistogramFormat", nil),
		NSLocalizedString(title, nil), ns, st, n, md, ((CGFloat)sum) / ns]
		drawAtPoint:(NSPoint){size.width * idx / 3. + 4., 10.}
		withAttributes:textAttributes];
}
- (void)drawWithType:(StatType)type indexBits:(NSInteger)idxBits bounds:(NSRect)bounds {
	static NSNumberFormatter *decFormat = nil;
	if (textAttributes == nil) {
		textAttributes = NSMutableDictionary.new;
		textAttributes[NSFontAttributeName] = [NSFont userFontOfSize:NSFont.systemFontSize];
		decFormat = NSNumberFormatter.new;
		decFormat.numberStyle = NSNumberFormatterDecimalStyle;
	}
	textAttributes[NSForegroundColorAttributeName] = stateColors[ColText];
	[stateColors[ColBackground] setFill];
	[NSBezierPath fillRect:bounds];
	switch (type) {
		case StatWhole: {
		NSBitmapImageRep *imgRep = [NSBitmapImageRep.alloc
			initWithBitmapDataPlanes:(unsigned char *[]){imgBm}
			pixelsWide:IMG_WIDTH pixelsHigh:IMG_HEIGHT bitsPerSample:8 samplesPerPixel:3
			hasAlpha:NO isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
			bytesPerRow:IMG_WIDTH * 4 bitsPerPixel:32];
		[imgRep drawInRect:drawing_area(bounds)
			fromRect:(NSRect){0, 0, ((steps == 0)? 1 : steps) / skip, IMG_HEIGHT}
			operation:NSCompositingOperationCopy fraction:1. respectFlipped:NO hints:nil];
		draw_tics(bounds, days);
		} break;
		case StatTimeEvo: {
		NSRect dRect = drawing_area(bounds);
		NSUInteger maxValue = ((idxBits & MskTransit) != 0)?
			show_time_evo(_transit, idxBits, maxTransit, days, skipDays, dRect) :
			show_time_evo(_statistics, idxBits, maxCounts, steps, skip, dRect);
		if (maxValue > 0) [[NSString stringWithFormat:@"%@ %@ (%.2f%%)",
			NSLocalizedString(@"max", nil),
			[decFormat stringFromNumber:@(maxValue)], maxValue * 100. / popSize]
				drawAtPoint:(NSPoint){6., (bounds.size.height - NSFont.systemFontSize) / 2.}
				withAttributes:textAttributes];
			draw_tics(bounds, days);
		} break;
		case StatPeriods:
		show_histogram(_IncubPHist, 0, bounds.size, @"Incubation Period");
		show_histogram(_RecovPHist, 1, bounds.size, @"Recovery Period");
		show_histogram(_DeathPHist, 2, bounds.size, @"Fatal Period");
	}
}
@end

@implementation StatPanel
- (instancetype)initWithInfo:(StatInfo *)info {
	if (!(self = [super initWithWindowNibName:@"StatPanel"])) return nil;
	statInfo = info;
	return self;
}
- (void)windowDidLoad {
	[super windowDidLoad];
	[statInfo.doc setPanelTitle:self.window];
	NSArray<NSButton *> *selBtns = idxSelectionView.subviews;
	for (NSInteger i = 0; i < selBtns.count; i ++) {
		selBtns[i].tag = 1 << i;
		selBtns[i].target = self;
		selBtns[i].action = @selector(switchIndexSelection:);
		if (selBtns[i].state == NSControlStateValueOn) idxBits |= 1 << i;
		selBtns[i].toolTip = selBtns[i].title;
	}
}
- (void)windowWillClose:(NSNotification *)notification {
	[statInfo statPanelDidClose:self];
}
- (void)switchIndexSelection:(NSButton *)sender {
	if (sender.state == NSControlStateValueOn) idxBits |= sender.tag;
	else idxBits &= ~ sender.tag;
	view.needsDisplay = YES;
}
- (void)drawView:(NSRect)bounds {
	[statInfo drawWithType:(StatType)typePopUp.indexOfSelectedItem
		indexBits:idxBits bounds:bounds];
}
- (IBAction)flushView:(id)sender {
	if (sender == typePopUp) {
		NSInteger idx = typePopUp.indexOfSelectedItem;
		idxSelectionView.hidden = (idx != StatTimeEvo);
	}
	view.needsDisplay = YES;
}
@end

@implementation StatView
- (void)drawRect:(NSRect)dirtyRect {
	[super drawRect:dirtyRect];
	[statPanel drawView:self.bounds];
}
@end
