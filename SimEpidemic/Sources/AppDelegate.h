//
//  AppDelegate.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CommonTypes.h"
#define N_ENV_COLORS 4
#define N_COLORS (NHealthTypes+N_ENV_COLORS)

enum { ColBackground = NHealthTypes,
	ColHospital, ColCemetery, ColText };
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
extern void error_msg(NSObject *obj, NSWindow *window, BOOL critical);
extern void confirm_operation(NSString *text, NSWindow *window, void (^proc)(void));
extern void show_anime_steps(NSTextField *txtField, NSInteger steps);
extern NSObject *get_propertyList_from_url(NSURL *url, Class class, NSWindow *window);
extern void load_property_data(NSArray<NSString *> *fileTypes, NSWindow *window,
	Class class, void (^block)(NSURL *url, NSObject *));
extern void save_property_data(NSString *fileType, NSWindow *window, NSObject *object);
extern NSString *keyAnimeSteps;
extern NSInteger defaultAnimeSteps;
extern RuntimeParams defaultRuntimeParams, userDefaultRuntimeParams;
extern WorldParams defaultWorldParams, userDefaultWorldParams;
extern NSArray<NSString *> *paramKeys, *paramNames;
extern NSArray<NSNumberFormatter *> *paramFormatters;
extern NSDictionary<NSString *, NSString *> *paramKeyFromName;
extern NSDictionary<NSString *, NSNumber *> *paramIndexFromKey;
extern NSDictionary *param_dict(RuntimeParams *rp, WorldParams *wp);
extern void set_params_from_dict(RuntimeParams *rp, WorldParams *wp, NSDictionary *d);
extern NSInteger stateRGB[N_COLORS];
extern NSColor *stateColors[N_COLORS], *warpColors[NHealthTypes];
extern CGFloat warpOpacity;
extern CGFloat panelsAlpha;
extern BOOL makePanelChildWindow;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@interface Preferences : NSWindowController {
	IBOutlet NSStepper *animeStepper;
	IBOutlet NSTextField *animeStepTxt;
	IBOutlet NSColorWell
		*bgColWell, *hospitalColWell, *cemeteryColWell, *textColWell,
		*susColWell, *asyColWell, *symColWell, *recColWell, *dieColWell;
	IBOutlet NSSlider *warpOpacitySld, *panelsAlphaSld;
	IBOutlet NSTextField *warpOpacityDgt, *panelsAlphaDgt;
	IBOutlet NSButton *childWinCBox;
}
@end
