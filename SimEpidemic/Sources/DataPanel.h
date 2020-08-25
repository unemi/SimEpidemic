//
//  DataPanel.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/10.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CommonTypes.h"

NS_ASSUME_NONNULL_BEGIN
typedef enum { TableTimeEvo, TableTransit, TableTests, TableHistgram } TableType;
@class StatInfo;

@interface DataPanel : NSWindowController
	<NSWindowDelegate, NSTableViewDataSource> {
	IBOutlet NSScrollView
		*timeEvoScrlView, *transitScrlView, *testsScrView, *histogramScrlView;
	IBOutlet NSTableView
		*timeEvoTableView, *transitTableView, *testsTableView, *histogramTableView;
	IBOutlet NSPopUpButton *typePopUp, *intervalPopUp;
	StatInfo *statInfo;
	NSArray<NSDictionary<NSString *, NSNumber *> *> *tableData;
	TableType tableType;
}
- (instancetype)initWithInfo:(StatInfo *)info;
@end

NS_ASSUME_NONNULL_END
