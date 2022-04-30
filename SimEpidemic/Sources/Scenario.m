//
//  Scenario.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2021/10/01.
//  Copyright © 2021 Tatsuo Unemi. All rights reserved.
//
#import "Scenario.h"
#import "StatPanel.h"
#ifndef NOGUI
#import "Document.h"
#endif

@implementation World (ScenarioExtension)
static NSInteger age_span_index_from_key(NSString *key) {
	NSScanner *scan = [NSScanner scannerWithString:key];
	[scan scanUpToString:@" " intoString:NULL];
	if (scan.atEnd) return -1;
	NSInteger idx = [key substringFromIndex:scan.scanLocation + 1].integerValue;
	return (idx < 0)? 0 : (idx > MAX_N_AGE_SPANS)? MAX_N_AGE_SPANS - 1 : idx;
}
- (void)reviseFinalVaxRate:(CGFloat)newRate index:(NSInteger)spanIdx {
	VaccineFinalRate *fr = runtimeParams.vcnFnlRt + spanIdx;
	NSInteger npop = spanNPop[spanIdx], n = round(npop * (newRate - fr->rate));
	if (n == 0) return;
	NSInteger *IDs = malloc(sizeof(NSInteger) * npop);
	memcpy(IDs, ageSpanIDs + ageSpanIdxs[spanIdx], sizeof(NSInteger) * npop);
	struct FVInfo { BOOL acc; ForVaccine fVcn; } info;
	if (n > 0) info = (struct FVInfo){ NO, VcnAccept };
	else { info = (struct FVInfo){ YES, VcnReject }; n = -n; }
	for (NSInteger i = 0; i < npop && n > 0; i ++) {
		NSInteger j = random() % (npop - i) + i;
		Agent *a = self.agents + IDs[j];
		if (j != i) IDs[j] = IDs[i];
		if ((a->forVcn == VcnAccept) == info.acc && a->health != Died)
			{ a->forVcn = info.fVcn; n --; }
	}
	fr->rate = newRate;
	free(IDs);
}
- (void)execScenario {
	predicateToStop = nil;
	if (scenario == nil) return;
	char *visitFlags = malloc(scenario.count);
	memset(visitFlags, 0, scenario.count);
	NSPredicate *pred = nil;
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
					case 3:	if ([arr[1] respondsToSelector:@selector(intValue)]) {
					 // add infected individuals of specified variant
						int varType = [self variantTypeFromName:arr[2]];
						InfecLocation loc = [arr[1] intValue];
						if (varType >= 0) [self addInfected:n location:loc variant:varType];
				}}
			} else if ([arr[1] isKindOfClass:NSPredicate.class]) {	// continue until --
				pred = (NSPredicate *)arr[1];
			} else if (arr.count == 2) md[arr[0]] = arr[1];	// paramter assignment
			else if ([(NSString *)arr[0] hasPrefix:@"vaccineFinalRate"]) {
				md[arr[0]] = arr[1]; // final vax rate must not be delayed.
			} else {	// parameter assignment with delay
				NSObject *goal = arr[1];
				if (![(NSString *)arr[0] hasPrefix:@"vaccineAnti"]) {
					NSInteger idx = paramIndexFromKey[arr[0]].integerValue;
					if (idx >= IDX_D && idx < IDX_I && [arr[1] isKindOfClass:NSNumber.class])
						goal = @[goal, goal, goal];
				}
				paramChangers[arr[0]] = @[goal,
					@(runtimeParams.step / worldParams.stepsPerDay + [(arr[2]) doubleValue])];
			}
		} else if ([item isKindOfClass:NSDictionary.class]) {	// for upper compatibility
			[md addEntriesFromDictionary:(NSDictionary *)item];
		} else if ([item isKindOfClass:NSNumber.class]) {	// add infected individuals
			[self addInfected:((NSNumber *)item).integerValue
				location:IfcLocScattered variant:0];
		} else if ([item isKindOfClass:NSPredicate.class])	// predicate to stop
			pred = (NSPredicate *)item;
		if (pred != nil && ![pred evaluateWithObject:statInfo]) {
			predicateToStop = pred; hasStopCond = YES; break;
		}
	}
	free(visitFlags);
#ifndef NOGUI
	if (hasStopCond)
		[NSNotificationCenter.defaultCenter postNotificationName:nnScenarioText object:self];
#endif
	if (md.count > 0) {	// parameter change
		NSNumber *idxNum;
		for (NSString *key in md) {
			if ([key hasPrefix:@"vaccine"]) {
				if ([key hasPrefix:@"vaccineFinalRate"]) {
					CGFloat newRate = fmax(0., fmin(1., ((NSNumber *)md[key]).doubleValue / 100.));
					NSInteger spanIdx = age_span_index_from_key(key);
					if (spanIdx < 0) {
						VaccineFinalRate *fr = runtimeParams.vcnFnlRt;
						NSInteger orgN = 0, nSubPop = 0;
						for (NSInteger idx = 0; idx < nAgeSpans; idx ++)
							if (fr[idx].rate > 0.) {
								orgN += round(spanNPop[idx] * fr[idx].rate);
								nSubPop += spanNPop[idx];
							}
						CGFloat a = (1. - newRate) / (1. - (CGFloat)orgN / nSubPop);
						for (NSInteger idx = 0; idx < nAgeSpans; idx ++)
							if (fr[idx].rate > 0.)
								[self reviseFinalVaxRate:1. - a * (1. - fr[idx].rate) index:idx];
					} else [self reviseFinalVaxRate:newRate index:spanIdx];
				} else if ((idxNum = paramIndexFromKey[key]) != nil) {
					NSInteger idx = idxNum.integerValue;
					if (idx >= IDX_R && idx < IDX_E)
						(&worldParams.PARAM_R1)[idx - IDX_R] = ((NSNumber *)md[key]).doubleValue;
				} else {
					int vcnType;
					NSString *varName = [self varNameFromKey:key vcnTypeReturn:&vcnType];
					if (vcnType < 0) continue;
					VaccinationInfo *vInfo = &runtimeParams.vcnInfo[vcnType];
					NSNumber *num = (NSNumber *)md[key];
					if ([varName hasSuffix:@"Rate"]) vInfo->performRate = num.doubleValue;
					else if ([varName hasSuffix:@"Regularity"]) vInfo->regularity = num.doubleValue;
					else {
						int pr = num.intValue;
						if (pr >= VcnPrRandom && pr <= VcnPrBooster && pr != vInfo->priority) {
							vInfo->priority = pr;
							if (pr == VcnPrBooster) [self resetBoostQueue];
						}
					}
				}
			} else if ([key hasPrefix:@"regGat "]) {
				set_reg_gat_value(self.gatheringsList, key, (NSNumber *)md[key], 1.);
			} else { // parameters other than vaccination
				if ((idxNum = paramIndexFromKey[key]) == nil) continue;
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
#endif
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
- (NSArray *)scenarioPList {
	if (scenario == nil || scenario.count == 0) return @[];
	NSObject *items[scenario.count];
	for (NSInteger i = 0; i < scenario.count; i ++)
		items[i] = property_from_element(scenario[i]);
	return [NSArray arrayWithObjects:items count:scenario.count];
}
- (void)setScenarioPList:(NSArray *)plist {
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
@end
