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

@interface ShotIntervalView : NSTableCellView
@property IBOutlet NSButton *checkBox;
@end

@interface VVNameTextField : NSTextField
@property NSInteger row;
@property (assign) NSArray<NSDictionary *> *list;
@end

@class Document;
@interface VVPanel : NSWindowController
	<NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation> {
	IBOutlet NSTableView *variantTable, *vaccineTable;
	IBOutlet NSButton *rmVariantBtn, *rmVaccineBtn, *addVaccineBtn;
	IBOutlet NSTextField *vcn1stEffcDgt, *vcnMaxEffcDgt, *vcnMaxEffcSDgt,
		*vcnEDelayDgt, *vcnEPeriodDgt, *vcnEDecayDgt, *vcnSvEffcDgt,
		*infecDistBiasDgt;
	IBOutlet NSSlider *vcn1stEffcSld, *vcnMaxEffcSld, *vcnMaxEffcSSld,
		*vcnEDelaySld, *vcnEPeriodSld, *vcnEDecaySld, *vcnSvEffcSld,
		*infecDistBiasSld;
	IBOutlet NSButton *pasteBtn, *applyBtn;
}
- (instancetype)initWithDocument:(Document *)doc;
- (void)adjustApplyBtnEnabled;
@end

NS_ASSUME_NONNULL_END
