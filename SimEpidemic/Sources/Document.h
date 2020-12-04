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
extern void in_main_thread(dispatch_block_t block);
#ifdef DEBUG
extern void my_exit(void);
#endif
extern NSInteger nQueues;

@interface WarpInfo : NSObject
@property Agent *agent;
@property CGPoint goal;
@property WarpType mode;
- (instancetype)initWithAgent:(Agent *)a goal:(CGPoint)p mode:(WarpType)md;
@end

@class MyView, LegendView, StatInfo, MyCounter;
#ifdef NOGUI
@class PeriodicReporter;
#endif

#ifndef NOGUI
@interface Document : NSDocument <NSWindowDelegate> {
	IBOutlet MyView *view;
	IBOutlet NSTextField *daysNum, *qNSNum, *qDSNum, *spsNum,
		*scenarioText, *animeStepsTxt, *stopAtNDaysDgt;
	IBOutlet NSButton *startBtn, *stepBtn, *scnBtn, *prmBtn, *sttBtn, *datBtn,
		*stopAtNDaysCBox, *showGatheringsCBox;
	IBOutlet NSStepper *animeStepper;
	IBOutlet LegendView *lvSuc, *lvAsy, *lvSym, *lvRec, *lvDea; 
	NSArray<LegendView *> *lvViews;
#else
@interface Document : NSObject {
#endif
	RuntimeParams runtimeParams, initParams;
	WorldParams worldParams, tmpWorldParams;
	NSLock *popLock;
	IBOutlet StatInfo *statInfo;
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
- (NSArray *)scenario;
- (void)testInfectionOfAgent:(Agent *)agent reason:(TestType)reason;
- (void)addNewWarp:(WarpInfo *)info;
#ifdef NOGUI
@property (readonly) NSString *ID;
@property (readonly) NSLock *lastTLock;
@property NSDate *lastTouch;
@property NSString *docKey;
@property void (^stopCallBack)(LoopMode);
- (CGFloat)howMuchBusy;
- (BOOL)touch;
- (void)start:(NSInteger)stopAt maxSPS:(CGFloat)maxSps priority:(CGFloat)prio;
- (void)step;
- (void)stop:(LoopMode)mode;
- (void)resetPop;
- (void)addReporter:(PeriodicReporter *)rep;
- (void)removeReporter:(PeriodicReporter *)rep;
- (void)reporterConnectionWillClose:(int)desc;
- (void)discardMemory;
- (StatInfo *)statInfo;
- (NSArray *)scenarioPList;
- (void)setScenarioWithPList:(NSArray *)plist;
#else
- (NSArray<Gathering *> *)gatherings;
- (void)setScenario:(NSArray *)newScen;
- (void)setPanelTitle:(NSWindow *)panel;
- (void)reviseColors;
- (void)setInitialParameters:(NSData *)newParams;
- (void)openScenarioFromURL:(NSURL *)url;
- (void)openParamsFromURL:(NSURL *)url;
- (void)revisePanelsAlpha;
- (void)revisePanelChildhood;
#endif
@end

@interface NSWindowController (ChildWindowExtension)
- (void)showWindowWithParent:(NSWindow *)parentWindow;
@end
