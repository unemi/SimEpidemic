//
//  StatPanel.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/09.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CommonTypes.h"
#define IMG_WIDTH (320*4)
#define IMG_HEIGHT	320
#define MAX_N_REC	IMG_WIDTH

NS_ASSUME_NONNULL_BEGIN

extern StatData *new_stat(void);

typedef struct {
	NSUInteger positive, negative;
} TestResultCount;

@interface MyCounter : NSObject
@property NSInteger cnt;
- (instancetype)initWithCount:(NSInteger)count;
- (void)inc;
- (void)dec;
@end

#ifndef NOGUI
@interface ULinedButton : NSButton
@property NSColor *underLineColor;
@end
#endif

typedef struct { int orgV, newV; } InfectionCntInfo;
@interface NSValue (InfectionExtension)
+ (NSValue *)valueWithInfect:(InfectionCntInfo)info;
- (InfectionCntInfo)infectValue;
@end

@class World;
#ifndef NOGUI
@class Document, StatPanel;
#endif

typedef struct {
	CGFloat *rec;
	NSInteger len, n, tail;
} InfecQueInfo;

// Statistics for Severe Symptom Patients
#define SSP_MaxSteps MAX_N_REC
#define SSP_NRanks 50

@interface StatInfo : NSObject {
	NSUInteger maxCounts[NIntIndexes], maxTransit[NIntIndexes];
#ifndef NOGUI
	unsigned char *imgBm;
	NSArray<NSNumber *> *phaseInfo;	// line numbers of condition to run util ...
	NSArray<NSString *> *labelInfo; // label of condition to run until ...
	NSMutableArray<NSNumber *> *scenarioPhases;	// step, p, s, ... p
#endif
	NSInteger popSize, steps, skip, days, skipDays;
	StatData statCumm, transDaily, transCumm;
	NSUInteger testCumm[NIntTestTypes];
	TestResultCount testResultsW[7];
	CGFloat maxStepPRate, maxDailyPRate;	// Rate of positive
	InfecQueInfo infectedSeq;	// record of the number of infected to calculate ReproRate
	CGFloat minReproRate, maxReproRate;
}
@property __weak World * __nullable world;
@property (readonly) NSMutableArray<MyCounter *> *IncubPHist, *RecovPHist, *DeathPHist, *NInfectsHist;
@property StatData *statistics, *transit;
@property TestResultCount testResultCnt;	// weekly total
@property NSMutableData *sspData, *variantsData;

- (void)reset:(PopulationHConf)popConf;
- (void)cummulateHistgrm:(HistogramType)type days:(CGFloat)d;
- (BOOL)calcStatWithTestCount:(NSUInteger *)testCount
	infects:(NSArray<NSArray<NSValue *> *> *)infects;
#ifdef NOGUI
- (NSInteger)skipSteps;
- (NSInteger)skipDays;
- (void)discardMemory;
#else
@property __weak Document * __nullable doc;
@property (readonly) NSMutableArray<StatPanel *> *statPanels;
- (void)setPhaseInfo:(NSArray<NSNumber *> *)info;
- (void)setLabelInfo:(NSArray<NSString *> *)info;
- (void)phaseChangedTo:(NSInteger)lineNumber;
- (void)reviseColors;
- (StatPanel *)openStatPanel:(NSWindow *)parentWindow;
- (void)flushPanels;
#endif
@end

#ifndef NOGUI
#define SSP_NDrawRanks 10
typedef struct {
	NSInteger idxBits, nIndexes, windowSize;
} TimeEvoInfo;

typedef enum {
	StatWhole, StatTimeEvo, StatSeverity, StatVariants, StatPeriods, StatSpreaders
} StatType;

typedef enum {
	MskSusceptible = (1<<Susceptible),
	MskInfected = (1<<Asymptomatic),
	MskSymptomatic = (1<<Symptomatic),
	MskRecovered = (1<<Recovered),
	MskDied = (1<<Died),
	MskVaccinated = (1<<Vaccinated),
	MskQrtnA = (1<<QuarantineAsym),
	MskQrtnS = (1<<QuarantineSymp),
	MskTestTotal = (1<<(TestTotal+NStateIndexes)),
	MskTestSym = (1<<(TestAsSymptom+NStateIndexes)),
	MskTestCon = (1<<(TestAsContact+NStateIndexes)),
	MskTestSus = (1<<(TestAsSuspected+NStateIndexes)),
	MskTestP = (1<<(TestPositive+NStateIndexes)),
	MskTestN = (1<<(TestNegative+NStateIndexes)),
	MskTestPRate = (1<<(TestPositiveRate+NStateIndexes)),
	MskReproRate = (1<<ReproductRate),
	MskTransit = (1<<NAllIndexes)
} IndexMask;

@interface StatView : NSView {
	IBOutlet StatPanel *statPanel;
}
@end

@interface StatPanel : NSWindowController <NSWindowDelegate> {
	IBOutlet NSPopUpButton *typePopUp;
	IBOutlet NSButton *idxSelectionBtn;
	IBOutlet NSWindow *idxSelectionSheet;
	IBOutlet NSView *mvAvrgView;
	IBOutlet NSTextField *mvAvrgDgt, *mvAvrgUnit;
	IBOutlet NSStepper *mvAvrgStp;
	IBOutlet StatView *view;
	NSMutableArray<ULinedButton *> *indexCBoxes;
	NSButton *transitCBox, *reproRateCBox;
	StatInfo *statInfo;
	TimeEvoInfo timeEvoInfo;
	BOOL isClosing;
}
- (instancetype)initWithInfo:(StatInfo *)info;
- (void)setupColorForCBoxes;
- (IBAction)stepMvAvrg:(id)sender;
- (IBAction)flushView:(id)sender;
- (NSView *)view;
@end
#endif
NS_ASSUME_NONNULL_END
