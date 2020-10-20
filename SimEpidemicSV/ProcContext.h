//
//  ProcContext.h
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/09/10.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>
#import "CommonTypes.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum { IdxTypeIndex, IdxTypeTestI, IdxTypeTestF, IdxTypeUnknown } IndexType;

@class Document, MyCounter, DeflaterStream;
extern Document *make_new_world(NSString *type, NSString * _Nullable browserID);
extern void send_bytes(int desc, const char *bytes, NSInteger size);
extern NSArray *make_history(StatData *stat, NSInteger nItems,
	NSNumber *(^getter)(StatData *));
extern NSArray *dist_cnt_array(NSArray<MyCounter *> *hist);
extern NSDictionary<NSString *, NSArray<MyCounter *> *> *distribution_name_map(Document *doc);
extern NSData *JSON_pop(Document *doc);
extern NSData *JSON_pop2(Document *doc);

@interface NSString (IndexNameExtension)
- (NSString *)stringByRemovingFirstWord;
- (NSString *)stringByAddingFirstWord:(NSString *)word;
@end

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
	void (^postProc)(void);
}
@property (readonly) NSString *requestString;
- (instancetype)initWithSocket:(int)desc ip:(uint32)ipaddr;
- (long)receiveData:(NSInteger)length;
- (void)setOKMessage;
- (void)notImplementedYet;
- (int)makeResponse;
- (void)setJSONDataAsResponse:(NSObject *)object;
- (void)checkDocument;
- (void)connectionWillClose;
@end

NS_ASSUME_NONNULL_END
