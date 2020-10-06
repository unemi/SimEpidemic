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
#import "Document.h"
#import "StatPanel.h"
#import "DataCompress.h"
#define BUFFER_SIZE 8192
#define MAX_INT32 0x7fffffff

static NSArray<NSString *> *commandList = nil;
static NSString *headerFormat = @"HTTP/1.1 %03d %@\nDate: %@\nServer: simepidemic\n\
%@Connection: keep-alive\n%@%@\n";

@implementation NSString (IndexNameExtension)
- (NSString *)stringByRemovingFirstWord {
	NSInteger len = self.length;
	unichar uc[len];
	[self getCharacters:uc range:(NSRange){0, len}];
	NSInteger i;
	for (i = 1; i < len; i ++)
		if (uc[i] >= 'A' && uc[i] <= 'Z') break;
	if (i >= len) return self;
	uc[i] += 'a' - 'A';
	return [NSString stringWithCharacters:uc + i length:len - i];
}
- (NSString *)stringByAddingFirstWord:(NSString *)word {
	NSInteger wLen = word.length, myLen = self.length;
	unichar uc[wLen + myLen];
	[word getCharacters:uc range:(NSRange){0, wLen}];
	[self getCharacters:uc + wLen range:(NSRange){0, myLen}];
	if (uc[wLen] >= 'a' && uc[wLen] <= 'z') uc[wLen] -= 'a' - 'A';
	return [NSString stringWithCharacters:uc length:wLen + myLen];
}
@end

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

Document *make_new_world(NSString *type, NSString * _Nullable browserID) {
	if (theDocuments.count >= maxNDocuments) @throw [NSString stringWithFormat:
		@"500 This server already have too many (%ld) worlds.", maxNDocuments];
	Document *doc = Document.new;
	if (browserID != nil) {
		theDocuments[doc.ID] = doc;
		[NSTimer scheduledTimerWithTimeInterval:documentTimeout target:doc
			selector:@selector(expirationCheck:) userInfo:nil repeats:NO];
		os_log(OS_LOG_DEFAULT,
			"%@ world %@ was created for %@. %ld world(s) in total.",
			type, doc.ID, browserID, theDocuments.count);
	} else os_log(OS_LOG_DEFAULT, "%@ world %@ was created.", type, doc.ID);
	return doc;
}
@implementation ProcContext
- (instancetype)initWithSocket:(int)dsc ip:(uint32)ipaddr {
	if (!(self = [super init])) return nil;
	desc = dsc;
	bufData = [NSMutableData dataWithLength:BUFFER_SIZE];
	ip4addr = ipaddr;
	if (commandList == nil) commandList = @[
		@"getWorldID", @"newWorld", @"closeWorld",
		@"getParams", @"setParams",
		@"start", @"step", @"stop", @"reset",
		@"getIndexes", @"getDistribution", @"periodicReport", @"getPopulation",
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
	printf("(%d)-> %ld bytes.\n%s", desc, dataLength, buf);
#endif
	if (dataLength > 0) {
		if (length < 0) {
			char b[128];
			memcpy(b, buf, 120);
			NSInteger i;
			for (i = 0; i < 120; i ++) {
				if (b[i] == '\r' || b[i] == '\n') { b[i] = '\0'; break; }
				else if (b[i] < ' ') b[i] = ' ';
			}
			if (i == 120) memcpy(b + 119, "...", 4);
			os_log(OS_LOG_DEFAULT, "Received %s from IP=%{network:in_addr}d", b, ip4addr); 
		} else os_log(OS_LOG_DEFAULT, "Received %ld bytes from IP=%{network:in_addr}d",
			dataLength, ip4addr);
	}
	return dataLength;
}
static void send_bytes(int desc, const char *bytes, NSInteger size) {
	if (desc < 0) return;
	ssize_t result = send(desc, bytes, size, 0);
	if (result < 0) @throw @(errno);
	else if (result < size) @throw @"send answer";
#ifdef DEBUG
	printf("(%d)<- %ld bytes.\n", desc, size);
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
static void send_large_data(int desc, const char *bytes, NSInteger size) {
	if (desc < 0) return;
	for (NSInteger sizeLeft = size; sizeLeft > 0; sizeLeft -= BUFFER_SIZE) {
		send_bytes(desc, bytes, (sizeLeft < BUFFER_SIZE)? sizeLeft : BUFFER_SIZE);
		bytes += BUFFER_SIZE;
	}
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
		send_large_data(desc, bytes, fileSize);
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
	os_log(OS_LOG_DEFAULT, "Responded code=%d size=%ld to %@ IP=%{network:in_addr}d",
		code, length, (browserID == nil)? @"-" : browserID, ip4addr);
}
static NSString *ip4_string(uint32 ip4addr) {
	uint32 a = EndianU32_BtoN(ip4addr);
	return [NSString stringWithFormat:@"%d.%d.%d.%d",
		a >> 24, (a >> 16) & 0xff, (a >> 8) & 0xff, a & 0xff];
}
- (void)checkDocument {
	NSString *brwsID = query[@"me"], *worldID = query[@"world"];
	if (brwsID != nil) browserID = brwsID;
	if (worldID == nil) worldID = query[@"name"];
	if (worldID == nil || [worldID isEqualToString:@"default"]) {
		document = defaultDocuments[browserID];
		if (document == nil || ![document touch]) {
			if (browserID == nil) browserID = ip4_string(ip4addr);
			document = make_new_world(@"Default", browserID);
			defaultDocuments[browserID] = document;
			document.docKey = browserID;
		}
	} else {
		document = theDocuments[worldID];
		if (document == nil) @throw [NSString stringWithFormat:
			@"500 World of ID %@ doesn't exist.", worldID];
	}
}
- (void)setJSONDataAsResponse:(NSObject *)object {
	NSString *valueStr = query[@"format"];
	NSError *error;
	content = [NSJSONSerialization dataWithJSONObject:object 
		options:(valueStr == nil)? JSONOptions : valueStr.integerValue error:&error];
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
	document = make_new_world(@"New",
		(browserID == nil)? ip4_string(ip4addr) : browserID);
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
//
static NSArray<NSString *> *extraIndexes = nil;
static NSArray<NSString *> *valid_report_item_names(void) {
	static NSArray<NSString *> *validNames = nil;
	if (validNames == nil) {
		extraIndexes = @[@"step", @"days", @"testPositiveRate"];
		NSString *names[extraIndexes.count
			+ indexNames.count * 2 + distributionNames.count];
		NSInteger k;
		for (k = 0; k < extraIndexes.count; k ++) names[k] = extraIndexes[k];
		NSEnumerator *enm = indexNames.keyEnumerator;
		for (NSInteger i = 0; i < indexNames.count; i ++) names[k ++] = enm.nextObject;
		enm = indexNames.keyEnumerator;
		for (NSInteger i = 0; i < indexNames.count; i ++)
			names[k ++] = [(NSString *)enm.nextObject stringByAddingFirstWord:@"daily"];
		for (NSInteger i = 0; i < distributionNames.count; i ++)
			names[k ++] = distributionNames[i];
		validNames = [NSArray arrayWithObjects:names count:k];
	}
	return validNames;
}
static NSArray *make_history(StatData *stat, NSInteger nItems,
	NSNumber *(^getter)(StatData *)) {
	if (nItems == 1 && stat != NULL) return @[getter(stat)];
	NSNumber *nums[nItems];
	NSInteger i = nItems - 1;
	for (StatData *p = stat; i >= 0 && p != NULL; i --, p = p->next)
		nums[i] = getter(p);
	return [NSArray arrayWithObjects:nums + i + 1 count:nItems - i - 1];
}
static NSArray *index_array(StatData *stat, NSInteger nItems, NSString *name) {
	NSNumber *num;
	NSInteger idx;
	if ((num = indexNameToIndex[name])) idx = num.integerValue;
	else if ((num = testINameToIdx[name])) idx = num.integerValue + NStateIndexes;
	else return @[];
	return make_history(stat, nItems, ^(StatData *st){ return @(st->cnt[idx]); });
}
- (NSDictionary<NSString *, NSArray<MyCounter *> *> *)distributionNameMap {
	StatInfo *statInfo = document.statInfo;
	return [NSDictionary dictionaryWithObjects:
			@[statInfo.IncubPHist, statInfo.RecovPHist,
			statInfo.DeathPHist, statInfo.NInfectsHist] forKeys:distributionNames];
}
static NSArray *dist_cnt_array(NSArray<MyCounter *> *hist) {
	NSMutableArray *ma = NSMutableArray.new;
	NSInteger st = -1, n = hist.count;
	for (NSInteger i = 0; i < n; i ++) {
		NSInteger cnt = hist[i].cnt;
		if (st == -1 && cnt > 0) [ma addObject:@((st = i))];
		if (st >= 0) [ma addObject:@(cnt)];
	}
	return ma;
}
- (void)sendReport {
	[document popLock];
	NSInteger step = document.runtimeParamsP->step,
		stepsPerDay = document.worldParamsP->stepsPerDay;
	NSInteger n = step - prevRepStep;
	if (n <= 0) {
		[document popUnlock];
		send_bytes(desc, ":\r\n\r\n", 5);
		return;
	}
	NSMutableDictionary *md = NSMutableDictionary.new;
	StatData *stat = document.statInfo.statistics;
	for (NSString *name in repItemsIdx) md[name] = index_array(stat, n, name);
	stat = document.statInfo.transit;
	n = step / stepsPerDay - prevRepStep / stepsPerDay;
	if (n > 0) for (NSString *name in repItemsDly) md[name] = index_array(stat, n, name);
	NSDictionary<NSString *, NSArray<MyCounter *> *> *nameMap = self.distributionNameMap;
	for (NSString *name in repItemsDst) {
		NSArray<MyCounter *> *hist = nameMap[name];
		if (hist != nil) md[name] = dist_cnt_array(hist);
	}
	for (NSString *name in repItemsExt) {
		if ([name isEqualToString:@"step"]) md[name] = @(step);
		else if ([name isEqualToString:@"days"]) md[name] = @(step / stepsPerDay);
		else if ([name isEqualToString:@"testPositiveRate"])
			md[name] = make_history(stat, n, ^(StatData *st) { return @(st->pRate); });
	}
	[document popUnlock];
	prevRepStep = step;
	NSError *error;
	NSData *data = [NSJSONSerialization dataWithJSONObject:md options:0 error:&error];
	NSMutableData *mData = [NSMutableData dataWithLength:data.length + 10];
	char *bytes = mData.mutableBytes;
	memcpy(bytes, "data: ", 6); bytes += 6;
	memcpy(bytes, data.bytes, data.length); bytes += data.length;
	memcpy(bytes, "\r\n\r\n", 4);
	send_large_data(desc, mData.bytes, mData.length);
}
- (void)stopReport {	// must run in the main thread.
	if (reportTimer == nil) { [reportTimer invalidate]; reportTimer = nil; }
}
- (void)periodicReport {
	void (^timerBlock)(NSTimer * _Nonnull timer) = nil;
	@try {
	NSString *report = query[@"report"], *intervalStr = query[@"interval"];
	if (report == nil) @throw @"Report request must be attached.";
	report = report.stringByRemovingPercentEncoding;
	NSError *error;
	NSArray<NSString *> *idxs = [NSJSONSerialization JSONObjectWithData:
		[NSData dataWithBytes:report.UTF8String length:report.length]
		options:0 error:&error];
	if (idxs == nil) @throw error.localizedDescription;
	if (![idxs isKindOfClass:NSArray.class]) @throw
		@"Report information should be an array of index names.";
	NSArray *validNames = valid_report_item_names();
	NSMutableSet *ms = NSMutableSet.new, *trash = NSMutableSet.new;
	for (NSString *name in idxs)
		if ([validNames containsObject:name]) [ms addObject:name];
	NSInteger n = ms.count, nn = 0, nd = 0, nD = 0, nE = 0;
	NSString *an[n], *ad[n], *aD[n], *aE[n];
	for (NSString *name in ms) {
		if (indexNames[name] != nil) an[nn ++] = name;
		else if ([name hasPrefix:@"daily"]) {
			NSString *key = name.stringByRemovingFirstWord;
			if (indexNames[key] != nil) ad[nd ++] = key;
		} else if ([distributionNames containsObject:name]) aD[nD ++] = name;
		else if ([extraIndexes containsObject:name]) aE[nE ++] = name;
		else [trash addObject:name]; 
	}
	if (trash.count > 0) {
		NSMutableString *mstr = NSMutableString.new;
		NSString *pnc = @" ";
		for (NSString *nm in trash)
			{ [mstr appendFormat:@"%@%@", pnc, nm]; pnc = @", "; }
		@throw [NSString stringWithFormat:
			@"Unknown index names: %@.", mstr];
	}
	repItemsIdx = [NSArray arrayWithObjects:an count:nn];
	repItemsDly = [NSArray arrayWithObjects:ad count:nd];
	repItemsDst = [NSArray arrayWithObjects:aD count:nD];
	repItemsExt = [NSArray arrayWithObjects:aE count:nE];
	if (nn + nd + nD + nE == 0) { in_main_thread(^{ [self stopReport]; }); return; }
	CGFloat interval = (intervalStr == nil)? 0. : intervalStr.doubleValue;
	if (interval <= 0.) interval = 1.;
	repN = (interval > 4.)? (NSInteger)ceil(interval / 4.) : 1;
	interval /= repN;
	repCnt = 0;
	timerBlock = ^(NSTimer * _Nonnull timer) {
		[self sendReport];
		self->reportTimer = [NSTimer scheduledTimerWithTimeInterval:interval
			repeats:YES block:^(NSTimer * _Nonnull timer) {
			if ((++ self->repCnt) >= self->repN)
				{ self->repCnt = 0; [self sendReport]; }
			else send_bytes(self->desc, ":\r\n\r\n", 5);	// comment to keep alive.
		}]; };
	content = @"";
	} @catch (NSString *msg) {
		timerBlock = ^(NSTimer * _Nonnull timer) {
			const char *str = msg.UTF8String;
			NSUInteger strLen = strlen(str);
			char buf[strLen + 10], *p = buf;
			memcpy(p, "data: ", 6); p += 6;
			memcpy(p, str, strLen); p += strLen;
			memcpy(p, "\r\n\r\n", 4);
			send_bytes(self->desc, buf, strLen + 10);
		};
	}
	in_main_thread(^{
		[self stopReport];
		if (timerBlock != nil)
			[NSTimer scheduledTimerWithTimeInterval:.2 repeats:NO block:timerBlock];
	});
	type = @"text/event-stream";
	code = 200;
}
- (void)connectionWillClose {
	[self stopReport];
	desc = -1;
}
//
- (void)start {
	[self checkDocument];
	NSString *opStr = query[@"stopAt"];
	NSInteger stopAt = (opStr == nil)? 0 : opStr.integerValue;
	Document *doc = document;
	in_main_thread(^{
		if ([doc start:stopAt] == LoopFinished) self->prevRepStep = 0; });
	if (query[@"report"] != nil) [self periodicReport];
}
- (void)step { [self checkDocument]; [document step]; }
- (void)stop {
	[self checkDocument];
	Document *doc = document;
	in_main_thread(^{ [doc stop:LoopEndByUser]; });
}
- (void)reset { [self checkDocument]; [document resetPop]; }
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
	NSMutableSet *distNames = NSMutableSet.new;
	for (NSString *key in query.keyEnumerator) {
		if ([key isEqualToString:@"names"])
			[self collectNamesInto:distNames];
		else if (query[key].integerValue != 0)
			[distNames addObject:key];
	}
	if (distNames.count == 0) @throw @"417 Distribution name is not sepcified.";
	NSMutableDictionary *md = NSMutableDictionary.new;
	NSDictionary<NSString *, NSArray<MyCounter *> *> *nameMap = self.distributionNameMap;
	[document popLock];
	for (NSString *distName in distNames) {
		NSArray<MyCounter *> *hist = nameMap[distName];
		if (hist != nil) md[distName] = dist_cnt_array(hist);
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
