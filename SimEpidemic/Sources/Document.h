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
extern void init_global_locks(void);
extern TestEntry *new_testEntry(void);
extern ContactInfo *new_cinfo(void);
extern void free_gatherings(Gathering *gats);
extern Gathering *new_n_gatherings(NSInteger n);
extern NSPredicate *predicate_in_item(NSObject *item, NSString **comment);
extern NSObject *scenario_element_from_property(NSObject *prop);
extern NSString *check_scenario_element_from_property(NSObject *prop);
#ifndef NOGUI
extern void copy_plist_as_JSON_text(NSObject *plist, NSWindow *window);
#endif
#ifdef DEBUG
extern void my_exit(void);
#endif

typedef struct { Agent *agent; NSInteger newIdx; } MoveToIdxInfo;
typedef struct { Agent *agent; WarpType mode; NSPoint goal; } WarpInfo;
typedef struct { Agent *agent; HistogramType type; CGFloat days; } HistInfo;
typedef struct { Agent *agent; TestType reason; } TestInfo;

@interface NSValue (WorldExtension)
#define DEC_VAL(t,b,g) + (NSValue *)b:(t)info; -(t)g;
DEC_VAL(MoveToIdxInfo, valueWithMoveToIdxInfo, moveToIdxInfoValue)
DEC_VAL(WarpInfo, valueWithWarpInfo, warpInfoValue)
DEC_VAL(HistInfo, valueWithHistInfo, histInfoValue)
DEC_VAL(TestInfo, valueWithTestInfo, testInfoValue)					
@end

@class MyView, LegendView, StatInfo, MyCounter;
@class Scenario, ParamPanel, DataPanel;
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
	NSArray<LegendView *> *lvViews;
	IBOutlet NSView *savePanelAccView;
	IBOutlet NSButton *savePopCBox, *saveGUICBox;
	NSMutableArray<void (^)(StatInfo *)> *statPanelInitializer;
	void (^panelInitializer)(Document *);
	Scenario *scenarioPanel;
	ParamPanel *paramPanel;
	DataPanel *dataPanel;
	NSInteger animeSteps;
#else
@interface Document : NSObject {
#endif
	RuntimeParams runtimeParams, initParams;
	WorldParams worldParams, tmpWorldParams;
	LoopMode loopMode;
	NSInteger stopAtNDays;
	NSLock *popLock;
	NSArray *scenario;
	NSInteger scenarioIndex;
	NSPredicate *predicateToStop;
	IBOutlet StatInfo *statInfo;
	NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *paramChangers;
	TestEntry *testQueHead, *testQueTail;
	Gathering *gatherings;
	NSInteger *vaccineList, vcnListIndex;
	CGFloat vcnSubjectsRem;
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
- (void)setVaccinePriority:(VaccinePriority)newValue toInit:(BOOL)isInit;
- (void)resetVaccineList;
- (void)testInfectionOfAgent:(Agent *)agent reason:(TestType)reason;
- (void)setScenarioWithPList:(NSArray *)plist;
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
#else
- (Gathering *)gatherings;
- (void)adjustScenarioText;
- (void)setScenario:(NSArray *)newScen;
- (void)setPanelTitle:(NSWindow *)panel;
- (void)reviseColors;
- (void)openScenarioFromURL:(NSURL *)url;
- (void)openParamsFromURL:(NSURL *)url;
- (void)revisePanelsAlpha;
- (void)revisePanelChildhood;
- (NSArray *)scenarioPList;
- (IBAction)openScenarioPanel:(id)sender;
- (IBAction)openParamPanel:(id)sender;
- (IBAction)openDataPanel:(id)sender;
#endif
@end

@interface NSWindowController (ChildWindowExtension)
- (void)showWindowWithParent:(NSWindow *)parentWindow;
@end
