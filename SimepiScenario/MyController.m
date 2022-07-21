//
//  Controller.m
//  SimepiScenario
//
//  Created by Tatsuo Unemi on 2022/07/12.
//  Copyright © 2022 Tatsuo Unemi. All rights reserved.
//

#import "MyController.h"
#import "../SimEpidemic/ParamInfo.h"

void in_main_thread(void (^block)(void)) {
	dispatch_async(dispatch_get_main_queue(), block);
}
void error_msg(NSObject *obj) {
	if ([obj isKindOfClass:NSError.class]) {
		[[NSAlert alertWithError:(NSError *)obj] runModal];
	} else {
		NSAlert *alt = NSAlert.new;
		alt.messageText = obj.description;
		[alt runModal];
	}
}
static NSDictionary *param_info(void) {
	NSInteger cnt = 0, n = 0;
	for (ParamInfo *p = paramInfo; p->type != ParamTypeNone; p ++) n ++;
	NSString *keys[n];
	NSObject *objs[n];
	for (NSInteger i = 0; i < n; i ++) {
		keys[cnt] = paramInfo[i].key;
		switch (paramInfo[i].type) {
			case ParamTypeFloat: case ParamTypeRate:
			objs[cnt ++] = @(paramInfo[i].v.f.defaultValue);
			break;
			case ParamTypeDist:
			objs[cnt ++] = @[@(paramInfo[i].v.d.defMin),
				@(paramInfo[i].v.d.defMax), @(paramInfo[i].v.d.defMode)];
			default: break;
		}
	}
	return [NSDictionary dictionaryWithObjects:objs forKeys:keys count:cnt];
}
static NSMutableArray *add_object(NSMutableArray *array, NSObject *object) {
	if (array == nil) return [NSMutableArray arrayWithObject:object];
	else { [array addObject:object]; return array; }
}
DayRange day_range_from_item(NSDictionary *item) {
	DayRange rng = {0, 0};
	id dayInfo = item[@"day"];
	if ([dayInfo isKindOfClass:NSDictionary.class]) {
		NSDictionary<NSString *, NSNumber *> *item = dayInfo;
		rng.start = item[@"start"].doubleValue;
		rng.duration = item[@"duration"].doubleValue;
	} else rng.start = [dayInfo doubleValue];
	return rng;
}
@implementation MyController
- (void)setup {
	NSError *error;
	NSOpenPanel *op = NSOpenPanel.new;
	if ([op runModal] != NSModalResponseOK) [NSApp terminate:nil];
	NSString *srcStr = [NSString stringWithContentsOfURL:op.URL
		usedEncoding:NULL error:&error];
	if (srcStr == nil) { error_msg(error); [NSApp terminate:nil]; }
	NSScanner *scan = [NSScanner scannerWithString:srcStr];
	NSString *content;
	if (![scan scanUpToString:@"\n1 " intoString:&content])
		{ error_msg(@"No header part."); [NSApp terminate:nil]; }
	header = content;
	if (![scan scanUpToString:@"\nEOF\n" intoString:&content])
		{ error_msg(@"No tail part."); [NSApp terminate:nil]; }
	tail = [srcStr substringFromIndex:scan.scanLocation];
	NSMutableArray *srcSeq = NSMutableArray.new;
	for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
		if (line.length <= 0 || [line hasPrefix:@"#"]) continue;
		scan = [NSScanner scannerWithString:line];
		NSInteger day;
		if (![scan scanInteger:&day]) continue;
		NSString *elmStr = [NSString stringWithFormat:@"[%@]",
			[line substringFromIndex:scan.scanLocation]];
		NSData *data = [NSData dataWithBytes:elmStr.UTF8String length:elmStr.length];
		NSMutableArray *elms = [NSJSONSerialization JSONObjectWithData:data
			options:NSJSONReadingMutableContainers error:&error];
		if (elms == nil) { error_msg(error); [NSApp terminate:nil]; }
		[elms insertObject:@(day) atIndex:0];
		[srcSeq addObject:elms];
	}
	[srcSeq sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
		NSInteger i = [a[0] integerValue], j = [b[0] integerValue];
		return (i < j)? NSOrderedAscending : (i > j)? NSOrderedDescending : NSOrderedSame;
	}];
	NSMutableDictionary *collection = NSMutableDictionary.new;
	NSDictionary *info = param_info();
	for (NSArray *elm in srcSeq) {
		NSInteger day = [elm[0] integerValue];
		NSMutableArray *others = nil;
		for (NSInteger idx = 1; idx < elm.count; idx ++) {
			NSArray *item = elm[idx];
			NSString *name = item[0];
			if (![name isKindOfClass:NSString.class])
				{ others = add_object(others, item); continue; }
			NSMutableArray *seq = collection[name];
			if (seq == nil) {
				if (info[name] != nil) collection[name] = seq =
					[NSMutableArray arrayWithObject:@{@"day":@0, @"value":info[name]}];
				else { others = add_object(others, item); continue; }
			}
			switch (item.count) {
				case 2: [seq addObject:@{@"day":@(day), @"value":item[1]}]; break;
				case 3: [seq addObject:@{@"day":@{@"start":@(day), @"duration":item[2]},
					  @"value":item[1]}];
				default: break;
			}
			
		}
		if (others != nil) {
			[others insertObject:@(day) atIndex:0];
			if (auxItems == nil) auxItems = [NSMutableArray arrayWithObject:others];
			else [auxItems addObject:others];
		}
	}
	sequence = NSMutableArray.new;
	_lastDay = 0;
	for (NSString *name in collection) {
		NSMutableArray<NSDictionary *> *items = collection[name];
		[items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
			CGFloat dayA = day_range_from_item(a).start;
			CGFloat dayB = day_range_from_item(b).start;
			return (dayA < dayB)? NSOrderedAscending :
				(dayA > dayB)? NSOrderedDescending : NSOrderedSame;
		}];
		[sequence addObject:@{@"name":name, @"info":items}];
		DayRange rng = day_range_from_item(items.lastObject);
		CGFloat day = rng.start + rng.duration;
		if (_lastDay < day) _lastDay = day;
	}
	[sequence sortUsingComparator:^(NSDictionary *a, NSDictionary *b) {
		return [a[@"name"] compare:b[@"name"]];
	}];
	[nameView reloadData];
	[prmView reloadData];
//NSLog(@"%ld elements. %@, %@", sequence.count, sequence[0], sequence.lastObject);
	[NSNotificationCenter.defaultCenter addObserver:self
		selector:@selector(tableDidLiveScroll:)
		name:NSScrollViewDidLiveScrollNotification object:nil];
}
- (void)tableDidLiveScroll:(NSNotification *)note {
	NSScrollView *scrlView = note.object;
	NSView *docView = scrlView.documentView, *tgtView
		= (docView == nameView)? prmView : (docView == prmView)? nameView : nil;
	[tgtView scrollPoint:scrlView.documentVisibleRect.origin];
}
// NSTableViewDataSource methods
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return sequence.count;
}
// NSTableViewDelegate methods
- (NSView *)tableView:(NSTableView *)tableView
	viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	if (tableView == nameView) {
		NSTableCellView *cView = [tableView makeViewWithIdentifier:@"ParamName" owner:self];
		cView.textField.stringValue = sequence[row][@"name"];
		return cView;
	} else if (tableView == prmView) {
		TrendView *tView = [tableView makeViewWithIdentifier:@"TimeEvo" owner:self];
		[tView setupWithController:self seq:sequence[row][@"info"]];
		return tView;
	} else return nil;
}
@end
