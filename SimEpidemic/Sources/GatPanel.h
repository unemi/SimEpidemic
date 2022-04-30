//
//  GatPanel.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2022/03/09.
//  Copyright © 2022 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *nnRegGatChanged;

@class Document;
@interface GatPanel : NSWindowController
	<NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation>
- (instancetype)initWithDocument:(Document *)doc;
@end

NS_ASSUME_NONNULL_END
