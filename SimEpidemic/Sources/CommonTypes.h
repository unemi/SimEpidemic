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
	NIndexes,
	NHealthTypes = QuarantineAsym,
} HealthType;

typedef enum {
	WarpInside, WarpToHospital, WarpToCemeteryF, WarpToCemeteryH, WarpBack
} WarpType;

typedef struct {
	CGFloat min, max, mode;
} DistInfo;

typedef struct {
	CGFloat infec, infecDst; // infection probability and distance
	CGFloat qnsRt, qnsDl, qdsRt, qdsDl;	// Quarantine rate and delay
	CGFloat dstST, dstOB; // Distancing strength and obedience
	CGFloat mobFr; // Mobility frequency
	DistInfo mobDist; // and distance
	DistInfo incub, fatal, recov, immun; // incubation, fatality, recovery, immunity
} RuntimeParams;
typedef struct {
	NSInteger initPop, worldSize, mesh, nInitInfec, stepsPerDay;
} WorldParams;

#define PARAM_F1 infec
#define PARAM_D1 mobDist
#define PARAM_I1 initPop

typedef struct StatDataRec {
	struct StatDataRec *next;
	NSUInteger cnt[NIndexes];
} StatData;

typedef struct AgentRec {
	NSInteger ID;
	struct AgentRec *prev, *next;
	CGFloat app, prf, x, y, vx, vy, fx, fy;
	CGPoint orgPt;
	CGFloat daysI, daysD, daysToRecover, daysToOnset, daysToDie, imExpr;
	HealthType health, newHealth;
	BOOL distancing, isWarping, gotAtHospital;
	struct AgentRec *best;
	CGFloat bestDist;
} Agent;
