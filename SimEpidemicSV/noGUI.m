//
//  noGUI.m
//  simepidemic
//
//  Created by Tatsuo Unemi on 2020/08/31.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <sys/socket.h>
#import <arpa/inet.h>
#import "noGUI.h"
#import "AppDelegate.h"
#import "StatPanel.h"
#include "noGUIInfo.h"
#define SERVER_PORT 8000U
#define BUFFER_SIZE 8192
static int soc = -1; // TCP stream socket
static struct sockaddr_in name = {
	sizeof(name), AF_INET, EndianU16_NtoB(SERVER_PORT), {INADDR_ANY}
};
static void unix_error_msg(NSString *msg, int code) {
	fprintf(stderr, "%s: %s.\n", msg.UTF8String, strerror(errno));
	if (code > 0) exit(code);
}

NSMutableArray<Document *> *theDocuments = nil;
static NSUInteger JSONOptions = 0;
static NSString *fileDirectory;
static NSDictionary *extToMime, *codeMeaning, *indexNames;
static NSDateFormatter *dateFormat = nil;
static NSString *headerFormat = @"HTTP/1.1 %03d %@\nDate: %@\nServer: simepidemic\n\
Content-Length: %ld\nConnection: keep-alive\n%@%@\n";

@interface ProcContext : NSObject {
	NSMutableData *bufData;	// buffer to receive
	long dataLength;
}
@property (readonly) Document *document;
@property (readonly) NSDictionary<NSString *, NSString *> *query;
@property (readonly) int desc, code;
@property (readonly) NSString *method, *type, *moreHeader;
@property (readonly) NSObject *content;
@property (readonly) NSInteger fileSize;
@end
@implementation ProcContext
- (instancetype)initWithSocket:(int)desc {
	if (!(self = [super init])) return nil;
	_desc = desc;
	bufData = [NSMutableData dataWithLength:BUFFER_SIZE];
	return self;
}
- (long)receiveData:(NSInteger)length {
	unsigned char *buf = bufData.mutableBytes;
	dataLength = 0;
	do {
		long len = recv(_desc, buf + dataLength, BUFFER_SIZE - 1 - dataLength, 0);
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
- (void)sendHeader {
	NSString *dateStr = [dateFormat stringFromDate:NSDate.date],
		*meaning = codeMeaning[@(_code)];
	NSString *header = [NSString stringWithFormat:headerFormat, _code,
		(meaning == nil)? @"" : meaning, dateStr, _fileSize,
		(_type == nil)? @"" : [NSString stringWithFormat:@"Content-Type: %@\n", _type],
		(_moreHeader == nil)? @"" : _moreHeader];
	send_bytes(_desc, header.UTF8String, header.length);
}
- (void)sendData {
	if ([_method isEqualToString:@"HEAD"]) [self sendHeader];
	else if ([_content isKindOfClass:NSInputStream.class]) {
		[self sendHeader];
		NSInputStream *stream = (NSInputStream *)_content;
		[stream open];
		@try {
			NSMutableData *data = [NSMutableData dataWithLength:BUFFER_SIZE];
			char *bytes = data.mutableBytes;
			NSInteger size;
			while ((size = [stream read:(uint8_t *)bytes maxLength:BUFFER_SIZE]) > 0)
				send_bytes(_desc, bytes, size);
		} @catch (NSObject *obj) { NSLog(@"%@", obj);  }
		[stream close];
	} else {
		const char *bytes = NULL;
		if ([_content isKindOfClass:NSData.class]) {
			_fileSize = ((NSData *)_content).length;
			bytes = ((NSData *)_content).bytes;
		} else if ([_content isKindOfClass:NSString.class]) {
			_fileSize = ((NSString *)_content).length;
			bytes = ((NSString *)_content).UTF8String;
		} else return;
		[self sendHeader];
		send_bytes(_desc, bytes, _fileSize);
	}
}
- (void)setErrorMessage:(NSString *)msg {
	_code = [msg substringToIndex:3].intValue;
	_type = @"text/plain";
	_content = msg;
}
- (void)setOKMessage {
	_code = 200;
	_type = @"text/plain";
	_content = @"OK";
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
		_type = extToMime[ext];
		if (_type == nil) @throw [NSString stringWithFormat:
			@"415 It doesn't support the path extension: %@.", ext];
		NSDictionary *attr =
			[NSFileManager.defaultManager attributesOfItemAtPath:exPath error:&error];
		if (attr == nil) @throw error;
		NSNumber *num = attr[NSFileSize];
		if (num == nil) @throw @"500 Couldn't get the file size.";
		_fileSize = num.integerValue;
		NSDate *modDate = attr[NSFileModificationDate];
		if (modDate != nil) _moreHeader = [NSString stringWithFormat:
			@"Last-Modified: %@\n", [dateFormat stringFromDate:modDate]];
		if ([_method isEqualToString:@"HEAD"]) _content = nil;
		else if (_fileSize < BUFFER_SIZE) {
			_content = [NSData dataWithContentsOfFile:exPath options:0 error:&error];
			if (_content == nil) @throw error;
		} else {
			_content = [NSInputStream inputStreamWithFileAtPath:exPath];
			if (_content == nil) @throw @"500 Couldn't make an input stream.";
		}
		_code = 200;
	} @catch (NSError *error) {
		@throw [NSString stringWithFormat:
			@"404 File access denied: \"%@\" %@", exPath, error.localizedDescription];
	} @catch (NSString *msg) { @throw msg; }
}
- (void)makeResponse {
	if (theDocuments.count > 0) _document = theDocuments[0];
	_content = _moreHeader = nil;
	NSString *req = [NSString stringWithUTF8String:bufData.bytes];
	NSScanner *scan = [NSScanner scannerWithString:req];
	NSString *request, *command, *optionStr, *JSONStr = nil;
	@try {
		NSString *method;
		if (![scan scanUpToString:@" " intoString:&method])
			@throw bad_request_message(req);
		[scan scanCharactersFromSet:NSCharacterSet.whitespaceCharacterSet intoString:NULL];
		if (![scan scanUpToString:@" " intoString:&request])
			@throw bad_request_message(req);
		_method = method;
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
			scan = [NSScanner scannerWithString:headerStr];
			NSString *contentType = nil;
			[scan scanUpToString:@"Content-Type: " intoString:NULL];
			if (scan.atEnd) @throw @"400 No content type indicated.";
			scan.scanLocation = scan.scanLocation + 14;
			if (![scan scanUpToString:@"\r\n" intoString:&contentType])
				@throw @"400 Content type is missing.";
			NSInteger contentLength;
			scan.scanLocation = 0;
			[scan scanUpToString:@"Content-Length: " intoString:NULL];
			if (scan.atEnd) @throw @"411 No content length indicated.";
			scan.scanLocation = scan.scanLocation + 16;
			if (![scan scanInteger:&contentLength]) @throw @"411 Content length is missing.";
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
				[scan scanUpToString:@"filename=" intoString:NULL];
				if (scan.atEnd) @throw @"417 No filename specified.";
				[scan scanUpToString:@"\r\n" intoString:&optionStr];
				optionStr = [optionStr
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
		SEL selector = NSSelectorFromString(command);
		if (![self respondsToSelector:selector]) {
			@throw [@"404 Unknown command: " stringByAppendingString:command];
		} else if ([method isEqualToString:@"HEAD"]) [self setOKMessage];
		else {
			if (optionStr == nil) _query = nil;
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
					_query = [NSDictionary dictionaryWithObjects:objs forKeys:keys count:m];
				} else _query = nil;
			}
//			[self performSelectorOnMainThread:selector withObject:nil waitUntilDone:YES];
			[self performSelector:selector];
			if (_content == nil) [self setOKMessage];
		}
	} @catch (NSString *info) { [self setErrorMessage:info];
	} @catch (NSNumber *num) {}
	[self sendData];
}
- (void)checkDocument {
	if (_document == nil) @throw @"500 No target world exist.";
}
- (NSUInteger)JSONOptions {
	NSString *valueStr = _query[@"format"];
	return (valueStr == nil)? JSONOptions : valueStr.integerValue;
}
- (void)setJSONDataAsResponse:(NSObject *)object {
	NSError *error;
	_content = [NSJSONSerialization dataWithJSONObject:object 
		options:self.JSONOptions error:&error];
	if (_content == nil) @throw [NSString stringWithFormat:
		@"500 Couldn't make a JSON data: %@", error.localizedDescription];
	_type = @"application/json";
	_code = 200;
}
- (void)getInfo:(NSObject *)plist {
	[self checkDocument];
	NSString *savePath = _query[@"save"];
	if (savePath != nil) {
		NSString *extension = @"json";
		_moreHeader = [NSString stringWithFormat:
			@"Content-Disposition: attachment; filename=\"%@\"\n",
			[[savePath pathExtension] isEqualToString:extension]? savePath :
			[savePath stringByAppendingPathExtension:extension]];
	}
	[self setJSONDataAsResponse:plist];
}
- (void)getParams {
	[self getInfo:param_dict(_document.runtimeParamsP, _document.worldParamsP)];
}
- (void)setParams {
	[self checkDocument];
	NSDictionary *dict = nil;
	NSString *JSONstr = _query[@"JSON"];
	if (JSONstr != nil) {
		NSError *error;
		NSData *data = [JSONstr dataUsingEncoding:NSUTF8StringEncoding];
		dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
		if (dict == nil) @throw [NSString stringWithFormat:
			@"417 Failed to interprete JSON data: %@", error.localizedDescription];
		if (![dict isKindOfClass:NSDictionary.class])
			@throw @"417 JSON data doesn't represent a dictionary.";
	} else dict = _query;
#ifdef DEBUG
printf("--- parameters\n%s\n", dict.description.UTF8String);
#endif
	RuntimeParams *rp = _document.runtimeParamsP;
	WorldParams *wp = (rp->step == 0)?
		_document.worldParamsP : _document.tmpWorldParamsP;
	set_params_from_dict(rp, wp, dict);
}
- (void)start {
	[self checkDocument];
	NSString *opStr = _query[@"stopAt"];
	[_document start:(opStr == nil)? 0 : opStr.integerValue];
}
- (void)step { [self checkDocument]; [_document step]; }
- (void)stop { [self checkDocument]; [_document stop]; }
- (void)reset { [self checkDocument]; [_document resetPop]; }
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
	NSString *arrStr = [_query[@"names"] stringByRemovingPercentEncoding];
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
	for (NSString *key in _query.keyEnumerator) {
		if ([key isEqualToString:@"names"])
			[self collectNamesInto:idxNames];
		else if ([key isEqualToString:@"fromDay"]) {
			fromDay = _query[key].integerValue;
		} else if ([key isEqualToString:@"fromStep"]) {
			fromStep = _query[key].integerValue;
		} else if ([key isEqualToString:@"window"]) {
			daysWindow = _query[key].integerValue;
		} else if (_query[key].integerValue != 0)
			[idxNames addObject:key];
	}
	if (idxNames.count == 0) @throw @"417 Index name is not sepcified.";
	RuntimeParams *rp = _document.runtimeParamsP;
	WorldParams *wp = _document.worldParamsP;
	if (fromDay != MAX_INT32) fromStep = fromDay * wp->stepsPerDay;
	else if (fromStep != MAX_INT32) fromDay = fromStep / wp->stepsPerDay;
	NSInteger nDays, nSteps;
	nSteps = (fromStep < 0)? -fromStep :
		(rp->step < fromStep)? 1 : rp->step - fromStep + 1;
	nDays = (fromDay == MAX_INT32)? 1 : (nSteps + wp->stepsPerDay - 1) / wp->stepsPerDay;
	NSMutableDictionary *md = NSMutableDictionary.new;
	StatInfo *statInfo = _document.statInfo;
	StatData *statData = (daysWindow == 0)? statInfo.statistics : statInfo.transit;
	NSInteger nItems = (daysWindow == 0)?
		(nSteps - 1) / statInfo.skipSteps + 1 : (nDays - 1) / statInfo.skipDays + 1;
	for (NSString *idxName in idxNames) {
		if ([idxName isEqualToString:@"isRunning"])
			md[idxName] = @(_document.running);
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
	if (md.count == 0) @throw @"417 No valid index names are specified.";
	[self setJSONDataAsResponse:md];
}
- (void)getDistribution {
	[self checkDocument];
	StatInfo *statInfo = _document.statInfo;
	NSDictionary<NSString *, NSArray<MyCounter *> *> *nameMap =
		@{@"incubasionPeriod":statInfo.IncubPHist,
		@"recoveryPeriod":statInfo.RecovPHist,
		@"fatalPeriod":statInfo.DeathPHist,
		@"infects":statInfo.NInfectsHist };
	NSMutableSet *distNames = NSMutableSet.new;
	for (NSString *key in _query.keyEnumerator) {
		if ([key isEqualToString:@"names"])
			[self collectNamesInto:distNames];
		else if (_query[key].integerValue != 0)
			[distNames addObject:key];
	}
	if (distNames.count == 0) @throw @"417 Distribution name is not sepcified.";
	NSMutableDictionary *md = NSMutableDictionary.new;
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
	if (md.count == 0) @throw @"417 No valid distribution names are specified.";
	[self setJSONDataAsResponse:md];
}
- (void)getScenario {
	[self getInfo:[_document scenarioPList]];
}
- (void)setScenario {
	[self checkDocument];
	NSString *source = _query[@"scenario"];
	if (source == nil) source = _query[@"JSON"];
	if (source == nil) @throw @"417 Scenario data is missing.";
	NSData *data = [[source stringByRemovingPercentEncoding]
		dataUsingEncoding:NSUTF8StringEncoding];
	NSError *error;
	NSArray *plist = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if (plist == nil) @throw [NSString stringWithFormat:
		@"417 Failed to interprete JSON data: %@", error.localizedDescription];
	if (![plist isKindOfClass:NSArray.class])
		@throw @"417 JSON data doesn't represent an array form.";
	@try { [_document setScenarioWithPList:plist]; }
	@catch (NSString *msg) { @throw [@"500 " stringByAppendingString:msg]; }
}
@end
static NSDictionary *code_meaning_map(void) {
	return @{ //@(100):@"Continue", @(101):@"Switching Protocols",
	@(200):@"OK", //@(201):@"Created", @(202):@"Accepted",
//	@(203):@"Non-Authoritative Information", @(204):@"No Content",
//	@(205):@"Reset Content",
//	@(300):@"Multiple Choices", @(301):@"Moved Permanently",
//	@(302):@"Found", @(303):@"See Other", @(305):@"Use Proxy",
//	@(307):@"Temporary Redirect",
	@(400):@"Bad Request", //@(402):@"Payment Required",
	@(403):@"Forbidden", @(404):@"Not Found", @(405):@"Method Not Allowed",
	@(406):@"Not Acceptable", @(408):@"Request Timeout", @(409):@"Conflict",
//	@(410):@"Gone",
	@(411):@"Length Required",
	@(413):@"Payload Too Large", @(414):@"URI Too Long", @(415):@"Unsupported Media Type",
	@(417):@"Expectation Failed", //@(426):@"Upgrade Required",
	@(500):@"Internal Server Error", @(501):@"Not Implemented",
//	@(503):@"Service Unavailable", @(504):@"Gateway Timeout",
//	@(505):@"HTTP Version Not Supported"
	};
}
static NSDictionary *ext_mime_map(void) {
	NSDictionary *defaultMap = @{
		@"html":@"text/html", @"css":@"text/css", @"js":@"text/javascript",
		@"txt":@"text/plain",
		@"jpg":@"image/jpeg", @"jpeg":@"image/jpeg", @"png":@"image/png",
		@"svg":@"image/svg+xml", @"ico":@"image/x-icon", @"gif":@"image/gif",
	};
@autoreleasepool {
	NSData *data = [NSData dataWithContentsOfFile:@"/etc/apache2/mime.types"];
	if (data == nil) return defaultMap;
	NSMutableDictionary *md = [NSMutableDictionary dictionaryWithDictionary:defaultMap];
	const char *dataBytes = data.bytes;
	NSInteger len = data.length, jdx, lineLen;
	char buf[128];
	for (NSInteger idx = 0; idx < len; idx = jdx + 1) {
		for (jdx = idx; jdx < len; jdx ++) if (dataBytes[jdx] == '\n') break;
		lineLen = jdx - idx + 1;
		if (dataBytes[idx] != '#' && lineLen < 128) {
			memcpy(buf, dataBytes + idx, lineLen);
			for (NSInteger i = lineLen - 1; i >= 0 && buf[i] < ' '; i --) buf[i] = '\0';
			NSString *line = [NSString stringWithUTF8String:buf];
			NSScanner *scan = [NSScanner scannerWithString:line];
			NSString *mimeType, *extension;
			[scan scanUpToCharactersFromSet:NSCharacterSet.whitespaceCharacterSet
				intoString:&mimeType];
			NSString *category = [mimeType componentsSeparatedByString:@"/"][0];
			if ([@[@"application", @"image", @"text"] indexOfObject:category] != NSNotFound)
			while (!scan.atEnd) {
				[scan scanUpToCharactersFromSet:NSCharacterSet.alphanumericCharacterSet
					intoString:NULL];
				[scan scanCharactersFromSet:NSCharacterSet.alphanumericCharacterSet
					intoString:&extension];
				if (extension != nil && extension.length > 0) md[extension] = mimeType;
			}
		}
	}
	return md;
} }
static NSDictionary *index_name_map(void) {
	static NSString *names[] = {
		@"susceptible", @"asymptomatic", @"symptomatic", @"recovered", @"died",
		@"quarantineAsymptomatic", @"quarantineSymptomatic",
		@"tests", @"testAsSymptom", @"testAsContact", @"testAsSuspected",
		@"testPositive", @"testNegative",
	nil};
	NSInteger n = 0; while (names[n] != nil) n ++;
	NSNumber *idxes[n];
	for (NSInteger i = 0; i < n; i ++) idxes[i] = @(i);
	return [NSDictionary dictionaryWithObjects:idxes forKeys:names count:n];
}
static void interaction_thread(int desc) {
@autoreleasepool {
	NSThread.currentThread.name = @"Network interaction";
#ifdef DEBUG
	NSLog(@"Receiving thread started (%d).", desc);
#endif
	ProcContext *context = [ProcContext.alloc initWithSocket:desc];
	BOOL isConnected = YES;
	while (isConnected) @autoreleasepool { @try {
		if ([context receiveData:-1] > 0) [context makeResponse];
		else @throw @0;
	} @catch (id _) { isConnected = NO; } }
	close(desc);
#ifdef DEBUG
	NSLog(@"Receiving thread ended.");
#endif
}}
void connection_thread(void) {
	unsigned int addrlen;
	int desc = -1;
#ifdef DEBUG
	NSLog(@"Connection thread started.");
#endif
	NSThread.currentThread.name = @"Network connection";
	for (;;) @autoreleasepool {
		for (;;) {
			addrlen = sizeof(name);
			desc = accept(soc, (struct sockaddr *)&name, &addrlen);
			if (desc < 0) unix_error_msg(@"accept", desc);
			else break;
		}
		[NSThread detachNewThreadWithBlock:^{ interaction_thread(desc); }];
	}
//	close(soc); soc = -1;
#ifdef DEBUG
//	NSLog(@"Connection thread ended.");
#endif
}

int main(int argc, const char * argv[]) {
@autoreleasepool {
	int port = SERVER_PORT;
	short err;
	NSMutableString *dirPath = NSMutableString.new;
// Check command options
	for (NSInteger i = 1; i < argc; i ++) if (argv[i][0] == '-') {
		if (strcmp(argv[i], "-p") == 0 || strcmp(argv[i], "--port") == 0) {
			if (i + 1 < argc) port = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-f") == 0 || strcmp(argv[i], "--format") == 0) {
			if (i + 1 < argc) JSONOptions = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-d") == 0 || strcmp(argv[i], "--directory") == 0) {
			if (i + 1 < argc) {
				NSString *path = [NSString stringWithUTF8String:argv[++ i]];
				if ([path hasPrefix:@"/"]) [dirPath appendString:path];
				else [dirPath appendFormat:@"%@/%@",
					NSFileManager.defaultManager.currentDirectoryPath, path];
			}
		} else if (strcmp(argv[i], "--version") == 0) {
			printf("%s\n", version); exit(0);
		} else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
			printf("\n"); exit(0);
		}
	}
	if (dirPath.length == 0)
		[dirPath appendString:NSFileManager.defaultManager.currentDirectoryPath];
	if (![dirPath hasSuffix:@"/"]) [dirPath appendString:@"/"];
	fileDirectory = dirPath;

// Date formatter for "Date" item in the header	
	dateFormat = NSDateFormatter.new;
	dateFormat.locale = [NSLocale.alloc initWithLocaleIdentifier:@"en_GB"];
	dateFormat.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
	dateFormat.dateFormat = @"E, d MMM Y HH:mm:ss zzz"; //Mon, 31 Aug 2020 05:08:47 GMT
//
	codeMeaning = code_meaning_map();
	extToMime = ext_mime_map();
	indexNames = index_name_map();

// Open the server side socket to wait for connection request from a client.
	name.sin_port = EndianU16_NtoB((unsigned short)port);
	soc = socket(PF_INET, SOCK_STREAM, 0);
	if (soc < 0) unix_error_msg(@"TCP socket", 1);
	if ((err = bind(soc, (struct sockaddr *)&name, sizeof(name))))
		unix_error_msg(@"TCP bind", 2);
	if ((err = listen(soc, 1))) unix_error_msg(@"listen", 3);

// Prepare and start the Runloop to use Cocoa framework.
	NSApplication *app = NSApplication.sharedApplication;
	app.activationPolicy = NSApplicationActivationPolicyRegular;
	app.delegate = AppDelegate.new;
	theDocuments = NSMutableArray.new;
	[app run];
}
	return 0;
}
