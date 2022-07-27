//
//  SaveState.h
//  SimEpidemicSV
//
//  Created by Tatsuo Unemi on 2021/02/08.
//  Copyright © 2021 Tatsuo Unemi. All rights reserved.
//

#import "SaveState.h"
#import "noGUI.h"
#import "../SimEpidemic/Sources/SaveDoc.h"

NSString *save_state_dir(void) {
	static NSString *stateDir = nil;
	if (stateDir == nil) stateDir = data_hostname_path(@"States");
	return stateDir;
}
NSString *save_state_file_path(NSString *fname) {
	return [save_state_dir() stringByAppendingFormat:@"/%@.sEpi", fname];
}
static NSString *data_file_path(NSString *dir, NSString *fname) {
	return [[dataDirectory stringByAppendingPathComponent:dir]
		stringByAppendingPathComponent:fname];
}
NSString *fullpath_of_load_state(NSString *fname) {
	if (hostname != nil) {
		NSArray<NSString *> *names = [fname pathComponents];
		return (names.count < 2)? save_state_file_path(fname) :
			data_file_path(names[0], [names[1] stringByAppendingPathExtension:@"sEpi"]);
	} else return save_state_file_path(fname);
}

@implementation World (SaveStateExpension)
- (void)saveStateTo:(NSString *)fname {
	NSString *stateDirPath = save_state_dir();
	NSFileManager *fm = NSFileManager.defaultManager;
	NSError *error;
	if (![fm createDirectoryAtPath:stateDirPath withIntermediateDirectories:YES
		attributes:nil error:&error]) @throw error;
	NSFileWrapper *fw = [self fileWrapperOfWorld];
	if (fw == nil) @throw @"Could not make a data of the world.";
	NSString *filePath = save_state_file_path(fname);
	if (![fw writeToURL:[NSURL fileURLWithPath:filePath] options:NSFileWrapperWritingAtomic
		originalContentsURL:nil error:&error]) @throw error;
}
- (void)loadStateFrom:(NSString *)filePath {
	static NSLock *fwLock = nil;
	if (fwLock == nil) fwLock = NSLock.new;
	NSError *error = nil;
	[fwLock lock];
	@try {
		NSFileWrapper *fw = [NSFileWrapper.alloc initWithURL:
			[NSURL fileURLWithPath:filePath] options:0 error:&error];
		if (fw == nil) @throw error;
		if (![self readFromFileWrapper:fw error:&error]) @throw error;
		if (![NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:NSDate.date}
			ofItemAtPath:filePath error:&error]) @throw error;
	} @catch (id _) { }
	[fwLock unlock];
	if (error != nil) @throw error;
}
- (void)loadPopDistMapFrom:(NSString *)fname {
	NSString *filePath = data_file_path(@"PopDistMap", fname);
	NSImage *image = [NSImage.alloc initWithContentsOfFile:filePath];
	if (image != nil) self.popDistImage = image;
	else @throw [NSString stringWithFormat:@"Couldn't make an image from \"%@\".", fname];
}
void correct_vaccine_list(MutableDictArray vaList, MutableDictArray vrList) {
	for (NSInteger i = 0; i < vaList.count; i ++) {
		NSMutableDictionary *dict = vaList[i];
		if (![dict isKindOfClass:NSMutableDictionary.class])
			@throw @"Vaccine list includes object other than dictionary.";
		NSString *name = dict[@"name"];
		if (name == nil) @throw [NSString stringWithFormat:@"Element %ld has no name.", i];
		NSDictionary *defaultVals = @{
			@"intervalDays":@(21), @"intervalOn":@YES, @"efficacyDur":@(1.) };
		for (NSString *key in defaultVals) {
			NSNumber *num = dict[key];
			if (num == nil || ![num isKindOfClass:NSNumber.class]) dict[key] = defaultVals[key];
		}
		for (NSDictionary *vr in vrList) {
			NSString *vrNm = vr[@"name"];
			if (dict[vrNm] == nil) dict[vrNm] = @(1.);
		}
	}
}
void correct_variant_list(MutableDictArray vrList, MutableDictArray vaList) {
	for (NSInteger i = 0; i < vrList.count; i ++) {
		NSMutableDictionary *dict = vrList[i];
		if (![dict isKindOfClass:NSMutableDictionary.class])
			@throw @"417 Variant list includes object other than dictionary.";
		NSString *name = dict[@"name"];
		if (name == nil) @throw [NSString stringWithFormat:@"Element %ld has no name.", i];
		for (NSString *key in @[@"reproductivity", @"toxicity"]) {
			NSNumber *num = dict[key];
			if (num == nil || ![num isKindOfClass:NSNumber.class]) dict[key] = @(1.);
		}
	}
	for (NSDictionary *vrA in vrList) {
		NSString *vrNm = vrA[@"name"];
		for (NSMutableDictionary *vrB in vrList)
			if (vrB[vrNm] == nil) vrB[vrNm] = @(1.);
		for (NSMutableDictionary *vrB in vaList)
			if (vrB[vrNm] == nil) vrB[vrNm] = @(1.);
	}
}
NSDictionary *variants_vaccines_from_path(NSString *fname) {
	NSString *filePath = data_file_path(@"VariantsAndVaccines", fname);
	NSData *data = [NSData dataWithContentsOfFile:filePath];
	if (data == nil) @throw [NSString stringWithFormat:@"Couldn't find \"%@\".", fname];
	NSError *error;
	NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data
		options:NSJSONReadingMutableContainers error:&error];
	if (dict == nil) @throw [error.localizedDescription stringByAppendingString:
		@"variant and vaccine list."];
	NSMutableArray *vxList, *vrList;
	if ((vxList = dict[@"vaccineList"]) == nil) @throw @"Vaccine list is missing.";
	if ((vrList = dict[@"variantList"]) == nil) @throw @"Variant list is missing.";
	correct_vaccine_list(vxList, vrList);
	correct_variant_list(vrList, vxList);
	return dict;
}
- (void)loadVarianatsAndVaccinesFrom:(NSString *)fname {
	NSDictionary *dict = variants_vaccines_from_path(fname);
	self.vaccineList = dict[@"vaccineList"];
	self.variantList = dict[@"variantList"];
}
MutableDictArray gatherings_list_from_path(NSString *fname) {
	NSString *filePath = data_file_path(@"GatheringsList", fname);
	NSData *data = [NSData dataWithContentsOfFile:filePath];
	if (data == nil) @throw [NSString stringWithFormat:@"Couldn't find \"%@\".", fname];
	NSError *error;
	MutableDictArray list = [NSJSONSerialization JSONObjectWithData:data
		options:NSJSONReadingMutableContainers error:&error];
	if (list == nil) @throw [error.localizedDescription stringByAppendingString:
		@"gatherings list."];
	return list;
}
@end

@implementation ProcContext (SaveStateExtension)
- (void)saveState {
	[self checkWorld];
	NSString *ID = new_uniq_string();
	[world saveStateTo:ID];
	content = ID;
	type = @"text/plain";
	code = 200;
}
- (NSString *)stateID {
	NSString *stateID = query[@"ID"];
	if (stateID == nil) @throw @"417 Pop ID is missing.";
	return stateID;
}
- (void)loadState {
	[self checkWorld];
	[world loadStateFrom:fullpath_of_load_state([self stateID])];
}
- (void)removeState {
	NSError *error;
	NSString *stateFilePath = save_state_file_path([self stateID]);
	if (![NSFileManager.defaultManager removeItemAtPath:stateFilePath error:&error])
		@throw error;
}
- (void)getState {
	NSError *error;
	NSString *filePath = save_state_file_path([self stateID]);
	NSFileWrapper *fw = [NSFileWrapper.alloc initWithURL:
		[NSURL fileURLWithPath:filePath] options:0 error:&error];
	if (fw == nil) @throw error;
	NSData *data = [fw serializedRepresentation];
	if (data == nil) @throw @"500 Error in state serialization.";
	[self setupLocalFileToSave:@"sEpi"];
	content = data;
	code = 200;
}
- (void)putState {
}
- (NSString *)nameArgument {
	NSString *name = query[@"name"];
	if (name == nil) @throw @"417 Name is missing.";
	return name;
}
- (void)loadVariantsAndVaccines {
	[self checkWorld];
	[world loadVarianatsAndVaccinesFrom:[self nameArgument]];
}
- (void)loadGatherings {
	[self checkWorld];
	MutableDictArray list = gatherings_list_from_path([self nameArgument]);
	if (list != nil) world.gatheringsList = list;
}
- (void)getVaccineList {
	[self checkWorld];
	[self getInfo:world.vaccineList];
}
- (void)setVaccineList {
	[self checkWorld];
	NSMutableArray *list = (NSMutableArray *)[self
		plistFromJSONArgument:NSJSONReadingMutableContainers
		class:NSMutableArray.class type:@"vaccine list"];
	if (list == nil) @throw @"417 No data for vaccine list.";
	correct_vaccine_list(list, world.variantList);
	world.vaccineList = list;
}
- (void)getVariantList {
	[self checkWorld];
	[self getInfo:world.variantList];
}
- (void)setVariantList {
	[self checkWorld];
	NSMutableArray *list = (NSMutableArray *)[self
		plistFromJSONArgument:NSJSONReadingMutableContainers
		class:NSMutableArray.class type:@"variant list"];
	if (list == nil) @throw @"417 No data for variant list.";
	correct_variant_list(list, world.vaccineList);
	world.variantList = list;
}
- (void)getGatheringsList {
	[self checkWorld];
	[self getInfo:world.gatheringsList];
}
- (void)setGatheringsList {
	[self checkWorld];
	NSMutableArray *list = (NSMutableArray *)[self
		plistFromJSONArgument:NSJSONReadingMutableContainers
		class:NSMutableArray.class type:@"gatherings list"];
	if (list == nil) @throw @"417 No data for gatherings list.";
	world.gatheringsList = list;
}
@end
