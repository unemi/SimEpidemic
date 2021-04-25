//
//  CommonTypes.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/05.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//
#define VER_1_8
#define VER_1_8_3

typedef enum {
	Susceptible, Asymptomatic, Symptomatic, Recovered, Died,
	Vaccinated,	// added in ver.1.8.3
	QuarantineAsym, QuarantineSymp,
	NStateIndexes,
	NHealthTypes = QuarantineAsym,
} HealthType;

typedef enum {
	TestNone,
	TestAsSymptom, TestAsContact, TestAsSuspected,
	TestPositive, TestNegative,
	TestPositiveRate,
	NAllTestTypes,
	TestTotal = TestNone
} TestType;

#define NIntTestTypes TestPositiveRate
#define NIntIndexes (NStateIndexes+NIntTestTypes)
#define ReproductRate (NStateIndexes+NAllTestTypes)
#define NAllIndexes (ReproductRate+1)

typedef enum {
	WarpNone, WarpInside, WarpToHospital, WarpToCemeteryF, WarpToCemeteryH, WarpBack
} WarpType;

typedef enum {
	HistNone, HistIncub, HistRecov, HistDeath
} HistogramType;

typedef enum {
	LoopNone, LoopRunning, LoopFinished, LoopEndByUser,
	LoopEndByCondition, LoopEndAsDaysPassed, LoopEndByTimeLimit
} LoopMode;

typedef enum {
	WrkPlcNone, WrkPlcUniform, WrkPlcCentered, WrkPlcPopDistImg
} WrkPlcMode;

typedef enum {
	VcnPrRandom, VcnPrActive, VcnPrInactive, VcnPrCentral,
	VcnPrPopDens, VcnPrActAndCntr
} VaccinePriority;

typedef enum {
	TrcTst, TrcVcn, TrcBoth
} TracingOperation;

typedef struct {
	CGFloat min, max, mode;
} DistInfo;

typedef struct {
	CGFloat mass, friction, avoidance, maxSpeed;
	CGFloat actMode, actKurt; // activeness as individuality
	CGFloat massAct, mobAct, gatAct; // bias for mility and gatherings
	CGFloat incubAct, fatalAct, recovAct, immuneAct;	// correlation
	CGFloat contagDelay, contagPeak; // contagion delay and peak;
	CGFloat infec, infecDst; // infection probability and distance
	CGFloat dstST, dstOB; // Distancing strength and obedience
	CGFloat backHmRt; // probability per day for travelers to go back home
	CGFloat gatFr;	// Gathering's frequency
	CGFloat cntctTrc; // Contact tracing
	CGFloat tstDelay, tstProc, tstInterval, tstSens, tstSpec; // test delay, process, interval, sensitivity, and specificity
	CGFloat tstSbjAsy, tstSbjSym; // Subjects for test of asymptomatic, and symptomatic. contacts are tested 100%.
	CGFloat vcnPRate, vcn1stEff, vcnMaxEff, vcnEDelay, vcnEPeriod;	// vaccination
	DistInfo mobDist; // mass and warp distance
	DistInfo incub, fatal, recov, immun; // contagiousness, incubation, fatality, recovery, immunity
	DistInfo gatSZ, gatDR, gatST; // Event gatherings: size, duration, strength
	DistInfo mobFreq; // Participation frequency in long travel
	DistInfo gatFreq; // Participation frequency in gathering
	VaccinePriority vcnPri;	// vaccination priority
	TracingOperation trcOpe; // How to treat the contacts, tests or vaccination, or both
	NSInteger step;
} RuntimeParams;

typedef struct {
	NSInteger initPop, worldSize, mesh, stepsPerDay;
	CGFloat infected, recovered;	// initial ratio in population
	CGFloat qAsymp, qSymp;	// initial ratio of separation for each health state
	CGFloat vcnAntiRate, avClstrRate, avClstrGran, avTestRate;	// Anti-Vax
	WrkPlcMode wrkPlcMode;
} WorldParams;

#define PARAM_F1 mass
#define PARAM_D1 mobDist
#define PARAM_I1 initPop
#define PARAM_R1 infected
#define PARAM_E1 vcnPri
#define PARAM_H1 wrkPlcMode
#define IDX_D 1000
#define IDX_I 2000
#define IDX_R 3000
#define IDX_E 4000
#define IDX_H 5000

typedef struct {
	NSInteger susc, asym, symp, recv, died;
	NSInteger qAsym, qSymp;
} PopulationHConf;

typedef struct StatDataRec {
	struct StatDataRec *next;
	NSUInteger cnt[NIntIndexes];
	CGFloat pRate;	// Positive rate
	CGFloat reproRate;	// log2 of Reproduction rate
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

typedef struct GatheringRec {
	struct GatheringRec *prev, *next;
	CGFloat size, duration, strength;
	NSPoint p;
	NSInteger nAgents;
	struct AgentRec **agents;
} Gathering;

typedef enum {
	VcnAccept = 0,
	VcnReject = 1,
	VcnNoTest = 2
} ForVaccine;

typedef struct AgentRec {
	NSInteger ID;
	struct AgentRec *prev, *next;
	CGFloat app, prf, x, y, vx, vy;
	NSPoint orgPt;
	CGFloat daysInfected, daysDiseased;
	CGFloat daysToRecover, daysToOnset, daysToDie, imExpr;
	CGFloat mass;
	CGFloat mobFreq, gatFreq;	// frequency of participation in travel & gathering
	CGFloat activeness;
	HealthType health;
	int nInfects; //, virusType;
	BOOL distancing, isOutOfField, isWarping, inTestQueue;
	NSInteger lastTested;
	ContactInfo *contactInfoHead, *contactInfoTail;
	Gathering *gathering;
	ForVaccine forVcn;
// working memory
	CGFloat fx, fy;
	HealthType newHealth;
	int newNInfects;
	struct AgentRec *best;
	CGFloat bestDist, gatDist;
	CGFloat daysToCompleteRecov;
	BOOL gotAtHospital, vaccineTicket;
} Agent;

#define daysVaccinated daysInfected
#define agentImmunity daysDiseased
//
//typedef struct {
//	CGFloat infec, toxic;
//	CGFloat vcnEficacy;
//} VariantVirus;
