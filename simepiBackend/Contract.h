//
//  Contract.h
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/10/26.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Foundation/Foundation.h>

#define UDP_SERVER_PORT 50100U
#define UDP_BUFSIZE 64

@interface Contractor : NSObject
@property (readonly) NSString *ID;
@end

typedef struct {
	in_addr_t ipaddr;
	in_port_t port;
} IPandPort;

extern void setup_contractor(uint16 port);
extern IPandPort find_contractor(void);
