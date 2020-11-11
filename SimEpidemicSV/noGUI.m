//
//  noGUI.m
//  simepidemic
//
//  Created by Tatsuo Unemi on 2020/08/31.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <sys/socket.h>
#import <sys/stat.h>
#import <arpa/inet.h>
#import <signal.h>
#import "noGUI.h"
#import "../SimEpidemic/Sources/AppDelegate.h"
#import "Document.h"
#import "StatPanel.h"
#import "noGUIInfo.h"
#import "ProcContext.h"
#import "BatchJob.h"
#import "BlockingInfo.h"
#define SERVER_PORT 8000U

static int soc = -1; // TCP stream socket
static struct sockaddr_in nameTemplate = {
	sizeof(struct sockaddr_in), AF_INET, EndianU16_NtoB(SERVER_PORT), {INADDR_ANY}
};
void unix_error_msg(NSString *msg, int code) {
	MY_LOG("%@ %d: %s.", msg, code, strerror(errno));
	if (code > 0) exit(code);
}

NSMutableDictionary<NSString *, id> *infoDictionary = nil;
NSMutableDictionary<NSString *, Document *> *defaultDocuments = nil;
NSMutableDictionary<NSString *, Document *> *theDocuments = nil;
NSUInteger JSONOptions = 0;
uint32 BCA4Contract = INADDR_BROADCAST;
NSInteger maxPopSize = 1000000, maxNDocuments = 128, maxRuntime = 48*3600,
	documentTimeout = 20*60, maxJobsInQueue = 64, maxTrialsAtSameTime = 4,
	jobRecExpirationHours = 24*7;
NSString *fileDirectory = nil, *dataDirectory = nil, *logFilePath = nil;
NSDictionary *extToMime, *codeMeaning, *indexNames;
NSArray *distributionNames;
NSDictionary *indexNameToIndex = nil, *testINameToIdx = nil;
NSDateFormatter *dateFormat = nil;
static NSString *pidFilename = @"pid", *IDCntFilename = @"IDCount",
	*infoFilename = @"simeipInfo.plist",
	*keyUniqIDCounter = @"uniqIDCounter", *keyUniqIDChars = @"uniqIDChars",
	*keyBlockList = @"blockList",
	*logFilename = @"log";

static void save_info_dict(void) {
	NSData *infoData = [NSPropertyListSerialization
		dataWithPropertyList:infoDictionary
		format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
	if (infoData) [infoData writeToFile:
		[dataDirectory stringByAppendingPathComponent:infoFilename] atomically:YES];
}
static NSLock *uniqStrLock = nil;
#define N_UNIQ_CHARS 61
NSString *new_uniq_string(void) {
	static NSString *IDCntPath = nil;
	static char chars[N_UNIQ_CHARS + 1];
	static NSUInteger counter = 0;
	if (uniqStrLock == nil) uniqStrLock = NSLock.new;
	[uniqStrLock lock];
	if (IDCntPath == nil) {
		IDCntPath = [dataDirectory stringByAppendingPathComponent:IDCntFilename];
		NSString *str = [NSString stringWithContentsOfFile:IDCntPath
			encoding:NSUTF8StringEncoding error:NULL];
		if (str != nil) counter = str.integerValue;
		else {	// for version transition
			NSNumber *num = infoDictionary[keyUniqIDCounter];
			if (num != nil) {
				counter = num.integerValue;
				[infoDictionary removeObjectForKey:keyUniqIDCounter];
			}
		}
		counter ++;
		if ((str = infoDictionary[keyUniqIDChars]) == nil || str.length != N_UNIQ_CHARS) {
			for (int i = 0; i < N_UNIQ_CHARS+1; i ++) chars[i] =
				(i < 10)? '0' + i : (i < 36)? 'A' - 10 + i : 'a' - 36 + i;
			for (int i = 0; i < N_UNIQ_CHARS; i ++) {
				int k = (random() % (N_UNIQ_CHARS+1 - i)) + i;
				char c = chars[i]; chars[i] = chars[k]; chars[k] = c;
			}
			chars[N_UNIQ_CHARS] = '\0';
			infoDictionary[keyUniqIDChars] = [NSString stringWithUTF8String:chars];
			save_info_dict();
		} else memcpy(chars, str.UTF8String, str.length);
	} else counter ++;
	NSError *error;
	if (![@(counter).stringValue writeToFile:IDCntPath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
		MY_LOG("Could not write ID Counter: %@.", error.localizedDescription);
		terminateApp(EXIT_FAILED_IDCNT);  
	}
	char buf[32];
	NSUInteger j = counter, k = 0x8000000000000000UL, n;
	if (j >= k) j = counter = 0;	// almost impossible but for safety.
	for (NSUInteger h = 0x4000000000000000UL; j > 0 && h > 0;
		h >>= 1, j >>= 1) if (j & 1) k |= h;
	for (n = 0; k > 0 && n < 31; n ++, k /= 61) buf[n] = chars[(k + n) % 61];
	[uniqStrLock unlock];
	buf[n] = '\0';
	return [NSString stringWithUTF8String:buf];
}
NSString *ip4_string(uint32 ip4addr) {
	uint32 a = EndianU32_BtoN(ip4addr);
	return [NSString stringWithFormat:@"%d.%d.%d.%d",
		a >> 24, (a >> 16) & 0xff, (a >> 8) & 0xff, a & 0xff];
}
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
			if ([@[@"application", @"image", @"text"] containsObject:category])
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
static NSDictionary *index_name_to_index(void) {
	return @{
	@"susceptible":@(Susceptible),
	@"asymptomatic":@(Asymptomatic),
	@"symptomatic":@(Symptomatic),
	@"recovered":@(Recovered),
	@"died":@(Died),
	@"quarantineAsym":@(QuarantineAsym),
	@"quarantineSymp":@(QuarantineSymp)};
}
static NSDictionary *test_index_name_to_index(void) {
	return @{
	@"testTotal":@(TestTotal),
	@"testAsSymptom":@(TestAsSymptom),
	@"testAsContact":@(TestAsContact),
	@"testAsSuspected":@(TestAsSuspected),
	@"testPositive":@(TestPositive),
	@"testNegative":@(TestNegative)};
}
static NSString *path_from_unix_string(const char *pathName) {
	NSString *path = [NSString stringWithUTF8String:pathName];
	return [path hasPrefix:@"/"]? path :
		[NSString stringWithFormat:@"%@/%@",
		NSFileManager.defaultManager.currentDirectoryPath, path];
}
static NSString *adjust_dir_path(NSString *path) {
	if (path == nil) path = NSFileManager.defaultManager.currentDirectoryPath;
	return [path hasSuffix:@"/"]? path : [path stringByAppendingString:@"/"];
}
static void interaction_thread(int desc, uint32 ipaddr) {
@autoreleasepool {
	NSThread.currentThread.name = @"Network interaction";
	MY_LOG_DEBUG("Receiving thread started %@ (%d).", ip4_string(ipaddr), desc);
	ProcContext *context = [ProcContext.alloc initWithSocket:desc ip:ipaddr];
	BOOL isConnected = YES;
	while (isConnected) @autoreleasepool { @try {
		if ([context receiveData:-1 offset:0] > 0) {
			int code = [context makeResponse];
			if (code > 399 && code < 500)
				if (check_blocking(code, ipaddr, context.requestString)) {
					MY_LOG("%@ Blocked.", ip4_string(ipaddr));
					@throw @1;
				}
		} else @throw @0;
	} @catch (id _) { isConnected = NO; } }
	in_main_thread(^{
		[context connectionWillClose];
		close(desc);
	});
	MY_LOG_DEBUG( "Receiving thread ended (%d).", desc);
}}
void connection_thread(void) {
	uint32 addrlen;
	int desc = -1;
	MY_LOG_DEBUG("Connection thread started.");
	NSThread.currentThread.name = @"Network connection";
	for (;;) @autoreleasepool {
		struct sockaddr_in name;
		for (;;) {
			name = nameTemplate;
			addrlen = sizeof(name);
			desc = accept(soc, (struct sockaddr *)&name, &addrlen);
			if (desc < 0) unix_error_msg(@"accept", desc);
			else if (should_block_it(name.sin_addr.s_addr)) close(desc);
			else break;
		}
		[NSThread detachNewThreadWithBlock:
			^{ interaction_thread(desc, name.sin_addr.s_addr); }];
	}
}
static NSConditionLock *loggingLock = nil;
static NSMutableString *loggingString = nil;
static void logging_thread(void) {
	static NSDateFormatter *dateForm = nil;
	if (loggingLock == nil) loggingLock = NSConditionLock.new;
	for (int cnt = 0; cnt < 18;) {
		[loggingLock lockWhenCondition:1];
		@autoreleasepool { @try {
			NSError *error;
			NSFileManager *fmn = NSFileManager.defaultManager;
			NSDictionary *fInfo = [fmn attributesOfItemAtPath:logFilePath error:&error];
			if (fInfo == nil) @throw error;
			if ([fInfo[NSFileSize] integerValue] > (1L<<20)) {
				if (dateForm == nil) {
					dateForm = NSDateFormatter.new;
					dateForm.dateFormat = @"yyyyMMddHHmmss";
				}
				NSString *newPath = [NSString stringWithFormat:@"%@_%@.txt",
					logFilePath.stringByDeletingPathExtension,
					[dateForm stringFromDate:NSDate.date]];
				if (![fmn moveItemAtPath:logFilePath toPath:newPath error:&error])
					@throw error;
			}
		} @catch (NSError *err) {
			if ([err.domain isEqualToString:NSCocoaErrorDomain]
			  && err.code == NSFileReadNoSuchFileError)
			os_log(OS_LOG_DEFAULT, "Logfile, %@ will be newly created.",
				logFilePath.lastPathComponent);
			else os_log(OS_LOG_DEFAULT, "Logfile, %@", err.localizedDescription);
		} @catch (NSException *excp) {
			os_log(OS_LOG_DEFAULT, "Logfile, %@", excp.reason);
		}}
		FILE *logFile = fopen(logFilePath.UTF8String, "a");
		NSInteger cond = 0;
		if (logFile != NULL) {
			fputs(loggingString.UTF8String, logFile);
			fclose(logFile);
			[loggingString deleteCharactersInRange:(NSRange){0, loggingString.length}];
		} else cond = 1;
		[loggingLock unlockWithCondition:cond];
		if (cond == 1) { sleep(10); cnt ++; }
		else cnt = 0;
	}
	loggingLock = nil;
	os_log(OS_LOG_DEFAULT, "Gave up logging.");
}
void my_log(const char *fmt, ...) {
	if (loggingLock == nil) return;	// logging thread isn't running.
	static NSDateFormatter *dtFmt = nil;
	if (dtFmt == nil) {
		dtFmt = NSDateFormatter.new;
		dtFmt.dateFormat = @"yyyy/MM/dd HH:mm:ss";
	}
	va_list valist;
	va_start(valist, fmt);
	NSString *dtStr = [dtFmt stringFromDate:NSDate.date];
	CFStringRef fmtStr = CFStringCreateWithCString(NULL, fmt, kCFStringEncodingUTF8),
		msg = CFStringCreateWithFormatAndArguments(NULL, NULL, fmtStr, valist);
	[loggingLock lock];
	if (loggingString == nil) loggingString = NSMutableString.new;
	[loggingString appendFormat:@"%@ %@\n", dtStr, (__bridge NSString *)msg];
	[loggingLock unlockWithCondition:1];
	CFRelease(fmtStr);
	CFRelease(msg);
	va_end(valist);
}
BOOL shouldKeepRunning = YES;
int resultCode = 0;
void terminateApp(int code) {
	BOOL isMain = NSThread.isMainThread;
	MY_LOG_DEBUG("terminateApp called in %s thread.", isMain? "main" : "sub");
	infoDictionary[keyBlockList] = block_list();
	save_info_dict();
	[loggingLock lockWhenCondition:0];
	[loggingLock unlock];
	shutdown(soc, SHUT_RDWR);
	if (isMain) exit(code);
	else {
		resultCode = code;
		shouldKeepRunning = NO;
		[NSThread exit];
	}
}
void catch_signal(int sig) {
	MY_LOG_DEBUG("I caught a signal %d.\n", sig);
// better to wait for all of the sending processes completed.
	MY_LOG("Quit.");
	terminateApp(EXIT_NORMAL);
}
int main(int argc, const char * argv[]) {
@autoreleasepool {
	BOOL contractMode = NO;
	short err;
	uint16 port = SERVER_PORT;
// Check command options
	for (NSInteger i = 1; i < argc; i ++) if (argv[i][0] == '-') {
		if (strcmp(argv[i], "-p") == 0 || strcmp(argv[i], "--port") == 0) {
			if (i + 1 < argc) port = (uint16)atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-f") == 0 || strcmp(argv[i], "--format") == 0) {
			if (i + 1 < argc) JSONOptions = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-d") == 0 || strcmp(argv[i], "--documentRoot") == 0) {
			if (i + 1 < argc) fileDirectory = path_from_unix_string(argv[++ i]);
		} else if (strcmp(argv[i], "-D") == 0 || strcmp(argv[i], "--dataStorage") == 0) {
			if (i + 1 < argc) dataDirectory = path_from_unix_string(argv[++ i]);
		} else if (strcmp(argv[i], "-s") == 0 || strcmp(argv[i], "--maxPopSize") == 0) {
			if (i + 1 < argc) maxPopSize = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-n") == 0 || strcmp(argv[i], "--maxNWorlds") == 0) {
			if (i + 1 < argc) maxNDocuments = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-r") == 0 || strcmp(argv[i], "--maxRuntime") == 0) {
			if (i + 1 < argc) maxRuntime = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-t") == 0 || strcmp(argv[i], "--documentTimeout") == 0) {
			if (i + 1 < argc) documentTimeout = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-T") == 0 || strcmp(argv[i], "--maxTrials") == 0) {
			if (i + 1 < argc) maxTrialsAtSameTime = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-e") == 0 || strcmp(argv[i], "--jobExprHours") == 0) {
			if (i + 1 < argc) jobRecExpirationHours = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-c") == 0 || strcmp(argv[i], "--contract") == 0) {
			if (i + 1 < argc) BCA4Contract = inet_addr(argv[++ i]);
		} else if (strcmp(argv[i], "--version") == 0) {
			printf("%s\n", version); exit(EXIT_NORMAL);
		} else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
			printf("\n"); exit(EXIT_NORMAL);
		}
	}
	if (BCA4Contract != 0 && contractMode) {
		fprintf(stderr, "Cannot be both consigner and consignee.\n");
		exit(EXIT_INVALID_ARGS);
	}
//#define TEST
#ifdef TEST
	find_contractor();
	return 0;
#else
	fileDirectory = adjust_dir_path(fileDirectory);
	dataDirectory = adjust_dir_path(dataDirectory);
	logFilePath = [dataDirectory stringByAppendingPathComponent:
		[NSString stringWithFormat:@"%@_%04d.txt", logFilename, port]];
	[NSThread detachNewThreadWithBlock:^{ logging_thread(); }];
	MY_LOG_DEBUG("fileDir=%s\ndataDir=%s\n",
		fileDirectory.UTF8String, dataDirectory.UTF8String);
//
	NSData *infoData = [NSData dataWithContentsOfFile:
		[dataDirectory stringByAppendingPathComponent:infoFilename]];
	if (infoData != nil) infoDictionary = [NSPropertyListSerialization
		propertyListWithData:infoData options:NSPropertyListMutableContainers
		format:NULL error:NULL];
	if (infoDictionary == nil) infoDictionary = NSMutableDictionary.new;
	NSArray *blockList = infoDictionary[keyBlockList];
	if (blockList != nil) block_list_from_plist(blockList);
// Date formatter for "Date" item in the header	
	dateFormat = NSDateFormatter.new;
	dateFormat.locale = [NSLocale.alloc initWithLocaleIdentifier:@"en_GB"];
	dateFormat.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
	dateFormat.dateFormat = @"E, d MMM Y HH:mm:ss zzz"; //Mon, 31 Aug 2020 05:08:47 GMT
//
	codeMeaning = code_meaning_map();
	extToMime = ext_mime_map();
	indexNames = index_name_map();
	distributionNames =
		@[@"incubasionPeriod", @"recoveryPeriod", @"fatalPeriod", @"infects"];
	indexNameToIndex = index_name_to_index();
	testINameToIdx = test_index_name_to_index();
//
	signal(SIGTERM, catch_signal);
// Open the server side socket to wait for connection request from a client.
	nameTemplate.sin_port = EndianU16_NtoB(port);
	soc = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
	if (soc < 0) unix_error_msg(@"TCP socket", EXIT_SOCKET);
	if ((err = bind(soc, (struct sockaddr *)&nameTemplate, sizeof(nameTemplate))))
		unix_error_msg(@"TCP bind", EXIT_BIND);
	if ((err = listen(soc, 1))) unix_error_msg(@"TCP listen", EXIT_LISTEN);
//
	NSError *error;
	NSString *pidPath = [dataDirectory stringByAppendingPathComponent:
		[NSString stringWithFormat:@"%@_%04d", pidFilename, port]];
	if (![@(getpid()).stringValue writeToFile:pidPath
		atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
		MY_LOG("Couldn't write pid. %@", error.localizedDescription);
		terminateApp(EXIT_PID_FILE); }
//
	defaultDocuments = NSMutableDictionary.new;
	theDocuments = NSMutableDictionary.new;
	applicationSetups();	// defined in AppDelegate.m
	[NSThread detachNewThreadWithBlock:^{ connection_thread(); }];
// for debugging, (lldb) process handle -s0 -p1 SIGTERM
	schedule_clean_up_blocking_info(); // defined in BlockingInfo.m
	schedule_job_expiration_check(); // defined in BatchJob.m
	MY_LOG("%s launched by %@.", version, NSProcessInfo.processInfo.userName);
//	[NSRunLoop.currentRunLoop run];
	NSRunLoop *theRL = NSRunLoop.currentRunLoop;
	while (shouldKeepRunning)
		if (![theRL runMode:NSDefaultRunLoopMode beforeDate:
			[NSDate dateWithTimeIntervalSinceNow:10.]])
			{ resultCode = -4; break; }
	#endif
}
	return resultCode;
}
