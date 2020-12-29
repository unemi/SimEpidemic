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

@class Document;
#ifndef NOGUI
@class StatPanel;
#endif

@interface StatInfo : NSObject {
	IBOutlet Document *doc;
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
	CGFloat maxStepPRate, maxDailyPRate, pRateCumm;	// Rate of positive
}
@property (readonly) NSMutableArray<MyCounter *> *IncubPHist, *RecovPHist, *DeathPHist, *NInfectsHist;
- (Document *)doc;
- (void)reset:(NSInteger)nPop infected:(NSInteger)nInitInfec;
- (void)cummulateHistgrm:(HistogramType)type days:(CGFloat)d;
- (BOOL)calcStatWithTestCount:(NSUInteger *)testCount
	infects:(NSArray<NSArray<NSValue *> *> *)infects;
#ifdef NOGUI
@property (readonly) StatData *statistics, *transit;
@property (readonly) TestResultCount testResultCnt;	// weekly total
- (NSInteger)skipSteps;
- (NSInteger)skipDays;
- (void)setDoc:(Document *)doc;
- (void)discardMemory;
#else
@property StatData *statistics, *transit;
@property TestResultCount testResultCnt;	// weekly total
@property (readonly) NSMutableArray<StatPanel *> *statPanels;
- (void)setPhaseInfo:(NSArray<NSNumber *> *)info;
- (void)setLabelInfo:(NSArray<NSString *> *)info;
- (void)phaseChangedTo:(NSInteger)lineNumber;
- (void)reviseColors;
- (void)openStatPanel:(NSWindow *)parentWindow;
- (void)flushPanels;
#endif
@end

#ifndef NOGUI
typedef struct {
	NSInteger idxBits, nIndexes, windowSize;
} TimeEvoInfo;

typedef enum {
	StatWhole, StatTimeEvo, StatPeriods, StatSpreaders
} StatType;

typedef enum {
	MskSusceptible = (1<<Susceptible),
	MskInfected = (1<<Asymptomatic),
	MskSymptomatic = (1<<Symptomatic),
	MskRecovered = (1<<Recovered),
	MskDied = (1<<Died),
	MskQrtnA = (1<<QuarantineAsym),
	MskQrtnS = (1<<QuarantineSymp),
	MskTestTotal = (1<<(TestTotal+NStateIndexes)),
	MskTestSym = (1<<(TestAsSymptom+NStateIndexes)),
	MskTestCon = (1<<(TestAsContact+NStateIndexes)),
	MskTestSus = (1<<(TestAsSuspected+NStateIndexes)),
	MskTestP = (1<<(TestPositive+NStateIndexes)),
	MskTestN = (1<<(TestNegative+NStateIndexes)),
	MskTestPRate = (1<<(TestPositiveRate+NStateIndexes)),
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
	NSButton *transitCBox;
	StatInfo *statInfo;
	TimeEvoInfo timeEvoInfo;
	BOOL isClosing;
}
- (instancetype)initWithInfo:(StatInfo *)info;
- (void)setupColorForCBoxes;
- (IBAction)flushView:(id)sender;
- (NSView *)view;
@end
#endif
NS_ASSUME_NONNULL_END
