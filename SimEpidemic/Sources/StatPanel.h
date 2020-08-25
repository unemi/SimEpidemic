//
//  StatPanel.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/09.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CommonTypes.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct {
	NSInteger idxBits, nIndexes, windowSize;
} TimeEvoInfo;

typedef struct {
	NSUInteger positive, negative;
} TestResultCount;

@interface MyCounter : NSObject
@property NSInteger cnt;
- (void)inc;
@end

@interface ULinedButton : NSButton
@property NSColor *underLineColor;
@end

@class Document, StatPanel, WarpInfo;
@interface StatInfo : NSObject {
	IBOutlet Document *doc;
	NSUInteger maxCounts[NIntIndexes], maxTransit[NIntIndexes];
	unsigned char *imgBm;
	NSInteger popSize, steps, skip, days, skipDays;
	StatData statCumm, transDaily, transCumm;
	NSUInteger testCumm[NIntTestTypes];
	TestResultCount testResultsW[7];
	CGFloat maxStepPRate, maxDailyPRate, pRateCumm;
	NSArray<NSNumber *> *phaseInfo;	// line numbers of condition to run util ...
	NSMutableArray<NSNumber *> *scenarioPhases;	// step, p, s, ... p
}
@property (readonly) NSMutableArray<StatPanel *> *statPanels;
@property (readonly) StatData *statistics, *transit;
@property (readonly) TestResultCount testResultCnt;	// weekly total
@property (readonly) NSMutableArray<MyCounter *> *IncubPHist, *RecovPHist, *DeathPHist;
- (Document *)doc;
- (void)reviseColors;
- (void)reset:(NSInteger)nPop infected:(NSInteger)nInitInfec;
- (void)setPhaseInfo:(NSArray<NSNumber *> *)info;
- (void)phaseChangedTo:(NSInteger)lineNumber;
- (BOOL)calcStat:(Agent *_Nullable *_Nonnull)Pop nCells:(NSInteger)nCells
	qlist:(Agent *)qlist clist:(Agent *)clist warp:(NSArray<WarpInfo *> *)warp
	testCount:(NSUInteger *)testCount stepsPerDay:(NSInteger)stepsPerDay;
- (void)openStatPanel:(NSWindow *)parentWindow;
- (void)flushPanels;
@end

typedef enum {
	StatWhole, StatTimeEvo, StatPeriods
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
	StatInfo *statInfo;
	TimeEvoInfo timeEvoInfo;
	BOOL isClosing;
}
- (instancetype)initWithInfo:(StatInfo *)info;
- (IBAction)flushView:(id)sender;
@end

NS_ASSUME_NONNULL_END
