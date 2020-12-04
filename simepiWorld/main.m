//
//  main.m
//  simepiWorld
//
//  Created by Tatsuo Unemi on 2020/11/11.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "main.h"
#import "Statistics.h"

Document *document;
char *inBuf = NULL;
ComLen inBufLen = 0;
NSInteger maxRuntime = 48*3600;
void terminateApp(int code) { exit(code); }
NSString *new_uniq_string(void) { return @"IDString"; } // dummy

void respond_ok(void) {
	ResponseOK res = {sizeof(ResponseOK), RspnsOK};
	write(1, &res, sizeof(res));
}
void respond_err(NSString *msg) {
	uint32 length = sizeof(ResponseAny) + (uint32)msg.length;
	ResponseError *res = malloc(length);
	res->length = length;
	res->type = RspnsError;
	memcpy(res->str, msg.UTF8String, msg.length);
	write(1, res, length);
	free(res);
}
void respond_JSON(NSObject *plist) {
	NSError *error;
	NSData *data = [NSJSONSerialization dataWithJSONObject:plist options:0 error:&error];
	if (data == nil) { respond_err(error.localizedDescription); return; }
	uint32 length = sizeof(ResponseAny) + (uint32)data.length;
	ResponseJSON *outBuf = malloc(length);
	outBuf->length = length;
	outBuf->type = RspnsJSON;
	memcpy(outBuf->str, data.bytes, data.length);
	write(1, outBuf, length);
	free(outBuf);
}
NSObject *object_from_JSON(ComWithData *c) {
	NSData *data = [NSData dataWithBytes:c->str length:c->length - sizeof(ComWithWorld)];
	NSError *error;
	NSObject *object = [NSJSONSerialization JSONObjectWithData:data
		options:0 error:&error];
	if (object == nil) respond_err(error.localizedDescription);
	return object;
}
static void get_params(void) {
	[document popLock];
	NSObject *plist = param_dict(document.runtimeParamsP, document.worldParamsP);
	[document popUnlock];
	respond_JSON(plist);
}
static void set_params(ComSetParams *c) {
	NSDictionary *plist = (NSDictionary *)object_from_JSON(c);
	if (plist == nil) return;
	[document popLock];
	set_params_from_dict(document.runtimeParamsP, document.tmpWorldParamsP, plist);
	[document popUnlock];
	respond_ok();
}
static void get_scenario(void) {
	[document popLock];
	NSObject *plist = [document scenarioPList];
	[document popUnlock];
	respond_JSON(plist);
}
static void set_scenario(ComSetScenario *c) {
	if (document.runtimeParamsP->step > 0 || document.running) {
		respond_err(@"setScenario command can be issued only before starting the simulation.");
		return;
	}
	NSArray *plist = (NSArray *)object_from_JSON(c);
	if (plist == nil) return;
	[document popLock];
	@try {
		[document setScenarioWithPList:plist];
		respond_ok();
	} @catch (NSString *msg) { respond_err(msg); }
	[document popUnlock];
}
int main(int argc, const char * argv[]) {
	document = Document.new;
	while (document != nil) @autoreleasepool {
		ComLen length;
		ssize_t sz = read(0, &length, sizeof(length));
		if (sz < sizeof(length)) break;
		if (length > inBufLen) {
			inBuf = realloc(inBuf, length);
			inBufLen = length;
		}
		ssize_t dataLen = length;
		*(ComLen *)inBuf = length;
		char *p = inBuf + sizeof(length);
		while ((dataLen -= sz) > 0) {
			sz = read(0, p, dataLen);
			p += sz;
		}
		BackEndCommand *c = (BackEndCommand *)inBuf;
		switch (c->any.command) {
			case CmndCloseWorld: respond_ok(); document = nil; break;
			case CmndGetParams: get_params(); break;
			case CmndSetParams: set_params((ComSetParams *)c); break;
			case CmndGetScenario: get_scenario(); break;
			case CmndSetScenario: set_scenario((ComSetScenario *)c); break;
			case CmndStart:
				[document start:c->start.stopAt maxSPS:c->start.maxSPS priority:-.1];
				respond_ok(); break;
			case CmndStep: [document step]; respond_ok(); break;
			case CmndStop: [document stop:LoopEndByUser]; respond_ok(); break;
			case CmndReset: [document resetPop]; respond_ok(); break;
			case CmndGetIndexes: get_indexes((ComGetIndexes *)c); break;
			case CmndGetDistribution: get_distribution((ComGetDistribution *)c); break;
			case CmndGetPopulation:
			case CmndMakeReporter:
			case CmndSetReporter: case CmndQuitReporter:
			default: break;
		}
	}
	return 0;
}
