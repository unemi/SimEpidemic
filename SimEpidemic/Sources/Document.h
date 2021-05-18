//
//  Document.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#ifdef NOGUI
//#define DEBUGz
#endif

extern NSString *nnScenarioText, *nnParamChanged;

@class World, MyView, LegendView, StatInfo, MyCounter;
@class Scenario, ParamPanel, DataPanel;

@interface Document : NSDocument <NSWindowDelegate> {
	IBOutlet MyView *view;
	IBOutlet NSTextField *daysNum, *qNSNum, *qDSNum, *spsNum,
		*scenarioText, *animeStepsTxt, *stopAtNDaysDgt;
	IBOutlet NSButton *startBtn, *stepBtn, *scnBtn, *prmBtn, *sttBtn, *datBtn,
		*stopAtNDaysCBox, *showGatheringsCBox;
	IBOutlet NSPopUpButton *colTypePopUp;
	IBOutlet NSStepper *animeStepper;
	NSArray<LegendView *> *lvViews;
	IBOutlet NSView *savePanelAccView;
	IBOutlet NSButton *savePopCBox, *saveGUICBox, *savePMapCBox;
	NSMutableArray<void (^)(StatInfo *)> *statPanelInitializer;
	BOOL (^worldInitializer)(World *, NSError **);
	void (^panelInitializer)(Document *);
	World *world;
	Scenario *scenarioPanel;
	ParamPanel *paramPanel;
	DataPanel *dataPanel;
	NSInteger animeSteps;
}
@property (readonly) World *world;
- (void)adjustScenarioText;
- (void)setScenario:(NSArray *)newScen;
- (void)setPanelTitle:(NSWindow *)panel;
- (void)reviseColors;
- (void)openScenarioFromURL:(NSURL *)url;
- (void)openParamsFromURL:(NSURL *)url;
- (void)revisePanelsAlpha;
- (void)revisePanelChildhood;
- (IBAction)openScenarioPanel:(id)sender;
- (IBAction)openParamPanel:(id)sender;
- (IBAction)openDataPanel:(id)sender;
@end

@interface NSWindowController (ChildWindowExtension)
- (void)showWindowWithParent:(NSWindow *)parentWindow;
@end
