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

extern NSString *keyParameters, *keyScenario, *keyDaysToStop;
extern void add_new_cinfo(Agent *a, Agent *b, NSInteger tm);
extern void in_main_thread(dispatch_block_t block);
#ifndef NOGUI
extern TestEntry *new_testEntry(void);
extern ContactInfo *new_cinfo(void);
extern void copy_plist_as_JSON_text(NSObject *plist, NSWindow *window);
#endif
#ifdef DEBUG
extern void my_exit(void);
#endif

typedef struct { Agent *agent; NSInteger newIdx; } MoveToIdxInfo;
typedef struct { Agent *agent; WarpType mode; CGPoint goal; } WarpInfo;
typedef struct { Agent *agent; HistogramType type; CGFloat days; } HistInfo;
typedef struct { Agent *agent; TestType reason; } TestInfo;

@interface NSValue (WoldExtension)
#define DEC_VAL(t,b,g) + (NSValue *)b:(t)info; -(t)g;
DEC_VAL(MoveToIdxInfo, valueWithMoveToIdxInfo, moveToIdxInfoValue)
DEC_VAL(WarpInfo, valueWithWarpInfo, warpInfoValue)
DEC_VAL(HistInfo, valueWithHistInfo, histInfoValue)
DEC_VAL(TestInfo, valueWithTestInfo, testInfoValue)					
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
	IBOutlet NSView *savePanelAccView;
	IBOutlet NSButton *savePopCBox;
	NSArray<void (^)(StatInfo *)> *statInfoInitializer;
#else
@interface Document : NSObject {
#endif
	RuntimeParams runtimeParams, initParams;
	WorldParams worldParams, tmpWorldParams;
	NSInteger animeSteps, stopAtNDays;
	NSLock *popLock;
	NSArray *scenario;
	NSInteger scenarioIndex;
	IBOutlet StatInfo *statInfo;
	NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *paramChangers;
	TestEntry *testQueHead, *testQueTail;
	GatheringMap *gatheringsMap;
	NSMutableArray<Gathering *> *gatherings;
}
@property (readonly) Agent *agents, **Pop, *QList, *CList;
@property (readonly) NSMutableDictionary<NSNumber *, NSValue *> *WarpList;
#ifdef DEBUGz
@property NSInteger phaseInStep;
#endif
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
- (void)addOperation:(void (^)(void))block;
- (void)waitAllOperations;
- (NSArray *)scenario;
- (void)allocateMemory;
- (void)testInfectionOfAgent:(Agent *)agent reason:(TestType)reason;
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
- (void)openScenarioFromURL:(NSURL *)url;
- (void)openParamsFromURL:(NSURL *)url;
- (void)revisePanelsAlpha;
- (void)revisePanelChildhood;
- (NSArray *)scenarioPList;
- (void)setScenarioWithPList:(NSArray *)plist;
#endif
@end

@interface NSWindowController (ChildWindowExtension)
- (void)showWindowWithParent:(NSWindow *)parentWindow;
@end
