//
//  AppDelegate.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "AppDelegate.h"
#import "Document.h"
#import "World.h"
#import "SaveDoc.h"
#ifdef NOGUI
#import "../../SimEpidemicSV/noGUI.h"
#else
#import "Preferences.h"
#endif
#import <sys/time.h>
#import <sys/sysctl.h>

NSInteger nCores = 1;
BOOL isARM = NO;
unsigned long current_time_us(void) {
	static long startTime = -1;
	struct timeval tv;
	gettimeofday(&tv, NULL);
	if (startTime < 0) startTime = tv.tv_sec;
	return (tv.tv_sec - startTime) * 1000000L + tv.tv_usec;
}
#ifndef NOGUI
void error_msg(NSObject *obj, NSWindow *window, BOOL critical) {
	NSString *message = [obj isKindOfClass:NSString.class]? (NSString *)obj :
		[obj isKindOfClass:NSError.class]? [NSString stringWithFormat:@"%@ %@ (%ld)",
			((NSError *)obj).localizedDescription,
			((NSError *)obj).localizedFailureReason,
			((NSError *)obj).code] :
		[obj isKindOfClass:NSException.class]? ((NSException *)obj).reason :
		[NSString stringWithFormat:@"%@ (%@)", obj.description, obj.className];
	NSAlert *alt = NSAlert.new;
	alt.alertStyle = critical? NSAlertStyleCritical : NSAlertStyleWarning;
	alt.messageText = message;
	if (window != nil) [alt beginSheetModalForWindow:window
		completionHandler:^(NSModalResponse returnCode)
			{ if (critical) [NSApp terminate:nil]; }];
	else {
		[alt runModal];
		if (critical) [NSApp terminate:nil];
	}
}
void confirm_operation(NSString *text, NSWindow *window, void (^proc)(void)) {
	NSAlert *alt = NSAlert.new;
	alt.alertStyle = NSAlertStyleWarning;
	alt.messageText = NSLocalizedString(@"This operation cannot be undone.", nil);
	alt.informativeText = NSLocalizedString(text, nil);
	[alt addButtonWithTitle:@"OK"];
	[alt addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
	[alt beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
		if (returnCode == NSAlertFirstButtonReturn) proc();
	}];
}
void show_anime_steps(NSTextField *txtField, NSInteger steps) {
	txtField.stringValue = (steps == 1)?
		NSLocalizedString(@"Draw in each step.", nil) :
		[NSString stringWithFormat:NSLocalizedString(@"AnimeStepsFormat", nil), steps];
}
NSObject *get_propertyList_from_url(NSURL *url, Class class, NSWindow *window) {
	NSError *error;
	NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
	if (data == nil) { @try {
		if (error.code != NSFileReadNoPermissionError) @throw error;
		NSFileWrapper *fw = [NSFileWrapper.alloc initWithURL:url options:0 error:NULL];
		if (fw == nil || !fw.isDirectory) @throw error;
		fw = fw.fileWrappers[fnParamsPList];
		if (fw == nil || !fw.isRegularFile) @throw error;
		data = fw.regularFileContents;
		} @catch (NSError *err) { error_msg(err, window, NO); return nil; }
	}
	NSObject *object = [url.pathExtension isEqualToString:@"json"]?
		[NSJSONSerialization JSONObjectWithData:data options:0 error:&error] :
		[NSPropertyListSerialization propertyListWithData:data
		options:NSPropertyListImmutable format:NULL error:&error];
	if (object == nil) { error_msg(error, window, NO); return nil; }
	if (class != NULL && ![object isKindOfClass:class])
		{ error_msg(@"Property is invalid class.", window, NO); return nil; }
	return object;
}
void load_property_data(NSArray<NSString *> *fileTypes, NSWindow *window,
	Class class, void (^block)(NSURL *url, NSObject *)) {
	NSOpenPanel *op = NSOpenPanel.openPanel;
	op.allowedFileTypes = fileTypes;
	[op beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		NSObject *object = get_propertyList_from_url(op.URL, class, window);
		if (object != nil) block(op.URL, object);
	}];
}
void save_property_data(NSString *fileType, NSWindow *window, NSObject *object) {
	NSSavePanel *sp = NSSavePanel.savePanel;
	sp.allowedFileTypes = @[fileType, @"json"];
	[sp beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		NSError *error;
		NSData *data = [sp.URL.pathExtension isEqualToString:@"json"]?
			[NSJSONSerialization dataWithJSONObject:object
				options:JSONFormat error:&error] :
			[NSPropertyListSerialization dataWithPropertyList:object
			format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
		if (data == nil) { error_msg(error, window, NO); return; }
		if (![data writeToURL:sp.URL options:0 error:&error])
			error_msg(error, window, NO);
	}];
}
static NSString *keyWinFrame = @"windowFrame", *keyWinOrder = @"windowOrder";
NSMutableDictionary *dict_of_window_geom(NSWindow *window) {
	NSMutableDictionary *md = NSMutableDictionary.new;
	NSRect frm = window.frame;
	md[keyWinFrame] = @[@(frm.origin.x), @(frm.origin.y), @(frm.size.width), @(frm.size.height)];
	md[keyWinOrder] = @(window.isVisible? window.orderedIndex : -1);
	return md;
}
NSRect frame_rect_from_dict(NSDictionary *dict) {
	NSArray<NSNumber *> *array = dict[keyWinFrame];
	if (array == nil || array.count < 4) return NSZeroRect;
	return (NSRect){array[0].doubleValue, array[1].doubleValue,
		array[2].doubleValue, array[3].doubleValue};
}
void window_order_info(NSWindow *window, NSDictionary *dict, NSMutableArray *winList) {
	NSNumber *num = dict[keyWinOrder];
	if (num != nil) [winList addObject:@[window, num]]; 
}
void rearrange_window_order(NSMutableArray<NSArray *> *winList) {
	if (winList.count <= 1) return;
	[winList sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
		NSInteger ia = [a[1] integerValue], ib = [b[1] integerValue];
		return (ia < ib)? NSOrderedAscending : (ia > ib)? NSOrderedDescending
			: NSOrderedSame;
	}];
	for (NSInteger i = winList.count - 1; i > 0; i --)
		[(NSWindow *)winList[i][0] orderFront:nil];
	[(NSWindow *)winList[0][0] makeKeyAndOrderFront:nil];
}
NSString *keyAnimeSteps = @"animeSteps";
#endif
ParamInfo paramInfo[] = {
	{ ParamTypeFloat, @"mass", {.f = { 20., 1., 100.}}},
	{ ParamTypeFloat, @"friction", {.f = { 80., 0., 100.}}},
	{ ParamTypeFloat, @"avoidance", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"maxSpeed", {.f = { 50., 10., 100.}}},

	{ ParamTypeFloat, @"activenessMode", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"activenessKurtosis", {.f = { 0., -100., 100.}}},
	{ ParamTypeFloat, @"massBias", {.f = { 4., 1., 10.}}},
	{ ParamTypeFloat, @"mobilityBias", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"gatheringBias", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"incubationBias", {.f = { 0., -100., 100.}}},
	{ ParamTypeFloat, @"fatalityBias", {.f = { 0., -100., 100.}}},
//	{ ParamTypeFloat, @"recoveryBias", {.f = { 0., -100., 100.}}},
	{ ParamTypeFloat, @"immunityBias", {.f = { 0., -100., 100.}}},
	{ ParamTypeFloat, @"therapyEfficacy", {.f = { 0., 0., 100.}}},

	{ ParamTypeFloat, @"contagionDelay", {.f = { .5, 0., 10.}}},
	{ ParamTypeFloat, @"contagionPeak", {.f = { 3., 1., 10.}}},
	{ ParamTypeFloat, @"infectionProberbility", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"infectionDistance", {.f = { 3., .1, 10.}}},

	{ ParamTypeFloat, @"distancingStrength", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"distancingObedience", {.f = { 20., 0., 100.}}},
	{ ParamTypeFloat, @"backHomeRate", {.f = { 75., 0., 100.}}},
	{ ParamTypeFloat, @"gatheringFrequency", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"gatheringSpotRandom", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"contactTracing", {.f = { 20., 0., 100.}}},
	{ ParamTypeFloat, @"testDelay", {.f = { 1., 0., 10.}}},
	{ ParamTypeFloat, @"testProcess", {.f = { 1., 0., 10.}}},
	{ ParamTypeFloat, @"testInterval", {.f = { 2., 0., 10.}}},
	{ ParamTypeFloat, @"testSensitivity", {.f = { 70., 0., 100.}}},
	{ ParamTypeFloat, @"testSpecificity", {.f = { 99.8, 0., 100.}}},
	{ ParamTypeFloat, @"subjectAsymptomatic", {.f = { 1., 0., 100.}}},
	{ ParamTypeFloat, @"subjectSymptomatic", {.f = { 99., 0., 100.}}},
	{ ParamTypeFloat, @"testCapacity", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"testDelayLimit", {.f = { 3., 1., 14.}}},
	{ ParamTypeFloat, @"immuneMaxPeriod", {.f = { 200., 50., 500.}}},
	{ ParamTypeFloat, @"immuneMaxPrdSeverity", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"immuneMaxEfficacy", {.f = { 90., 0., 100.}}},
	{ ParamTypeFloat, @"immuneMaxEffcSeverity", {.f = { 20., 0., 100.}}},

	{ ParamTypeDist, @"mobilityDistance", {.d = { 10., 30., 80.}}},
	{ ParamTypeDist, @"incubation", {.d = { 1., 5., 14.}}},
	{ ParamTypeDist, @"fatality", {.d = { 4., 16., 20.}}},
//	{ ParamTypeDist, @"recovery", {.d = { 4., 10., 40.}}},
//	{ ParamTypeDist, @"immunity", {.d = { 30., 180., 360.}}},
	{ ParamTypeDist, @"gatheringSize", {.d = { 5., 10., 20.}}},
	{ ParamTypeDist, @"gatheringDuration", {.d = { 6., 12., 24.}}},
	{ ParamTypeDist, @"gatheringStrength", {.d = { 50., 80., 100.}}},
	{ ParamTypeDist, @"mobilityFrequency", {.d = { 40., 70., 100.}}},
	{ ParamTypeDist, @"gatheringParticipation", {.d = { 40., 70., 100.}}},
	
	{ ParamTypeInteger, @"populationSize", {.i = { 10000, 100, 999900}}},
	{ ParamTypeInteger, @"worldSize", {.i = { 360, 10, 999999}}},
	{ ParamTypeInteger, @"mesh", {.i = { 18, 1, 999}}},
//	{ ParamTypeInteger, @"initialInfected", {.i = { 20, 1, 999}}},
	{ ParamTypeInteger, @"stepsPerDay", {.i = { 12, 1, 999}}},
	
	{ ParamTypeRate, @"initialInfectedRate", {.f = { .1, 0., 100.}}},
	{ ParamTypeRate, @"initialRecovered", {.f = { 0., 0., 100.}}},
	{ ParamTypeRate, @"quarantineAsymptomatic", {.f = { 20., 0., 100.}}},
	{ ParamTypeRate, @"quarantineSymptomatic", {.f = { 50., 0., 100.}}},
	{ ParamTypeRate, @"gatheringSpotFixed", {.f = { 0., 0., 100.}}},
//	{ ParamTypeRate, @"vaccineAntiRate", {.f = { 30., 0., 100.}}},
	{ ParamTypeRate, @"antiVaxClusterRate", {.f = { 60., 0., 100.}}},
	{ ParamTypeRate, @"antiVaxClusterGranularity", {.f = { 50., 0., 100.}}},
	{ ParamTypeRate, @"antiVaxTestRate", {.f = { 50., 0., 100.}}},
	{ ParamTypeRate, @"recoveryBias", {.f = { 150., 0., 200.}}},
	{ ParamTypeRate, @"recoveryTemp", {.f = { 50., 1., 100.}}},
	{ ParamTypeRate, @"recoveryUpperRate", {.f = { 500., 100., 900.}}},
	{ ParamTypeRate, @"recoveryLowerRate", {.f = { 40., 0., 100.}}},
	{ ParamTypeRate, @"vaccineFirstDoseEfficacy", {.f = { 30., 0., 100.}}},
	{ ParamTypeRate, @"vaccineMaxEfficacy", {.f = { 90., 0., 100.}}},
	{ ParamTypeRate, @"vaccineEfficacySymp", {.f = { 95., 0., 100.}}},
	{ ParamTypeRate, @"vaccineEffectDelay", {.f = { 14., 0., 30.}}},
	{ ParamTypeRate, @"vaccineEffectPeriod", {.f = { 200., 50., 500.}}},
	{ ParamTypeRate, @"vaccineEffectDecay", {.f = { 100., 0., 500.}}},
	{ ParamTypeRate, @"vaccineSvEfficacy", {.f = { 90., 0., 99.}}},

	{ ParamTypeEnum, @"tracingOperation", {.e = {0, 2}}},
	{ ParamTypeEnum, @"vaccineTypeForTracingVaccination", {.e = {0, MAX_N_VAXEN - 1}}},
	{ ParamTypeWEnum, @"workPlaceMode", {.e = {0, 3}}},

	{ ParamTypeNone, nil }
};
static VaccineFinalRate defaultVaxFnlRt[MAX_N_AGE_SPANS] = {
	{2, 0.}, {12, 0.}, {15, .9}, {20, .7}, {50, .8}, {65, .85}, {200, .9},
	{-1, 0.}
};

NSString *keyVaxPerformRate = @"performRate", *keyVaxRegularity = @"regularity",
	*keyVaxPriority = @"priority", *keyVaccinationInfo = @"vaccinationInfo",
	*keyVaccineFinalRate = @"vaccineFinalRate";
NSInteger defaultAnimeSteps = 1;
RuntimeParams defaultRuntimeParams, userDefaultRuntimeParams;
WorldParams defaultWorldParams, userDefaultWorldParams;
NSArray<NSString *> *paramKeys;
NSArray<NSNumberFormatter *> *paramFormatters;
NSDictionary<NSString *, NSString *> *paramKeyFromName;
NSDictionary<NSString *, NSNumber *> *paramIndexFromKey;
NSString *keyInitialInfected = @"initialInfected";
typedef struct {
	CGFloat *fp, *tp;
	DistInfo *dp;
	NSInteger *ip;
	sint32 *ep, *hp;
} ParamPointers;
static ParamPointers param_pointers(RuntimeParams *rp, WorldParams *wp) {
	return (ParamPointers) {
		(rp != NULL)? &rp->PARAM_F1 : NULL,
		(wp != NULL)? &wp->PARAM_R1 : NULL,
		(rp != NULL)? &rp->PARAM_D1 : NULL,
		(wp != NULL)? &wp->PARAM_I1 : NULL,
		(rp != NULL)? (sint32 *)&rp->PARAM_E1 : NULL,
		(wp != NULL)? (sint32 *)&wp->PARAM_H1 : NULL
	};
}
static void add_vax_info(NSMutableDictionary *md, VaccinationInfo *vp) {
	NSMutableArray *ma = NSMutableArray.new;
	for (NSInteger idx = 0; idx < MAX_N_VAXEN; idx ++) {
		if (vp[idx].priority == VcnPrNone) break;
		[ma addObject:@{keyVaxPerformRate:@(vp[idx].performRate),
			keyVaxRegularity:@(vp[idx].regularity), keyVaxPriority:@(vp[idx].priority)}];
	}
	if (ma.count > 0) md[keyVaccinationInfo] = ma;
}
static void add_final_vax(NSMutableDictionary *md, VaccineFinalRate *vp) {
	NSMutableArray *ma = NSMutableArray.new;
	for (NSInteger idx = 0; idx < MAX_N_AGE_SPANS; idx ++) {
		[ma addObjectsFromArray:@[@(vp[idx].upperAge), @(vp[idx].rate * 100.)]];
		if (vp[idx].upperAge > 150) break;
	}
	if (ma.count > 0) md[keyVaccineFinalRate] = ma;
}
NSMutableDictionary *param_dict(RuntimeParams *rp, WorldParams *wp) {
	NSMutableDictionary *md = NSMutableDictionary.new;
	ParamPointers pp = param_pointers(rp, wp);
	for (ParamInfo *p = paramInfo; p->key != nil; p ++) switch (p->type) {
		case ParamTypeFloat:
			if (pp.fp != NULL) md[p->key] = @(*(pp.fp ++)); break;
		case ParamTypeDist: if (pp.dp != NULL) {
			md[p->key] = @[@(pp.dp->min), @(pp.dp->max), @(pp.dp->mode)];
			pp.dp ++;
		} break;
		case ParamTypeInteger: if (pp.ip != NULL) md[p->key] = @(*(pp.ip ++)); break;
		case ParamTypeRate: if (pp.tp != NULL) md[p->key] = @(*(pp.tp ++)); break;
		case ParamTypeEnum: if (pp.ep != NULL) md[p->key] = @(*(pp.ep ++)); break;
		case ParamTypeWEnum: if (pp.hp != NULL) md[p->key] = @(*(pp.hp ++)); break;
		default: break;
	}
	if (rp != NULL) {
		add_vax_info(md, rp->vcnInfo);
		add_final_vax(md, rp->vcnFnlRt);
	}
	return md;
}
void set_params_from_dict(RuntimeParams *rp, WorldParams *wp, NSDictionary *dict) {
	ParamPointers pp = param_pointers(rp, wp);
	NSInteger initInfected = -1;
	for (NSString *key in dict.keyEnumerator) {
		NSNumber *idxNum = paramIndexFromKey[key];
		if (idxNum == nil) {
			if ([key isEqualToString:keyInitialInfected] && wp != NULL) // for upper compatibility.
				initInfected = [dict[key] integerValue];
			else if ([key isEqualToString:keyVaccinationInfo] &&
				[dict[key] isKindOfClass:NSArray.class]) {
				NSArray<NSDictionary *> *vaxList = dict[key];
				NSInteger nVaxen = vaxList.count;
				if (nVaxen > MAX_N_VAXEN) nVaxen = MAX_N_VAXEN;
				for (NSInteger idx = 0; idx < nVaxen; idx ++) {
					NSDictionary *elm = vaxList[idx];
					rp->vcnInfo[idx].performRate = [elm[keyVaxPerformRate] doubleValue];
					rp->vcnInfo[idx].regularity = [elm[keyVaxRegularity] doubleValue];
					rp->vcnInfo[idx].priority = [elm[keyVaxPriority] intValue];
				}
				for (NSInteger idx = nVaxen; idx < MAX_N_VAXEN; idx ++)
					rp->vcnInfo[idx].priority = VcnPrNone;
			} else if ([key isEqualToString:keyVaccineFinalRate] &&
				[dict[key] isKindOfClass:NSArray.class]) {
				NSArray<NSNumber *> *frList = dict[key];
				NSInteger nSpans = frList.count / 2;
				if (nSpans > MAX_N_AGE_SPANS) nSpans = MAX_N_AGE_SPANS;
				for (NSInteger idx = 0; idx < nSpans; idx ++) {
					rp->vcnFnlRt[idx].upperAge = frList[idx * 2].integerValue;
					rp->vcnFnlRt[idx].rate = frList[idx * 2 + 1].doubleValue / 100.;
				}
				if (rp->vcnFnlRt[nSpans - 1].upperAge < 150)
					rp->vcnFnlRt[nSpans - 1].upperAge = 200;
			}
			continue;
		}
		NSInteger index = idxNum.integerValue;
		if (index < IDX_D) {
			if (pp.fp != NULL) {
				if ([dict[key] isKindOfClass:NSNumber.class])
					pp.fp[index] = [dict[key] doubleValue];
				else if ([dict[key] isKindOfClass:NSArray.class]
					&& ((NSArray *)dict[key]).count > 2)
					pp.fp[index] = [((NSArray *)dict[key])[2] doubleValue];
			}
		} else if (index < IDX_I) { if (pp.dp != NULL) {
			NSArray<NSNumber *> *arr = dict[key];
			if ([arr isKindOfClass:NSArray.class] && arr.count >= 3)
				pp.dp[index - IDX_D] = (DistInfo){
					arr[0].doubleValue, arr[1].doubleValue, arr[2].doubleValue};
			else if ([arr isKindOfClass:NSNumber.class]) {	// for compatibility
				CGFloat value = ((NSNumber *)arr).doubleValue;
				pp.dp[index - IDX_D] = (DistInfo){value, value, value};
			}
		}} else if (index < IDX_R) {
			if (pp.ip != NULL) pp.ip[index - IDX_I] = [dict[key] integerValue];
		} else if (index < IDX_E) {
			if (pp.tp != NULL) pp.tp[index - IDX_R] = [dict[key] doubleValue];
		} else if (index < IDX_H) {
			if (pp.ep != NULL) pp.ep[index - IDX_E] = [dict[key] intValue];
		} else if (pp.hp != NULL) pp.hp[index - IDX_H] = [dict[key] intValue];
	}
	// for upper compatibility.
	if (initInfected >= 0) wp->infected = initInfected * 100. / wp->initPop;
}
NSMutableDictionary *param_diff_dict(
	RuntimeParams *rpNew, RuntimeParams *rpOrg, WorldParams *wpNew, WorldParams *wpOrg) {
	NSMutableDictionary *md = NSMutableDictionary.new;
	ParamPointers ppNew = param_pointers(rpNew, wpNew),
		ppOrg = param_pointers(rpOrg, wpOrg);
	for (ParamInfo *p = paramInfo; p->key != nil; p ++) switch (p->type) {
		case ParamTypeFloat: if (*ppNew.fp != *ppOrg.fp) md[p->key] = @(*ppNew.fp);
			ppNew.fp ++; ppOrg.fp ++; break;
		case ParamTypeDist: if (ppNew.dp->min != ppOrg.dp->min ||
			ppNew.dp->max != ppOrg.dp->max || ppNew.dp->mode != ppOrg.dp->mode)
			md[p->key] = @[@(ppNew.dp->min), @(ppNew.dp->max), @(ppNew.dp->mode)];
			ppNew.dp ++; ppOrg.dp ++; break;
		case ParamTypeInteger: if (wpNew != NULL && wpOrg != NULL) {
			if (*ppNew.ip != *ppOrg.ip) md[p->key] = @(*ppNew.ip);
			ppNew.ip ++; ppOrg.ip ++;
		} break;
		case ParamTypeRate: if (wpNew != NULL && wpOrg != NULL) {
		   if (*ppNew.tp != *ppOrg.tp) md[p->key] = @(*ppNew.tp);
		   ppNew.tp ++; ppOrg.tp ++;
		} break;
		case ParamTypeEnum: if (rpNew != NULL && rpOrg != NULL) {
			if (*ppNew.ep != *ppOrg.ep) md[p->key] = @(*ppNew.ep);
			ppNew.ep ++; ppOrg.ep ++;
		} break;
		case ParamTypeWEnum: if (wpNew != NULL && wpOrg != NULL) {
			if (*ppNew.hp != *ppOrg.hp) md[p->key] = @(*ppNew.hp);
			ppNew.hp ++; ppOrg.hp ++;
		} break;
		default: break;
	}
	BOOL isSame = YES;
	for (NSInteger idx = 0; idx < MAX_N_VAXEN; idx ++) {
		if (rpNew->vcnInfo[idx].priority == VcnPrNone
			&& rpOrg->vcnInfo[idx].priority == VcnPrNone) break;
		if (memcmp(&rpNew->vcnInfo[idx], &rpOrg->vcnInfo[idx], sizeof(VaccinationInfo)))
			{ isSame = NO; break; }
	}
	if (!isSame) add_vax_info(md, rpNew->vcnInfo);
	isSame = YES;
	for (NSInteger idx = 0; idx < MAX_N_AGE_SPANS; idx ++) {
		if (rpNew->vcnFnlRt[idx].upperAge != rpOrg->vcnFnlRt[idx].upperAge
		 || rpNew->vcnFnlRt[idx].rate != rpOrg->vcnFnlRt[idx].rate) { isSame = NO; break; }
		if (rpNew->vcnFnlRt[idx].upperAge > 150 && rpOrg->vcnFnlRt[idx].upperAge > 150) break;
	}
	if (!isSame) add_final_vax(md, rpNew->vcnFnlRt);
	return md;
}
#ifndef NOGUI
#define RGB3(r,g,b) ((r<<16)|(g<<8)|b)
NSInteger defaultStateRGB[N_COLORS] = {
	RGB3(39,85,154),	// susceptible
	RGB3(246,214,0),	// infected - asymptomatic
	RGB3(250,48,46),	// infected - symptomatic
	RGB3(32,120,100),	// recovered
	RGB3(182,182,182),
//	RGB3(16,160,50),	// vaccinated
	RGB3(255,255,255),	// vaccinated
	RGB3(0,0,0),		// background of field
	RGB3(64,0,0),		// hospital
	RGB3(51,51,51),		// cemetery
	RGB3(255,255,255),	// text
	RGB3(64,64,0)		// gatherings
}, stateRGB[N_COLORS];
NSColor *stateColors[N_COLORS] = {nil}, *warpColors[NHealthTypes];
NSString *colKeys[] = {
	@"colorSusceptible", @"colorAsymptomatic", @"colorSymptomatic",
	@"colorRecovered", @"colorDied", @"colorVaccinated",
	@"colorBackgournd", @"colorHospital", @"colorCemetery", @"colorText",
	@"colorGathering"
};
CGFloat warpOpacity = DEFAULT_WARP_OPACITY;
CGFloat panelsAlpha = DEFAULT_PANELS_ALPHA;
BOOL makePanelChildWindow = DEFAULT_CHILD_WIN;
NSJSONWritingOptions JSONFormat = DEFAULT_JSON_FORM;
NSString *keyWarpOpacity = @"warpOpacity", *keyPanelsAlpha = @"panelsAlpha",
	*keyChildWindow = @"makePanelChildWindow", *keyJSONFormat = @"JSONFormat";
BOOL bgIsDark = YES;
void setup_colors(void) {
	NSColorSpace *colSpc = NSColorSpace.genericRGBColorSpace;
	for (NSInteger i = 0; i < N_COLORS; i ++) {
		CGFloat cols[4];
		for (NSInteger j = 0; j < 3; j ++)
			cols[j] = ((stateRGB[i] >> (8 * (2 - j))) & 0xff) / 255.;
		cols[3] = 1.;
		stateColors[i] = [NSColor colorWithColorSpace:colSpc components:cols count:4];
		if (i < NHealthTypes) {
			cols[3] = warpOpacity;
			warpColors[i] = [NSColor colorWithColorSpace:colSpc components:cols count:4];
		}
		if (i == ColBackground) bgIsDark = (cols[0] + cols[1] + cols[2]) < 1.5;
	}
}
#endif

#ifdef NOGUI
void
#else
static NSString *archtectureName = nil;
static NSInteger
#endif
	applicationSetups(void) {
	int mib[2] = { CTL_HW, HW_MACHINE };
	size_t dataSize = 128;
	char archName[128];
	memset(archName, 0, 128);
	if (sysctl(mib, 2, archName, &dataSize, NULL, 0) < 0) {
		fprintf(stderr, "sysctl err = %d\n", errno);
		[NSApp terminate:nil];
	}
	isARM = strcmp(archName, "x86_64") != 0;
	nCores = NSProcessInfo.processInfo.processorCount;
	if (sizeof(sint32) != sizeof(TracingOperation)) {
		fprintf(stderr, "The size of 'enum' is not %ld but %ld.",
			sizeof(sint32), sizeof(TracingOperation));
		exit(1);
	}
	NSInteger nF = 0, nD = 0, nI = 0, nR = 0, nE = 0, nH = 0;
	for (ParamInfo *p = paramInfo; p->key != nil; p ++) switch (p->type) {
		case ParamTypeFloat:
			(&defaultRuntimeParams.PARAM_F1)[nF ++] = p->v.f.defaultValue; break;
		case ParamTypeDist: (&defaultRuntimeParams.PARAM_D1)[nD ++] =
			(DistInfo){p->v.d.defMin, p->v.d.defMax, p->v.d.defMode}; break;
		case ParamTypeInteger: (&defaultWorldParams.PARAM_I1)[nI ++] = p->v.i.defaultValue;
			break;
		case ParamTypeRate: (&defaultWorldParams.PARAM_R1)[nR ++] = p->v.f.defaultValue;
			break;
		case ParamTypeEnum: (&defaultRuntimeParams.PARAM_E1)[nE ++] = p->v.e.defaultValue;
			break;
		case ParamTypeWEnum: (&defaultWorldParams.PARAM_H1)[nH ++] = p->v.e.defaultValue;
		default: break;
	}
	defaultRuntimeParams.vcnInfo[0].performRate = 0.;
	defaultRuntimeParams.vcnInfo[0].regularity = 100.;
	defaultRuntimeParams.vcnInfo[0].priority = VcnPrRandom;
	defaultRuntimeParams.vcnInfo[1].priority = VcnPrNone;
	NSInteger upper = 0;
	for (NSInteger i = 0; i < MAX_N_AGE_SPANS; i ++) {
		if (upper < 0) defaultVaxFnlRt[i] = (VaccineFinalRate){-1, 0.};
		else if (defaultVaxFnlRt[i].upperAge > 150) upper = -1;
	}
	memcpy(defaultRuntimeParams.vcnFnlRt, defaultVaxFnlRt, sizeof(defaultVaxFnlRt));
	
	NSInteger nn = nF + nD + nI + nR + nE + nH;
	NSString *keys[nn], *names[nF];
	NSNumber *indexes[nn];

#ifdef SDEF_PROPS
	for (NSInteger i = 0; i < nn; i ++) {
		ParamInfo *p = paramInfo + i;
		char keyOrg[64], key[64];
		NSUInteger len;
		[p->key getBytes:keyOrg maxLength:64 usedLength:&len encoding:NSUTF8StringEncoding
		 options:0 range:(NSRange){0, p->key.length} remainingRange:NULL];
		NSInteger j = 0;
		for (NSInteger i = 0; i < len && j < 64; i ++, j ++) {
			if (keyOrg[i] >= 'A' && keyOrg[i] <= 'Z')
				{ key[j ++] = ' '; key[j] = keyOrg[i] + 'a' - 'A'; }
			else key[j] = keyOrg[i];
		}
		key[j] = '\0';
		switch (p->type) {
		case ParamTypeFloat:
		printf("<property name=\"%s\" code=\"rt%02ld\" type=\"real\"/>\n", key, i); break;
		case ParamTypeDist:
		printf("<property name=\"%s\" code=\"rt%02ld\"><type type=\"real\" list=\"yes\"/></property>\n",
			key, i); break;
		case ParamTypeEnum:
		printf("<property name=\"%s\" code=\"rt%02ld\" type=\"integer\"/>\n", key, i); break;
		default: break;
		}

		switch (p->type) {
		case ParamTypeInteger: case ParamTypeWEnum:
		printf("<property name=\"%s\" code=\"wp%02ld\" type=\"integer\"/>\n", key, i); break;
		case ParamTypeRate:
		printf("<property name=\"%s\" code=\"wp%02ld\" type=\"real\"/>\n", key, i); break;
		default: break;
		}
	}
	[NSApp terminate:nil];
#endif
	for (NSInteger i = 0; i < nn; i ++) {
		ParamInfo *p = paramInfo + i;
		keys[i] = p->key;
		switch (p->type) {
			case ParamTypeFloat:
			indexes[i] = @(i);
			names[i] = NSLocalizedString(p->key, nil);
			break;
			case ParamTypeDist: indexes[i] = @(i - nF + IDX_D); break;
			case ParamTypeInteger: indexes[i] = @(i - nF - nD + IDX_I); break;
			case ParamTypeRate: indexes[i] = @(i - nF - nD - nI + IDX_R); break;
			case ParamTypeEnum: indexes[i] = @(i - nF - nD - nI - nR + IDX_E); break;
			case ParamTypeWEnum: indexes[i] = @(i - nF - nD - nI - nR - nE + IDX_H);
			default: break;
		}
	}
	paramKeys = [NSArray arrayWithObjects:keys count:nn];
	paramKeyFromName = [NSDictionary dictionaryWithObjects:keys forKeys:names count:nF];
	paramIndexFromKey = [NSDictionary dictionaryWithObjects:indexes forKeys:keys count:nn];
	memcpy(&userDefaultRuntimeParams, &defaultRuntimeParams, sizeof(RuntimeParams));
	memcpy(&userDefaultWorldParams, &defaultWorldParams, sizeof(WorldParams));
#ifndef NOGUI
	memcpy(stateRGB, defaultStateRGB, sizeof(stateRGB));
	archtectureName = [NSString stringWithUTF8String:archName];
	return nF + nI + nR;
#endif
}

#ifndef NOGUI
@implementation AppDelegate
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
	NSInteger nFmt = applicationSetups(), k = 0;
	NSNumberFormatter *formatters[nFmt], *fmt;
	for (ParamInfo *p = paramInfo; p->type != ParamTypeNone; p ++) switch (p->type) {
		case ParamTypeFloat: case ParamTypeRate:
		fmt = NSNumberFormatter.new;
		fmt.allowsFloats = YES;
		fmt.minimum = @(p->v.f.minValue);
		fmt.maximum = @(p->v.f.maxValue);
		fmt.minimumFractionDigits = fmt.maximumFractionDigits =
			(p->v.f.maxValue >= 100.)? 2 : 3;
		fmt.minimumIntegerDigits = 1;
		formatters[k ++] = fmt;
		break;
		case ParamTypeInteger:
		fmt = NSNumberFormatter.new;
		fmt.allowsFloats = NO;
		fmt.minimum = @(p->v.i.minValue);
		fmt.maximum = @(p->v.i.maxValue);
		fmt.usesGroupingSeparator = YES;
		fmt.groupingSize = 3;
		formatters[k ++] = fmt;
		default: break;
	}
	paramFormatters = [NSArray arrayWithObjects:formatters count:nFmt];
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
#ifdef DEBUG
	[ud setBool:YES forKey:@"NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints"];
#endif

	NSNumber *num;
	NSObject *obj;
	NSArray<NSNumber *> *arr;
	if ((num = [ud objectForKey:keyAnimeSteps])) defaultAnimeSteps = num.integerValue;
	for (NSInteger i = 0; i < N_COLORS; i ++)
		if ((num = [ud objectForKey:colKeys[i]])) stateRGB[i] = num.integerValue;
	NSInteger kF = 0, kD = 0, kI = 0, kR = 0, kE = 0, kH = 0;
	for (ParamInfo *p = paramInfo; p->type != ParamTypeNone; p ++)
	if ((obj = [ud objectForKey:p->key])) switch (p->type) {
		case ParamTypeFloat: {
			CGFloat *vp = &(&userDefaultRuntimeParams.PARAM_F1)[kF ++];
			if ([obj isKindOfClass:NSNumber.class]) *vp = ((NSNumber *)obj).doubleValue;
			else if ([obj isKindOfClass:NSArray.class] && ((NSArray *)obj).count > 2)
				*vp = [((NSArray *)obj)[2] doubleValue];
		} break;
		case ParamTypeDist: if ([obj isKindOfClass:NSArray.class] && ((NSArray *)obj).count > 2) {
			arr = (NSArray *)obj;
			(&userDefaultRuntimeParams.PARAM_D1)[kD ++] = (DistInfo){
				arr[0].doubleValue, arr[1].doubleValue, arr[2].doubleValue};
		} break;
		case ParamTypeInteger: if ([obj isKindOfClass:NSNumber.class])
			(&userDefaultWorldParams.PARAM_I1)[kI ++] = ((NSNumber *)obj).integerValue;
		break;
		case ParamTypeRate: if ([obj isKindOfClass:NSNumber.class])
			(&userDefaultWorldParams.PARAM_R1)[kR ++] = ((NSNumber *)obj).doubleValue;
		break;
		case ParamTypeEnum: if ([obj isKindOfClass:NSNumber.class])
			(&userDefaultRuntimeParams.PARAM_E1)[kE ++] = ((NSNumber *)obj).intValue;
		break;
		case ParamTypeWEnum: if ([obj isKindOfClass:NSNumber.class])
			(&userDefaultWorldParams.PARAM_H1)[kH ++] = ((NSNumber *)obj).intValue;
		default: break;
	}
	if ((num = [ud objectForKey:keyWarpOpacity])) warpOpacity = num.doubleValue;
	if ((num = [ud objectForKey:keyPanelsAlpha])) panelsAlpha = num.doubleValue;
	if ((num = [ud objectForKey:keyChildWindow])) makePanelChildWindow = num.boolValue;
	if ((num = [ud objectForKey:keyJSONFormat])) JSONFormat = num.integerValue;
	setup_colors();
	NSBezierPath.defaultLineJoinStyle = NSLineJoinStyleBevel;
}
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
	NSArray<Document *> *docs = NSDocumentController.sharedDocumentController.documents;
	if (docs.count == 0) return;
	Document *doc = docs[0];
	BOOL scen = YES, params = YES;
	for (NSURL *url in urls) {
		NSString *ext = url.pathExtension;
		if (scen && [ext isEqualToString:@"sEpS"])
			{ [doc openScenarioFromURL:url]; scen = NO; }
		else if (params && [ext isEqualToString:@"sEpP"])
			{ [doc openParamsFromURL:url]; params = NO; }
	}
}
- (void)applicationWillTerminate:(NSNotification *)notification {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	if (defaultAnimeSteps == 1) [ud removeObjectForKey:keyAnimeSteps];
	else [ud setInteger:defaultAnimeSteps forKey:keyAnimeSteps];
	for (NSInteger i = 0; i < N_COLORS; i ++) {
		if (stateRGB[i] == defaultStateRGB[i]) [ud removeObjectForKey:colKeys[i]];
		else [ud setInteger:stateRGB[i] forKey:colKeys[i]];
	}
	if (warpOpacity == DEFAULT_WARP_OPACITY)
		[ud removeObjectForKey:keyWarpOpacity];
	else [ud setDouble:warpOpacity forKey:keyWarpOpacity];
	if (panelsAlpha == DEFAULT_WARP_OPACITY)
		[ud removeObjectForKey:keyPanelsAlpha];
	else [ud setDouble:panelsAlpha forKey:keyPanelsAlpha];
	if (makePanelChildWindow == DEFAULT_CHILD_WIN)
		[ud removeObjectForKey:keyChildWindow];
	else [ud setBool:makePanelChildWindow forKey:keyChildWindow];
#ifdef DEBUG
	[ud removeObjectForKey:@"NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints"];
#endif
}
- (IBAction)orderFrontMyAboutPanel:(id)sender {
	NSURL *url = [NSBundle.mainBundle URLForResource:@"Credits" withExtension:@"rtf"];
	NSMutableAttributedString *credit = [NSMutableAttributedString.alloc
		initWithRTF:[NSData dataWithContentsOfURL:url] documentAttributes:nil];
	NSMutableParagraphStyle *style = NSMutableParagraphStyle.new;
	style.alignment = NSTextAlignmentCenter;
	[credit appendAttributedString:[NSAttributedString.alloc initWithString:
		[NSString stringWithFormat:@"\nNow running on %@ architecture.", archtectureName]
		attributes:@{NSFontAttributeName:[NSFont messageFontOfSize:10],
			NSParagraphStyleAttributeName:style}]];
	[NSApp orderFrontStandardAboutPanelWithOptions:
		@{NSAboutPanelOptionCredits:credit}];
}
- (IBAction)openPreferencePanel:(id)sender {
	static Preferences *pref = nil;
	if (pref == nil) pref = Preferences.new;
	[pref showWindow:sender];
}
@end
#endif
