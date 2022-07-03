//
//  CommonTypes.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/05.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//
#define VER_1_8

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
	TestPositive, TestNegative, //TestGivenUp,
	TestPositiveRate,
	NAllTestTypes,
	TestTotal = TestNone
} TestType;

#define MAX_N_VAXEN 8
#define MAX_N_VARIANTS 8
#define MAX_N_AGE_SPANS 12
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
	LoopPauseByCondition, LoopEndByCondition,
	LoopEndAsDaysPassed, LoopEndByTimeLimit
} LoopMode;

typedef enum {
	WrkPlcNone, WrkPlcUniform, WrkPlcCentered, WrkPlcPopDistImg
} WrkPlcMode;

typedef enum {
	VcnPrRandom, VcnPrOlder, VcnPrCentral, VcnPrPopDens, VcnPrBooster,
	VcnPrNone = -1
} VaccinePriority;
#define N_VCN_QUEQUE (VcnPrBooster+1)

typedef enum {
	TrcTst, TrcVcn, TrcBoth
} TracingOperation;

typedef struct {
	CGFloat min, max, mode;
} DistInfo;

typedef struct {
	CGFloat performRate, regularity;
	VaccinePriority priority;
} VaccinationInfo;

typedef struct {
	NSInteger upperAge;
	CGFloat rate;
} VaccinationRate;

typedef struct {
	CGFloat reproductivity, toxicity;
	CGFloat efficacy[MAX_N_VARIANTS];
} VariantInfo;

typedef struct {
	NSInteger interval;
	CGFloat efficacy[MAX_N_VARIANTS];
} VaccineInfo;

typedef struct {
	CGFloat mass, friction, avoidance, maxSpeed;
	CGFloat actMode, actKurt; // activeness as individuality
	CGFloat massAct, mobAct, gatAct; // bias for mobility and gatherings
	CGFloat incubAct, fatalAct, immuneAct;	// correlation
	CGFloat therapyEffc;	// therapy efficacy
	CGFloat contagDelay, contagPeak; // contagion delay and peak;
	CGFloat infec, infecDst; // infection probability and distance
	CGFloat dstST, dstOB; // Distancing strength and obedience
	CGFloat backHmRt; // probability per day for travelers to go back home
	CGFloat gatFr, gatRndRt;	// Gathering's frequency, random spot rate (%)
	CGFloat gatActiveBias;	// Activeness bias in gatherings (%)
	CGFloat cntctTrc; // Contact tracing
	CGFloat tstDelay, tstProc, tstInterval, tstSens, tstSpec; // test delay, process, interval, sensitivity, and specificity
	CGFloat tstSbjAsy, tstSbjSym; // Subjects for test of asymptomatic, and symptomatic. contacts are tested 100%.
	CGFloat tstCapa, tstDlyLim; // Test capacity (per 1,000 persons per day), test delay limit (days)
	CGFloat imnMaxDur, imnMaxDurSv, imnMaxEffc, imnMaxEffcSv;	// acquired immunity by infection
	DistInfo mobDist; // mass and warp distance
	DistInfo incub, fatal; // incubation, fatality
	DistInfo gatSZ, gatDR, gatST; // Event gatherings: size, duration, strength
	DistInfo mobFreq; // Participation frequency in long travel
	DistInfo gatFreq; // Participation frequency in gathering
	TracingOperation trcOpe; // How to treat the contacts, tests or vaccination, or both
	sint32 trcVcnType;	// vaccine type for tracing vaccination
	VaccinationInfo vcnInfo[MAX_N_VAXEN];
	VaccinationRate vcnFnlRt[MAX_N_AGE_SPANS];
	NSInteger step;
} RuntimeParams;

typedef struct {
	NSInteger initPop, worldSize, mesh, stepsPerDay;
	CGFloat infected, recovered;	// initial ratio in population
	CGFloat qAsymp, qSymp;	// initial ratio of separation for each health state
	CGFloat popDistMapLog2Gamma; // log_2 gamma correction for population density map
	CGFloat gatSpotFixed; // number of fixed gathering spots per population
	CGFloat avClstrRate, avClstrGran, avTestRate;	// Anti-Vax
	CGFloat rcvBias, rcvTemp; // coefficients to calculate recovery from age
	CGFloat rcvUpper, rcvLower; // boundaries of period to start recovery
	CGFloat vcn1stEffc, vcnMaxEffc, vcnEffcSymp;
	CGFloat	vcnEDelay, vcnEPeriod, vcnEDecay, vcnSvEffc; // standard vaccine efficacy
	CGFloat infecDistBias;	// coefficient for furthest distance of infection
	CGFloat contagBias; // exponent (%) for contageon
	WrkPlcMode wrkPlcMode;
} WorldParams;

#define PARAM_F1 mass
#define PARAM_D1 mobDist
#define PARAM_I1 initPop
#define PARAM_R1 infected
#define PARAM_E1 trcOpe
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
#ifndef NOGUI
	NSInteger type;	// random = 0, or regular = 1,2,...
#endif
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
	CGFloat firstDoseDate, agentImmunity;
	CGFloat massR;
	CGFloat mobFreq, gatFreq;	// frequency of participation in travel & gathering
	CGFloat age, activeness;
	CGFloat severity;
	HealthType health;
	int nInfects, virusVariant, vaccineType;
	BOOL distancing, isOutOfField, isWarping, inTestQueue, onRecovery;
	NSInteger lastTested;
	ContactInfo *contactInfoHead, *contactInfoTail;
	Gathering *gathering;
	ForVaccine forVcn;
// working memory
	CGFloat fx, fy;
	HealthType newHealth;
	int newNInfects;
	int ageSpanIndex;
	struct AgentRec *best;
	CGFloat bestDist, gatDist;
	BOOL gotAtHospital, vaccineTicket;
} Agent;
