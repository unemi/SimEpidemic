//
//  SaveState.h
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2021/02/08.
//  Copyright © 2021 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>
#import "../SimEpidemic/Sources/World.h"
#import "ProcContext.h"
NS_ASSUME_NONNULL_BEGIN

extern NSString *save_state_dir(void);

@interface World (SaveStateExpension)
- (void)saveStateTo:(NSString *)fname;
- (void)loadStateFrom:(NSString *)fname;
- (void)loadPopDistMapFrom:(NSString *)fname;
@end

@interface ProcContext (SaveStateExtension)
- (void)saveState;
- (void)loadState;
- (void)removeState;
- (void)getState;
- (void)putState;
@end
NS_ASSUME_NONNULL_END
