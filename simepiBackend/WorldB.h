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

@interface WorldB : NSObject {
	pid_t pid;
	int pipeWrite, pipeRead;
}
@property (readonly) uint32 ID;
- (void)sendCommand:(BackEndCommand *)command;
- (NSData *)recvDataResponse;
@end

extern void init_world_env(void);
extern void add_world(WorldB *world);
extern void remove_world(WorldB *world);
extern WorldB *get_world(uint32 ID);
extern BackEndResponse *make_new_world(WorldB *_Nonnull* _Nullable wp);

NS_ASSUME_NONNULL_END
