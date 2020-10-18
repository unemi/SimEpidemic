//
//  BlockingInfo.m
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/10/17.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "BlockingInfo.h"
#import "noGUI.h"

static CGFloat penalty[] = {
	1.,	// 400 Bad Request
	1., // 401
	1., // 402 Payment Required
	1., // 403 Forbidden
	.1,	// 404 Not Found
	1., // 405 Method Not Allowed
	1., // 406 Not Acceptable
	.2, // 408 Request Timeout
	1., // 409 Conflict
	1., // 410 Gone
	1., // 411 Length Required
	1., // 412
	.2, // 413 Payload Too Large
	.2, // 414 URI Too Long
	2., // 415 Unsupported Media Type
	1., // 416
	1., // 417 Expectation Failed
};
#define CODE_MAX 417
#define DECAY_BY_SEC .98
#define BLOCK_TH 3.
@interface BlockingInfo () {
	NSDate *date;
	CGFloat point;
}
@end
@implementation BlockingInfo
- (void)revisePoint:(NSDate *)now {
	point *= pow(DECAY_BY_SEC, [now timeIntervalSinceDate:date]);
}
- (BOOL)shouldBlock { return point > BLOCK_TH; }
- (void)checkInWithCode:(int)code {
	NSDate *now = NSDate.date;
	if (date != nil) [self revisePoint:now];
	date = now;
	point += (code >= 400 && code <= CODE_MAX)? penalty[code - 400] : 1.;
	MY_LOG_DEBUG("block point = %.3f", point);
}
@end

static NSMutableDictionary<NSNumber *, BlockingInfo *> *blockDict = nil;
BOOL check_blocking(int code, uint32 ipaddr) {
	if (blockDict == nil) blockDict = NSMutableDictionary.new;
	NSNumber *key = @(ipaddr);
	BlockingInfo *info = blockDict[key];
	if (info == nil) blockDict[key] = info = BlockingInfo.new;
	[info checkInWithCode:code];
	return [info shouldBlock];
}
BOOL should_block_it(uint32 ipaddr) {
	BlockingInfo *info = blockDict[@(ipaddr)];
	if (info == nil) return NO;
	[info revisePoint:NSDate.date];
	return [info shouldBlock];
}
