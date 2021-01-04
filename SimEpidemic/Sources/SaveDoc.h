//
//  SaveDoc.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/12/14.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Document.h"

NS_ASSUME_NONNULL_BEGIN
typedef struct {
	NSUInteger cnt[NIntIndexes];
	CGFloat pRate;
} StatDataSave;

typedef struct {
	NSInteger timeStamp;
	BOOL isPositive;
	NSInteger agentID;
} TestEntrySave;

typedef struct {
	WarpType mode;
	CGPoint goal;
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
	CGFloat app, prf, x, y, vx, vy;
	CGPoint orgPt;
	CGFloat daysInfected, daysDiseased;
	CGFloat daysToRecover, daysToOnset, daysToDie, imExpr;
	CGFloat mobFreq, gatFreq;
	CGFloat activeness;
	HealthType health;
	int nInfects;
	BOOL distancing, isOutOfField, isWarping, gotAtHospital,
		inTestQueue;
	NSInteger lastTested;
} AgentSave;

extern NSString *fnParamsPList;
@interface Document (SaveDocExtension)
@end

NS_ASSUME_NONNULL_END
