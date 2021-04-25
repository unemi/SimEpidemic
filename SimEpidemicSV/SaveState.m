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
static NSString *pop_dist_map_file_path(NSString *fname) {
	return [[dataDirectory stringByAppendingPathComponent:@"PopDistMap"]
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
	NSString *filePath = pop_dist_map_file_path(fname);
	NSImage *image = [NSImage.alloc initWithContentsOfFile:filePath];
	if (image != nil) self.popDistImage = image;
	else @throw [NSString stringWithFormat:@"Couldn't make an image from \"%@\".", fname];
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
@end
