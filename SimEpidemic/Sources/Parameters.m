//
//  Parameters.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/08/01.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "Parameters.h"
#import "Document.h"

@implementation NSApplication (ScriptingExtension)
- (NSDictionary *)factoryDefaultsRuntime { return param_dict(&defaultRuntimeParams, NULL); }
- (NSDictionary *)userDefaultsRuntime { return param_dict(&userDefaultRuntimeParams, NULL); }
- (NSDictionary *)factoryDefaultsWorld { return param_dict(NULL, &defaultWorldParams); }
- (NSDictionary *)userDefaultsWorld { return param_dict(NULL, &userDefaultWorldParams); }
@end

@implementation Document (ScriptingExtension)
- (NSDictionary *)runtimeParameter { return param_dict(&runtimeParams, NULL); }
- (NSDictionary *)initialRuntimeParameter { return param_dict(&initParams, NULL); }
- (NSDictionary *)worldParameter { return param_dict(NULL, &worldParams); }
- (NSDictionary *)temporaryWorldParameter { return param_dict(NULL, &tmpWorldParams); }
- (void)setRuntimeParameter:(NSDictionary *)dict {
	set_params_from_dict(&runtimeParams, NULL, dict);
}
- (void)setInitialRuntimeParameter:(NSDictionary *)dict {
	set_params_from_dict(&initParams, NULL, dict);
}
- (void)setTemporaryWorldParameter:(NSDictionary *)dict {
	set_params_from_dict(NULL, &tmpWorldParams, dict);
}
@end
