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

typedef NSMutableArray<NSMutableDictionary *> * MutableDictArray;
extern NSString *keyParameters, *keyScenario, *keyDaysToStop;
extern void in_main_thread(dispatch_block_t block);
extern NSPredicate *predicate_in_item(NSObject *item, NSString **comment);
extern NSObject *scenario_element_from_property(NSObject *prop);
extern void set_dist_values(DistInfo *dp, NSArray<NSNumber *> *arr, CGFloat steps);
extern void set_reg_gat_value(MutableDictArray gatInfo, NSString *key,
	NSNumber *goal, CGFloat steps);
#ifndef NOGUI
extern void copy_plist_as_JSON_text(NSObject *plist, NSWindow *window);
#endif
#ifdef DEBUG
extern void my_exit(void);
#endif
extern MutableDictArray default_variants(void);
extern MutableDictArray default_vaccines(void);

typedef enum { IfcLocScattered, IfcLocCenter, IfcLocRandomCluster } InfecLocation;
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
	NSInteger spanNPop[MAX_N_AGE_SPANS], ageSpanIdxs[MAX_N_AGE_SPANS], *ageSpanIDs;
	int nAgeSpans;
	BOOL rndPopIndexesFull;
	NSInteger *rndPopIndexes, rndPopOffset;
	NSData *gatSpotsFixed;
	NSMutableDictionary<NSString *, NSMutableArray *> *regGatInfo;
	CGFloat *agentsRnd;
}
@property LoopMode loopMode;
@property NSInteger stopAtNDays;
@property (readonly) Agent *agents, **Pop, *QList, *CList;
@property (readonly) NSMutableDictionary<NSNumber *, NSValue *> *WarpList;
@property NSImage *popDistImage;
@property MutableDictArray variantList, vaccineList;
@property MutableDictArray gatheringsList;
#ifdef DEBUGz
@property NSInteger phaseInStep;
#endif
- (Agent **)QListP;
- (Agent **)CListP;
- (RuntimeParams *)runtimeParamsP;
- (RuntimeParams *)initParamsP;
- (WorldParams *)worldParamsP;
- (WorldParams *)tmpWorldParamsP;
- (VariantInfo *)variantInfoP;
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
- (NSString *)varNameFromKey:(NSString *)key vcnTypeReturn:(int *)vcnTypeP;
- (void)allocateMemory;
- (void)resetBoostQueue;
- (void)resetVaccineQueue;
- (void)organizeAgeSpanInfo;
-(void)doItExclusivelyForRandomIndexes:(NSInteger *)ibuf n:(NSInteger)n
	block:(void (^)(NSInteger, NSInteger))block;
- (BOOL)resetPop;
- (void)testInfectionOfAgent:(Agent *)agent reason:(TestType)reason;
- (void)discardMemory;
- (int)variantTypeFromName:(NSString *)varName;
- (void)addInfected:(NSInteger)n location:(InfecLocation)location variant:(int)variantType;
- (void)setupVaxenAndVariantsFromLists;
#ifdef NOGUI
@property (readonly) NSString *ID;
@property (readonly) NSLock *lastTLock;
@property NSDate *lastTouch;
@property NSString *worldKey;
@property void (^stopCallBack)(LoopMode);
- (CGFloat)howMuchBusy;
- (BOOL)touch;
- (void)start:(NSInteger)stopAt maxSPS:(CGFloat)maxSps priority:(CGFloat)prio;
- (void)step;
- (void)stop:(LoopMode)mode;
- (void)addReporter:(PeriodicReporter *)rep;
- (void)removeReporter:(PeriodicReporter *)rep;
- (void)reporterConnectionWillClose:(int)desc;
#else
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
