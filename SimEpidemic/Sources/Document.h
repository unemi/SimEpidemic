//
//  Document.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

extern NSString *keyParameters, *keyScenario;
extern void add_new_cinfo(Agent *a, Agent *b, NSInteger tm);
#ifdef DEBUG
extern void my_exit(void);
#endif

@interface WarpInfo : NSObject
@property Agent *agent;
@property CGPoint goal;
@property WarpType mode;
- (instancetype)initWithAgent:(Agent *)a goal:(CGPoint)p mode:(WarpType)md;
@end

@class MyView, LegendView, StatInfo, MyCounter;

@interface Document : NSDocument <NSWindowDelegate> {
	IBOutlet MyView *view;
	IBOutlet NSTextField *daysNum, *qNSNum, *qDSNum, *spsNum,
		*scenarioText, *animeStepsTxt, *stopAtNDaysDgt;
	IBOutlet NSButton *startBtn, *stepBtn, *stopAtNDaysCBox;
	IBOutlet NSStepper *animeStepper;
	IBOutlet LegendView *lvSuc, *lvAsy, *lvSym, *lvRec, *lvDea; 
	NSArray<LegendView *> *lvViews;
	RuntimeParams runtimeParams, initParams;
	WorldParams worldParams, tmpWorldParams;
	NSLock *popLock;
	IBOutlet StatInfo *statInfo;
// for Scripting
}
@property (readonly) Agent **Pop, *QList, *CList;
@property (readonly) NSMutableArray<WarpInfo *> *WarpList;
- (Agent **)QListP;
- (Agent **)CListP;
- (RuntimeParams *)runtimeParamsP;
- (RuntimeParams *)initParamsP;
- (WorldParams *)worldParamsP;
- (WorldParams *)tmpWorldParamsP;
- (BOOL)running;
- (void)popLock;
- (void)popUnlock;
- (NSMutableArray<MyCounter *> *)RecovPHist;
- (NSMutableArray<MyCounter *> *)IncubPHist;
- (NSMutableArray<MyCounter *> *)DeathPHist;
- (void)setPanelTitle:(NSWindow *)panel;
- (void)reviseColors;
- (void)setInitialParameters:(NSData *)newParams;
- (NSArray *)scenario;
- (void)setScenario:(NSArray *)newScen;
- (void)testInfectionOfAgent:(Agent *)agent reason:(TestType)reason;
- (void)addNewWarp:(WarpInfo *)info;
- (void)openScenarioFromURL:(NSURL *)url;
- (void)openParamsFromURL:(NSURL *)url;
- (void)revisePanelsAlpha;
- (void)revisePanelChildhood;
@end

@interface NSWindowController (ChildWindowExtension)
- (void)showWindowWithParent:(NSWindow *)parentWindow;
@end
