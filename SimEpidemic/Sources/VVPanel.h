//
//  VVPanel.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2021/08/17.
//  Copyright © 2021 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CommonTypes.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *VaccineListChanged, *VariantListChanged;
@interface NSMutableArray (CopyVVListExtension)
- (NSMutableArray *)vvListCopy;
- (BOOL)isEqultToVVList:(NSArray<NSDictionary *> *)list;
@end

@interface ShotIntervalView : NSTableCellView
@property IBOutlet NSButton *checkBox;
@end

@interface VVNameTextField : NSTextField
@property NSInteger row;
@property (assign) NSArray<NSDictionary *> *list;
@end

@class World;
@interface VVPanel : NSWindowController
	<NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate> {
	IBOutlet NSTableView *variantTable, *vaccineTable;
	IBOutlet NSButton *rmVariantBtn, *rmVaccineBtn, *addVaccineBtn;
	IBOutlet NSTextField *vcn1stEffcDgt, *vcnMaxEffcDgt, *vcnMaxEffcSDgt,
		*vcnEDelayDgt, *vcnEPeriodDgt, *vcnEDecayDgt, *vcnSvEffcDgt;
	IBOutlet NSSlider *vcn1stEffcSld, *vcnMaxEffcSld, *vcnMaxEffcSSld,
		*vcnEDelaySld, *vcnEPeriodSld, *vcnEDecaySld, *vcnSvEffcSld;
	IBOutlet NSButton *applyBtn;
}
- (instancetype)initWithWorld:(World *)wd;
- (void)adjustApplyBtnEnabled;
@end

NS_ASSUME_NONNULL_END
