//
//  PeriodicReporter.m
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/10/08.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "PeriodicReporter.h"
#import "noGUI.h"
#import "Document.h"
#import "StatPanel.h"
#import "DataCompress.h"
#import <os/log.h>
#import <zlib.h>
#define BUF_SIZE 8192
#define COMMENT_INTERVAL 10.

static NSMutableDictionary<NSString *, PeriodicReporter *> *theReporters = nil;

@interface PeriodicReporter () {
	Document * __weak document;
	int desc;
	uint32 ip4addr;
	z_stream strm;
	NSInteger prevRepStep, byteCount, workingTime;
	NSDate *workBegin;
	NSArray<NSString *> *repItemsIdx, *repItemsDly, *repItemsDst, *repItemsExt;
	BOOL repPopulation;
	NSData *(*dataOfPopInfo)(Document *);
	unsigned long lastReportTime, lastCommentTime;
	CGFloat repInterval;
	NSTimer *idlingTimer;
	NSLock *configLock;
}
@end

@implementation PeriodicReporter
static NSArray<NSString *> *extraIndexes = nil;
static NSString *keyPopulation = @"population";
static NSArray<NSString *> *valid_report_item_names(void) {
	static NSArray<NSString *> *validNames = nil;
	if (validNames == nil) {
		extraIndexes = @[@"step", @"days", @"testPositiveRate"];
		NSString *names[extraIndexes.count
			+ indexNames.count * 2 + distributionNames.count + 1];
		NSInteger k;
		for (k = 0; k < extraIndexes.count; k ++) names[k] = extraIndexes[k];
		NSEnumerator *enm = indexNames.keyEnumerator;
		for (NSInteger i = 0; i < indexNames.count; i ++) names[k ++] = enm.nextObject;
		enm = indexNames.keyEnumerator;
		for (NSInteger i = 0; i < indexNames.count; i ++)
			names[k ++] = [(NSString *)enm.nextObject stringByAddingFirstWord:@"daily"];
		for (NSInteger i = 0; i < distributionNames.count; i ++)
			names[k ++] = distributionNames[i];
		names[k ++] = keyPopulation;
		validNames = [NSArray arrayWithObjects:names count:k];
	}
	return validNames;
}
- (void)setupWithQuery:(NSDictionary *)query init:(BOOL)forInit {
	NSString *report = query[@"report"], *intervalStr = query[@"interval"],
		*fmtStr = query[@"popFormat"];
	if (report != nil) {
		report = report.stringByRemovingPercentEncoding;
		NSError *error;
		NSArray<NSString *> *idxs = [NSJSONSerialization JSONObjectWithData:
			[report dataUsingEncoding:NSUTF8StringEncoding]
			options:0 error:&error];
		if (idxs == nil) @throw error.localizedDescription;
		if (![idxs isKindOfClass:NSArray.class]) @throw
			@"Report information should be an array of index names.";
		NSArray *validNames = valid_report_item_names();
		NSMutableSet *ms = NSMutableSet.new, *trash = NSMutableSet.new;
		for (NSString *name in idxs)
			if ([validNames containsObject:name]) [ms addObject:name];
		BOOL repPop = NO;
		NSInteger n = ms.count, nn = 0, nd = 0, nD = 0, nE = 0;
		NSString *an[n], *ad[n], *aD[n], *aE[n];
		for (NSString *name in ms) {
			if (indexNames[name] != nil) an[nn ++] = name;
			else if ([name hasPrefix:@"daily"]) {
				NSString *key = name.stringByRemovingFirstWord;
				if (indexNames[key] != nil) ad[nd ++] = key;
			} else if ([distributionNames containsObject:name]) aD[nD ++] = name;
			else if ([extraIndexes containsObject:name]) aE[nE ++] = name;
			else if ([name isEqualToString:keyPopulation]) repPop = YES;
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
		[configLock lock];
		repPopulation = repPop;
		repItemsIdx = [NSArray arrayWithObjects:an count:nn];
		repItemsDly = [NSArray arrayWithObjects:ad count:nd];
		repItemsDst = [NSArray arrayWithObjects:aD count:nD];
		repItemsExt = [NSArray arrayWithObjects:aE count:nE];
		[configLock unlock];
	MY_LOG_DEBUG("Idx:%ld, Dly:%ld, Dst:%ld, Ext:%ld, Intv=%.3f, Pop:%@",
		nn, nd, nD, nE, repInterval, repPopulation? @"YES" : @"NO");
	} else if (forInit) @throw @"Report request must be attached.";
	[configLock lock];
	if (intervalStr != nil) {
		repInterval = intervalStr.doubleValue;
		if (repInterval <= 0.) repInterval = 1.;
	} else if (forInit) repInterval = 1.;
	if (fmtStr != nil) dataOfPopInfo =
		(fmtStr.integerValue != 2)? JSON_pop : JSON_pop2;
	[configLock unlock];
}
- (instancetype)initWithDocument:(Document *)doc addr:(uint32)addr desc:(int)dsc {
	if (!(self = [super init])) return nil;
	strm.data_type = Z_TEXT;
	int ret = deflateInit(&strm, Z_BEST_COMPRESSION);
	if (ret != Z_OK) {
		MY_LOG("Couldn't initialize a data compresser (%d).", ret);
		exit(EXIT_FAILED_DEFLATER);	// this is a fatal error!
	}
	document = doc;
	ip4addr = addr;
    desc = dsc;
    _ID = new_uniq_string();
    configLock = NSLock.new;
    if (theReporters == nil) theReporters = NSMutableDictionary.new;
    theReporters[_ID] = self;
    prevRepStep = -1;
    dataOfPopInfo = JSON_pop;	// default format
	MY_LOG_DEBUG("Repoter %@(%d) was created for world %@.", _ID, desc, doc.ID);
 	return self;
}
- (void)sendBytes:(const void *)bytes length:(uint32)dataLen {
//NSLog(@"Will send %d source bytes.", dataLen);
	unsigned char *outBuf = malloc(BUF_SIZE);
	strm.next_in = (z_const Bytef *)bytes;
	strm.avail_in = dataLen;
	for (;;) {
		strm.avail_out = BUF_SIZE;
		strm.next_out = outBuf;
//NSLog(@"deflate %d of %d bytes.", strm.avail_in, dataLen);
		int ret = deflate(&strm, Z_SYNC_FLUSH);
//NSLog(@"deflate returned %d", ret);
		if (ret != Z_OK && ret != Z_BUF_ERROR) { free(outBuf); @throw @(ret); }
		NSInteger nBytes = BUF_SIZE - strm.avail_out;
//NSLog(@"Will send %ld compressed bytes.", nBytes);
		send_bytes(desc, (const char *)outBuf, nBytes);
		byteCount += nBytes;
		if (strm.avail_in <= 0) {
			unsigned rBytes; int rBits;
			int ret = deflatePending(&strm, &rBytes, &rBits);
			if (ret != Z_OK) { free(outBuf); @throw @(ret); }
			if (rBytes + rBits == 0) break;
//NSLog(@"%d bytes %d bits are remaining in output buffer.", rBytes, rBits);
		}
	}
	free(outBuf);
//NSLog(@"Did end send %d Bytes.", dataLen);
}
//
static NSArray *index_array(StatData *stat, NSInteger nItems, NSString *name) {
	NSNumber *num;
	NSInteger idx;
	if ((num = indexNameToIndex[name])) idx = num.integerValue;
	else if ((num = testINameToIdx[name])) idx = num.integerValue + NStateIndexes;
	else return @[];
	return make_history(stat, nItems, ^(StatData *st){ return @(st->cnt[idx]); });
}
- (BOOL)sendReport {
	@autoreleasepool {
	[document popLock];
	NSInteger step = document.runtimeParamsP->step,
		stepsPerDay = document.worldParamsP->stepsPerDay;
	StatInfo *statInfo = document.statInfo;
	NSInteger skp = statInfo.skipSteps, n = step / skp - prevRepStep / skp;
	if (n <= 0) { [document popUnlock]; return NO; }
	NSMutableDictionary *md = NSMutableDictionary.new;
	StatData *stat = statInfo.statistics;
	[configLock lock];
	NSArray<NSString *> *Idx = repItemsIdx, *Dly = repItemsDly,
		*Dst = repItemsDst, *Ext = repItemsExt;
	BOOL repPop = repPopulation;
	NSData *(*popProc)(Document *) = dataOfPopInfo;
	[configLock unlock];
	for (NSString *name in Idx) md[name] = index_array(stat, n, name);
	stat = statInfo.transit;
	skp = statInfo.skipDays;
	n = step / stepsPerDay / skp - prevRepStep / stepsPerDay / skp;
	if (n > 0) for (NSString *name in Dly) md[name] = index_array(stat, n, name);
	NSDictionary<NSString *, NSArray<MyCounter *> *>
		*nameMap = distribution_name_map(document);
	for (NSString *name in Dst) {
		NSArray<MyCounter *> *hist = nameMap[name];
		if (hist != nil) md[name] = dist_cnt_array(hist);
	}
	for (NSString *name in Ext) {
		if ([name isEqualToString:@"step"]) md[name] = @(step);
		else if ([name isEqualToString:@"days"]) md[name] = @(step / stepsPerDay);
		else if ([name isEqualToString:@"testPositiveRate"])
			md[name] = make_history(stat, n, ^(StatData *st) { return @(st->pRate); });
	}
	NSData *popData = repPop? popProc(document) : nil;
	[document popUnlock];
	prevRepStep = step;
	NSError *error;
	NSData *data = [NSJSONSerialization dataWithJSONObject:md options:0 error:&error];
	MY_LOG_DEBUG("idx data:%ld bytes, pop data:%ld bytes", data.length, popData.length);
	NSInteger bufLen = data.length + 10 + ((popData == nil)? 0 : popData.length + 29);
	char *bytes = malloc(bufLen), *p = bytes;
	memcpy(p, "data: ", 6); p += 6;
	memcpy(p, data.bytes, data.length); p += data.length;
	memcpy(p, "\r\n\r\n", 4);
	if (popData != nil) {
		p += 4;
		memcpy(p, "event: population\r\ndata: ", 25); p += 25;
		memcpy(p, popData.bytes, popData.length); p += popData.length;
		memcpy(p, "\r\n\r\n", 4);
	}
	[self sendBytes:bytes length:(uint32)bufLen];
	free(bytes);
	}
	return YES;
}
- (void)sendComment:(unsigned long)now {
	[self sendBytes:":\r\n\r\n" length:5];
	lastCommentTime = now;
}
- (void)sendReportPeriodic {
	if (desc < 0) return;
	unsigned long now = current_time_us();
	if ((now - lastReportTime) * 1e-6 >= repInterval) {
		if ([self sendReport]) lastReportTime = now;
	}
	if ((now - ((lastReportTime > lastCommentTime)? lastReportTime : lastCommentTime))
		* 1e-6 > COMMENT_INTERVAL) [self sendComment:now];
}
- (void)reset {
	if (desc < 0) return;
	prevRepStep = -1;
	[self sendReport];
}
- (void)start {
	if (idlingTimer != nil) { [idlingTimer invalidate]; idlingTimer = nil; }
	workBegin = NSDate.date;
	MY_LOG("%@ Repoter %@(%d) started.", ip4_string(ip4addr), _ID, desc);
}
- (void)cumulateWorkTime {
	if (workBegin == nil) return;
	CGFloat interval = [NSDate.date timeIntervalSinceDate:workBegin];
	workingTime += interval * 1000;
	workBegin = nil;
}
- (void)pause {
	if (desc < 0) return;
	[self sendReport];
	in_main_thread(^{
	self->idlingTimer = [NSTimer scheduledTimerWithTimeInterval:COMMENT_INTERVAL repeats:YES
		block:^(NSTimer * _Nonnull timer) {
			if (self->desc < 0) {
				[timer invalidate]; self->idlingTimer = nil;
			} else [self sendComment:current_time_us()];
		}];
	});
	[self cumulateWorkTime];
}
- (void)quit {
	if (desc < 0) return;
	(void)deflateEnd(&strm);
	[self cumulateWorkTime];
	NSNumberFormatter *numFmt = NSNumberFormatter.new;
	numFmt.numberStyle = NSNumberFormatterDecimalStyle;
	MY_LOG("%@ Repoter %@(%d) quits. %.3f sec. %@ bytes.", ip4_string(ip4addr),
		_ID, desc, workingTime / 1000., [numFmt stringFromNumber:@(byteCount)]);
	desc = -1;
}
- (BOOL)connectionWillClose:(int)dsc {
	if (dsc != desc) return NO;
	else { [self quit]; return YES; }
}
- (void)removeFromDoc {
	[document removeReporter:self];
}
@end

@implementation ProcContext (PeriodicReportExtension)
- (void)periodicReport {
	[self checkDocument];
	PeriodicReporter *rep = [PeriodicReporter.alloc
		initWithDocument:document addr:ip4addr desc:desc];
	[rep setupWithQuery:query init:YES];
	nReporters ++;
	Document *doc = document;
	postProc = ^{
		NSString *idInfo = [NSString stringWithFormat:
			@"event: process\r\ndata: %@\r\n\r\n", rep.ID];
		[rep sendBytes:idInfo.UTF8String length:(uint32)idInfo.length];
		if (doc.running) [rep sendReport];
		else [rep pause];
		[doc addReporter:rep];
	};
	fileSize = 0;
	content = nil;
	type = @"text/event-stream";
	moreHeader = @"Content-Encoding: deflate\n";
	code = 200;
}
- (PeriodicReporter *)reporterFromID:(NSString *__nullable *)IDreturn {
	NSString *repID = query[@"process"];
	if (repID == nil) @throw @"417 Report process ID is missing.";
	PeriodicReporter *rep = theReporters[repID];
	if (rep == nil) @throw [NSString stringWithFormat:
		@"500 Periodic report process %@ does not exist.", repID];
	if (IDreturn != NULL) *IDreturn = repID;
	return rep;
}
- (void)quitReport {
	NSString *repID;
	PeriodicReporter *rep = [self reporterFromID:&repID];
	[theReporters removeObjectForKey:repID];
	[rep removeFromDoc];
	[rep quit];
	nReporters --;
	code = 0;
}
- (void)changeReport {
	PeriodicReporter *rep = [self reporterFromID:NULL];
	[rep setupWithQuery:query init:NO];
	code = 0;
}
@end
