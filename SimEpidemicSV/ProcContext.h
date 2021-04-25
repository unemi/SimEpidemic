//
//  ProcContext.h
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2020/09/10.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>
#import "../SimEpidemic/Sources/CommonTypes.h"
#define BUFFER_SIZE 8192

NS_ASSUME_NONNULL_BEGIN

typedef enum { IdxTypeIndex, IdxTypeTestI, IdxTypePRate, IdxTypeRRate, IdxTypeUnknown } IndexType;
typedef enum { MethodHEAD, MethodGET, MethodPOST, MethodNone = NSNotFound } MethodType;
@class World, MyCounter, DeflaterStream;
extern World *make_new_world(NSString *type, NSString * _Nullable browserID);
extern void send_bytes(int desc, const char *bytes, NSInteger size);
extern void load_params_from_dict(World *wd, WorldParams * _Nullable wp, NSDictionary *dict);
extern NSArray *make_history(StatData *stat, NSInteger nItems,
	NSNumber *(^getter)(StatData *));
extern NSArray *dist_cnt_array(NSArray<MyCounter *> *hist);
extern NSDictionary<NSString *, NSArray<MyCounter *> *> *distribution_name_map(World *world);
extern NSData *JSON_pop(World *world);
extern NSData *JSON_pop2(World *world);
extern void init_context(void);

@interface NSString (IndexNameExtension)
- (NSString *)stringByRemovingFirstWord;
- (NSString *)stringByAddingFirstWord:(NSString *)word;
@end

@interface ProcContext : NSObject {
	int desc, code;
	uint32 ip4addr;
	NSString *browserID;
	World *world;
	NSMutableData *bufData;	// buffer to receive
	long dataLength;
	MethodType method;
	NSDictionary<NSString *, NSString *> *query;
	NSString *type, *moreHeader;
	NSObject *content;
	NSInteger fileSize;
	void (^proc)(ProcContext *);
	void (^postProc)(void);
	NSInteger nReporters;
}
@property (readonly) NSString *requestString;
- (instancetype)initWithSocket:(int)desc ip:(uint32)ipaddr;
- (long)receiveData:(NSInteger)length offset:(NSInteger)offset;
- (void)setOKMessage;
- (void)notImplementedYet;
- (int)makeResponse;
- (void)setJSONDataAsResponse:(NSObject *)object;
- (BOOL)setupLocalFileToSave:(NSString *)extension;
- (void)checkWorld;
- (void)connectionWillClose;
@end

NS_ASSUME_NONNULL_END
