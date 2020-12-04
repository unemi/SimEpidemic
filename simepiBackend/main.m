//
//  main.m
//  simepiBackend
//
//  Created by Tatsuo Unemi on 2020/11/08.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <net/if.h>
#import "backend.h"
#import "WorldB.h"
#define UDP_BUFSIZE 64
#define MAX_COM_LEN 0x7FFFU
#define MAX_N_WORLDS 512

static NSInteger nCores = 1;
static int sockUDP = 0, sockTCP = 0;
static struct sockaddr_in udpName = { sizeof(struct sockaddr_in),
	AF_INET, EndianU16_NtoB(UDP_SERVER_PORT), {INADDR_ANY} };
static struct sockaddr_in tcpName = { sizeof(struct sockaddr_in),
	AF_INET, EndianU16_NtoB(TCP_COMMAND_PORT), {INADDR_ANY} };
static void terminate_me(int s) {
	if (sockUDP > 0) close(sockUDP);
	if (sockTCP > 0) close(sockTCP);
	exit(0);
}
static BOOL acceptancePaused = NO;
static void contract_pause(int s) { acceptancePaused = YES; }
static void contract_resume(int s) { acceptancePaused = NO; }
static double how_much_busy(void) { return 0.; }
static void respond_udp(void) {
	char recvBuf[UDP_BUFSIZE];
	struct sockaddr clientAddr;
	socklen_t addrLen = sizeof(struct sockaddr);
	for (;;) {
		ssize_t sz = recvfrom(sockUDP, recvBuf, UDP_BUFSIZE, 0, &clientAddr, &addrLen);
		if (sz < 0 || acceptancePaused) continue;
		char buf[64];
		sz = sprintf(buf, "%.6f %ld %u\n", how_much_busy(), nCores, TCP_COMMAND_PORT);
		sendto(sockUDP, buf, sz, 0, &clientAddr, addrLen);
	}
}
static BackEndResponse *response_from_string(ResponseType type, char *str) {
	size_t len = strlen(str);
	char *buf = malloc(sizeof(ResponseAny) + len);
	ResponseBytes *res = (ResponseBytes *)buf;
	memcpy(buf + sizeof(ResponseAny), str, len);
	res->length = sizeof(ResLen) + (uint32)len;
	res->type = type;
	return (BackEndResponse *)res;
}
static BackEndResponse *response_error(char *format, ...) {
	va_list ap;
	va_start(ap, format);
	char buf[256];
	vsnprintf(buf, 256, format, ap);
	va_end(ap);
	return response_from_string(RspnsError, buf);
}
static BackEndResponse *response_no_world(BackEndCommand *c) {
	return response_error("World %u does not exist.", c->withWorld.worldID);
}
#define CHECK_WORLD if ((world = get_world(c->withWorld.worldID)) == nil)\
	return response_no_world(c);
static BackEndResponse *make_response(BackEndCommand *c, WorldB **wp) {
	WorldB *world;
	switch (c->any.command) {
		case CmndMakeWorld: return make_new_world(wp);
		case CmndCloseWorld: CHECK_WORLD
			remove_world(world);
			break;
		default: CHECK_WORLD
	}
	[world sendCommand:c];
	return (BackEndResponse *)[world recvDataResponse].bytes;
}
static void interaction_tcp(int desc, uint32 addr) {
	size_t sz, cSz = 0;
	ComAny com;
	BackEndCommand *c = NULL;
	WorldB *world = nil;
	while ((sz = recv(desc, &com, sizeof(com), 0)) > 0) {
		if (com.length > MAX_COM_LEN) {
			fprintf(stderr, "Command length %u is too large.", com.length);
			break;
		}
		if (com.command >= CmndUpperLimit) {
			fprintf(stderr, "Command number %u is too large.", com.command);
			break;
		}
		if (cSz < com.length) {
			c = realloc(c, com.length);
			if (c == NULL) {
				fprintf(stderr, "Malloc error for %u bytes.", com.length);
				break;
			}
			cSz = com.length;
		}
		c->any = com;
		char *p = (char *)c + sizeof(com);
		while (sz < com.length) {
			size_t s = recv(desc, p, com.length - sz, 0);
			if (s <= 0) break;
			sz += s;
		}
		if (sz < com.length) break;
		BackEndResponse *res = make_response(c, &world);
		if (res != NULL) {
			sz = send(desc, res, res->any.length, 0);
			free(res);
		}
	}
	close(desc);
	if (c != NULL) free(c);
}
int main(int argc, const char *argv[]) {
	int err;
	nCores = NSProcessInfo.processInfo.processorCount;
	@try {
		sockUDP = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP);
		if (sockUDP < 0) @throw @(errno);
		if ((err = bind(sockUDP, (struct sockaddr *)&udpName, sizeof(udpName))))
			@throw @(err);
		sockTCP = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
		if (sockTCP < 0) @throw @(errno);
		if ((err = bind(sockTCP, (struct sockaddr *)&tcpName, sizeof(tcpName))))
			@throw @(err);
		if ((err = listen(sockTCP, 1))) @throw @(err);
	} @catch (NSNumber *errNum) {
		perror(argv[0]);
		if (sockUDP > 0) close(sockUDP);
		if (sockTCP > 0) close(sockTCP);
		return errNum.intValue;
	}
	init_world_env();
	signal(SIGTERM, terminate_me);
	signal(SIGUSR1, contract_pause);
	signal(SIGUSR2, contract_resume);
	[NSThread detachNewThreadWithBlock:^{ respond_udp(); }];
	uint32 addrlen;
	int desc = -1;
	for (;;) @autoreleasepool {
		struct sockaddr_in name;
		for (;;) {
			name = tcpName;
			addrlen = sizeof(name);
			desc = accept(sockTCP, (struct sockaddr *)&name, &addrlen);
			if (desc < 0) perror(argv[0]);
			else break;
		}
		[NSThread detachNewThreadWithBlock:
			^{ interaction_tcp(desc, name.sin_addr.s_addr); }];
	}
	return 0;
}
