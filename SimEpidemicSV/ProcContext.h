//
//  ProcContext.h
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/09/10.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class Document, MyCounter;
extern Document *make_new_world(NSString *type, NSString *browserID);

@interface ProcContext : NSObject {
	int desc, code;
	uint32 ip4addr;
	NSString *browserID;
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
- (void)setOKMessage;
- (void)notImplementedYet;
- (void)makeResponse;
- (void)setJSONDataAsResponse:(NSObject *)object;
- (NSDictionary<NSString *, NSArray<MyCounter *> *> *)distributionNameMap;
@end

NS_ASSUME_NONNULL_END
