//
//  AppDelegate.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "AppDelegate.h"
#import "Document.h"
#import <sys/time.h>

NSInteger nCores = 1;
unsigned long current_time_us(void) {
	static long startTime = -1;
	struct timeval tv;
	gettimeofday(&tv, NULL);
	if (startTime < 0) startTime = tv.tv_sec;
	return (tv.tv_sec - startTime) * 1000000L + tv.tv_usec;
}
void error_msg(NSObject *obj, NSWindow *window, BOOL critical) {
	NSAlert *alt = NSAlert.new;
	alt.alertStyle = critical? NSAlertStyleCritical : NSAlertStyleWarning;
	alt.messageText =
		[obj isKindOfClass:NSString.class]? (NSString *)obj :
		[obj isKindOfClass:NSError.class]? [NSString stringWithFormat:
			@"%@ (%ld)", ((NSError *)obj).localizedDescription, ((NSError *)obj).code] :
		[obj isKindOfClass:NSException.class]? ((NSException *)obj).reason :
		[NSString stringWithFormat:@"%@ (%@)", obj.description, obj.className];
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
	if (data == nil) { error_msg(error, window, NO); return nil; }
	NSObject *object = [NSPropertyListSerialization propertyListWithData:data
		options:NSPropertyListImmutable format:NULL error:&error];
	if (object == nil) { error_msg(error, window, NO); return nil; }
	if (class != NULL && ![object isKindOfClass:class])
		{ error_msg(@"Property is invalid class.", window, NO); return nil; }
	return object;
}
void load_property_data(NSString *fileType, NSWindow *window,
	Class class, void (^block)(NSObject *)) {
	NSOpenPanel *op = NSOpenPanel.openPanel;
	op.allowedFileTypes = @[fileType];
	[op beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		NSObject *object = get_propertyList_from_url(op.URL, class, window);
		if (object != nil) block(object);
	}];
}
void save_property_data(NSString *fileType, NSWindow *window, NSObject *object) {
	NSSavePanel *sp = NSSavePanel.savePanel;
	sp.allowedFileTypes = @[fileType];
	[sp beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		NSError *error;
		NSData *data = [NSPropertyListSerialization dataWithPropertyList:object
			format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
		if (data == nil) { error_msg(error, window, NO); return; }
		if (![data writeToURL:sp.URL options:0 error:&error])
			error_msg(error, window, NO);
	}];
}
NSString *keyAnimeSteps = @"animeSteps";
static ParamInfo paramInfo[] = {
	{ ParamTypeFloat, @"infec", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"infecDst", {.f = { 4., 1., 20.}}},
	{ ParamTypeFloat, @"recovMean", {.f = { 10., 0., 20.}}},
	{ ParamTypeFloat, @"recovSTD", {.f = { 4., 0., 20.}}},
	{ ParamTypeFloat, @"incubPMin", {.f = { 1., 0., 20.}}},
	{ ParamTypeFloat, @"incubPMax", {.f = { 15., 0., 50.}}},
	{ ParamTypeFloat, @"incubPBias", {.f = { 20., -99., 100.}}},
	{ ParamTypeFloat, @"diseaRt", {.f = { 25., 0., 100.}}},
	{ ParamTypeFloat, @"imunMean", {.f = { 180., 0., 360.}}},
	{ ParamTypeFloat, @"imunSTD", {.f = { 10., 0., 100.}}},
	{ ParamTypeFloat, @"qnsRt", {.f = { 10., 0., 100.}}},
	{ ParamTypeFloat, @"qnsDl", {.f = { 10., 0., 20.}}},
	{ ParamTypeFloat, @"qdsRt", {.f = { 80., 0., 100.}}},
	{ ParamTypeFloat, @"qdsDl", {.f = { 5., 0., 20.}}},
	{ ParamTypeFloat, @"dstST", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"dstOB", {.f = { 20., 0., 100.}}},
	{ ParamTypeFloat, @"mobFr", {.f = { 50., 0., 100.}}},
	{ ParamTypeFloat, @"mobDs", {.f = { 50., 0., 100.}}},
	{ ParamTypeInteger, @"initPop", {.i = { 10000, 100, 999900}}},
	{ ParamTypeInteger, @"worldSize", {.i = { 360, 10, 999999}}},
	{ ParamTypeInteger, @"mesh", {.i = { 18, 1, 999}}},
	{ ParamTypeInteger, @"stepsPerDay", {.i = { 4, 1, 999}}},
	{ ParamTypeInteger, @"nInitInfec", {.i = { 4, 1, 999}}},
	{ ParamTypeNone, nil }
};
NSInteger defaultAnimeSteps = 1;
Params defaultParams, userDefaultParams;
NSArray<NSString *> *paramKeys, *paramNames;
NSArray<NSNumberFormatter *> *paramFormatters;
NSDictionary<NSString *, NSString *> *paramKeyFromName;
NSDictionary<NSString *, NSNumber *> *paramIndexFromKey;
NSDictionary *param_dict(Params *pp) {
	NSMutableDictionary *md = NSMutableDictionary.new;
	CGFloat *fp = &pp->infec;
	NSInteger *ip = &pp->initPop;
	for (ParamInfo *p = paramInfo; p->key != nil; p ++) {
		if (p->type == ParamTypeFloat) md[p->key] = @(*(fp ++));
		else md[p->key] = @(*(ip ++));
	}
	return [NSDictionary dictionaryWithDictionary:md];
}
void set_params_from_dict(Params *pp, NSDictionary *dict) {
	for (NSString *key in dict.keyEnumerator) {
		NSNumber *idxNum = paramIndexFromKey[key];
		if (idxNum == nil) continue;
		NSInteger index = idxNum.integerValue;
		if (index < 1000) (&pp->infec)[index] = [dict[key] doubleValue];
		else (&pp->initPop)[index - 1000] = [dict[key] integerValue];
	}
}
#define RGB3(r,g,b) ((r<<16)|(g<<8)|b)
NSInteger defaultStateRGB[N_COLORS] = {
	RGB3(39,85,154), RGB3(246,214,0), RGB3(250,48,46), RGB3(32,120,100), RGB3(182,182,182),
	RGB3(0,0,0), RGB3(64,0,0), RGB3(51,51,51), RGB3(255,255,255)
}, stateRGB[N_COLORS];
NSColor *stateColors[N_COLORS] = {nil}, *warpColors[NHealthTypes];
__weak NSColorWell *colWells[N_COLORS];
static NSString *colKeys[] = {
	@"colorSusceptible", @"colorAsymptomatic", @"colorSymptomatic",
	@"colorRecovered", @"colorDied",
	@"colorBackgournd", @"colorHospital", @"colorCemetery", @"colorText"
};
#define DEFAULT_WARP_OPACITY .5
CGFloat warpOpacity = DEFAULT_WARP_OPACITY;
static NSString *keyWarpOpacity = @"warpOpacity";
static void setup_colors(void) {
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
@implementation AppDelegate
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
	nCores = NSProcessInfo.processInfo.processorCount;
	NSInteger nF = 0, nI = 0;
	for (ParamInfo *p = paramInfo; p->key != nil; p ++) {
		if (p->type == ParamTypeFloat) (&defaultParams.infec)[nF ++] = p->v.f.defaultValue;
		else (&defaultParams.initPop)[nI ++] = p->v.i.defaultValue;
	}
	NSInteger nn = nF + nI;
	NSString *keys[nn], *names[nn];
	NSNumber *indexes[nn];
	NSNumberFormatter *formatters[nn];
	for (NSInteger i = 0; i < nn; i ++) {
		names[i] = NSLocalizedString((keys[i] = paramInfo[i].key), nil);
		indexes[i] = @((paramInfo[i].type == ParamTypeFloat)? i : i - nF + 1000);
		NSNumberFormatter *fmt = NSNumberFormatter.new;
		if (paramInfo[i].type == ParamTypeFloat) {
			fmt.allowsFloats = YES;
			fmt.minimum = @(paramInfo[i].v.f.minValue);
			fmt.maximum = @(paramInfo[i].v.f.maxValue);
			fmt.minimumFractionDigits = fmt.maximumFractionDigits =
			fmt.minimumIntegerDigits = 1;
		} else {
			fmt.allowsFloats = NO;
			fmt.minimum = @(paramInfo[i].v.i.minValue);
			fmt.maximum = @(paramInfo[i].v.i.maxValue);
		}
		formatters[i] = fmt;
	}
	paramKeys = [NSArray arrayWithObjects:keys count:nn];
	paramNames = [NSArray arrayWithObjects:names count:nn];
	paramFormatters = [NSArray arrayWithObjects:formatters count:nn];
	paramKeyFromName = [NSDictionary dictionaryWithObjects:keys forKeys:names count:nn];
	paramIndexFromKey = [NSDictionary dictionaryWithObjects:indexes forKeys:keys count:nn];
	memcpy(&userDefaultParams, &defaultParams, sizeof(Params));
	memcpy(stateRGB, defaultStateRGB, sizeof(stateRGB));
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSNumber *num;
	if ((num = [ud objectForKey:keyAnimeSteps])) defaultAnimeSteps = num.integerValue;
	for (NSInteger i = 0; i < N_COLORS; i ++)
		if ((num = [ud objectForKey:colKeys[i]])) stateRGB[i] = num.integerValue;
	for (NSInteger i = 0; i < nF; i ++)
		if ((num = [ud objectForKey:paramInfo[i].key]))
			(&userDefaultParams.infec)[i] = num.doubleValue;
	for (NSInteger i = 0; i < nI; i ++)
		if ((num = [ud objectForKey:paramInfo[i + nF].key]))
			(&userDefaultParams.initPop)[i] = num.integerValue;
	if ((num = [ud objectForKey:keyWarpOpacity])) warpOpacity = num.doubleValue;
	setup_colors();
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
	if (warpOpacity != DEFAULT_WARP_OPACITY)
		[ud setDouble:warpOpacity forKey:keyWarpOpacity];
}
- (IBAction)openPreferencePanel:(id)sender {
	static Preferences *pref = nil;
	if (pref == nil) pref = Preferences.new;
	[pref showWindow:sender];
}
@end

@implementation Preferences
- (NSString *)windowNibName { return @"Preferences"; }
- (void)windowDidLoad {
	show_anime_steps(animeStepTxt, defaultAnimeSteps);
	NSArray<NSColorWell *> *cws = @[susColWell, asyColWell, symColWell, recColWell, dieColWell,
		bgColWell, hospitalColWell, cemeteryColWell, textColWell];
	for (NSInteger i = 0; i < N_COLORS; i ++) {
		colWells[i] = cws[i];
		colWells[i].tag = i;
		colWells[i].target = self; colWells[i].action = @selector(changeColor:);
		colWells[i].color = stateColors[i];
	}
	warpOpacitySld.doubleValue = warpOpacityDgt.doubleValue = warpOpacity;
}
- (IBAction)changeAnimeSteps:(id)sender {
	defaultAnimeSteps = 1 << animeStepper.integerValue;
	show_anime_steps(animeStepTxt, defaultAnimeSteps);
}
- (void)changeColor:(NSObject *)sender {
	NSColorWell *colWell = nil;
	NSInteger index = -1;
	if ([sender isKindOfClass:NSColorPanel.class]) {
		for (index = 0; index < N_COLORS; index ++)
			if (colWells[index].active) { colWell = colWells[index]; break; }
	} else if ([sender isKindOfClass:NSColorWell.class]) {
		colWell = (NSColorWell *)sender;
		index = colWell.tag;
	}
	if (colWell == nil) return;
	stateColors[index] = colWell.color;
	CGFloat r, g, b;
	[stateColors[index] getRed:&r green:&g blue:&b alpha:NULL];
	stateRGB[index] = ((NSInteger)(r * 255) << 16)
		| ((NSInteger)(g * 255) << 8) | (NSInteger)(b * 255);
}
- (IBAction)changeWarpOpacity:(NSControl *)sender {
	warpOpacity = sender.doubleValue;
	if (sender != warpOpacitySld) warpOpacitySld.doubleValue = warpOpacity;
	if (sender != warpOpacityDgt) warpOpacityDgt.doubleValue = warpOpacity;
}
- (IBAction)applyToAllDocuments:(id)sender {
	for (NSInteger i = 0; i < NHealthTypes; i ++)
		warpColors[i] = [stateColors[i] colorWithAlphaComponent:warpOpacity];
	for (Document *doc in NSDocumentController.sharedDocumentController.documents)
		[doc reviseColors];
}
- (IBAction)clearUserDefaults:(id)sender {
	confirm_operation(@"Will clear the current user's defaults.", self.window, ^{
		NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
		[ud removeObjectForKey:keyAnimeSteps];
		for (NSInteger i = 0; i < N_COLORS; i ++)
			[ud removeObjectForKey:colKeys[i]];
		[ud removeObjectForKey:keyWarpOpacity];
		self->warpOpacitySld.doubleValue = self->warpOpacityDgt.doubleValue = 
		warpOpacity = DEFAULT_WARP_OPACITY;
		memcpy(stateRGB, defaultStateRGB, sizeof(stateRGB));
		setup_colors();
		for (NSInteger i = 0; i < N_COLORS; i ++)
			colWells[i].color = stateColors[i];
	});
}
@end
