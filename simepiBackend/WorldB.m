//
//  World.m
//  simepiBackend
//
//  Created by Tatsuo Unemi on 2020/11/10.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "WorldB.h"

static uint32 NextID = 0;
static NSMutableDictionary<NSNumber *, WorldB *> *theWorldList = nil;
static NSLock *worldListLock;

void init_world_env(void) {
	worldListLock = NSLock.new;
	theWorldList = NSMutableDictionary.new;
}
@implementation WorldB
- (instancetype)initWithPID:(pid_t)p write:(int)w read:(int)r {
	if (!(self = [super init])) return nil;
	_ID = NextID ++;
	pid = p;
	pipeWrite = w;
	pipeRead = r;
	return self;
}
- (void)sendCommand:(BackEndCommand *)command {
	write(pipeWrite, command, command->any.length);
}
- (NSData *)recvDataResponse {
	uint32 length;
	ssize_t sz = read(pipeRead, &length, sizeof(length));
	if (sz < sizeof(length)) return nil;
	NSMutableData *md = [NSMutableData dataWithLength:length];
	char *p = (char *)md.mutableBytes;
	*(uint32 *)p = length;
	p += sizeof(length);
	while ((length -= sz) > 0) {
		sz = read(pipeRead, p, length);
		p += sz;
	}
	return md;
}
@end

void add_world(WorldB *world) {
	[worldListLock lock];
	theWorldList[@(world.ID)] = world;
	[worldListLock unlock];
}
void remove_world(WorldB *world) {
	[worldListLock lock];
	theWorldList[@(world.ID)] = nil;
	[worldListLock unlock];
}
WorldB *get_world(uint32 ID) {
	[worldListLock lock];
	WorldB *world = theWorldList[@(ID)];
	[worldListLock unlock];
	return world;
}
static BackEndResponse *response_for_unix_error(void) {
	char *buf = malloc(128), *msg = buf + sizeof(ResponseAny);
	memcpy(msg, "ERROR ", 6);
	strerror_r(errno, msg + 6, 128 - 6 - sizeof(ResponseAny));
	ResponseError *res = (ResponseError *)buf;
	res->length = sizeof(ResLen) + (ResLen)strlen(msg);
	res->type = RspnsError;
	return (BackEndResponse *)res;
}
BackEndResponse *make_new_world(WorldB *_Nonnull* _Nullable wp) {
	extern char **environ;
	int pipeP2C[2], pipeC2P[2];
	pid_t pidChild;
	if (pipe(pipeP2C) < 0) return response_for_unix_error();
	else if (pipe(pipeC2P) < 0) {
		close(pipeP2C[0]); close(pipeP2C[1]);
		return response_for_unix_error();
	} else if ((pidChild = fork()) < 0) {
		close(pipeP2C[0]); close(pipeP2C[1]);
		close(pipeC2P[0]); close(pipeC2P[1]);
		return response_for_unix_error();
	} else if (pidChild == 0) {
		close(pipeP2C[1]); close(pipeC2P[0]);
		dup2(pipeP2C[0], 0); dup2(pipeC2P[1], 1);
		execve("simepiWorld", (char *const[]){"simepiWorld", NULL}, environ);
		printf("ERROR: %s", strerror(errno));
		exit(1);
	} else {
		close(pipeP2C[0]); close(pipeC2P[1]);
		WorldB *world = [WorldB.alloc initWithPID:pidChild
			write:pipeP2C[1] read:pipeC2P[0]];
		add_world(world);
		char *buf = malloc(sizeof(ResponseID));
		ResponseID *res = (ResponseID *)buf;
		*res = (ResponseID){sizeof(res), RspnsID, world.ID};
		*wp = world;
		return (BackEndResponse *)res;
	}
}
