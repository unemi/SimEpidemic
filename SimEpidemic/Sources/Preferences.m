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
	NSArray<NSColorWell *> *cws = @[susColWell, asyColWell, symColWell, recColWell, dieColWell,
		bgColWell, hospitalColWell, cemeteryColWell, textColWell];
	for (NSInteger i = 0; i < N_COLORS; i ++) {
		colWells[i] = cws[i];
		colWells[i].tag = i;
		colWells[i].target = self; colWells[i].action = @selector(changeColor:);
		colWells[i].color = stateColors[i];
	}
	warpOpacitySld.doubleValue = warpOpacityDgt.doubleValue = warpOpacity;
	panelsAlphaSld.doubleValue = panelsAlphaDgt.doubleValue = panelsAlpha;
	childWinCBox.state = makePanelChildWindow;
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
@end
