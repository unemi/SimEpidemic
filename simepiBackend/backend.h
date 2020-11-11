//
//  backend.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/11/09.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#ifndef backend_h
#define backend_h

#define UDP_SERVER_PORT 50100U
#define TCP_COMMAND_PORT 50101U

typedef enum {
	CmndNone,
	CmndMakeWorld, CmndBindWorld, CmndCloseWorld,
	CmndGetParams, CmndSetParams,
	CmndGetScenario, CmndSetScenario,
	CmndStart, CmndStep, CmndStop, CmndReset,
	CmndGetIndexes, CmndGetDistribution, CmndGetPopulation,
	CmndSetReporter, CmndStopReporter,
	CmndUpperLimit
} CommandType;

typedef uint16 ComLen;
typedef struct {
	ComLen length; CommandType command;
} ComAny;
typedef ComAny ComMakeWorld;
typedef struct {
	ComLen length; CommandType command; uint16 worldID;
} ComBindWorld;
typedef ComAny ComCloseWorld;
typedef ComAny ComGetParams;
typedef struct {
	ComLen length; CommandType command;
	char str[32];
} ComSetParams;
typedef ComGetParams ComGetScenario;
typedef ComSetParams ComSetScenatio;
typedef struct {
	ComLen length; CommandType command;
	sint32 stopAt; float maxSPS;
} ComStart;
typedef ComAny ComStop;
typedef ComAny ComReset;
typedef ComGetParams ComGetIndexes;
typedef ComGetParams ComGetDistribution;
typedef struct {
	ComLen length; CommandType command;
	uint16 type;
} ComGetPopulation;

typedef union {
	ComAny any;
	ComMakeWorld makeWorld;
	ComBindWorld bindWorld;
	ComCloseWorld closeWorld;
	ComGetParams getParams;
	ComSetParams setParams;
	ComGetScenario getScenario;
	ComSetScenatio setScenario;
	ComStart start;
	ComStop stop;
	ComReset reset;
	ComGetIndexes getIndexes;
	ComGetDistribution getDist;
	ComGetPopulation getPop;
} BackEndCommand;

//

typedef enum {
	RspnsNone,
	RspnsOK, RspnsError,
	RspnsWorldID, RspnsNotify,
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
} ResponseWorldID;
typedef struct {
	ResLen length; ResponseType type; uint16 reason;
} ResNotification;
typedef ResponseBytes ResponseJSON;

typedef union {
	ResponseAny any;
	ResponseOK ok;
	ResponseError error;
	ResponseWorldID worldID;
	ResNotification notify;
	ResponseJSON json;
} BackEndResponse;

#endif /* backend_h */
