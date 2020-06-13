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

@interface MyCounter : NSObject
@property NSInteger cnt;
- (void)inc;
@end

@class Document, StatPanel, WarpInfo;
@interface StatInfo : NSObject {
	IBOutlet Document *doc;
	NSUInteger maxCounts[NIndexes], maxTransit[NIndexes];
	unsigned char *imgBm;
	NSInteger popSize, steps, skip, days, skipDays;
	StatData statCumm, transDaily, transCumm;
}
@property (readonly) NSMutableArray<StatPanel *> *statPanels;
@property (readonly) StatData *statistics, *transit;
@property (readonly) NSMutableArray<MyCounter *> *IncubPHist, *RecovPHist, *DeathPHist;
- (Document *)doc;
- (void)reviseColors;
- (void)reset:(NSInteger)nPop infected:(NSInteger)nInitInfec;
- (BOOL)calcStat:(Agent *_Nullable *_Nonnull)Pop nCells:(NSInteger)nCells
	qlist:(Agent *)qlist clist:(Agent *)clist warp:(NSArray<WarpInfo *> *)warp
	stepsPerDay:(NSInteger)stepsPerDay;
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
	MskTransit = (1<<NIndexes)
} IndexMask;

@interface StatView : NSView {
	IBOutlet StatPanel *statPanel;
}
@end

@interface StatPanel : NSWindowController <NSWindowDelegate> {
	IBOutlet NSPopUpButton *typePopUp;
	IBOutlet NSView *idxSelectionView;
	IBOutlet StatView *view;
	StatInfo *statInfo;
	NSInteger idxBits;
}
- (instancetype)initWithInfo:(StatInfo *)info;
- (IBAction)flushView:(id)sender;
@end

NS_ASSUME_NONNULL_END
