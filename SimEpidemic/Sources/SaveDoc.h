//
//  SaveDoc.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/12/14.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CommonTypes.h"
#ifdef NOGUI
#import "World.h"
#endif

NS_ASSUME_NONNULL_BEGIN
typedef struct {
	NSUInteger cnt[NIntIndexes];
	CGFloat pRate, reproRate;
} StatDataSave;

typedef struct {
	NSInteger timeStamp;
	BOOL isPositive;
	NSInteger agentID;
} TestEntrySave;

typedef struct {
	WarpType mode;
	NSPoint goal;
	NSInteger agentID;
} WarpInfoSave;

typedef struct {
	CGFloat size, duration, strength;
	NSPoint p;
	NSInteger nAgents;
	NSInteger agentIDs[1];	//
} GatheringSave;

typedef struct {
	NSInteger timeStamp;
	NSInteger agentID;
} ContactInfoSave;

typedef struct {
	CGFloat subjRem;
	NSInteger index;
	NSInteger list[1];
} VaccineListSaveOld1;

typedef struct {
	CGFloat subjRem;
	NSInteger index, lateIdx;
	NSInteger list[1];
} VaccineListSave;

typedef struct {
	CGFloat app, prf, x, y, vx, vy;
	NSPoint orgPt;
	CGFloat daysInfected, daysDiseased, daysToCompleteRecov;
	CGFloat daysToRecover, daysToOnset, daysToDie, imExpr;
	CGFloat mass, mobFreq, gatFreq;
	CGFloat activeness;
	HealthType health;
	int nInfects;
	BOOL distancing, isOutOfField, isWarping, gotAtHospital,
		inTestQueue;
	NSInteger lastTested;
} AgentSave;

extern NSString *fnParamsPList;

typedef enum {
	SaveOnlyParams = 0,
	SavePopulation = 1,
	SaveGUI = 2,
	SavePMap = 4
} SavePopFlags;

#ifdef NOGUI
@interface World (SaveDocExtension)
- (NSFileWrapper *)fileWrapperOfWorld;
- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper error:(NSError **)outError;
@end
#endif

NS_ASSUME_NONNULL_END
