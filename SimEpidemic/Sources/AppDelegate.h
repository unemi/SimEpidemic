//
//  AppDelegate.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CommonTypes.h"
#define N_ENV_COLORS 5
#define N_COLORS (NHealthTypes+N_ENV_COLORS)
#define DEFAULT_WARP_OPACITY .5
#define DEFAULT_PANELS_ALPHA .9
#define DEFAULT_CHILD_WIN NO

enum { ColBackground = NHealthTypes,
	ColHospital, ColCemetery, ColText, ColGathering };
typedef enum {
	ParamTypeNone, ParamTypeFloat, ParamTypeDist, ParamTypeInteger
} ParamType;
typedef struct {
	ParamType type;
	NSString *key;
	union {
		struct { CGFloat defaultValue, minValue, maxValue; } f;
		struct { CGFloat defMin, defMode, defMax; } d;
		struct { NSInteger defaultValue, minValue, maxValue; } i;
	} v;
} ParamInfo;

extern NSInteger nCores;
extern unsigned long current_time_us(void);
extern NSString *keyAnimeSteps;
extern NSInteger defaultAnimeSteps;
extern RuntimeParams defaultRuntimeParams, userDefaultRuntimeParams;
extern WorldParams defaultWorldParams, userDefaultWorldParams;
extern NSArray<NSString *> *paramKeys;
extern NSArray<NSNumberFormatter *> *paramFormatters;
extern NSDictionary<NSString *, NSString *> *paramKeyFromName;
extern NSDictionary<NSString *, NSNumber *> *paramIndexFromKey;
extern NSMutableDictionary *param_dict(RuntimeParams *rp, WorldParams *wp);
extern void set_params_from_dict(RuntimeParams *rp, WorldParams *wp, NSDictionary *d);
#ifdef NOGUI
extern void applicationSetups(void);
#else
extern void error_msg(NSObject *obj, NSWindow *window, BOOL critical);
extern NSObject *get_propertyList_from_url(NSURL *url, Class class, NSWindow *window);
extern void load_property_data(NSArray<NSString *> *fileTypes, NSWindow *window,
	Class class, void (^block)(NSURL *url, NSObject *));
extern void save_property_data(NSString *fileType, NSWindow *window, NSObject *object);
extern NSMutableDictionary *dict_of_window_geom(NSWindow *window);
extern NSRect frame_rect_from_dict(NSDictionary *dict);
extern void window_order_info(NSWindow *window, NSDictionary *dict, NSMutableArray *winList);
extern void rearrange_window_order(NSMutableArray<NSArray *> *winList);
extern void confirm_operation(NSString *text, NSWindow *window, void (^proc)(void));
extern void show_anime_steps(NSTextField *txtField, NSInteger steps);
extern NSMutableDictionary *param_diff_dict(RuntimeParams *rpNew, RuntimeParams *rpOrg);
extern void setup_colors(void);
extern NSInteger defaultStateRGB[N_COLORS], stateRGB[N_COLORS];
extern NSColor *stateColors[N_COLORS], *warpColors[NHealthTypes];
extern NSString *colKeys[];
extern CGFloat warpOpacity;
extern CGFloat panelsAlpha;
extern BOOL makePanelChildWindow;
extern NSJSONWritingOptions JSONFormat;
extern NSString *keyWarpOpacity, *keyPanelsAlpha, *keyChildWindow, *keyJSONFormat;
#define DEFAULT_JSON_FORM (NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys)

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end
#endif
