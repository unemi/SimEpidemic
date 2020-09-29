//
//  noGUI.m
//  simepidemic
//
//  Created by Tatsuo Unemi on 2020/08/31.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <sys/socket.h>
#import <arpa/inet.h>
#import <signal.h>
#import <os/log.h>
#import "noGUI.h"
#import "AppDelegate.h"
#import "StatPanel.h"
#import "noGUIInfo.h"
#import "ProcContext.h"
#define SERVER_PORT 8000U

static int soc = -1; // TCP stream socket
static struct sockaddr_in nameTemplate = {
	sizeof(struct sockaddr_in), AF_INET, EndianU16_NtoB(SERVER_PORT), {INADDR_ANY}
};
static void unix_error_msg(NSString *msg, int code) {
	os_log_error(OS_LOG_DEFAULT, "%@ %d: %{errno}d.\n", msg, code, errno);
	if (code > 0) exit(code);
}

NSMutableDictionary<NSString *, id> *infoDictionary = nil;
NSMutableDictionary<NSString *, Document *> *defaultDocuments = nil;
NSMutableDictionary<NSString *, Document *> *theDocuments = nil;
NSUInteger JSONOptions = 0;
NSInteger maxPopSize = 1000000, maxNDocuments = 128, maxRuntime = 48*3600,
	documentTimeout = 20*60, maxJobsInQueue = 64, maxTrialsAtSameTime = 4,
	jobRecExpirationHours = 24*7;
NSString *fileDirectory = nil, *dataDirectory = nil;
NSDictionary *extToMime, *codeMeaning, *indexNames;
NSArray *distributionNames;
NSDateFormatter *dateFormat = nil;
static NSString *infoFilename = @"simeipInfo.plist",
	*keyUniqIDCounter = @"uniqIDCounter", *keyUniqIDChars = @"uniqIDChars";
static BOOL infoChanged = NO;

#define N_UNIQ_CHARS 61
NSString *new_uniq_string(void) {
	static char chars[N_UNIQ_CHARS + 1];
	static NSUInteger counter = 0;
	NSNumber *num; NSString *str;
	if ((num = infoDictionary[keyUniqIDCounter])) counter = num.integerValue;
	if ((str = infoDictionary[keyUniqIDChars]) == nil || str.length != N_UNIQ_CHARS) {
		for (int i = 0; i < N_UNIQ_CHARS+1; i ++) chars[i] =
			(i < 10)? '0' + i : (i < 36)? 'A' - 10 + i : 'a' - 36 + i;
		for (int i = 0; i < N_UNIQ_CHARS; i ++) {
			int k = (random() % (N_UNIQ_CHARS+1 - i)) + i;
			char c = chars[i]; chars[i] = chars[k]; chars[k] = c;
		}
		chars[N_UNIQ_CHARS] = '\0';
		infoDictionary[keyUniqIDChars] = [NSString stringWithUTF8String:chars];
	} else memcpy(chars, str.UTF8String, str.length);
	char buf[32];
	NSUInteger j = (++ counter), k = 0x8000000000000000UL, n;
	if (j >= k) j = counter = 0;	// almost impossible but for safety.
	for (NSUInteger h = 0x4000000000000000UL, l = 1; h > l;
		h >>= 1, l <<= 1) if (j & l) k |= h;
	for (n = 0; k != 0 && n < 31; n ++, k /= 61) buf[n] = chars[k % 61];
	infoDictionary[keyUniqIDCounter] = @(counter);
	infoChanged = YES;
	buf[n] = '\0';
	return [NSString stringWithUTF8String:buf];
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
	os_log_debug(OS_LOG_DEFAULT,
		"Receiving thread started %{network:in_addr}d (%d).", ipaddr, desc);
	ProcContext *context = [ProcContext.alloc initWithSocket:desc ip:ipaddr];
	BOOL isConnected = YES;
	while (isConnected) @autoreleasepool { @try {
		if ([context receiveData:-1] > 0) [context makeResponse];
		else @throw @0;
	} @catch (id _) { isConnected = NO; } }
	close(desc);
	os_log_debug(OS_LOG_DEFAULT, "Receiving thread ended (%d).", desc);
}}
void connection_thread(void) {
	unsigned int addrlen;
	int desc = -1;
	os_log_debug(OS_LOG_DEFAULT, "Connection thread started.");
	NSThread.currentThread.name = @"Network connection";
	for (;;) @autoreleasepool {
		struct sockaddr_in name;
		for (;;) {
			name = nameTemplate;
			addrlen = sizeof(name);
			desc = accept(soc, (struct sockaddr *)&name, &addrlen);
			if (desc < 0) unix_error_msg(@"accept", desc);
			else break;
		}
		[NSThread detachNewThreadWithBlock:
			^{ interaction_thread(desc, name.sin_addr.s_addr); }];
	}
//	close(soc); soc = -1;
#ifdef DEBUG
//	NSLog(@"Connection thread ended.");
#endif
}
void catch_signal(int sig) {
#ifdef DEBUG
	fprintf(stderr, "I caught a signal %d.\n", sig);
#endif
	if (sig == SIGTERM) {
		if (infoChanged) {
			NSData *infoData = [NSPropertyListSerialization
				dataWithPropertyList:infoDictionary
				format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
			if (infoData) [infoData writeToFile:
				[dataDirectory stringByAppendingPathComponent:infoFilename] atomically:YES];
		}
// better to wait for all of the sending processes completed.
//		shutdown(soc, SHUT_RDWR);
		os_log(OS_LOG_DEFAULT, "Stopped.");
		[NSApp terminate:nil];
	}
}
int main(int argc, const char * argv[]) {
@autoreleasepool {
	int port = SERVER_PORT;
	short err;
// Check command options
	for (NSInteger i = 1; i < argc; i ++) if (argv[i][0] == '-') {
		if (strcmp(argv[i], "-p") == 0 || strcmp(argv[i], "--port") == 0) {
			if (i + 1 < argc) port = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-f") == 0 || strcmp(argv[i], "--format") == 0) {
			if (i + 1 < argc) JSONOptions = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-d") == 0 || strcmp(argv[i], "--directory") == 0) {
			if (i + 1 < argc) fileDirectory = path_from_unix_string(argv[++ i]);
		} else if (strcmp(argv[i], "-D") == 0 || strcmp(argv[i], "--dataStorage") == 0) {
			if (i + 1 < argc) dataDirectory = path_from_unix_string(argv[++ i]);
		} else if (strcmp(argv[i], "-s") == 0 || strcmp(argv[i], "--maxPopSize") == 0) {
			if (i + 1 < argc) maxPopSize = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-n") == 0 || strcmp(argv[i], "--maxNDocuments") == 0) {
			if (i + 1 < argc) maxNDocuments = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-r") == 0 || strcmp(argv[i], "--maxRuntime") == 0) {
			if (i + 1 < argc) maxRuntime = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-t") == 0 || strcmp(argv[i], "--documentTimeout") == 0) {
			if (i + 1 < argc) documentTimeout = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "-e") == 0 || strcmp(argv[i], "--jobExprHours") == 0) {
			if (i + 1 < argc) jobRecExpirationHours = atoi(argv[++ i]);
		} else if (strcmp(argv[i], "--version") == 0) {
			printf("%s\n", version); exit(0);
		} else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
			printf("\n"); exit(0);
		}
	}
	fileDirectory = adjust_dir_path(fileDirectory);
	dataDirectory = adjust_dir_path(dataDirectory);
#ifdef DEBUG
printf("fileDir=%s\ndataDir=%s\n", fileDirectory.UTF8String, dataDirectory.UTF8String);
#endif
//
	NSData *infoData = [NSData dataWithContentsOfFile:
		[dataDirectory stringByAppendingPathComponent:infoFilename]];
	if (infoData != nil) infoDictionary = [NSPropertyListSerialization
		propertyListWithData:infoData options:NSPropertyListMutableContainers
		format:NULL error:NULL];
	if (infoDictionary == nil) infoDictionary = NSMutableDictionary.new;
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
//
	signal(SIGTERM, catch_signal);
// Open the server side socket to wait for connection request from a client.
	nameTemplate.sin_port = EndianU16_NtoB((unsigned short)port);
	soc = socket(PF_INET, SOCK_STREAM, 0);
	if (soc < 0) unix_error_msg(@"TCP socket", 1);
	if ((err = bind(soc, (struct sockaddr *)&nameTemplate, sizeof(nameTemplate))))
		unix_error_msg(@"TCP bind", 2);
	if ((err = listen(soc, 1))) unix_error_msg(@"listen", 3);

// Prepare and start the Runloop to use Cocoa framework.
	NSApplication *app = NSApplication.sharedApplication;
	app.activationPolicy = NSApplicationActivationPolicyRegular;
	app.delegate = AppDelegate.new;
	defaultDocuments = NSMutableDictionary.new;
	theDocuments = NSMutableDictionary.new;
	os_log(OS_LOG_DEFAULT, "Started by %@.", NSProcessInfo.processInfo.userName);
	[app run];
}
	return 0;
}
