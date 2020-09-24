//
//  ProcContext.m
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/09/10.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <sys/socket.h>
#import <os/log.h>
#import "ProcContext.h"
#import "noGUI.h"
#import "StatPanel.h"
#import "DataCompress.h"
#define BUFFER_SIZE 8192

static NSArray<NSString *> *commandList = nil;
static NSString *headerFormat = @"HTTP/1.1 %03d %@\nDate: %@\nServer: simepidemic\n\
%@Connection: keep-alive\n%@%@\n";

@implementation Document (TimeOutExtension)
- (void)expirationCheck:(NSTimer *)timer {
	if (theDocuments[self.ID] != self) return;
	NSTimeInterval nextCheck = documentTimeout;
	[self.lastTLock lock];
	if (!self.running) {
		NSDate *lastT = self.lastTouch;
		if (lastT == nil) nextCheck = 0.;
		else nextCheck += lastT.timeIntervalSinceNow;
	}
	self.lastTouch = nil;
	if (nextCheck > 0.) [NSTimer scheduledTimerWithTimeInterval:nextCheck target:self
		selector:@selector(expirationCheck:) userInfo:nil repeats:NO];
	else {
		os_log(OS_LOG_DEFAULT, "World %@ closed by timeout.", self.ID);
		[theDocuments removeObjectForKey:self.ID];
		if (self.docKey != nil) [defaultDocuments removeObjectForKey:self.docKey];
	}
	[self.lastTLock unlock];
}
@end

Document *make_new_world(NSString *type, NSNumber *ip4addr) {
	if (theDocuments.count >= maxNDocuments) @throw [NSString stringWithFormat:
		@"500 This server already have too many (%ld) worlds.", maxNDocuments];
	Document *doc = Document.new;
	theDocuments[doc.ID] = doc;
	[NSTimer scheduledTimerWithTimeInterval:documentTimeout target:doc
		selector:@selector(expirationCheck:) userInfo:nil repeats:NO];
	os_log(OS_LOG_DEFAULT,
		"%@ world %{network:in_addr}d:%@ was created. %ld world(s) in total.",
		type, ip4addr.intValue, doc.ID, theDocuments.count);
	return doc;
}
@implementation ProcContext
- (instancetype)initWithSocket:(int)dsc ip:(uint32)ipaddr {
	if (!(self = [super init])) return nil;
	desc = dsc;
	bufData = [NSMutableData dataWithLength:BUFFER_SIZE];
	ip4addr = @(ipaddr);
	if (commandList == nil) commandList = @[
		@"getWorldID", @"newWorld", @"closeWorld",
		@"getParams", @"setParams",
		@"start", @"step", @"stop", @"reset",
		@"getIndexes", @"getDistribution", @"getPopulation",
		@"getScenario", @"setScenario",
		@"submitJob", @"getJobStatus", @"getJobQueueStatus",
		@"stopJob", @"getJobResults"
	];
	return self;
}
- (long)receiveData:(NSInteger)length {
	unsigned char *buf = bufData.mutableBytes;
	dataLength = 0;
	do {
		long len = recv(desc, buf + dataLength, BUFFER_SIZE - 1 - dataLength, 0);
		if (len < 0) @throw @"recv command";
		else if (len == 0) break;
		dataLength += len;
	} while (dataLength < length);
	buf[dataLength] = '\0';
#ifdef DEBUG
	printf("---> %ld bytes.\n%s", dataLength, buf);
#endif
	return dataLength;
}
static void send_bytes(int desc, const char *bytes, NSInteger size) {
	ssize_t result = send(desc, bytes, size, 0);
	if (result < 0) @throw @(errno);
	else if (result < size) @throw @"send answer";
#ifdef DEBUG
	printf("<--- %ld bytes.\n", size);
	if (size < 512) {
		char buf[size + 1];
		memcpy(buf, bytes, size);
		for (NSInteger i = 0; i < size; i ++)
		if (buf[i] < ' ') switch (buf[i]) {
			case '\n': case '\t': break;
			default: buf[i] = '.';
		}
		buf[size] = '\0';
		printf("%s\n", buf);
	}
#endif
}
- (NSInteger)sendHeader {
	NSString *dateStr = [dateFormat stringFromDate:NSDate.date],
		*meaning = codeMeaning[@(code)];
	NSString *header = [NSString stringWithFormat:headerFormat, code,
		(meaning == nil)? @"" : meaning, dateStr,
		(fileSize == 0)? @"" : [NSString stringWithFormat:@"Content-Length: %ld\n", fileSize],
		(type == nil)? @"" : [NSString stringWithFormat:@"Content-Type: %@\n", type],
		(moreHeader == nil)? @"" : moreHeader];
	send_bytes(desc, header.UTF8String, header.length);
	return header.length;
}
- (NSInteger)sendData {
	if ([method isEqualToString:@"HEAD"]) return [self sendHeader];
	else if ([content isKindOfClass:NSInputStream.class]) {
		NSInteger length = [self sendHeader];
		NSInputStream *stream = (NSInputStream *)content;
		[stream open];
		@try {
			NSMutableData *data = [NSMutableData dataWithLength:BUFFER_SIZE];
			char *bytes = data.mutableBytes;
			NSInteger size;
			while ((size = [stream read:(uint8_t *)bytes maxLength:BUFFER_SIZE]) > 0)
				{ send_bytes(desc, bytes, size); length += size; }
		} @catch (NSObject *obj) { NSLog(@"%@", obj);  }
		[stream close];
		return length;
	} else {
		const char *bytes = NULL;
		if ([content isKindOfClass:NSData.class]) {
			fileSize = ((NSData *)content).length;
			bytes = ((NSData *)content).bytes;
		} else if ([content isKindOfClass:NSString.class]) {
			fileSize = ((NSString *)content).length;
			bytes = ((NSString *)content).UTF8String;
		} else return [self sendHeader];
		NSInteger length = [self sendHeader];
		for (NSInteger sizeLeft = fileSize; sizeLeft > 0; sizeLeft -= BUFFER_SIZE) {
			send_bytes(desc, bytes, (sizeLeft < BUFFER_SIZE)? sizeLeft : BUFFER_SIZE);
			bytes += BUFFER_SIZE;
		}
		return length + fileSize;
	}
}
- (void)notImplementedYet {
	code = 501;
	type = @"text/plain";
	content = @"Not implemented yet.";
}
- (void)setErrorMessage:(NSString *)msg {
	code = [msg substringToIndex:3].intValue;
	type = @"text/plain";
	content = msg;
}
- (void)setOKMessage {
	code = 200;
	type = @"text/plain";
	content = @"OK";
}
static NSString *bad_request_message(NSString *req) {
	NSString *shortend = (req.length < 20)? req :
		[[req substringToIndex:19] stringByAppendingString:@"…"];
	return [NSString stringWithFormat:@"400 Bad request: %@",
		[shortend stringByReplacingOccurrencesOfString:@"\r\n" withString:@"⤶"]];
}
- (void)respondFile:(NSString *)path {
	NSError *error;
	NSString *exPath = [fileDirectory stringByAppendingString:path];
	@try {
		NSString *ext = path.pathExtension;
		type = extToMime[ext];
		if (type == nil) @throw [NSString stringWithFormat:
			@"415 It doesn't support the path extension: %@.", ext];
		NSDictionary *attr =
			[NSFileManager.defaultManager attributesOfItemAtPath:exPath error:&error];
		if (attr == nil) @throw error;
		NSNumber *num = attr[NSFileSize];
		if (num == nil) @throw @"500 Couldn't get the file size.";
		fileSize = num.integerValue;
		NSDate *modDate = attr[NSFileModificationDate];
		if (modDate != nil) moreHeader = [NSString stringWithFormat:
			@"Last-Modified: %@\n", [dateFormat stringFromDate:modDate]];
		if ([method isEqualToString:@"HEAD"]) content = nil;
		else if (fileSize < BUFFER_SIZE) {
			content = [NSData dataWithContentsOfFile:exPath options:0 error:&error];
			if (content == nil) @throw error;
		} else {
			content = [NSInputStream inputStreamWithFileAtPath:exPath];
			if (content == nil) @throw @"500 Couldn't make an input stream.";
		}
		code = 200;
	} @catch (NSError *error) {
		@throw [NSString stringWithFormat:
			@"404 File access denied: \"%@\" %@", exPath, error.localizedDescription];
	} @catch (NSString *msg) { @throw msg; }
}
static NSDictionary<NSString *, NSString *> *header_dictionary(NSString *headerStr) {
	NSMutableDictionary<NSString *, NSString *> *headers = NSMutableDictionary.new;
	for (NSString *entry in [headerStr componentsSeparatedByString:@"\r\n"]) {
		NSScanner *sc = [NSScanner scannerWithString:entry];
		NSString *name;
		if ([sc scanUpToString:@": " intoString:&name])
			headers[name] = [entry substringFromIndex:sc.scanLocation + 2];
	}
	return headers;
}
- (void)makeResponse {
	printf("makeResponse 1\n");
	content = moreHeader = nil;
	NSString *req = [NSString stringWithUTF8String:bufData.bytes];
	NSScanner *scan = [NSScanner scannerWithString:req];
	NSString *request, *command, *optionStr, *JSONStr = nil;
	@try {
		NSString *methodName;
		if (![scan scanUpToString:@" " intoString:&methodName])
			@throw bad_request_message(req);
		[scan scanCharactersFromSet:NSCharacterSet.whitespaceCharacterSet intoString:NULL];
		if (![scan scanUpToString:@" " intoString:&request])
			@throw bad_request_message(req);
		method = methodName;
		if ([method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"]) {
			if ([request isEqualToString:@"/"])
				{ [self respondFile:@"index.html"]; @throw @0; }
			scan = [NSScanner scannerWithString:request];
			[scan scanCharactersFromSet:
				[NSCharacterSet characterSetWithCharactersInString:@"/"] intoString:NULL];
			if (![scan scanUpToString:@"?" intoString:&command])
				@throw bad_request_message(req);
			if (command.pathExtension.length > 0)
				{ [self respondFile:command]; @throw @0; }
			else optionStr = scan.atEnd? nil :
				[request substringFromIndex:scan.scanLocation + 1];
		} else if ([method isEqualToString:@"POST"]) {
			command = [request hasPrefix:@"/"]?
				[request substringFromIndex:1] : request;
			[scan scanUpToString:@"\r\n" intoString:NULL];
			NSString *headerStr;
			if (![scan scanUpToString:@"\r\n\r\n" intoString:&headerStr])
				@throw bad_request_message(req);
			NSDictionary<NSString *, NSString *> *headers = header_dictionary(headerStr);
			NSString *contentType = headers[@"Content-Type"];
			if (contentType == nil) @throw @"411 No content type indicated.";
			NSString *numStr = headers[@"Content-Length"];
			if (numStr == nil) @throw @"411 No content length indicated.";
			NSInteger contentLength = numStr.integerValue;
			if (contentLength > BUFFER_SIZE - 1) @throw @"413 Payload is too large.";
			[self receiveData:contentLength];
			if ([contentType isEqualToString:@"application/x-www-form-urlencoded"])
				optionStr = [NSString stringWithUTF8String:bufData.bytes];
			else if ([contentType hasPrefix:@"multipart/form-data"]) {
				scan = [NSScanner scannerWithString:contentType];
				[scan scanUpToString:@"boundary=" intoString:NULL];
				if (scan.atEnd) @throw @"417 No boundary string specified.";
				NSString *boundary =
					[contentType substringFromIndex:scan.scanLocation + 9];
				scan = [NSScanner scannerWithString:
					[NSString stringWithUTF8String:bufData.bytes]];
				[scan scanUpToString:@"Content-Disposition: " intoString:NULL];
				[scan scanUpToString:@"name=" intoString:NULL];
				if (scan.atEnd) @throw @"417 No name specified.";
				NSString *nameOptionStr, *fileOptionStr;
				[scan scanUpToString:@";" intoString:&nameOptionStr];
				[scan scanUpToString:@"filename=" intoString:NULL];
				if (scan.atEnd) @throw @"417 No filename specified.";
				[scan scanUpToString:@"\r\n" intoString:&fileOptionStr];
				optionStr = [[NSString stringWithFormat:@"%@&%@",
					nameOptionStr, fileOptionStr]
					stringByReplacingOccurrencesOfString:@"\"" withString:@""];
				[scan scanUpToString:@"Content-Type: application/json" intoString:NULL];
				if (scan.atEnd) @throw @"417 No JSON data received.";
				[scan scanUpToString:@"\r\n\r\n" intoString:NULL];
				if (scan.atEnd) @throw @"417 No JSON data provided.";
				if (![scan scanUpToString:boundary intoString:&JSONStr])
					@throw @"417 JSON data is empty.";
				if ([JSONStr hasSuffix:@"--"])
					JSONStr = [JSONStr substringToIndex:JSONStr.length - 2];
			} else @throw [NSString stringWithFormat:
				@"415 Unexpected content-type: %@", contentType];
		} else @throw
			[NSString stringWithFormat:@"405 \"%@\" method is not allowed.", method];
		if (![commandList containsObject:command]) {
			@throw [@"404 Unknown command: " stringByAppendingString:command];
		} else if ([method isEqualToString:@"HEAD"]) [self setOKMessage];
		else {
			if (optionStr == nil) query = nil;
			else {
				NSArray<NSString *> *opArray = [optionStr componentsSeparatedByString:@"&"];
				NSInteger n = opArray.count, m = n + ((JSONStr != nil)? 1 : 0);
				if (m > 0) {
					NSString *keys[m], *objs[m];
					for (NSInteger i = 0; i < n; i ++) {
						NSArray *opPair = [opArray[i] componentsSeparatedByString:@"="];
						keys[i] = opPair[0];
						objs[i] = (opPair.count > 1)? opPair[1] : @"";
					}
					if (JSONStr != nil) { keys[n] = @"JSON"; objs[n] = JSONStr; }
					query = [NSDictionary dictionaryWithObjects:objs forKeys:keys count:m];
				} else query = nil;
			}
			[self performSelector:NSSelectorFromString(command)];
			if (content == nil) [self setOKMessage];
		}
	} @catch (NSString *info) { [self setErrorMessage:info];
	} @catch (NSNumber *num) {}
//
	NSInteger length = [self sendData];
	char *p = bufData.mutableBytes;
	NSInteger idx = 0;
	for (; idx < 80; idx ++) if (p[idx] < ' ') { p[idx] = '\0'; break; }
	if (idx >= 80) memcpy(p + idx, "...", 4);
	os_log(OS_LOG_DEFAULT, "%d %ld %{network:in_addr}d %s",
		code, length, ip4addr.intValue, p);
}
- (void)checkDocument {
	NSString *worldID = query[@"world"];
	if (worldID == nil) worldID = query[@"name"];
	if (worldID == nil || [worldID isEqualToString:@"default"]) {
		document = defaultDocuments[ip4addr];
		if (document == nil || ![document touch]) {
			document = make_new_world(@"Default", ip4addr);
			defaultDocuments[ip4addr] = document;
			document.docKey = ip4addr;
		}
	} else {
		document = theDocuments[worldID];
		if (document == nil) @throw [NSString stringWithFormat:
			@"500 World of ID %@ doesn't exist.", worldID];
	}
}
- (NSUInteger)JSONOptions {
	NSString *valueStr = query[@"format"];
	return (valueStr == nil)? JSONOptions : valueStr.integerValue;
}
- (void)setJSONDataAsResponse:(NSObject *)object {
	NSError *error;
	content = [NSJSONSerialization dataWithJSONObject:object 
		options:self.JSONOptions error:&error];
	if (content == nil) @throw [NSString stringWithFormat:
		@"500 Couldn't make a JSON data: %@", error.localizedDescription];
	type = @"application/json";
	code = 200;
}
- (void)getInfo:(NSObject *)plist {
	[self checkDocument];
	NSString *savePath = query[@"save"];
	if (savePath != nil) {
		NSString *extension = @"json";
		moreHeader = [NSString stringWithFormat:
			@"Content-Disposition: attachment; filename=\"%@\"\n",
			[[savePath pathExtension] isEqualToString:extension]? savePath :
			[savePath stringByAppendingPathExtension:extension]];
	}
	[self setJSONDataAsResponse:plist];
}
- (void)setWorldIDAsResponse {
	content = document.ID;
	type = @"text/plain";
	code = 200;
}
- (void)getWorldID {
	[self checkDocument];
	[self setWorldIDAsResponse];
}
- (void)newWorld {
	document = make_new_world(@"New", ip4addr);
	[self setWorldIDAsResponse];
}
- (void)closeWorld {
	NSString *worldID = query[@"world"];
	if (worldID == nil) @throw @"417 World ID is missing.";
	Document *doc = theDocuments[worldID];
	if (doc == nil) @throw [NSString stringWithFormat:
		@"500 World of ID %@ doesn't exist.", worldID];
	else if (doc.docKey != nil)
		@throw @"500 It's not allowed to close a default world.";
	else [theDocuments removeObjectForKey:worldID];
}
- (void)getParams {
	[self checkDocument];
	[document popLock];
	NSObject *plist = param_dict(document.runtimeParamsP, document.worldParamsP);
	[document popUnlock];
	[self getInfo:plist];
}
- (void)setParams {
	[self checkDocument];
	NSDictionary *dict = nil;
	NSString *JSONstr = query[@"JSON"];
	if (JSONstr != nil) {
		NSError *error;
		NSData *data = [JSONstr dataUsingEncoding:NSUTF8StringEncoding];
		dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
		if (dict == nil) @throw [NSString stringWithFormat:
			@"417 Failed to interprete JSON data: %@", error.localizedDescription];
		if (![dict isKindOfClass:NSDictionary.class])
			@throw @"417 JSON data doesn't represent a dictionary.";
	} else dict = query;
#ifdef DEBUG
printf("--- parameters\n%s\n", dict.description.UTF8String);
#endif
	[document popLock];
	RuntimeParams *rp = document.runtimeParamsP;
	WorldParams *wp = (rp->step == 0)?
		document.worldParamsP : document.tmpWorldParamsP;
	set_params_from_dict(rp, wp, dict);
	NSInteger popSize = wp->initPop;
	if (popSize > maxPopSize) wp->initPop = maxPopSize;
	[document popUnlock];
	if (popSize > maxPopSize) @throw [NSString stringWithFormat:
		@"200 The specified population size %ld is too large.\
It was adjusted to maxmimum value: %ld.", popSize, maxPopSize];
}
- (void)start {
	[self checkDocument];
	NSString *opStr = query[@"stopAt"];
	Document *doc = document;
	in_main_thread(^{ [doc start:(opStr == nil)? 0 : opStr.integerValue]; });
}
- (void)step { [self checkDocument]; [document step]; }
- (void)stop {
	[self checkDocument];
	Document *doc = document;
	in_main_thread(^{ [doc stop]; });
}
- (void)reset { [self checkDocument]; [document resetPop]; }
static NSObject *make_history(StatData *st, NSInteger nItems,
	NSNumber *(^getter)(StatData *)) {
	if (nItems == 1 && st != NULL) return getter(st);
	NSMutableArray *ma = NSMutableArray.new;
	for (NSInteger i = 0; i < nItems && st != NULL; i ++, st = st->next)
		[ma insertObject:getter(st) atIndex:0];
	return ma;
}
- (void)collectNamesInto:(NSMutableSet *)nameSet {
	NSError *error;
	NSString *arrStr = [query[@"names"] stringByRemovingPercentEncoding];
	NSData *data = [arrStr dataUsingEncoding:NSUTF8StringEncoding];
	NSArray *array = [NSJSONSerialization JSONObjectWithData:data
		options:0 error:&error];
	if (array == nil) @throw [NSString stringWithFormat:
		@"417 %@", error.localizedDescription];
	if (![array isKindOfClass:NSArray.class])
		@throw @"417 Index name list must be an array of strings.";
	[nameSet addObjectsFromArray:array];
}
- (void)getIndexes {
	[self checkDocument];
	NSInteger fromDay = MAX_INT32, fromStep = MAX_INT32, daysWindow = 0;
	NSMutableSet *idxNames = NSMutableSet.new;
	for (NSString *key in query.keyEnumerator) {
		if ([key isEqualToString:@"names"])
			[self collectNamesInto:idxNames];
		else if ([key isEqualToString:@"fromDay"]) {
			fromDay = query[key].integerValue;
		} else if ([key isEqualToString:@"fromStep"]) {
			fromStep = query[key].integerValue;
		} else if ([key isEqualToString:@"window"]) {
			daysWindow = query[key].integerValue;
		} else if (query[key].integerValue != 0)
			[idxNames addObject:key];
	}
	if (idxNames.count == 0) @throw @"417 Index name is not sepcified.";
	RuntimeParams *rp = document.runtimeParamsP;
	WorldParams *wp = document.worldParamsP;
	if (fromDay != MAX_INT32) fromStep = fromDay * wp->stepsPerDay;
	else if (fromStep != MAX_INT32) fromDay = fromStep / wp->stepsPerDay;
	NSInteger nDays, nSteps;
	nSteps = (fromStep < 0)? -fromStep :
		(rp->step < fromStep)? 1 : rp->step - fromStep + 1;
	nDays = (fromDay == MAX_INT32)? 1 : (nSteps + wp->stepsPerDay - 1) / wp->stepsPerDay;
	NSMutableDictionary *md = NSMutableDictionary.new;
	StatInfo *statInfo = document.statInfo;
	StatData *statData = (daysWindow == 0)? statInfo.statistics : statInfo.transit;
	NSInteger nItems = (daysWindow == 0)?
		(nSteps - 1) / statInfo.skipSteps + 1 : (nDays - 1) / statInfo.skipDays + 1;
	[document popLock];
	for (NSString *idxName in idxNames) {
		if ([idxName isEqualToString:@"isRunning"])
			md[idxName] = @(document.running);
		else if ([idxName isEqualToString:@"step"]) md[idxName] = @(rp->step);
		else if ([idxName isEqualToString:@"days"])
			md[idxName] = @((CGFloat)rp->step / wp->stepsPerDay);
		else if ([idxName isEqualToString:@"testPositiveRate"])
			md[idxName] = make_history(statData, nItems,
				^(StatData *st) { return @(st->pRate); });
		else {
			NSNumber *num = indexNames[idxName];
			if (num != nil) {
				NSInteger idx = num.integerValue;
				md[idxName] = make_history(statData, nItems,
					^(StatData *st) { return @(st->cnt[idx]); });
	}}}
	[document popUnlock];
	if (md.count == 0) @throw @"417 No valid index names are specified.";
	[self setJSONDataAsResponse:md];
}
- (void)getDistribution {
	[self checkDocument];
	StatInfo *statInfo = document.statInfo;
	NSDictionary<NSString *, NSArray<MyCounter *> *> *nameMap =
		@{@"incubasionPeriod":statInfo.IncubPHist,
		@"recoveryPeriod":statInfo.RecovPHist,
		@"fatalPeriod":statInfo.DeathPHist,
		@"infects":statInfo.NInfectsHist };
	NSMutableSet *distNames = NSMutableSet.new;
	for (NSString *key in query.keyEnumerator) {
		if ([key isEqualToString:@"names"])
			[self collectNamesInto:distNames];
		else if (query[key].integerValue != 0)
			[distNames addObject:key];
	}
	if (distNames.count == 0) @throw @"417 Distribution name is not sepcified.";
	NSMutableDictionary *md = NSMutableDictionary.new;
	[document popLock];
	for (NSString *distName in distNames) {
		NSArray<MyCounter *> *hist = nameMap[distName];
		if (hist == nil) continue;
		NSMutableArray *ma = NSMutableArray.new;
		NSInteger st = -1, n = hist.count;
		for (NSInteger i = 0; i < n; i ++) {
			NSInteger cnt = hist[i].cnt;
			if (st == -1 && cnt > 0) [ma addObject:@((st = i))];
			if (st >= 0) [ma addObject:@(cnt)];
		}
		md[distName] = ma;
	}
	[document popUnlock];
	if (md.count == 0) @throw @"417 No valid distribution names are specified.";
	[self setJSONDataAsResponse:md];
}
static uint32 int_coord(CGFloat x, NSInteger worldSize) {
	return x * 10000 / worldSize;
}
static int store_agent_xyh(Agent *a, uint8 *buf, NSInteger worldSize) {
//	uint16 xy[2] = { a->x * 0x3fff / worldSize, a->y * 0x3fff / worldSize };
//	xy[0] |= (a->health & 0x0c) << 12;
//	xy[1] |= (a->health & 0x03) << 14;
//	memcpy(buf, xy, 4);
	return sprintf((char *)buf, "[%d,%d,%d],",
		int_coord(a->x, worldSize), int_coord(a->y, worldSize), a->health);
}
- (void)getPopulation {
	[self checkDocument];
	[document popLock];
	WorldParams *wp = document.worldParamsP;
	Agent **pop = document.Pop;
	NSInteger popSize = wp->initPop, nGrids = wp->mesh * wp->mesh,
		bufSize = popSize * 14 + 4;
	NSMutableData *srcData = [NSMutableData dataWithLength:bufSize];
	uint8 *buf = srcData.mutableBytes, *p = buf + 1;
	buf[0] = '[';
	uint32 nAgents = 0;
	for (NSInteger i = 0; i < nGrids; i ++)
		for (Agent *a = pop[i]; a != NULL; a = a->next, nAgents ++)
			p += store_agent_xyh(a, p, wp->worldSize);
	for (Agent *a = document.QList; a != NULL; a = a->next, nAgents ++)
		p += store_agent_xyh(a, p, wp->worldSize);
	for (Agent *a = document.CList; a != NULL; a = a->next, nAgents ++)
		p += store_agent_xyh(a, p, wp->worldSize);
	for (WarpInfo *info in document.WarpList) {
		Agent *a = info.agent;
		p += sprintf((char *)p, "[%d,%d,%d,%d,%d,%d],",
			int_coord(a->x, wp->worldSize), int_coord(a->y, wp->worldSize), a->health,
			int_coord(info.goal.x, wp->worldSize), int_coord(info.goal.y, wp->worldSize),
			info.mode);
		nAgents ++;
	}
	[document popUnlock];
	NSInteger srcSize = p - buf;
	if (nAgents > 0) p[-1] = ']';
	else { buf[1] = ']'; srcSize = 2; }
	srcData.length = srcSize;
	@try {
		NSData *dstData = [srcData zippedData];
#ifdef DEBUG
printf("%d agents -> %ld bytes\n", nAgents, dstData.length);
#endif
		content = dstData;
		type = @"application/json";
		moreHeader = @"Content-Encoding: deflate\n";
		code = 200;
	} @catch (NSNumber *errNum) {
		@throw [NSString stringWithFormat:
			@"500 Compression error (%d).", errNum.intValue];
	}
}
- (void)getScenario {
	[self checkDocument];
	[document popLock];
	NSObject *plist = [document scenarioPList];
	[document popUnlock];
	[self getInfo:plist];
}
- (void)setScenario {
	[self checkDocument];
	if (document.runtimeParamsP->step > 0 || document.running)
		@throw @"500 setScenario command can be issued only before starting the simulation.";
	NSString *source = query[@"scenario"];
	if (source == nil) source = query[@"JSON"];
	if (source == nil) @throw @"417 Scenario data is missing.";
	NSData *data = [[source stringByRemovingPercentEncoding]
		dataUsingEncoding:NSUTF8StringEncoding];
	NSError *error;
	NSArray *plist = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if (plist == nil) @throw [NSString stringWithFormat:
		@"417 Failed to interprete JSON data: %@", error.localizedDescription];
	if (![plist isKindOfClass:NSArray.class])
		@throw @"417 JSON data doesn't represent an array form.";
	@try { [document setScenarioWithPList:plist]; }
	@catch (NSString *msg) { @throw [@"500 " stringByAppendingString:msg]; }
}
@end