//
//  Statistics.m
//  simepiWorld
//
//  Created by Tatsuo Unemi on 2020/11/24.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "Statistics.h"
#import "../SimEpidemic/Sources/Agent.h"

NSString *indexNames[] = {
	@"susceptible", @"asymptomatic", @"symptomatic", @"recovered", @"died",
	@"vaccinated",
	@"quarantineAsymptomatic", @"quarantineSymptomatic",
	@"tests", @"testAsSymptom", @"testAsContact", @"testAsSuspected",
	@"testPositive", @"testNegative",
nil};
NSString *distributionNames[] = {
	@"incubasionPeriod", @"recoveryPeriod", @"fatalPeriod", @"infects",
nil};
NSArray *make_history(StatData *stat, NSInteger nItems,
	NSNumber *(^getter)(StatData *)) {
	if (nItems == 1 && stat != NULL) return @[getter(stat)];
	NSNumber *nums[nItems];
	NSInteger i = nItems - 1;
	for (StatData *p = stat; i >= 0 && p != NULL; i --, p = p->next)
		nums[i] = getter(p);
	return [NSArray arrayWithObjects:nums + i + 1 count:nItems - i - 1];
}
void get_indexes(ComGetIndexes *c) {
	RuntimeParams *rp = document.runtimeParamsP;
	WorldParams *wp = document.worldParamsP;
	NSInteger nSteps = (rp->step < c->fromStep)? 1 : rp->step - c->fromStep + 1;
	NSMutableDictionary *md = NSMutableDictionary.new;
	StatInfo *statInfo = document.statInfo;
	StatData *statData = (c->nameFlag & MskTransit)? statInfo.transit : statInfo.statistics;
	NSInteger nItems = (c->nameFlag & MskTransit)?
		(nSteps - 1) / statInfo.skipSteps + 1 :
		(nSteps / wp->stepsPerDay - 1) / statInfo.skipDays + 1;
	[document popLock];
	if (c->nameFlag & MskRunning) md[@"isRunning"] = @(document.running);
	if (c->nameFlag & MskStep) md[@"step"] = @(rp->step);
	if (c->nameFlag & MskDays) md[@"days"] = @((CGFloat)rp->step / wp->stepsPerDay);
	if (c->nameFlag & MskTestPRate) md[@"testPositiveRate"] =
		make_history(statData, nItems, ^(StatData *st) { return @(st->pRate); });
	if ((c->nameFlag & (MskReproRate|MskTransit)) == (MskReproRate|MskTransit))
		md[@"reproductionRate"] =
			make_history(statData, nItems, ^(StatData *st) { return @(st->reproRate); });
	uint32 msk = 1;
	for (NSInteger idx = 0; indexNames[idx] != NULL; idx ++, msk <<= 1)
	if (c->nameFlag & msk) md[indexNames[idx]] =
		make_history(statData, nItems, ^(StatData *st) { return @(st->cnt[idx]); });
	[document popUnlock];
	if (md.count == 0) respond_err(@"No valid index names are specified.");
	else respond_JSON(md);
}
NSArray *dist_cnt_array(NSArray<MyCounter *> *hist) {
	NSMutableArray *ma = NSMutableArray.new;
	NSInteger st = -1, n = hist.count;
	for (NSInteger i = 0; i < n; i ++) {
		NSInteger cnt = hist[i].cnt;
		if (st == -1 && cnt > 0) [ma addObject:@((st = i))];
		if (st >= 0) [ma addObject:@(cnt)];
	}
	return ma;
}
void get_distribution(ComGetDistribution *c) {
	NSMutableDictionary *md = NSMutableDictionary.new;
	StatInfo *statInfo = document.statInfo;
	NSArray<MyCounter *> *counters[] = {statInfo.IncubPHist,
		statInfo.RecovPHist, statInfo.DeathPHist, statInfo.NInfectsHist};
	[document popLock];
	uint32 msk = 1;
	for (NSInteger idx = 0; distributionNames[idx] != NULL; idx ++, msk <<= 1)
		if (c->nameFlag & msk)
			md[distributionNames[idx]] = dist_cnt_array(counters[idx]);
	[document popUnlock];
	if (md.count == 0) respond_err(@"No valid distribution names are specified.");
	else respond_JSON(md);
}
static uint32 int_coord(CGFloat x, NSInteger worldSize) {
	return x * 10000 / worldSize;
}
static NSArray *agent_cood_h(Agent *a, WorldParams *wp) {
	return @[@(int_coord(a->x, wp->worldSize)), @(int_coord(a->y, wp->worldSize)),
		@(a->health)];
}
static void get_population1(void) {
	WorldParams *wp = document.worldParamsP;
	NSMutableArray *md = NSMutableArray.new;
	[document popLock];
	Agent **pop = document.Pop;
	for (NSInteger i = 0; i < wp->mesh * wp->mesh; i ++)
		for (Agent *a = pop[i]; a != NULL; a = a->next)
			[md addObject:agent_cood_h(a, wp)];
	for (Agent *a = document.QList; a != NULL; a = a->next)
		[md addObject:agent_cood_h(a, wp)];
	for (Agent *a = document.CList; a != NULL; a = a->next)
		[md addObject:agent_cood_h(a, wp)];
	for (WarpInfo *info in document.WarpList.objectEnumerator) {
		Agent *a = info.agent;
		[md addObject:@[@(int_coord(a->x, wp->worldSize)),
			@(int_coord(a->y, wp->worldSize)), @(a->health),
			@(int_coord(info.goal.x, wp->worldSize)),
			@(int_coord(info.goal.y, wp->worldSize)),
			@(info.mode)]];
	}
	[document popUnlock];
	respond_JSON(md);
}
static NSArray *agent_cood(Agent *a, WorldParams *wp) {
	return @[@(int_coord(a->x, wp->worldSize)), @(int_coord(a->y, wp->worldSize))];
}
static void get_population2(void) {
	WorldParams *wp = document.worldParamsP;
	NSMutableArray *posts[NHealthTypes];
	for (NSInteger i = 0; i < NHealthTypes; i ++) posts[i] = NSMutableArray.new;
	[document popLock];
	Agent **pop = document.Pop;
	for (NSInteger i = 0; i < wp->mesh * wp->mesh; i ++)
		for (Agent *a = pop[i]; a != NULL; a = a->next)
			[posts[a->health] addObject:agent_cood(a, wp)];
	for (Agent *a = document.QList; a != NULL; a = a->next)
		[posts[a->health] addObject:agent_cood(a, wp)];
	for (Agent *a = document.CList; a != NULL; a = a->next)
		[posts[a->health] addObject:agent_cood(a, wp)];
	for (WarpInfo *info in document.WarpList.objectEnumerator) {
		Agent *a = info.agent;
		[posts[a->health] addObject:@[
			@(int_coord(a->x, wp->worldSize)), @(int_coord(a->y, wp->worldSize)),
			@(int_coord(info.goal.x, wp->worldSize)),
			@(int_coord(info.goal.y, wp->worldSize)), @(info.mode)]];
	}
	[document popUnlock];
	respond_JSON([NSArray arrayWithObjects:posts count:NHealthTypes]);
}
void get_population(ComGetPopulation *c) {
	if (c->format == PopFormat1) get_population1();
	else get_population2();
}
