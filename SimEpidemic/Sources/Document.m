//
//  Document.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#define GCD_CONCURRENT_QUEUE

#import <sys/sysctl.h>
#import <sys/resource.h>
#import "Document.h"
#import "World.h"
#import "Agent.h"
#import "Scenario.h"
#import "StatPanel.h"
#import "Parameters.h"
#import "Gatherings.h"
#import "MyView.h"
#import "DataPanel.h"
#import "ParamPanel.h"

#ifndef NOGUI
@implementation NSWindowController (ChildWindowExtension)
- (void)setupParentWindow:(NSWindow *)parentWindow {
	if (self.window.parentWindow == nil && makePanelChildWindow)
		[parentWindow addChildWindow:self.window ordered:NSWindowAbove];
}
- (void)showWindowWithParent:(NSWindow *)parentWindow {
	[self setupParentWindow:parentWindow];
	[self showWindow:self];
}
- (void)windowDidBecomeKey:(NSNotification *)notification {
	NSWindow *pWin = self.window.parentWindow;
	if (pWin != nil) {
		[pWin removeChildWindow:self.window];
		[pWin addChildWindow:self.window ordered:NSWindowAbove];
	}
}
@end
#endif

#ifdef GCD_CONCURRENT_QUEUE
#else
NSInteger nQueues = 10;
#endif
//#define MEASURE_TIME
#ifdef MEASURE_TIME
#define N_MTIME 8
#endif

NSString *nnScenarioText = @"nnScenatioText",
	*nnParamChanged = @"nnParamChanged";

@interface Document () {
	NSSize orgWindowSize, orgViewSize;
	NSMutableDictionary *orgViewInfo, *nnObjects;
	FillView *fillView;
}
@end

@implementation Document
@synthesize world;
- (void)setRunning:(BOOL)newState {
	BOOL orgState = world.loopMode == LoopRunning;
	if (orgState != newState) [self startStop:nil];
}
- (void)setPanelTitle:(NSWindow *)panel {
	NSString *orgTitle = panel.title;
	NSScanner *scan = [NSScanner scannerWithString:orgTitle];
	[scan scanUpToString:@": " intoString:NULL];
	panel.title = [NSString stringWithFormat:@"%@: %@", self.displayName,
		scan.atEnd? orgTitle : [orgTitle substringFromIndex:scan.scanLocation + 2]];
}
- (void)setDisplayName:(NSString *)name {
	[super setDisplayName:name];
	NSWindowController *winCon[] = {scenarioPanel, paramPanel, dataPanel};
	for (NSInteger i = 0; i < 3; i ++)
		if (winCon[i] != nil) [self setPanelTitle:winCon[i].window];
	for (StatPanel *panel in world.statInfo.statPanels)
		[self setPanelTitle:panel.window];
}
- (void)reviseColors {
	view.needsDisplay = YES;
	for (NSInteger i = 0; i < NHealthTypes; i ++) {
		lvViews[i].color = stateColors[i];
		lvViews[i].needsDisplay = YES;
	}
	[world.statInfo reviseColors];
}
- (void)adjustScenarioText {
	if (world.scenario != nil && world.scenario.count > 0)
		scenarioText.integerValue = world.scenarioIndex;
	else scenarioText.stringValue = NSLocalizedString(@"None", nil);
}
- (void)setupPhaseInfo {
	if (world.scenario.count == 0) {
		world.statInfo.phaseInfo = @[];
		world.statInfo.labelInfo = @[];
		return;
	}
	NSMutableArray<NSNumber *> *maPhase = NSMutableArray.new;
	NSMutableArray<NSString *> *maLabel = NSMutableArray.new;
	for (NSInteger i = 0; i < world.scenario.count; i ++) {
		NSObject *elm = world.scenario[i];
		NSString *label;
		NSPredicate *pred = predicate_in_item(elm, &label);
		if (pred != nil) {
			[maPhase addObject:@(i + 1)];
			[maLabel addObject:label];
		}
	}
	// if the final item is not an unconditional jump then add finale phase.
	NSArray *item = world.scenario.lastObject;
	if (![item isKindOfClass:NSArray.class] || item.count != 1 ||
		![item[0] isKindOfClass:NSNumber.class])
		[maPhase addObject:@(world.scenario.count + 1)];
	world.statInfo.phaseInfo = maPhase;
	world.statInfo.labelInfo = maLabel;
}
- (void)setScenario:(NSArray *)newScen {
	if (world.running) return;
	NSArray *orgScen = world.scenario;
	[self.undoManager registerUndoWithTarget:self handler:
		^(Document *target) { target.scenario = orgScen; }];
	[world setScenario:newScen index:0];
	[self setupPhaseInfo];
	[self adjustScenarioText];
	[scenarioPanel adjustControls:
		self.undoManager.undoing || self.undoManager.redoing];
}
- (void)showCurrentStatistics {
	StatData *stat = world.statInfo.statistics;
	for (NSInteger i = 0; i < NHealthTypes; i ++)
		lvViews[i].integerValue = stat->cnt[i];
	qNSNum.integerValue = stat->cnt[QuarantineAsym];
	qDSNum.integerValue = stat->cnt[QuarantineSymp];
	[world.statInfo flushPanels];
}
- (instancetype)init {
	if ((self = [super init]) == nil) return nil;
	animeSteps = defaultAnimeSteps;
	self.undoManager = NSUndoManager.new;
	return self;
}
- (void)resetPopulation {
	if ([world resetPop]) [self updateChangeCount:NSChangeDone];
	daysNum.doubleValue = 0.;
	[self showCurrentStatistics];
	[paramPanel adjustControls];
}
- (NSString *)windowNibName { return @"Document"; }
- (void)windowControllerDidLoadNib:(NSWindowController *)windowController {
	static NSString *lvNames[] = {
		@"Susceptible", @"Asymptomatic", @"Symptomatic", @"Recovered", @"Dead",
		@"Vaccinated"
	};
	LegendView *lviews[NHealthTypes];
	NSInteger k = 0;
	for (NSView *subv in windowController.window.contentView.subviews)
		if ([subv isKindOfClass:LegendView.class]) {
			lviews[k ++] = (LegendView *)subv;
			if (k >= NHealthTypes) break;
	}
	lvViews = [NSArray arrayWithObjects:lviews count:k];
	for (NSInteger i = 0; i < lvViews.count; i ++) {
		lvViews[i].color = stateColors[i];
		lvViews[i].name = NSLocalizedString(lvNames[i], nil);
		lvViews[i].integerValue = 0;
	}
	windowController.window.delegate = self;
	world = World.new;
	world.statInfo.doc = self;
	view.world = world;
	if (worldInitializer != nil) {
		NSError *error;
		if (!worldInitializer(world, &error))
			error_msg(error, view.window, NO);
	}
	nnObjects = NSMutableDictionary.new;
	NSNotificationCenter *ntfCenter = NSNotificationCenter.defaultCenter;
	[ntfCenter addObserver:self
		selector:@selector(adjustScenarioText) name:nnScenarioText object:world];
	nnObjects[nnScenarioText] = @YES;
	nnObjects[nnParamChanged] = [ntfCenter addObserverForName:nnParamChanged
		object:world queue:nil usingBlock:^(NSNotification *note) {
		[self->paramPanel adjustParamControls:note.userInfo[@"keys"]];
	}];
	if (world.scenario != nil) [self setupPhaseInfo];
	if (world.runtimeParamsP->step == 0) [self resetPopulation];
	else savePopCBox.state = NSControlStateValueOn;
	if (statPanelInitializer != nil) {
		for (void (^block)(StatInfo *) in statPanelInitializer) block(world.statInfo);
		[self showAllAfterStep];
		statPanelInitializer = nil;
	}
	animeStepper.integerValue = log2(animeSteps);
	show_anime_steps(animeStepsTxt, animeSteps);
	stopAtNDaysDgt.integerValue = (world.stopAtNDays > 0)? world.stopAtNDays : - world.stopAtNDays;
	stopAtNDaysCBox.state = world.stopAtNDays > 0;
	[self adjustScenarioText];
	orgWindowSize = windowController.window.frame.size;
	orgViewSize = view.frame.size;
}
// NSWindowDelegate methods
// You can find the other delegate methods in MyView.m
- (void)windowDidBecomeMain:(NSNotification *)notification {
	if (notification.object != view.window || panelInitializer == nil) return;
	void (^block)(Document *) = panelInitializer;
	panelInitializer = nil;
	block(self);
	if (view.scale > 1.) [view enableMagDownButton];
	saveGUICBox.state = NSControlStateValueOn;
}
- (void)windowWillClose:(NSNotification *)notification {
	if (scenarioPanel != nil) [scenarioPanel close];
	if (paramPanel != nil) [paramPanel close];
	if (dataPanel != nil) [dataPanel close];
	if (world.statInfo.statPanels != nil)
		for (NSInteger i = world.statInfo.statPanels.count - 1; i >= 0; i --)
			[world.statInfo.statPanels[i] close];
	NSNotificationCenter *ntfCenter = NSNotificationCenter.defaultCenter;
	for (NSString *nn in nnObjects) {
		if ([nnObjects[nn] isKindOfClass:NSNumber.class])
			[ntfCenter removeObserver:self name:nn object:nil];
		else [ntfCenter removeObserver:nnObjects[nn]];
	}
	[world discardMemory];
	((NSWindow *)notification.object).delegate = nil;
}
- (void)windowWillEnterFullScreen:(NSNotification *)notification {
	orgViewInfo = NSMutableDictionary.new;
	orgViewInfo[@"windowFrame"] = [NSValue valueWithRect:view.window.frame];
	orgViewInfo[@"viewFrame"] = [NSValue valueWithRect:view.frame];
}
- (void)windowDidEnterFullScreen:(NSNotification *)notification {
	NSView *contentView = view.superview;
	NSSize contentSize = contentView.frame.size;
	NSRect newViewFrame = {0, 0, contentSize.height * 1.2, contentSize.height};
	newViewFrame.origin.x = contentSize.width - newViewFrame.size.width;
	NSRect panelRect = {0, stopAtNDaysDgt.frame.origin.y - 10., newViewFrame.origin.x,};
	[view setFrame:newViewFrame];
	panelRect.origin.y -= (panelRect.size.height = panelRect.size.width / 4.);
	if (world.statInfo.statPanels != nil) {
		NSMutableArray *ma = NSMutableArray.new;
		for (StatPanel *sp in world.statInfo.statPanels) {
			NSView *statView = sp.view;
			[ma addObject:@[statView, statView.superview,
				[NSValue valueWithRect:statView.frame]]];
			[contentView addSubview:statView];
			[statView setFrame:panelRect];
			if ((panelRect.origin.y -= panelRect.size.height) < 0.) break;
		}
		orgViewInfo[@"statViews"] = ma;
	}
	fillView = [FillView.alloc initWithFrame:(NSRect)
		{0, 0, panelRect.size.width, NSMaxY(panelRect)}];
	[contentView addSubview:fillView];
	for (NSButton *btn in @[scnBtn, prmBtn, sttBtn, datBtn]) btn.enabled = NO;
}
- (void)windowDidExitFullScreen:(NSNotification *)notification {
	[view.window setFrame:
		[(NSValue *)orgViewInfo[@"windowFrame"] rectValue] display:YES];
	[view setFrame:[(NSValue *)orgViewInfo[@"viewFrame"] rectValue]];
	NSArray *statViews = orgViewInfo[@"statViews"];
	if (statViews != nil) for (NSArray *info in statViews) {
		[(NSView *)info[1] addSubview:info[0]];
		[(NSView *)info[0] setFrame:[(NSValue *)info[2] rectValue]];
	}
	[fillView removeFromSuperview];
	fillView = nil;
	orgViewInfo = nil;
	for (NSButton *btn in @[scnBtn, prmBtn, sttBtn, datBtn]) btn.enabled = YES;
}
//
void copy_plist_as_JSON_text(NSObject *plist, NSWindow *window) {
	NSError *error;
	NSData *data = [NSJSONSerialization dataWithJSONObject:plist
		options:JSONFormat error:&error];
	if (data != nil) {
		NSPasteboard *pb = NSPasteboard.generalPasteboard;
		[pb declareTypes:@[NSPasteboardTypeString] owner:NSApp];
		[pb setData:data forType:NSPasteboardTypeString];
	} else if (window != nil) error_msg(error, window, NO);
}
- (IBAction)copy:(id)sender {
	NSMutableDictionary *dict = NSMutableDictionary.new;
	if (world.stopAtNDays > 0) dict[@"stopAt"] = @(world.stopAtNDays);
	if (world.scenario != nil) dict[keyScenario] = [world scenarioPList];
	dict[keyParameters] = param_dict(world.initParamsP, world.worldParamsP);
	copy_plist_as_JSON_text(dict, view.window);
}
- (IBAction)copyImage:(id)sender {
	NSRect area = view.bounds;
	area.size.width = area.size.height;
	NSBitmapImageRep *imgRep = [view bitmapImageRepForCachingDisplayInRect:area];
	[view cacheDisplayInRect:area toBitmapImageRep:imgRep];
	imgRep.size = (NSSize){imgRep.pixelsWide, imgRep.pixelsHigh};
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	[pb declareTypes:@[NSPasteboardTypePNG] owner:self];
	[pb setData:[imgRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
		forType:NSPasteboardTypePNG];
}
- (void)showAllAfterStep {
	[self showCurrentStatistics];
	daysNum.doubleValue =
		floor(world.runtimeParamsP->step / world.worldParamsP->stepsPerDay);
	spsNum.doubleValue = world.stepsPerSec;
	view.needsDisplay = YES;
}
- (void)runningLoop {
	[world runningLoopWithAnimeSteps:animeSteps postProc:^{ [self showAllAfterStep]; }];
	in_main_thread(^{
		self->view.needsDisplay = YES;
		self->startBtn.title = NSLocalizedString(@"Start", nil);
		self->stepBtn.enabled = YES;
		[self->scenarioPanel adjustControls:NO];
	});
}
- (IBAction)startStop:(id)sender {
	if (world.loopMode != LoopRunning) {
		[world goAhead];
		startBtn.title = NSLocalizedString(@"Stop", nil);
		stepBtn.enabled = NO;
		world.loopMode = LoopRunning;
		[scenarioPanel adjustControls:NO];
		[NSThread detachNewThreadSelector:
			@selector(runningLoop) toTarget:self withObject:nil];
	} else {
		startBtn.title = NSLocalizedString(@"Start", nil);
		stepBtn.enabled = YES;
		world.loopMode = LoopEndByUser;
		[scenarioPanel adjustControls:NO];
	}
}
- (IBAction)step:(id)sedner {
	switch (world.loopMode) {
		case LoopRunning: return;
		case LoopFinished: case LoopEndByCondition: [world goAhead];
		default: [world doOneStep];
	}
	[self showAllAfterStep];
	world.loopMode = LoopEndByUser;
}
- (IBAction)reset:(id)sender {
	[self resetPopulation];
	view.needsDisplay = YES;
}
- (IBAction)addOneInfected:(id)sender {
	[world addInfected:1];
}
- (IBAction)switchDaysToStop:(id)sender {
	BOOL orgState = world.stopAtNDays > 0, newState = stopAtNDaysCBox.state;
	if (orgState == newState) return;
	[self.undoManager registerUndoWithTarget:stopAtNDaysCBox handler:^(NSButton *target) {
		target.state = orgState;
		[target sendAction:target.action to:target.target];
	}];
	world.stopAtNDays = - world.stopAtNDays;
}
- (IBAction)changeDaysToStop:(id)sender {
	NSInteger orgDays = world.stopAtNDays;
	[self.undoManager registerUndoWithTarget:stopAtNDaysDgt handler:^(NSTextField *target) {
		target.integerValue = orgDays;
		[target sendAction:target.action to:target.target];
	}];
	NSInteger days = stopAtNDaysDgt.integerValue;	
	world.stopAtNDays = stopAtNDaysCBox.state? days : - days;
}
- (IBAction)chooseColorType:(id)sender {
	ColorType orgValue = view.colorType, newValue = (ColorType)colTypePopUp.indexOfSelectedItem;
	if (newValue == orgValue) return;
	[self.undoManager registerUndoWithTarget:colTypePopUp handler:^(NSPopUpButton *target) {
		[target selectItemAtIndex:orgValue];
		[target sendAction:target.action to:target.target];
	}];
	view.colorType = newValue;
	view.needsDisplay = YES;
}
- (IBAction)switchShowGatherings:(id)sender {
	BOOL newValue = showGatheringsCBox.state == NSControlStateValueOn;
	if (newValue == view.showGatherings) return;
	[self.undoManager registerUndoWithTarget:showGatheringsCBox
		handler:^(NSButton *target) {
		target.state = 1 - target.state;
		[target sendAction:target.action to:target.target];
	}];
	view.showGatherings = newValue;
	view.needsDisplay = YES;
}
- (IBAction)changeAnimeSteps:(id)sender {
	NSInteger newSteps = 1 << animeStepper.integerValue;
	if (newSteps == animeSteps) return;
	NSInteger orgExp = 0;
	for (NSInteger i = 1; i < animeSteps; i <<= 1) orgExp ++;
	[self.undoManager registerUndoWithTarget:animeStepper handler:^(NSStepper *target) {
		target.integerValue = orgExp;
		[target sendAction:target.action to:target.target];
	}];
	animeSteps = newSteps;
	show_anime_steps(animeStepsTxt, animeSteps);
}
- (IBAction)animeStepsDouble:(id)sender {
	animeStepper.integerValue = animeStepper.integerValue + 1;
	[self changeAnimeSteps:sender];
}
- (IBAction)animeStepsHalf:(id)sender {
	animeStepper.integerValue = animeStepper.integerValue - 1;
	[self changeAnimeSteps:sender];
}
- (IBAction)openScenarioPanel:(id)sender {
	if (scenarioPanel == nil) scenarioPanel = [Scenario.alloc initWithDoc:self];
	[scenarioPanel showWindowWithParent:view.window];
}
- (IBAction)openParamPanel:(id)sender {
	if (paramPanel == nil) paramPanel = [ParamPanel.alloc initWithDoc:self];
	[paramPanel showWindowWithParent:view.window];
}
- (IBAction)openDataPanel:(id)sender {
	if (dataPanel == nil) dataPanel = [DataPanel.alloc initWithInfo:world.statInfo];
	[dataPanel showWindowWithParent:view.window];
}
- (IBAction)openStatPenel:(id)sender { [world.statInfo openStatPanel:view.window]; }
//
- (void)openScenarioFromURL:(NSURL *)url {
	NSObject *pList = get_propertyList_from_url(url, NSArray.class, view.window);
	if (pList != nil) {
		[self openScenarioPanel:self];
		[scenarioPanel setScenarioWithArray:(NSArray *)pList];
	}
}
- (void)openParamsFromURL:(NSURL *)url {
	NSObject *pList = get_propertyList_from_url(url, NSDictionary.class, view.window);
	if (pList != nil) {
		RuntimeParams tmpRParams;
		WorldParams tmpWParams;
		memcpy(&tmpRParams, world.runtimeParamsP, sizeof(RuntimeParams));
		memcpy(&tmpWParams, world.worldParamsP, sizeof(WorldParams));
		set_params_from_dict(&tmpRParams, &tmpWParams, (NSDictionary *)pList);
		[self openParamPanel:self];
		[paramPanel setParamsOfRuntime:&tmpRParams world:&tmpWParams];
	}
}
- (void)revisePanelsAlpha {
	if (paramPanel != nil) paramPanel.window.alphaValue = panelsAlpha;
	if (scenarioPanel != nil) scenarioPanel.window.alphaValue = panelsAlpha;
}
- (void)revisePanelChildhood {
	NSArray<NSWindow *> *children = view.window.childWindows;
	if (!makePanelChildWindow) {
		for (NSWindow *child in children)
			[view.window removeChildWindow:child];
	} else if (children == nil || children.count == 0) {
		if (paramPanel != nil) [paramPanel setupParentWindow:view.window];
		if (scenarioPanel != nil) [scenarioPanel setupParentWindow:view.window];
		if (dataPanel != nil) [dataPanel setupParentWindow:view.window];
		for (StatPanel *stp in world.statInfo.statPanels)
			[stp setupParentWindow:view.window];
	}
}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = menuItem.action;
	if (action == @selector(startStop:))
		menuItem.title = NSLocalizedString((world.loopMode == LoopRunning)? @"Stop" : @"Start", nil);
	else if (action == @selector(step:)) return (world.loopMode != LoopRunning);
	else if (action == @selector(animeStepsDouble:))
		return animeStepper.integerValue < animeStepper.maxValue;
	else if (action == @selector(animeStepsHalf:))
		return animeStepper.integerValue > animeStepper.minValue;
	return YES;
}
@end
