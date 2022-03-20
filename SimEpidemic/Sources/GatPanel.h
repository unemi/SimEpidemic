//
//  GatPanel.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2022/03/09.
//  Copyright © 2022 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class World;
@interface GatPanel : NSWindowController
	<NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate>
- (instancetype)initWithWorld:(World *)wd;
@end

NS_ASSUME_NONNULL_END
