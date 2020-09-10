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
#import "noGUIInfo.h"
#import "ProcContext.h"
#define SERVER_PORT 8000U

static int soc = -1; // TCP stream socket
static struct sockaddr_in nameTemplate = {
	sizeof(struct sockaddr_in), AF_INET, EndianU16_NtoB(SERVER_PORT), {INADDR_ANY}
};
static void unix_error_msg(NSString *msg, int code) {
	fprintf(stderr, "%s: %s.\n", msg.UTF8String, strerror(errno));
	if (code > 0) exit(code);
}

NSMutableDictionary<NSNumber *, Document *> *theDocuments = nil;
NSUInteger JSONOptions = 0;
NSString *fileDirectory;
NSDictionary *extToMime, *codeMeaning, *indexNames;
NSDateFormatter *dateFormat = nil;

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
static void interaction_thread(int desc, uint32 ipaddr) {
@autoreleasepool {
	NSThread.currentThread.name = @"Network interaction";
//	char nameBuf[20];
	//sprintf(nameBuf, "%d.%d.%d.%d",
#ifdef DEBUG
	ipaddr = EndianU32_BtoN(ipaddr);
	NSLog(@"Receiving thread started %d.%d.%d.%d (%d).",
		ipaddr>>24, (ipaddr>>16)&255, (ipaddr>>8)&255, ipaddr&255, desc);
#endif
	ProcContext *context = [ProcContext.alloc initWithSocket:desc ip:ipaddr];
	BOOL isConnected = YES;
	while (isConnected) @autoreleasepool { @try {
		if ([context receiveData:-1] > 0) [context makeResponse];
		else @throw @0;
	} @catch (id _) { isConnected = NO; } }
	close(desc);
#ifdef DEBUG
	NSLog(@"Receiving thread ended (%d).", desc);
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
	theDocuments = NSMutableDictionary.new;
	[app run];
}
	return 0;
}
