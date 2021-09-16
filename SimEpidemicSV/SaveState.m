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
	if (stateDir == nil) stateDir =
		[dataDirectory stringByAppendingPathComponent:@"States"];
	return stateDir;
}
static NSString *save_state_file_path(NSString *fname) {
	return [save_state_dir() stringByAppendingFormat:@"/%@.sEpi", fname];
}
static NSString *data_file_path(NSString *dir, NSString *fname) {
	return [[dataDirectory stringByAppendingPathComponent:dir]
		stringByAppendingPathComponent:fname];
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
	NSString *filePath = [stateDirPath stringByAppendingFormat:@"/%@.sEpi", fname];
	if (![fw writeToURL:[NSURL fileURLWithPath:filePath] options:NSFileWrapperWritingAtomic
		originalContentsURL:nil error:&error]) @throw error;
}
- (void)loadStateFrom:(NSString *)fname {
	static NSLock *fwLock = nil;
	if (fwLock == nil) fwLock = NSLock.new;
	NSError *error = nil;
	NSString *filePath = save_state_file_path(fname);
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
- (void)correctVaccineList:(NSMutableArray<NSMutableDictionary *> *)list {
	for (NSInteger i = 0; i < list.count; i ++) {
		NSMutableDictionary *dict = list[i];
		if (![dict isKindOfClass:NSMutableDictionary.class])
			@throw @"Vaccine list includes object other than dictionary.";
		NSString *name = dict[@"name"];
		if (name == nil) @throw [NSString stringWithFormat:@"Element %ld has no name.", i];
		NSNumber *num = dict[@"intervalDays"];
		 if (num == nil || ![num isKindOfClass:NSNumber.class]) dict[@"intervalDays"] = @(21);
		num = dict[@"intervalOn"];
		if (num == nil || ![num isKindOfClass:NSNumber.class]) dict[@"intervalOn"] = @YES;
		for (NSDictionary *vr in self.variantList) {
			NSString *vrNm = vr[@"name"];
			if (dict[vrNm] == nil) dict[vrNm] = @(1.);
		}
	}
}
- (void)correctVariantList:(NSMutableArray<NSMutableDictionary *> *)list {
	for (NSInteger i = 0; i < list.count; i ++) {
		NSMutableDictionary *dict = list[i];
		if (![dict isKindOfClass:NSMutableDictionary.class])
			@throw @"417 Variant list includes object other than dictionary.";
		NSString *name = dict[@"name"];
		if (name == nil) @throw [NSString stringWithFormat:@"Element %ld has no name.", i];
		NSNumber *num = dict[@"reproductivity"];
		 if (num == nil || ![num isKindOfClass:NSNumber.class]) dict[@"reproductivity"] = @(1.);
	}
	for (NSDictionary *vrA in list) {
		NSString *vrNm = vrA[@"name"];
		for (NSMutableDictionary *vrB in list)
			if (vrB[vrNm] == nil) vrB[vrNm] = @(1.);
		for (NSMutableDictionary *vrB in self.vaccineList)
			if (vrB[vrNm] == nil) vrB[vrNm] = @(1.);
	}
}
- (void)loadVarinatsAndVaccinesFrom:(NSString *)fname {
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
	[self correctVaccineList:vxList];
	[self correctVariantList:vrList];
	self.vaccineList = vxList;
	self.variantList = vrList;
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
	[world loadStateFrom:[self stateID]];
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
	[world loadVarinatsAndVaccinesFrom:[self nameArgument]];
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
	[world correctVaccineList:list];
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
	[world correctVariantList:list];
	world.variantList = list;
}
@end
