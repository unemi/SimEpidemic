//
//  AppDelegate.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "AppDelegate.h"
#import "Document.h"
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
void error_msg(NSObject *obj, NSWindow *window, BOOL critical) {
	NSString *message = [obj isKindOfClass:NSString.class]? (NSString *)obj :
		[obj isKindOfClass:NSError.class]? [NSString stringWithFormat:
			@"%@ (%ld)", ((NSError *)obj).localizedDescription, ((NSError *)obj).code] :
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
#ifndef NOGUI
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
static ParamInfo paramInfo[] = {
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
	{ ParamTypeFloat, @"recoveryBias", {.f = { 0., -100., 100.}}},
	{ ParamTypeFloat, @"immunityBias", {.f = { 0., -100., 100.}}},

	{ ParamTypeFloat, @"contagionDelay", {.f = { .5, 0., 10.}}},
	{ ParamTypeFloat, @"contagionPeak", {.f = { 3., 1., 10.}}},
	{ ParamTypeFloat, @"infectionProberbility", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"infectionDistance", {.f = { 3., .1, 10.}}},

	{ ParamTypeFloat, @"distancingStrength", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"distancingObedience", {.f = { 20., 0., 100.}}},
	{ ParamTypeFloat, @"gatheringFrequency", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"contactTracing", {.f = { 20., 0., 100.}}},
	{ ParamTypeFloat, @"testDelay", {.f = { 1., 0., 10.}}},
	{ ParamTypeFloat, @"testProcess", {.f = { 1., 0., 10.}}},
	{ ParamTypeFloat, @"testInterval", {.f = { 2., 0., 10.}}},
	{ ParamTypeFloat, @"testSensitivity", {.f = { 70., 0., 100.}}},
	{ ParamTypeFloat, @"testSpecificity", {.f = { 99.8, 0., 100.}}},
	{ ParamTypeFloat, @"subjectAsymptomatic", {.f = { 1., 0., 100.}}},
	{ ParamTypeFloat, @"subjectSymptomatic", {.f = { 99., 0., 100.}}},

	{ ParamTypeDist, @"mobilityDistance", {.d = { 10., 30., 80.}}},
	{ ParamTypeDist, @"incubation", {.d = { 1., 5., 14.}}},
	{ ParamTypeDist, @"fatality", {.d = { 4., 16., 20.}}},
	{ ParamTypeDist, @"recovery", {.d = { 4., 10., 40.}}},
	{ ParamTypeDist, @"immunity", {.d = { 30., 180., 360.}}},
	{ ParamTypeDist, @"gatheringSize", {.d = { 5., 10., 20.}}},
	{ ParamTypeDist, @"gatheringDuration", {.d = { 6., 12., 24.}}},
	{ ParamTypeDist, @"gatheringStrength", {.d = { 50., 80., 100.}}},
	{ ParamTypeDist, @"mobilityFrequency", {.d = { 40., 70., 100.}}},
	{ ParamTypeDist, @"gatheringParticipation", {.d = { 40., 70., 100.}}},
	
	{ ParamTypeInteger, @"populationSize", {.i = { 10000, 100, 999900}}},
	{ ParamTypeInteger, @"worldSize", {.i = { 360, 10, 999999}}},
	{ ParamTypeInteger, @"mesh", {.i = { 18, 1, 999}}},
	{ ParamTypeInteger, @"initialInfected", {.i = { 20, 1, 999}}},
	{ ParamTypeInteger, @"stepsPerDay", {.i = { 16, 1, 999}}},
	{ ParamTypeNone, nil }
};
NSInteger defaultAnimeSteps = 1;
RuntimeParams defaultRuntimeParams, userDefaultRuntimeParams;
WorldParams defaultWorldParams, userDefaultWorldParams;
NSArray<NSString *> *paramKeys;
NSArray<NSNumberFormatter *> *paramFormatters;
NSDictionary<NSString *, NSString *> *paramKeyFromName;
NSDictionary<NSString *, NSNumber *> *paramIndexFromKey;
NSMutableDictionary *param_dict(RuntimeParams *rp, WorldParams *wp) {
	NSMutableDictionary *md = NSMutableDictionary.new;
	CGFloat *fp = (rp != NULL)? &rp->PARAM_F1 : NULL;
	DistInfo *dp = (rp != NULL)? &rp->PARAM_D1 : NULL;
	NSInteger *ip = (wp != NULL)? &wp->PARAM_I1 : NULL;
	for (ParamInfo *p = paramInfo; p->key != nil; p ++) switch (p->type) {
		case ParamTypeFloat:
			if (fp != NULL) md[p->key] = @(*(fp ++)); break;
		case ParamTypeDist: if (dp != NULL) {
			md[p->key] = @[@(dp->min), @(dp->max), @(dp->mode)];
			dp ++;
		} break;
		case ParamTypeInteger: if (ip != NULL) md[p->key] = @(*(ip ++));
		default: break;
	}
	return md;
}
void set_params_from_dict(RuntimeParams *rp, WorldParams *wp, NSDictionary *dict) {
	CGFloat *fp = (rp != NULL)? &rp->PARAM_F1 : NULL;
	DistInfo *dp = (rp != NULL)? &rp->PARAM_D1 : NULL;
	NSInteger *ip = (wp != NULL)? &wp->PARAM_I1 : NULL;
	for (NSString *key in dict.keyEnumerator) {
		NSNumber *idxNum = paramIndexFromKey[key];
		if (idxNum == nil) continue;
		NSInteger index = idxNum.integerValue;
		if (index < IDX_D) {
			if (fp != NULL) {
				if ([dict[key] isKindOfClass:NSNumber.class])
					fp[index] = [dict[key] doubleValue];
				else if ([dict[key] isKindOfClass:NSArray.class]
					&& ((NSArray *)dict[key]).count > 2)
					fp[index] = [((NSArray *)dict[key])[2] doubleValue];
			}
		} else if (index < IDX_I) { if (dp != NULL) {
			NSArray<NSNumber *> *arr = dict[key];
			if ([arr isKindOfClass:NSArray.class] && arr.count >= 3)
				dp[index - IDX_D] = (DistInfo){
					arr[0].doubleValue, arr[1].doubleValue, arr[2].doubleValue};
			else if ([arr isKindOfClass:NSNumber.class]) {	// for compatibility
				CGFloat value = ((NSNumber *)arr).doubleValue;
				dp[index - IDX_D] = (DistInfo){value, value, value};
			}
		}} else if (ip != NULL) ip[index - IDX_I] = [dict[key] integerValue];
	}
}
#ifndef NOGUI
NSMutableDictionary *param_diff_dict(RuntimeParams *rpNew, RuntimeParams *rpOrg) {
	NSMutableDictionary *md = NSMutableDictionary.new;
	CGFloat *fpNew = &rpNew->PARAM_F1, *fpOrg = &rpOrg->PARAM_F1;
	DistInfo *dpNew = &rpNew->PARAM_D1, *dpOrg = &rpOrg->PARAM_D1;
	for (ParamInfo *p = paramInfo; p->key != nil; p ++) switch (p->type) {
		case ParamTypeFloat: if (*fpNew != *fpOrg) md[p->key] = @(*fpNew);
			fpNew ++; fpOrg ++; break;
		case ParamTypeDist: if (dpNew->min != dpOrg->min ||
			dpNew->max != dpOrg->max || dpNew->mode != dpOrg->mode)
			md[p->key] = @[@(dpNew->min), @(dpNew->max), @(dpNew->mode)];
			dpNew ++; dpOrg ++; break;
		default: break;
	}
	return md;
}

#define RGB3(r,g,b) ((r<<16)|(g<<8)|b)
NSInteger defaultStateRGB[N_COLORS] = {
	RGB3(39,85,154), RGB3(246,214,0), RGB3(250,48,46), RGB3(32,120,100), RGB3(182,182,182),
	RGB3(0,0,0), RGB3(64,0,0), RGB3(51,51,51), RGB3(255,255,255), RGB3(64,64,0)
}, stateRGB[N_COLORS];
NSColor *stateColors[N_COLORS] = {nil}, *warpColors[NHealthTypes];
NSString *colKeys[] = {
	@"colorSusceptible", @"colorAsymptomatic", @"colorSymptomatic",
	@"colorRecovered", @"colorDied",
	@"colorBackgournd", @"colorHospital", @"colorCemetery", @"colorText",
	@"colorGathering"
};
CGFloat warpOpacity = DEFAULT_WARP_OPACITY;
CGFloat panelsAlpha = DEFAULT_PANELS_ALPHA;
BOOL makePanelChildWindow = DEFAULT_CHILD_WIN;
NSJSONWritingOptions JSONFormat = DEFAULT_JSON_FORM;
NSString *keyWarpOpacity = @"warpOpacity", *keyPanelsAlpha = @"panelsAlpha",
	*keyChildWindow = @"makePanelChildWindow", *keyJSONFormat = @"JSONFormat";
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
	}
}
#endif

#ifdef NOGUI
void
#else
static NSString *archtectureName = nil;
struct SetupInfo { NSInteger nF, nD, nI, nn; };
static struct SetupInfo
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
	NSInteger nF = 0, nD = 0, nI = 0;
	for (ParamInfo *p = paramInfo; p->key != nil; p ++) switch (p->type) {
		case ParamTypeFloat:
			(&defaultRuntimeParams.PARAM_F1)[nF ++] = p->v.f.defaultValue; break;
		case ParamTypeDist: (&defaultRuntimeParams.PARAM_D1)[nD ++] =
			(DistInfo){p->v.d.defMin, p->v.d.defMax, p->v.d.defMode}; break;
		case ParamTypeInteger: (&defaultWorldParams.PARAM_I1)[nI ++] = p->v.i.defaultValue; break;
		default: break;
	}
	NSInteger nn = nF + nD + nI;
	NSString *keys[nn], *names[nF];
	NSNumber *indexes[nn];
	for (NSInteger i = 0; i < nn; i ++) {
		ParamInfo *p = paramInfo + i;
		keys[i] = p->key;
		switch (p->type) {
			case ParamTypeFloat:
			indexes[i] = @(i);
			names[i] = NSLocalizedString(p->key, nil);
			break;
			case ParamTypeDist: indexes[i] = @(i - nF + IDX_D); break;
			case ParamTypeInteger: indexes[i] = @(i - nF - nD + IDX_I);
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
	return (struct SetupInfo){nF, nD, nI, nn};
#endif
}

#ifndef NOGUI
@implementation AppDelegate
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
	struct SetupInfo info = applicationSetups();
	NSNumberFormatter *formatters[info.nF + info.nI], *fmt;
	for (NSInteger i = 0; i < info.nn; i ++) {
		ParamInfo *p = paramInfo + i;
		switch (p->type) {
			case ParamTypeFloat:
			fmt = NSNumberFormatter.new;
			fmt.allowsFloats = YES;
			fmt.minimum = @(p->v.f.minValue);
			fmt.maximum = @(p->v.f.maxValue);
			fmt.minimumFractionDigits = fmt.maximumFractionDigits =
			fmt.minimumIntegerDigits = 1;
			formatters[i] = fmt;
			break;
			case ParamTypeInteger:
			fmt = NSNumberFormatter.new;
			fmt.allowsFloats = NO;
			fmt.minimum = @(p->v.i.minValue);
			fmt.maximum = @(p->v.i.maxValue);
			fmt.usesGroupingSeparator = YES;
			fmt.groupingSize = 3;
			formatters[i - info.nD] = fmt;
			default: break;
		}
	}
	paramFormatters = [NSArray arrayWithObjects:formatters count:info.nF + info.nI];
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;

	NSNumber *num;
	NSArray<NSNumber *> *arr;
	if ((num = [ud objectForKey:keyAnimeSteps])) defaultAnimeSteps = num.integerValue;
	for (NSInteger i = 0; i < N_COLORS; i ++)
		if ((num = [ud objectForKey:colKeys[i]])) stateRGB[i] = num.integerValue;
	for (NSInteger i = 0; i < info.nF; i ++)
		if ((num = [ud objectForKey:paramInfo[i].key])) {
			CGFloat *vp = &(&userDefaultRuntimeParams.PARAM_F1)[i];
			if ([num isKindOfClass:NSNumber.class]) *vp = num.doubleValue;
			else if ([num isKindOfClass:NSArray.class] && ((NSArray *)num).count > 2)
				*vp = [((NSArray *)num)[2] doubleValue];
		}
	for (NSInteger i = 0; i < info.nD; i ++)
		if ((arr = [ud objectForKey:paramInfo[i + info.nF].key]))
			(&userDefaultRuntimeParams.PARAM_D1)[i] = (DistInfo){
				arr[0].doubleValue, arr[1].doubleValue, arr[2].doubleValue};
	for (NSInteger i = 0; i < info.nI; i ++)
		if ((num = [ud objectForKey:paramInfo[i + info.nF + info.nD].key]))
			(&userDefaultWorldParams.PARAM_I1)[i] = num.integerValue;
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
