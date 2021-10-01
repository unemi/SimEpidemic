//
//  SaveState.h
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2021/02/08.
//  Copyright © 2021 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>
#import "../SimEpidemic/Sources/World.h"
#import "ProcContext.h"
NS_ASSUME_NONNULL_BEGIN

extern NSString *save_state_dir(void);
extern NSDictionary *variants_vaccines_from_path(NSString *fname);
extern void correct_vaccine_list(MutableDictArray vaList, MutableDictArray vrList);
extern void correct_variant_list(MutableDictArray vrList, MutableDictArray vaList);

@interface World (SaveStateExpension)
- (void)saveStateTo:(NSString *)fname;
- (void)loadStateFrom:(NSString *)fname;
- (void)loadPopDistMapFrom:(NSString *)fname;
@end

@interface ProcContext (SaveStateExtension)
- (void)saveState;
- (void)loadState;
- (void)removeState;
- (void)getState;
- (void)putState;
- (void)loadVariantsAndVaccines;
- (void)getVaccineList;
- (void)setVaccineList;
- (void)getVariantList;
- (void)setVariantList;
@end
NS_ASSUME_NONNULL_END
