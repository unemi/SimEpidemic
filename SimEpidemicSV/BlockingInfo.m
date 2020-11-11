//
//  BlockingInfo.m
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/10/17.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <arpa/inet.h>
#import "BlockingInfo.h"
#import "noGUI.h"

static CGFloat penalty[] = {
	2.,	// 400 Bad Request
	1., // 401
	1., // 402 Payment Required
	1., // 403 Forbidden
	.3,	// 404 Not Found
	2., // 405 Method Not Allowed
	1., // 406 Not Acceptable
	.2, // 408 Request Timeout
	1., // 409 Conflict
	1., // 410 Gone
	1., // 411 Length Required
	1., // 412
	.3, // 413 Payload Too Large
	.3, // 414 URI Too Long
	2., // 415 Unsupported Media Type
	1., // 416
	1., // 417 Expectation Failed
};
#define BLOCK_EXPIRE (3600*24*2)
#define CODE_MAX 417
#define DECAY_BY_SEC .99999
#define BLOCK_TH 3.
#define IMMEDIATE_BLOCK 6.

static NSArray<NSRegularExpression *> *regexp_array(NSArray<NSString *> *strArr) {
	NSInteger n = strArr.count;
	if (n <= 0) return nil;
	NSError *error;
	NSRegularExpression *regs[n];
	for (NSInteger i = 0; i < n; i ++) {
		regs[i] = [NSRegularExpression regularExpressionWithPattern:strArr[i]
			options:0 error:&error];
		if (regs[i] == nil) {
			os_log_error(OS_LOG_DEFAULT, "RegExp: %@", error.localizedDescription);
			terminateApp(EXIT_FAILED_REGEXP);
		}
	}
	return [NSArray arrayWithObjects:regs count:n];
}
static CGFloat request_penalty(NSString *request) {
	static NSArray<NSRegularExpression *> *acceptable = nil;
	static NSArray<NSRegularExpression *> *prohibited = nil;
	if (acceptable == nil) {
		acceptable = regexp_array(@[@"\\AGET /apple-touch-icon\\.png ",
			@"\\AGET /apple-touch-icon-precomposed\\.png "]);
		prohibited = regexp_array(@[@"\\A\\P{Lu}", @"\\A\\p{Lu}\\P{Lu}",
			@"\\AGET /wp-content/", @"\\APOST /api/", @"\\A\\p{Lu}+ /boaform/",
			@"\\AGET /php", @"\\.php[ \\?]", @"\\.cgi[ \\?]", @"\\AGET /[\\.\\?]"]);
	}
	NSRange srcRng = {0, request.length};
	if (srcRng.length <= 4) return IMMEDIATE_BLOCK;
	for (NSRegularExpression *reg in acceptable) {
		NSRange rng = [reg rangeOfFirstMatchInString:request options:0 range:srcRng];
		if (rng.location != NSNotFound) return 0.;
	}
	for (NSRegularExpression *reg in prohibited) {
		NSRange rng = [reg rangeOfFirstMatchInString:request options:0 range:srcRng];
		if (rng.location != NSNotFound) return IMMEDIATE_BLOCK;
		//{ NSLog(@"prohibited.");break; }
	}
	return -1.;
}

@interface BlockingInfo () {
	NSDate *date;
	CGFloat point;
}
@end
@implementation BlockingInfo
- (instancetype)initWithPList:(NSArray *)plist {
	if (![plist isKindOfClass:NSArray.class]) return nil;
	if (plist.count != 3) return nil;
	if (![plist[1] isKindOfClass:NSDate.class]) return nil;
	if (![plist[2] isKindOfClass:NSNumber.class]) return nil;
	if (!(self = [super init])) return nil;
	date = plist[1]; point = [plist[2] doubleValue];
	return self;
}
- (void)revisePoint:(NSDate *)now {
	point *= pow(DECAY_BY_SEC, [now timeIntervalSinceDate:date]);
}
- (BOOL)shouldBlock { return point > BLOCK_TH; }
- (void)checkInWithCode:(int)code request:(NSString *)request {
	NSDate *now = NSDate.date;
	if (date != nil) [self revisePoint:now];
	date = now;
	CGFloat pnlty = request_penalty(request);
	if (pnlty < 0.) pnlty = (code >= 400 && code <= CODE_MAX)? penalty[code - 400] : 1.;
	point += pnlty;
	MY_LOG_DEBUG("block point = %.3f", point);
}
- (NSDate *)date { return date; }
- (NSArray *)plistWithKey:(NSNumber *)key { return @[key, date, @(point)]; }
@end

static NSMutableDictionary<NSNumber *, BlockingInfo *> *blockDict = nil;
static NSLock *blockDictLock = nil;
BOOL check_blocking(int code, uint32 ipaddr, NSString *request) {
	if (blockDictLock == nil) blockDictLock = NSLock.new;
	NSNumber *key = @(ipaddr);
	[blockDictLock lock];
	if (blockDict == nil) blockDict = NSMutableDictionary.new;
	BlockingInfo *info = blockDict[key];
	if (info == nil) blockDict[key] = info = BlockingInfo.new;
	[info checkInWithCode:code request:request];
	BOOL shouldBlock = [info shouldBlock];
	[blockDictLock unlock];
	return shouldBlock;
}
BOOL should_block_it(uint32 ipaddr) {
	if (ipaddr == inet_addr("193.27.229.26")) return YES;
	BOOL result = NO;
	[blockDictLock lock];
	BlockingInfo *info = blockDict[@(ipaddr)];
	if (info != nil) {
		[info revisePoint:NSDate.date];
		result = [info shouldBlock];
	}
	[blockDictLock unlock];
	return result;
}
void schedule_clean_up_blocking_info(void) {
	[NSTimer scheduledTimerWithTimeInterval:3600*24 repeats:YES block:
	^(NSTimer * _Nonnull timer) {
		if (blockDict == nil) return;
	@autoreleasepool {
		NSDate *now = NSDate.date;
		NSMutableArray<NSNumber *> *removeKeys = NSMutableArray.new;
		[blockDictLock lock];
		[blockDict enumerateKeysAndObjectsUsingBlock:
			^(NSNumber *key, BlockingInfo *obj, BOOL *stop) {
			if ([now timeIntervalSinceDate:obj.date] > BLOCK_EXPIRE)
				[removeKeys addObject:key];
		}];
		for (NSNumber *key in removeKeys) [blockDict removeObjectForKey:key];
		NSInteger remaining = blockDict.count;
		[blockDictLock unlock];
		if (removeKeys.count > 0)
			MY_LOG("Blocking Info: %ld entries were removed. %ld are remaining.",
				removeKeys.count, remaining);
	}}];
}
void block_list_from_plist(NSArray *plist) {
	NSInteger n = plist.count;
	if (n <= 0) return;
	NSNumber *keys[n];
	BlockingInfo *infos[n];
	for (NSInteger i = 0; i < n; i ++) {
		NSArray *item = plist[i];
		if (![item isKindOfClass:NSArray.class]) break;
		if (item.count != 3) break;
		keys[i] = item[0];
		infos[i] = [BlockingInfo.alloc initWithPList:item];
	}
	blockDict = [NSMutableDictionary dictionaryWithObjects:infos forKeys:keys count:n];
}
NSArray *block_list(void) {
	NSArray *result;
	[blockDictLock lock];
	NSInteger n = blockDict.count, i = 0;
	if (n > 0) {
		NSArray *arrs[n];
		for (NSNumber *key in blockDict)
			arrs[i ++] = [blockDict[key] plistWithKey:key];
		result = [NSArray arrayWithObjects:arrs count:n];
	} else result = @[];
	[blockDictLock unlock];
	return result;
}
