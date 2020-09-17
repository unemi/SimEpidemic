//
//  ProcContext.h
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/09/10.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class Document;
extern Document *make_new_world(NSString *type, NSNumber *ip4addr);

@interface ProcContext : NSObject {
	int desc, code;
	NSNumber *ip4addr;
	Document *document;
	NSMutableData *bufData;	// buffer to receive
	long dataLength;
	NSDictionary<NSString *, NSString *> *query;
	NSString *method, *type, *moreHeader;
	NSObject *content;
	NSInteger fileSize;
}
- (instancetype)initWithSocket:(int)desc ip:(uint32)ipaddr;
- (long)receiveData:(NSInteger)length;
- (void)notImplementedYet;
- (void)makeResponse;
@end

NS_ASSUME_NONNULL_END
