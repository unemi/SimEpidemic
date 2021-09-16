//
//  ProcContext.m
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/09/10.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <sys/socket.h>
#import <sys/select.h>
#import <os/log.h>
#import <sys/sysctl.h>
#import <sys/resource.h>

#import "ProcContext.h"
#import "noGUI.h"
#import "PeriodicReporter.h"
#import "SaveState.h"
#import "BatchJob.h"
#import "../SimEpidemic/Sources/World.h"
#import "../SimEpidemic/Sources/StatPanel.h"
#import "DataCompress.h"
#define MAX_INT32 0x7fffffff

static NSDictionary<NSString *, void (^)(ProcContext *)> *commandDict = nil;
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

@implementation World (TimeOutExtension)
- (void)expirationCheck:(NSTimer *)timer {
	if (theWorlds[self.ID] != self) return;
	NSTimeInterval nextCheck = worldTimeout;
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
		MY_LOG("World %@ closed by timeout.", self.ID);
		[theWorlds removeObjectForKey:self.ID];
		if (self.worldKey != nil) [defaultWorlds removeObjectForKey:self.worldKey];
	}
	[self.lastTLock unlock];
}
@end

World *make_new_world(NSString *type, NSString * _Nullable browserID) {
	if (theWorlds.count >= maxNWorlds) @throw [NSString stringWithFormat:
		@"500 This server already have too many (%ld) worlds.", maxNWorlds];
	World *world = World.new;
	if (browserID != nil) {
		theWorlds[world.ID] = world;
		[NSTimer scheduledTimerWithTimeInterval:worldTimeout target:world
			selector:@selector(expirationCheck:) userInfo:nil repeats:NO];
		MY_LOG("%@ world %@ was created for %@. %ld world(s) in total.",
			type, world.ID, browserID, theWorlds.count);
	} else MY_LOG("%@ world %@ was created.", type, world.ID);
	return world;
}
@implementation ProcContext
- (instancetype)initWithSocket:(int)dsc ip:(uint32)ipaddr {
	if (!(self = [super init])) return nil;
	desc = dsc;
	bufData = [NSMutableData dataWithLength:BUFFER_SIZE];
	ip4addr = ipaddr;
	return self;
}
#define RECV_WAIT 200000
#define RECV_TIMEOUT (60*1000000/RECV_WAIT)
- (long)receiveData:(NSInteger)length offset:(NSInteger)offset {
	unsigned char *buf = bufData.mutableBytes;
	dataLength = offset;
	if (length < 0 || offset < length) do {
		long len = 0;
		for (int waitCount = 0; waitCount < RECV_TIMEOUT; ) {
			if (waitCount > 0) usleep(RECV_WAIT);	// wait 0.2 second
			len = recv(desc, buf + offset, BUFFER_SIZE - 1 - offset, 0);
			if (len >= 0) break;
			else if (len != -1 || errno != EAGAIN) @throw @"recv command";
			if (nReporters > 0) waitCount = 0;
			else waitCount ++;
		}
#ifdef DEBUG
		if (len == 0) break;
		else if (len < 0) MY_LOG_DEBUG("(%d) Timeout", desc)
#else
		if (len <= 0) break;
#endif
		else offset += len;
	} while (offset < length);
	buf[(dataLength = offset)] = '\0';
	MY_LOG_DEBUG("(%d)-> %ld bytes.\n%s", desc, dataLength, buf);
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
			MY_LOG("%@ %s", ip4_string(ip4addr), b); 
		} else MY_LOG("%@ Payload %ld bytes", ip4_string(ip4addr), dataLength);
	}
	return dataLength;
}
static NSString *unix_err_msg(void) {
	return [NSString stringWithUTF8String:strerror(errno)];
}
void send_bytes(int desc, const char *bytes, NSInteger size) {
	if (desc < 0) return;
#define CHECK_BY_SELECT
#ifdef CHECK_BY_SELECT
	fd_set fdSet;
	FD_ZERO(&fdSet);
	FD_SET(desc, &fdSet);
	do {
		int n = select(desc + 1, NULL, &fdSet, NULL, &(struct timeval){0,100000});
		if (n == 0) @throw @"'select' got time out to send answer";
		else if (n < 0) @throw unix_err_msg();
	} while (!FD_ISSET(desc, &fdSet));
#endif
	NSInteger retry = 5;
	do {
		ssize_t result = send(desc, bytes, size, 0);
		if (result < 0) @throw unix_err_msg();
		else if (result >= size) break;
		if (result == 0) retry --;
		else { bytes += result; size -= result; }
		usleep(100000);
	} while (retry > 0);
	if (retry <= 0) @throw @"send answer";
#ifdef DEBUG
	MY_LOG_DEBUG("(%d)<- %ld bytes.\n", desc, size);
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
	if (method == MethodHEAD) return [self sendHeader];
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
	NSScanner *scan = [NSScanner scannerWithString:msg];
	NSString *numStr;
	if ([scan scanCharactersFromSet:
		NSCharacterSet.decimalDigitCharacterSet intoString:&numStr])
		code = numStr.intValue;
	else { code = 417; msg = [@"417 " stringByAppendingString:msg]; }
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
		if (method == MethodHEAD) content = nil;
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
			@"404 File access: %@", error.localizedDescription];
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
- (void)checkCommand:(NSString *)command {
	proc = commandDict[command];
	if (proc == nil) @throw [@"404 Unknown command: " stringByAppendingString:command];
}
- (int)makeResponse {
	content = moreHeader = nil;
	code = 0;
	@try {
		if (dataLength <= 4) {
			_requestString = @" ";
			@throw @"400 Lack of method name.";
		}
		NSString *req = [NSString stringWithUTF8String:bufData.bytes];
		NSScanner *scan = [NSScanner scannerWithString:req];
		scan.charactersToBeSkipped = nil;
		NSString *workStr, *path, *command, *optionStr, *JSONStr = nil;
		[scan scanUpToString:@"\r" intoString:&workStr];
		_requestString = workStr;
		scan.scanLocation = 0;
		NSString *methodName;
		if (![scan scanUpToString:@" " intoString:&methodName])
			@throw bad_request_message(req);
		[scan scanCharactersFromSet:NSCharacterSet.whitespaceCharacterSet intoString:NULL];
		if (![scan scanUpToString:@" " intoString:&path])
			@throw bad_request_message(req);
		if (![path hasPrefix:@"/"]) @throw bad_request_message(req);
		method = [@[@"HEAD", @"GET", @"POST"] indexOfObject:methodName];
		switch (method) {
			case MethodGET: case MethodHEAD: {
				scan = [NSScanner scannerWithString:(workStr = path)];
				if (![scan scanUpToString:@"?" intoString:&path])
					@throw bad_request_message(req);
				if ([path hasSuffix:@"/"])
					path = [workStr stringByAppendingPathComponent:@"index.html"];
				if (path.pathExtension.length > 0)
					{ [self respondFile:[path substringFromIndex:1]]; @throw @0; }
				[self checkCommand:(command = [path substringFromIndex:1])];
				optionStr = scan.atEnd? nil :
					[workStr substringFromIndex:scan.scanLocation + 1];
			} break;
			case MethodPOST: {
				[self checkCommand:(command = [path substringFromIndex:1])];
				[scan scanUpToString:@"\r\n" intoString:NULL];
				if (![scan scanUpToString:@"\r\n\r\n" intoString:&workStr])
					@throw bad_request_message(req);
				NSDictionary<NSString *, NSString *> *headers = header_dictionary(workStr);
				NSString *contentType = headers[@"Content-Type"];
				if (contentType == nil) @throw @"411 No content type.";
				NSString *numStr = headers[@"Content-Length"];
				if (numStr == nil) @throw @"411 No content length.";
				NSInteger contentLength = numStr.integerValue;
				if (contentLength > BUFFER_SIZE - 1) @throw @"413 Payload is too large.";
				[scan scanString:@"\r\n\r\n" intoString:NULL];
				if (!scan.atEnd) {
					NSString *restPart = [req substringFromIndex:scan.scanLocation];
					[restPart getCString:bufData.mutableBytes maxLength:BUFFER_SIZE-1
						encoding:NSUTF8StringEncoding];
					[self receiveData:contentLength offset:strlen(bufData.mutableBytes)];
				} else [self receiveData:contentLength offset:0];
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
			} break;
			case MethodNone: @throw
				[NSString stringWithFormat:@"405 \"%@\" method is not allowed.", methodName];
		}
		if (method == MethodHEAD) [self setOKMessage];
		else {
			if (optionStr == nil) query = nil;
			else {
				NSArray<NSString *> *opArray = [optionStr componentsSeparatedByString:@"&"];
				NSInteger n = opArray.count, m = n + ((JSONStr != nil)? 1 : 0);
				if (m > 0) {
					NSString *keys[m], *objs[m];
					NSInteger k = 0;
					for (NSInteger i = 0; i < n; i ++) {
						NSScanner *scan = [NSScanner scannerWithString:opArray[i]];
						NSString *key;
						if ([scan scanUpToString:@"=" intoString:&key]) {
							keys[k] = key;
							objs[k ++] = scan.atEnd? @"" :
								[opArray[i] substringFromIndex:scan.scanLocation + 1];
						}
					}
					if (JSONStr != nil) { keys[k] = @"JSON"; objs[k ++] = JSONStr; }
					query = [NSDictionary dictionaryWithObjects:objs forKeys:keys count:k];
				} else query = nil;
			}
			proc(self);
			if (code == 0) [self setOKMessage];
		}
	} @catch (NSString *info) { [self setErrorMessage:info];
	} @catch (NSException *excp) {
		[self setErrorMessage:[@"500 " stringByAppendingString:excp.reason]];
	} @catch (NSError *error) {
		[self setErrorMessage:[@"500 " stringByAppendingString:error.localizedDescription]];
	} @catch (NSNumber *num) { }
//
	@try {
		if (content != nil) {
			NSInteger length = [self sendData];
			MY_LOG("%@ %d %ld bytes to %@", ip4_string(ip4addr),
				code, length, (browserID == nil)? @"-" : browserID);
		} else if (postProc != nil) {
			[self sendHeader];
			postProc();
		}
	} @catch (id msg) {
		MY_LOG("%@ Error %@", ip4_string(ip4addr), msg);
		@throw @2;
	}
	return code;
}
- (void)checkWorld {
	NSString *brwsID = query[@"me"], *worldID = query[@"world"];
	if (brwsID != nil) browserID = brwsID;
	if (worldID == nil) worldID = query[@"name"];
	if (worldID == nil || [worldID isEqualToString:@"default"]) {
		if (browserID == nil) browserID = ip4_string(ip4addr);
		world = defaultWorlds[browserID];
		if (world == nil || ![world touch]) {
			world = make_new_world(@"Default", browserID);
			defaultWorlds[browserID] = world;
			world.worldKey = browserID;
		}
	} else {
		world = theWorlds[worldID];
		if (world == nil) @throw [NSString stringWithFormat:
			@"500 World of ID %@ doesn't exist.", worldID];
	}
}
- (void)connectionWillClose {
	[world reporterConnectionWillClose:desc];
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
- (BOOL)setupLocalFileToSave:(NSString *)extension {
	NSString *savePath = query[@"save"];
	if (savePath != nil) {
		moreHeader = [NSString stringWithFormat:
			@"Content-Disposition: attachment; filename=\"%@\"\n",
			[[savePath pathExtension] isEqualToString:extension]? savePath :
			[savePath stringByAppendingPathExtension:extension]];
		return YES;
	} else return NO;
}
- (void)getInfo:(NSObject *)plist {
	[self checkWorld];
	[self setupLocalFileToSave:@"json"];
	[self setJSONDataAsResponse:plist];
}
- (void)setWorldIDAsResponse {
	content = world.ID;
	type = @"text/plain";
	code = 200;
}
- (void)getWorldID {
	[self checkWorld];
	[self setWorldIDAsResponse];
}
- (void)newWorld {
	world = make_new_world(@"New",
		(browserID == nil)? ip4_string(ip4addr) : browserID);
	[self setWorldIDAsResponse];
}
- (void)closeWorld {
	NSString *worldID = query[@"world"];
	if (worldID == nil) @throw @"417 World ID is missing.";
	World *world = theWorlds[worldID];
	if (world == nil) @throw [NSString stringWithFormat:
		@"500 World of ID %@ doesn't exist.", worldID];
	else if (world.worldKey != nil)
		@throw @"500 It's not allowed to close a default world.";
	else [theWorlds removeObjectForKey:worldID];
}
- (void)getParams {
	[self checkWorld];
	[world popLock];
	NSObject *plist = param_dict(world.runtimeParamsP, world.worldParamsP);
	[world popUnlock];
	[self getInfo:plist];
}
- (NSObject *)plistFromJSONArgument:(NSJSONReadingOptions)option
	class:(Class)class type:(NSString *)type {
	NSString *JSONstr = query[@"JSON"];
	if (JSONstr == nil) return nil;
	NSError *error;
	NSData *data = [JSONstr dataUsingEncoding:NSUTF8StringEncoding];
	NSObject *obj = [NSJSONSerialization JSONObjectWithData:data options:option error:&error];
	if (obj == nil) @throw [NSString stringWithFormat:
		@"417 %@%@.", error.localizedDescription, type];
	if (class != NULL && ![obj isKindOfClass:class]) @throw [NSString stringWithFormat:
		@"417 JSON data is not form of %@.", class];
	return obj;
}
- (void)setParams {
	[self checkWorld];
	NSDictionary *dict = (NSDictionary *)
		[self plistFromJSONArgument:0 class:NSDictionary.class type:@"parameters"];
	if (dict == nil) dict = query;
	MY_LOG_DEBUG("--- parameters\n%s\n", dict.description.UTF8String);
	[world popLock];
	WorldParams *wp = world.tmpWorldParamsP;
	set_params_from_dict(world.runtimeParamsP, wp, dict);
	NSInteger popSize = wp->initPop;
	if (popSize > maxPopSize) wp->initPop = maxPopSize;
	[world popUnlock];
	if (popSize > maxPopSize) @throw [NSString stringWithFormat:
		@"200 The specified population size %ld is too large.\
It was adjusted to maxmimum value: %ld.", popSize, maxPopSize];
	RuntimeParams *rp = world.runtimeParamsP;
	if (rp->step == 0 && memcmp(world.worldParamsP, wp, sizeof(WorldParams))) {
		memcpy(world.worldParamsP, wp, sizeof(WorldParams));
		[world resetPop];
	}
}
//
NSArray *make_history(StatData *stat, NSInteger nItems,
	NSNumber *(^getter)(StatData *)) {
	if (nItems == 1 && stat != NULL) return @[getter(stat)];
	NSNumber *nums[nItems];
	NSInteger i = nItems - 1;
	for (StatData *p = stat; i >= 0 && p != NULL; i --, p = p->next)
		nums[i] = getter(p);
	return [NSArray arrayWithObjects:nums + i + 1 count:nItems - i - 1];
}
NSArray *dist_cnt_array(NSArray<MyCounter *> *hist) {
	NSMutableArray *ma = NSMutableArray.new;
	NSInteger st = -1, n = hist.count;
	for (NSInteger i = 0; i < n; i ++) {
		NSInteger cnt = hist[i].cnt;
		if (st == -1 && cnt > 0) [ma addObject:@((st = i))];
		if (st >= 0) [ma addObject:@(cnt)];
	}
	return ma;
}
NSDictionary<NSString *, NSArray<MyCounter *> *> *distribution_name_map(World *world) {
	StatInfo *statInfo = world.statInfo;
	return [NSDictionary dictionaryWithObjects:
			@[statInfo.IncubPHist, statInfo.RecovPHist,
			statInfo.DeathPHist, statInfo.NInfectsHist] forKeys:distributionNames];
}
//
- (void)start {
	[self checkWorld];
	NSString *opStr = query[@"stopAt"], *maxSPSStr = query[@"maxSPS"];
	NSInteger stopAt = (opStr == nil)? 0 : opStr.integerValue;
	CGFloat maxSps = (maxSPSStr == nil)? 0 : maxSPSStr.doubleValue;
	World *wd = world;
	in_main_thread(^{ [wd start:stopAt maxSPS:maxSps priority:-.1]; });
}
- (void)step {
	[self checkWorld];
	World *wd = world;
	in_main_thread(^{ [wd step]; });
}
- (void)stop {
	[self checkWorld];
	World *wd = world;
	in_main_thread(^{ [wd stop:LoopEndByUser]; });
}
- (void)reset {
	[self checkWorld];
	World *wd = world;
	in_main_thread(^{ [wd resetPop]; });
}
- (void)addInfected {
	[self checkWorld];
	NSString *arg = query[@"n"];
	NSInteger n = (arg == nil)? 1 : arg.integerValue;
	NSString *vrName = query[@"variant"];
	int variantType = (vrName == nil)? 0 : [world variantTypeFromName:vrName];
	if (variantType < 0) @throw [NSString stringWithFormat:
		@"Could not find a variant named \"%@.\"", vrName];
	World *wd = world;
	in_main_thread(^{ [wd addInfected:n variant:variantType]; });
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
	[self checkWorld];
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

	RuntimeParams *rp = world.runtimeParamsP;
	WorldParams *wp = world.worldParamsP;
	if (fromDay != MAX_INT32) fromStep = fromDay * wp->stepsPerDay;
	else if (fromStep != MAX_INT32) fromDay = fromStep / wp->stepsPerDay;
	NSInteger nDays, nSteps;
	nSteps = (fromStep < 0)? -fromStep :
		(rp->step < fromStep)? 1 : rp->step - fromStep + 1;
	nDays = (fromDay == MAX_INT32)? 1 : (nSteps + wp->stepsPerDay - 1) / wp->stepsPerDay;
	NSMutableDictionary *md = NSMutableDictionary.new;
	StatInfo *statInfo = world.statInfo;
	StatData *statData = (daysWindow == 0)? statInfo.statistics : statInfo.transit;
	NSInteger nItems = (daysWindow == 0)?
		(nSteps - 1) / statInfo.skipSteps + 1 : (nDays - 1) / statInfo.skipDays + 1;
	[world popLock];
	for (NSString *idxName in idxNames) {
		if ([idxName isEqualToString:@"isRunning"])
			md[idxName] = @(world.running);
		else if ([idxName isEqualToString:@"step"]) md[idxName] = @(rp->step);
		else if ([idxName isEqualToString:@"days"])
			md[idxName] = @((CGFloat)rp->step / wp->stepsPerDay);
		else if ([idxName isEqualToString:@"testPositiveRate"])
			md[idxName] = make_history(statData, nItems,
				^(StatData *st) { return @(st->pRate); });
		else if ([idxName isEqualToString:@"reproductionRate"] && daysWindow == 0)
			md[idxName] = make_history(statData, nItems,
				^(StatData *st) { return @(st->reproRate); });
		else {
			NSNumber *num = indexNames[idxName];
			if (num != nil) {
				NSInteger idx = num.integerValue;
				md[idxName] = make_history(statData, nItems,
					^(StatData *st) { return @(st->cnt[idx]); });
	}}}
	[world popUnlock];
	if (md.count == 0) @throw @"417 No valid index names are specified.";
	[self setJSONDataAsResponse:md];
}
- (void)getDistribution {
	[self checkWorld];
	NSMutableSet *distNames = NSMutableSet.new;
	for (NSString *key in query.keyEnumerator) {
		if ([key isEqualToString:@"names"])
			[self collectNamesInto:distNames];
		else if (query[key].integerValue != 0)
			[distNames addObject:key];
	}
	if (distNames.count == 0) @throw @"417 Distribution name is not sepcified.";
	NSMutableDictionary *md = NSMutableDictionary.new;
	NSDictionary<NSString *, NSArray<MyCounter *> *>
		*nameMap = distribution_name_map(world);
	[world popLock];
	for (NSString *distName in distNames) {
		NSArray<MyCounter *> *hist = nameMap[distName];
		if (hist != nil) md[distName] = dist_cnt_array(hist);
	}
	[world popUnlock];
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
NSData *JSON_pop(World *world) {
	WorldParams *wp = world.worldParamsP;
	Agent **pop = world.Pop;
	uint8 *buf = malloc(wp->initPop * 16 + 4), *p = buf + 1;
	buf[0] = '[';
	uint32 nAgents = 0;
	for (NSInteger i = 0; i < wp->mesh * wp->mesh; i ++)
		for (Agent *a = pop[i]; a != NULL; a = a->next, nAgents ++)
			p += store_agent_xyh(a, p, wp->worldSize);
	for (Agent *a = world.QList; a != NULL; a = a->next, nAgents ++)
		p += store_agent_xyh(a, p, wp->worldSize);
	for (Agent *a = world.CList; a != NULL; a = a->next, nAgents ++)
		p += store_agent_xyh(a, p, wp->worldSize);
	for (NSValue *value in world.WarpList.objectEnumerator) {
		WarpInfo info = value.warpInfoValue;
		Agent *a = info.agent;
		p += sprintf((char *)p, "[%d,%d,%d,%d,%d,%d],",
			int_coord(a->x, wp->worldSize), int_coord(a->y, wp->worldSize), a->health,
			int_coord(info.goal.x, wp->worldSize), int_coord(info.goal.y, wp->worldSize),
			info.mode);
		nAgents ++;
	}
	NSInteger srcSize = p - buf;
	if (nAgents > 0) p[-1] = ']';
	else { buf[1] = ']'; srcSize = 2; }
	return [NSData dataWithBytesNoCopy:buf length:srcSize freeWhenDone:YES];
}
- (void)getPop:(NSData *(World *))dataFunc {
	[self checkWorld];
	[world popLock];
	NSData *srcData = dataFunc(world);
	[world popUnlock];
	@try {
		NSData *dstData = [srcData zippedData];
		MY_LOG_DEBUG("agents -> %ld bytes\n", dstData.length);
		content = dstData;
		type = @"application/json";
		moreHeader = @"Content-Encoding: deflate\n";
		code = 200;
	} @catch (NSNumber *errNum) {
		@throw [NSString stringWithFormat:
			@"500 Compression error (%d).", errNum.intValue];
	}
}
- (void)getPopulation { [self getPop:JSON_pop]; }

static NSArray *agent_cood(Agent *a, WorldParams *wp) {
	return @[@(int_coord(a->x, wp->worldSize)), @(int_coord(a->y, wp->worldSize))];
}
NSData *JSON_pop2(World *world) {
	WorldParams *wp = world.worldParamsP;
	Agent **pop = world.Pop;
	NSMutableArray *posts[NHealthTypes];
	for (NSInteger i = 0; i < NHealthTypes; i ++) posts[i] = NSMutableArray.new;
	for (NSInteger i = 0; i < wp->mesh * wp->mesh; i ++)
		for (Agent *a = pop[i]; a != NULL; a = a->next)
			[posts[a->health] addObject:agent_cood(a, wp)];
	for (Agent *a = world.QList; a != NULL; a = a->next)
		[posts[a->health] addObject:agent_cood(a, wp)];
	for (Agent *a = world.CList; a != NULL; a = a->next)
		[posts[a->health] addObject:agent_cood(a, wp)];
	for (NSValue *value in world.WarpList.objectEnumerator) {
		WarpInfo info = value.warpInfoValue;
		Agent *a = info.agent;
		[posts[a->health] addObject:@[
			@(int_coord(a->x, wp->worldSize)), @(int_coord(a->y, wp->worldSize)),
			@(int_coord(info.goal.x, wp->worldSize)),
			@(int_coord(info.goal.y, wp->worldSize)), @(info.mode)]];
	}
	return [NSJSONSerialization dataWithJSONObject:
		[NSArray arrayWithObjects:posts count:NHealthTypes]
		options:0 error:NULL];
}
- (void)getPopulation2 { [self getPop:JSON_pop2]; }

- (void)getScenario {
	[self checkWorld];
	[world popLock];
	NSObject *plist = [world scenarioPList];
	[world popUnlock];
	[self getInfo:plist];
}
- (void)setScenario {
	[self checkWorld];
	if (world.runtimeParamsP->step > 0 || world.running)
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
	@try { [world setScenarioWithPList:plist]; }
	@catch (NSString *msg) { @throw [@"500 " stringByAppendingString:msg]; }
}
// utility command
#import "noGUIInfo.h"
- (void)version {
	code = 200;
	type = @"text/plain";
	content = [NSString stringWithUTF8String:version];
}
- (void)sysInfo {
	NSMutableDictionary *dict = NSMutableDictionary.new;
	int mib[2] = { CTL_HW, HW_MODEL };
	char modelName[64];
	size_t dataSize = 64;
	if (sysctl(mib, 2, modelName, &dataSize, NULL, 0) >= 0)
		dict[@"model"] = [NSString stringWithUTF8String:modelName];
	double loadavg[3];
	getloadavg(loadavg, 3);
	dict[@"loadaverage"] = @[@(loadavg[0]),@(loadavg[1]),@(loadavg[2])];
	struct rusage ru = {0};
	getrusage(RUSAGE_SELF, &ru);
	dict[@"rss"] = @(ru.ru_maxrss);
	NSProcessInfo *pInfo = NSProcessInfo.processInfo;
	dict[@"os"] = pInfo.operatingSystemVersionString;
	dict[@"ncpu"] = @(pInfo.processorCount);
	dict[@"memsize"] = @(pInfo.physicalMemory);
	dict[@"uptime"] = @(pInfo.systemUptime);
	dict[@"thermalState"] = @(pInfo.thermalState);
	[self setJSONDataAsResponse:dict];
}
@end

#define COM(c)	@#c:^(ProcContext *ctx){[ctx c];}
void init_context(void) {
	commandDict = @{
		COM(getWorldID), COM(closeWorld), COM(newWorld),
		COM(getParams), COM(setParams),
		COM(getVaccineList), COM(setVaccineList), COM(getVariantList), COM(setVariantList),
		COM(loadVariantsAndVaccines),
		COM(start), COM(step), COM(stop), COM(reset), COM(addInfected),
		COM(getIndexes), COM(getDistribution),
		COM(getPopulation), COM(getPopulation2),
		COM(periodicReport), COM(quitReport), COM(changeReport),
		COM(getScenario), COM(setScenario),
		COM(submitJob), COM(getJobStatus), COM(getJobQueueStatus),
		COM(getJobInfo), COM(stopJob), COM(getJobResults), COM(deleteJob),
		COM(saveState), COM(loadState), COM(removeState),
		COM(getState), COM(putState),
		COM(version), COM(sysInfo) };
}
