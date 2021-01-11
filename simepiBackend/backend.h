//
//  backend.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/11/09.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#ifndef backend_h
#define backend_h

#import "../SimEpidemic/Sources/CommonTypes.h"
#define UDP_SERVER_PORT 50100U
#define TCP_COMMAND_PORT 50101U

typedef enum {
	CmndNone,
	CmndMakeWorld, CmndCloseWorld,
	CmndGetParams, CmndSetParams,
	CmndGetScenario, CmndSetScenario,
	CmndStart, CmndStep, CmndStop, CmndReset,
	CmndGetIndexes, CmndGetDistribution, CmndGetPopulation,
	CmndMakeReporter, CmndSetReporter, CmndQuitReporter,
	CmndUpperLimit
} CommandType;

enum {
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
	MskReproRate = (1<<NAllIndexes),
	MskTransit = (1<<(NAllIndexes+1)),
	MskRunning = (1<<(NAllIndexes+2)),
	MskStep = (1<<(NAllIndexes+3)),
	MskDays = (1<<(NAllIndexes+4)),
};

enum {
	MskIncubasionPeriod = (1<<0),
	MskRecoveryPeriod = (1<<1),
	MskFatalPeriod = (1<<2),
	MskInfects = (1<<3)
};

enum {
	PopFormat1, PopFormat2
};

typedef uint16 ComLen;
#define WORLD_COM ComLen length; CommandType command; uint16 worldID;
typedef struct { ComLen length; CommandType command; } ComAny;
typedef struct { WORLD_COM } ComWithWorld;
typedef struct { WORLD_COM char str[1];	} ComWithData;
typedef ComAny ComMakeWorld;
typedef ComWithWorld ComCloseWorld;
typedef ComWithWorld ComGetParams;
typedef ComWithData ComSetParams;
typedef ComWithWorld ComGetScenario;
typedef ComWithData ComSetScenario;
typedef struct { WORLD_COM
	sint32 stopAt; float maxSPS;
} ComStart;
typedef ComWithWorld ComStop;
typedef ComWithWorld ComReset;
typedef struct { WORLD_COM
	uint32 nameFlag;
	sint32 fromStep;
} ComGetIndexes;
typedef struct { WORLD_COM
	uint32 nameFlag;
} ComGetDistribution;
typedef struct { WORLD_COM
	uint16 format;
} ComGetPopulation;
typedef struct { WORLD_COM
	float interval;	// report interval in seconds
	uint32 reports;	// bit flags for report items
} ComMakeReporter;
typedef ComMakeReporter ComSetReporter;
typedef struct { WORLD_COM
	uint16 reporterID;
} ComQuitReporter;

typedef union {
	ComAny any;
	ComWithWorld withWorld;
	ComMakeWorld makeWorld;
	ComCloseWorld closeWorld;
	ComGetParams getParams;
	ComSetParams setParams;
	ComGetScenario getScenario;
	ComSetScenario setScenario;
	ComStart start;
	ComStop stop;
	ComReset reset;
	ComGetIndexes getIndexes;
	ComGetDistribution getDist;
	ComGetPopulation getPop;
	ComMakeReporter makeReporter;
	ComSetReporter setReporter;
	ComQuitReporter quitReporter;
} BackEndCommand;

//

typedef enum {
	RspnsNone,
	RspnsOK, RspnsError,
	RspnsID, RspnsNotify,
	RspnsJSON,
	RspnsUpperLimit
} ResponseType;
typedef uint32 ResLen;
typedef struct {
	ResLen length; ResponseType type;
} ResponseAny;
typedef ResponseAny ResponseOK;
typedef struct {
	ResLen length; ResponseType type;
	char str[1];
} ResponseBytes;
typedef ResponseBytes ResponseError;
typedef struct {
	ResLen length; ResponseType type; uint32 worldID;
} ResponseID;
typedef struct {
	ResLen length; ResponseType type; uint16 reason;
} ResNotification;
typedef ResponseBytes ResponseJSON;

typedef union {
	ResponseAny any;
	ResponseOK ok;
	ResponseError error;
	ResponseID ID;
	ResNotification notify;
	ResponseJSON json;
} BackEndResponse;

#endif /* backend_h */
