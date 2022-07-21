//
//  ParamInfo.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2022/07/13.
//  Copyright © 2022 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef enum {
	ParamTypeNone, ParamTypeFloat, ParamTypeDist,
	ParamTypeInteger, ParamTypeRate, ParamTypeEnum, ParamTypeWEnum,
	ParamTypeVaxFloat, ParamTypeVaxEnum
} ParamType;

typedef struct {
	ParamType type;
	NSString *key;
	union {
		struct { CGFloat defaultValue, minValue, maxValue; } f;
		struct { CGFloat defMin, defMode, defMax; } d;
		struct { NSInteger defaultValue, minValue, maxValue; } i;
		struct { sint32 defaultValue, maxValue; } e;	// enumeration
	} v;
} ParamInfo;

extern ParamInfo paramInfo[];
