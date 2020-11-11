//
//  World.h
//  simepiBackend
//
//  Created by Tatsuo Unemi on 2020/11/10.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "backend.h"

NS_ASSUME_NONNULL_BEGIN

@interface World : NSObject {
	pid_t pid;
	int pipeWrite, pipeRead;
}
@property (readonly) uint32 ID;
- (void)sendCommand:(BackEndCommand *)command;
- (NSData *)recvDataResponse;
@end

extern void add_world(World *world);
extern void remove_world(World *world);
extern World *get_world(uint32 ID);
extern BackEndResponse *make_new_world(World *_Nonnull* _Nullable wp);

NS_ASSUME_NONNULL_END
