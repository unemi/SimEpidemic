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
	CGFloat subjRem[MAX_N_VAXEN];
	NSInteger index[N_VCN_QUEQUE];
	NSInteger queue[1];
} VaccineQueueSave;

typedef struct {
	CGFloat app, prf, x, y, vx, vy;
	NSPoint orgPt;
	CGFloat daysInfected, daysDiseased, daysToCompleteRecov;
	CGFloat daysToRecover, daysToOnset, daysToDie, imExpr;
	CGFloat firstDoseDate, agentImmunity;
	CGFloat mass, mobFreq, gatFreq;
	CGFloat age, activeness;
	HealthType health;
	ForVaccine forVcn;
	int nInfects, virusVariant, vaccineType;
	BOOL distancing, isOutOfField, isWarping,
		inTestQueue;
	NSInteger lastTested;
} AgentSave;

extern NSString *fnParamsPList;
extern NSDictionary *plist_from_data(NSData *data);
extern NSMutableArray *mutablized_array_of_dicts(NSArray<NSDictionary *> *list);

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
