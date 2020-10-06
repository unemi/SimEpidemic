//
//  ProcContext.h
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/09/10.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef enum { IdxTypeIndex, IdxTypeTestI, IdxTypeTestF, IdxTypeUnknown } IndexType;

@class Document, MyCounter;
extern Document *make_new_world(NSString *type, NSString * _Nullable browserID);

@interface NSString (IndexNameExtension)
- (NSString *)stringByRemovingFirstWord;
- (NSString *)stringByAddingFirstWord:(NSString *)word;
@end

@interface ProcContext : NSObject {
	int desc, code;
	uint32 ip4addr;
	NSString *browserID;
	Document *document;
	NSLock *lock;
	NSMutableData *bufData;	// buffer to receive
	long dataLength;
	NSDictionary<NSString *, NSString *> *query;
	NSString *method, *type, *moreHeader;
	NSObject *content;
	NSInteger fileSize;

	NSTimer *reportTimer;
	NSInteger repN, repCnt, prevRepStep;
	NSArray<NSString *> *repItemsIdx, *repItemsDly, *repItemsDst, *repItemsExt;
}
- (instancetype)initWithSocket:(int)desc ip:(uint32)ipaddr;
- (long)receiveData:(NSInteger)length;
- (void)setOKMessage;
- (void)notImplementedYet;
- (void)makeResponse;
- (void)setJSONDataAsResponse:(NSObject *)object;
- (void)connectionWillClose;
@end

NS_ASSUME_NONNULL_END
