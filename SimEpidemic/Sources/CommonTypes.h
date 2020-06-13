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
	CGFloat infec, infecDst, recovMean, recovSTD,
		incubPMin, incubPMax, incubPBias,
		diseaRt, imunMean, imunSTD;
	CGFloat qnsRt, qnsDl, qdsRt, qdsDl;	// Quarantine rate and delay
	CGFloat dstST, dstOB; // Distancing strength and obedience
	CGFloat mobFr, mobDs; // Mobility frequency and distance
	NSInteger initPop, worldSize, mesh, stepsPerDay, nInitInfec;
} Params;

typedef struct StatDataRec {
	struct StatDataRec *next;
	NSUInteger cnt[NIndexes];
} StatData;

typedef struct AgentRec {
	NSInteger ID;
	struct AgentRec *prev, *next;
	CGFloat app, prf, x, y, vx, vy, fx, fy;
	CGPoint orgPt;
	CGFloat daysI, daysD, daysToRecover, daysToDie, imExpr;
	HealthType health, newHealth;
	BOOL distancing, isWarping, gotAtHospital;
	struct AgentRec *best;
	CGFloat bestDist;
} Agent;
