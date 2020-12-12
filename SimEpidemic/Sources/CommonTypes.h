//
//  CommonTypes.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/05.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

typedef enum {
	Susceptible, Asymptomatic, Symptomatic, Recovered, Died,
	QuarantineAsym, QuarantineSymp,
	NStateIndexes,
	NHealthTypes = QuarantineAsym,
} HealthType;

typedef enum {
	TestTotal,
	TestAsSymptom, TestAsContact, TestAsSuspected,
	TestPositive, TestNegative,
	TestPositiveRate,
	NAllTestTypes
} TestType;

#define NIntTestTypes TestPositiveRate
#define NIntIndexes (NStateIndexes+NIntTestTypes)
#define NAllIndexes (NStateIndexes+NAllTestTypes)

typedef enum {
	WarpInside, WarpToHospital, WarpToCemeteryF, WarpToCemeteryH, WarpBack
} WarpType;

typedef enum {
	LoopNone, LoopRunning, LoopFinished, LoopEndByUser,
	LoopEndByCondition, LoopEndAsDaysPassed, LoopEndByTimeLimit
} LoopMode;

typedef struct {
	CGFloat min, max, mode;
} DistInfo;

typedef struct {
	CGFloat mass, friction, avoidance, maxSpeed;
	CGFloat contagDelay, contagPeak; // contagion delay and peak;
	CGFloat infec, infecDst; // infection probability and distance
	CGFloat dstST, dstOB; // Distancing strength and obedience
	CGFloat mobFr; // Mobility frequency
	CGFloat gatFr; // Gathering's frequency
	CGFloat cntctTrc; // Contact tracing
	CGFloat tstDelay, tstProc, tstInterval, tstSens, tstSpec; // test delay, process, interval, sensitivity, and specificity
	CGFloat tstSbjAsy, tstSbjSym; // Subjects for test of asymptomatic, and symptomatic. contacts are tested 100%.
	DistInfo mobDist; // mass and warp distance
	DistInfo incub, fatal, recov, immun; // contagiousness, incubation, fatality, recovery, immunity
	DistInfo gatSZ, gatDR, gatST; // Event gatherings: size, duration, strength
	NSInteger step;
} RuntimeParams;
typedef struct {
	NSInteger initPop, worldSize, mesh, nInitInfec, stepsPerDay;
} WorldParams;

#define PARAM_F1 mass
#define PARAM_D1 mobDist
#define PARAM_I1 initPop
#define IDX_D 1000
#define IDX_I 2000

typedef struct StatDataRec {
	struct StatDataRec *next;
	NSUInteger cnt[NIntIndexes];
	CGFloat pRate;
} StatData;

typedef struct TestEntryRec {
	struct TestEntryRec *prev, *next;
	NSInteger timeStamp;
	BOOL isPositive;
	struct AgentRec *agent;
} TestEntry;

typedef struct ContactInfoRec {
	struct ContactInfoRec *prev, *next;
	NSInteger timeStamp;
	struct AgentRec *agent;
} ContactInfo;

@class Gathering;
typedef NSMutableDictionary<NSNumber *, NSMutableArray<Gathering *> *>
	GatheringMap;

typedef struct AgentRec {
	NSInteger ID;
	struct AgentRec *prev, *next;
	CGFloat app, prf, x, y, vx, vy, fx, fy;
	CGPoint orgPt;
	CGFloat daysInfected, daysDiseased;
	CGFloat daysToRecover, daysToOnset, daysToDie, imExpr;
	HealthType health, newHealth;
	int nInfects, newNInfects;
	BOOL distancing, isOutOfField, isWarping, gotAtHospital,
		inTestQueue;
	NSInteger lastTested;
	struct AgentRec *best;
	CGFloat bestDist, gatDist;
	ContactInfo *contactInfoHead, *contactInfoTail;
} Agent;
