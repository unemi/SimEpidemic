//
//  World.h
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
extern void in_main_thread(dispatch_block_t block);
extern NSPredicate *predicate_in_item(NSObject *item, NSString **comment);
extern NSObject *scenario_element_from_property(NSObject *prop);
#ifdef NOGUI
extern NSString *check_scenario_element_from_property(NSObject *prop);
#else
extern void copy_plist_as_JSON_text(NSObject *plist, NSWindow *window);
#endif
#ifdef DEBUG
extern void my_exit(void);
#endif

typedef struct { Agent *agent; NSInteger newIdx; } MoveToIdxInfo;
typedef struct { Agent *agent; WarpType mode; NSPoint goal; } WarpInfo;
typedef struct { Agent *agent; HistogramType type; CGFloat days; } HistInfo;
typedef struct { Agent *agent; TestType reason; } TestInfo;
typedef struct { Agent *agent; CGFloat dist; } DistanceInfo;
typedef struct {
	RuntimeParams *rp;
	WorldParams *wp;
	VariantInfo *vrInfo;
	VaccineInfo *vxInfo;
} ParamsForStep;

@class StatInfo, MyCounter;
#ifdef NOGUI
@class PeriodicReporter;
#endif

@interface World : NSObject {
	RuntimeParams runtimeParams, initParams;
	WorldParams worldParams, tmpWorldParams;
	VariantInfo variantInfo[MAX_N_VARIANTS];
	VaccineInfo vaccineInfo[MAX_N_VAXEN];
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
	NSInteger *vcnQueue, vcnQueIdx[N_VCN_QUEQUE];
	CGFloat vcnSubjRem[MAX_N_VAXEN];
}
@property LoopMode loopMode;
@property NSInteger stopAtNDays;
@property (readonly) Agent *agents, **Pop, *QList, *CList;
@property (readonly) NSMutableDictionary<NSNumber *, NSValue *> *WarpList;
@property NSImage *popDistImage;
@property NSMutableArray<NSMutableDictionary *> *variantList, *vaccineList;
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
- (Gathering *)gatherings;
- (void)popLock;
- (void)popUnlock;
- (StatInfo *)statInfo;
- (NSMutableArray<MyCounter *> *)RecovPHist;
- (NSMutableArray<MyCounter *> *)IncubPHist;
- (NSMutableArray<MyCounter *> *)DeathPHist;
- (void)addOperation:(void (^)(void))block;
- (void)waitAllOperations;
- (TestEntry *)newTestEntry;
- (ContactInfo *)newCInfo;
- (void)addNewCInfoA:(Agent *)a B:(Agent *)b tm:(NSInteger)tm;
- (void)freeGatherings:(Gathering *)gats;
- (Gathering *)newNGatherings:(NSInteger)n;
- (NSArray *)scenario;
- (NSInteger)scenarioIndex;
- (void)setScenario:(NSArray *)newScen index:(NSInteger)idx;
- (void)allocateMemory;
- (void)resetBoostQueue;
- (void)resetVaccineQueue;
- (BOOL)resetPop;
- (void)testInfectionOfAgent:(Agent *)agent reason:(TestType)reason;
- (void)setScenarioWithPList:(NSArray *)plist;
- (void)discardMemory;
- (int)variantTypeFromName:(NSString *)varName;
- (void)addInfected:(NSInteger)n variant:(int)variantType;
#ifdef NOGUI
@property (readonly) NSString *ID;
@property (readonly) NSLock *lastTLock;
@property NSDate *lastTouch;
@property NSString *worldKey;
@property void (^stopCallBack)(LoopMode);
- (void)execScenario;
- (CGFloat)howMuchBusy;
- (BOOL)touch;
- (void)start:(NSInteger)stopAt maxSPS:(CGFloat)maxSps priority:(CGFloat)prio;
- (void)step;
- (void)stop:(LoopMode)mode;
- (void)addReporter:(PeriodicReporter *)rep;
- (void)removeReporter:(PeriodicReporter *)rep;
- (void)reporterConnectionWillClose:(int)desc;
- (NSArray *)scenarioPList;
#else
- (void)setupVaxenAndVarintsFromLists;
- (void)setupPhaseInfo;
- (NSArray *)scenarioPList;
- (CGFloat)stepsPerSec;
- (void)runningLoopWithAnimeSteps:(NSInteger)animeSteps postProc:(void (^)(void))stepPostProc;
- (void)goAhead;
- (void)doOneStep;
#endif
@end

@interface NSValue (WorldExtension)
#define DEC_VAL(t,b,g) + (NSValue *)b:(t)info; -(t)g;
DEC_VAL(MoveToIdxInfo, valueWithMoveToIdxInfo, moveToIdxInfoValue)
DEC_VAL(WarpInfo, valueWithWarpInfo, warpInfoValue)
DEC_VAL(HistInfo, valueWithHistInfo, histInfoValue)
DEC_VAL(TestInfo, valueWithTestInfo, testInfoValue)
DEC_VAL(DistanceInfo, valueWithDistanceInfo, distanceInfo)
@end
