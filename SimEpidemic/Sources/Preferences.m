//
//  Preferences.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/08/31.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "Preferences.h"
#import "AppDelegate.h"
#import "Document.h"

static __weak NSColorWell *colWells[N_COLORS];
@implementation Preferences
- (NSString *)windowNibName { return @"Preferences"; }
- (void)windowDidLoad {
	show_anime_steps(animeStepTxt, defaultAnimeSteps);
	NSArray<NSColorWell *> *cws = @[
		susColWell, asyColWell, symColWell, recColWell, dieColWell, vcnColWell,
		bgColWell, hospitalColWell, cemeteryColWell, textColWell, gatherColWell];
	for (NSInteger i = 0; i < N_COLORS; i ++) {
		colWells[i] = cws[i];
		colWells[i].tag = i;
		colWells[i].target = self; colWells[i].action = @selector(changeColor:);
		colWells[i].color = stateColors[i];
	}
	warpOpacitySld.doubleValue = warpOpacityDgt.doubleValue = warpOpacity;
	panelsAlphaSld.doubleValue = panelsAlphaDgt.doubleValue = panelsAlpha;
	childWinCBox.state = makePanelChildWindow;
	jsonPPCBox.state = (JSONFormat & NSJSONWritingPrettyPrinted) != 0;
	jsonSKCBox.state = (JSONFormat & NSJSONWritingSortedKeys) != 0;
	jsonPPCBox.tag = NSJSONWritingPrettyPrinted;
	jsonSKCBox.tag = NSJSONWritingSortedKeys;
}
- (void)loadSettingsFromURL:(NSURL *)url {
	NSError *error;
	NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
	if (data == nil) { error_msg(error, self.window, NO); return; }
	NSDictionary *dict = [NSPropertyListSerialization
		propertyListWithData:data options:0 format:NULL error:&error];
	if (dict == nil) { error_msg(error, self.window, NO); return; }
	NSNumber *num;
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	if ((num = dict[keyAnimeSteps]) != nil)
		[ud setInteger:(defaultAnimeSteps = num.integerValue) forKey:keyAnimeSteps];
	for (NSInteger i = 0; i < N_COLORS; i ++) if ((num = dict[colKeys[i]]) != nil)
		[ud setInteger:(stateRGB[i] = num.integerValue) forKey:colKeys[i]];
	setup_colors();
	if ((num = dict[keyWarpOpacity]))
		[ud setDouble:(warpOpacity = num.doubleValue) forKey:keyWarpOpacity];
	if ((num = dict[keyPanelsAlpha]))
		[ud setDouble:(panelsAlpha = num.doubleValue) forKey:keyPanelsAlpha];
	if ((num = dict[keyChildWindow]))
		[ud setBool:(makePanelChildWindow = num.boolValue) forKey:keyChildWindow];
	if ((num = dict[keyJSONFormat]))
		[ud setInteger:(JSONFormat = num.integerValue) forKey:keyJSONFormat];
	[self windowDidLoad];
}
- (void)saveSettingsToURL:(NSURL *)url {
	NSDictionary *dict = @{
		keyAnimeSteps:@(defaultAnimeSteps),
		keyWarpOpacity:@(warpOpacity), keyPanelsAlpha:@(panelsAlpha),
		keyChildWindow:@(makePanelChildWindow), keyJSONFormat:@(JSONFormat)
	};
	NSInteger n = dict.count + N_COLORS;
	NSString *keys[n]; NSNumber *objs[n]; NSInteger idx = 0;
	for (NSString *key in dict) { keys[idx] = key; objs[idx] = dict[key]; idx ++; }
	for (NSInteger i = 0; i < N_COLORS; i ++)
		{ keys[idx] = colKeys[i]; objs[idx] = @(stateRGB[i]); idx ++; }
	NSError *error;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:
		[NSDictionary dictionaryWithObjects:objs forKeys:keys count:n]
		format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
	if (data == nil) { error_msg(error, self.window, NO); return; }
	BOOL result = [data writeToURL:url options:0 error:&error];
	if (!result) error_msg(error, self.window, NO);
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
	NSColor *newCol = colWell.color;
	stateColors[index] = (newCol.numberOfComponents > 2)? newCol :
		[newCol colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
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
- (IBAction)changePanelsAlpha:(NSControl *)sender {
	panelsAlpha = sender.doubleValue;
	if (sender != panelsAlphaSld) panelsAlphaSld.doubleValue = panelsAlpha;
	if (sender != panelsAlphaDgt) panelsAlphaDgt.doubleValue = panelsAlpha;
	for (Document *doc in NSDocumentController.sharedDocumentController.documents)
		[doc revisePanelsAlpha];
}
- (IBAction)switchChildWindow:(id)sender {
	BOOL newValue = childWinCBox.state;
	if (newValue == makePanelChildWindow) return;
	makePanelChildWindow = newValue;
	for (Document *doc in NSDocumentController.sharedDocumentController.documents)
		[doc revisePanelChildhood];
}
- (IBAction)saveSettings:(id)sender {
	NSSavePanel *sp = NSSavePanel.new;
	sp.allowedFileTypes = @[@"sEpA"];
	[sp beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
		if (result == NSModalResponseOK) [self saveSettingsToURL:sp.URL];
	}];
}
- (IBAction)loadSettings:(id)sender {
	NSOpenPanel *op = NSOpenPanel.new;
	op.allowedFileTypes = @[@"sEpA"];
	[op beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
		if (result == NSModalResponseOK) [self loadSettingsFromURL:op.URL];
	}];
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
		[ud removeObjectForKey:keyPanelsAlpha];
		self->panelsAlphaSld.doubleValue = self->panelsAlphaDgt.doubleValue =
		panelsAlpha = DEFAULT_PANELS_ALPHA;
		[ud removeObjectForKey:keyChildWindow];
		self->childWinCBox.state = makePanelChildWindow = DEFAULT_CHILD_WIN;
		memcpy(stateRGB, defaultStateRGB, sizeof(stateRGB));
		setup_colors();
		for (NSInteger i = 0; i < N_COLORS; i ++)
			colWells[i].color = stateColors[i];
		for (NSString *key in paramKeys)
			[ud removeObjectForKey:key];
	});
}
- (IBAction)checkJSONform:(NSButton *)btn {
	NSInteger flag = btn.tag;
	NSJSONWritingOptions orgValue = JSONFormat;
	if (btn.state) JSONFormat |= flag;
	else JSONFormat &= ~flag;
	if (JSONFormat != orgValue)
		[NSUserDefaults.standardUserDefaults setInteger:JSONFormat forKey:keyJSONFormat];
}
@end
