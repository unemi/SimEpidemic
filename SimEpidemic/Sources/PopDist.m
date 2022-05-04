//
//  PopDist.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2021/03/25.
//  Copyright © 2021 Tatsuo Unemi. All rights reserved.
//

#import "PopDist.h"
#import "Document.h"
#import "Agent.h"
//#import <immintrin.h>

@interface PopDist () {
	NSUndoManager *undoManager;
	NSInteger nPoints;
	dispatch_group_t dsGroup;
	dispatch_queue_t dsQueue;
}
@end

@implementation PopDist
- (NSString *)windowNibName { return @"PopDist"; }
- (void)windowDidLoad {
    [super windowDidLoad];
    undoManager = NSUndoManager.new;
    nPoints = nPointsDgt.integerValue;
    if (_image != nil) imgView.image = _image;
    dsGroup = dispatch_group_create();
    dsQueue =
		dispatch_queue_create("jp.ac.soka.unemi.SimEpidemic.PopDist", DISPATCH_QUEUE_CONCURRENT);
}
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return undoManager;
}
- (void)windowDidBecomeKey:(NSNotification *)notification {
	pasteBtn.enabled = [NSPasteboard.generalPasteboard
		canReadObjectForClasses:@[NSImage.class] options:nil];
}
- (IBAction)changeNPoints:(NSTextField *)sender {
	NSInteger newValue = nPointsDgt.integerValue, orgValue = nPoints;
	if (newValue == orgValue) return;
	nPoints = newValue;
	[undoManager registerUndoWithTarget:nPointsDgt handler:^(NSTextField *target) {
		target.integerValue = orgValue;
		[target sendAction:target.action to:target.target];
	}];
}
- (void)changeParamValueSlider:(NSSlider *)sld digits:(NSTextField *)dgt sender:(NSControl *)sender {
	CGFloat newValue = sender.doubleValue, orgValue;
	if (sender != dgt) {
		orgValue = dgt.doubleValue;
		dgt.doubleValue = newValue;
	} else {
		orgValue = sld.doubleValue;
		sld.doubleValue = newValue;
	}
	if (orgValue != newValue)
		[undoManager registerUndoWithTarget:self handler:^(PopDist *target) {
			sld.doubleValue = orgValue;
			[target changeParamValueSlider:sld digits:dgt sender:sld];
		}];
}
- (IBAction)changeEdgeEffect:(NSControl *)sender {
	[self changeParamValueSlider:edgeSld digits:edgeDgt sender:sender];
}
- (IBAction)changeCenterBias:(NSControl *)sender {
	[self changeParamValueSlider:centerSld digits:centerDgt sender:sender];
}
- (IBAction)changeInterporateExponent:(NSControl *)sender {
	[self changeParamValueSlider:intExpSld digits:intExpDgt sender:sender];
}
- (IBAction)changeLogGamma:(NSControl *)sender {
	[self changeParamValueSlider:gammaSld digits:gammaDgt sender:sender];
}
- (void)setPopDistImage:(NSImage *)image {
	NSImage *orgImage = _image;
	[undoManager registerUndoWithTarget:self handler:
		^(PopDist *pp) { [pp setPopDistImage:orgImage]; }];
	_image = image;
	imgView.image = (image != nil)? image :
		[NSImage imageNamed:@"DropImageHere"];
	if (orgImage == nil && image != nil) saveBtn.enabled = YES;
	else if (orgImage != nil && image == nil) saveBtn.enabled = NO;
}
- (IBAction)makeImage:(id)sender {
	float edgeEffect = edgeSld.doubleValue;
	float centerBias = centerSld.doubleValue;
	float intExp = intExpSld.doubleValue;
	float gamma = pow(2., gammaSld.doubleValue);
	float *ptsX = malloc(sizeof(float) * 3 * nPoints);
	float *ptsY = ptsX + nPoints, *ptsZ = ptsY + nPoints;
	NSInteger nPts = nPoints, N = 4;
	for (NSInteger j = 0; j < N; j ++) {
		NSInteger k1 = j * nPts / N, k2 = (j < N - 1)? (j + 1) * nPts / N : nPts;
		dispatch_group_async(dsGroup, dsQueue,
			^() { for (NSInteger i = k1; i < k2; i ++) ptsX[i] = d_random(); });
		dispatch_group_async(dsGroup, dsQueue,
			^() { for (NSInteger i = k1; i < k2; i ++) ptsY[i] = d_random(); });
	}
	dispatch_group_wait(dsGroup, DISPATCH_TIME_FOREVER);
	N = 8;
	for (NSInteger j = 0; j < N; j ++) {
		NSInteger k1 = j * nPts / N, k2 = (j < N - 1)? (j + 1) * nPts / N : nPts;
		dispatch_group_async(dsGroup, dsQueue, ^() {
			for (NSInteger i = k1; i < k2; i ++) ptsZ[i] = d_random() *
				(1. - pow(hypot(ptsX[i] - .5, ptsY[i] - .5), 10. / centerBias)); });
	}
	NSBitmapImageRep *imgRep = make_pop_dist_bm();
	float *pxMap = (float *)imgRep.bitmapData;
	dispatch_group_wait(dsGroup, DISPATCH_TIME_FOREVER);
	NSInteger width = imgRep.pixelsWide, height = imgRep.pixelsHigh;
	for (NSInteger j = 0; j < N; j ++) {
		NSInteger k1 = j * height / N, k2 = (j < N - 1)? (j + 1) * height / N : height;
		dispatch_group_async(dsGroup, dsQueue, ^() {
			float *ww = malloc(sizeof(float) * 2 * nPts), *dyy = ww + nPts;
			for (NSInteger y = k1; y < k2; y ++) {
				float yy = (y + .5f) / height;
				for (NSInteger i = 0; i < nPts; i ++) dyy[i] = powf(yy - ptsY[i], 2.);
				for (NSInteger x = 0; x < width; x ++) {
					float xx = (x + .5) / width, s = 0., ws = 0.;
					BOOL just = NO;
					for (NSInteger i = 0; i < nPts; i ++) {
						ww[i] = powf(powf(xx - ptsX[i], 2.) + dyy[i], intExp / 2.);
						if (ww[i] < 1e-12) { s = ptsZ[i]; ws = 1.; just = YES; break; }
					}
					if (!just) {
						float ss[8] = {0.,}, wss[8] = {0.,};	// clang vectorization
						for (NSInteger i = 0; i < nPts; i +=8)
						for (NSInteger k = 0; k < 8; k ++)
							{ ss[k] += ptsZ[i + k] / ww[i + k]; wss[k] += 1. / ww[i + k]; }
						NSInteger n = nPts % 8, ii = nPts - n;
						for (NSInteger k = 0; k < n; k ++)
							{ ss[k] += ptsZ[ii + k] / ww[ii + k]; wss[k] += 1. / ww[ii + k]; }
						for (NSInteger k = 0; k < 8; k ++)
							{ s += ss[k]; ws += wss[k]; }
					}
					float dw = fminf(fminf(xx, 1. - xx), fminf(yy, 1. - yy));
					pxMap[y * imgRep.bytesPerRow / sizeof(float) + x] =
						powf(powf(s / (ws + powf(dw, -2.) * edgeEffect), 2.), gamma);
			}} free(ww); });
	}
	NSImage *image = [NSImage.alloc initWithSize:imgRep.size];
	dispatch_group_wait(dsGroup, DISPATCH_TIME_FOREVER);
	[image addRepresentation:imgRep];
	[self setPopDistImage:image];
	free(ptsX);
}
- (IBAction)pasteImage:(id)sender {
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	NSArray *arr = [pb readObjectsForClasses:@[NSImage.class] options:nil];
	if (arr == nil || arr.count == 0) return;
	[self setPopDistImage:arr[0]];
}
- (IBAction)loadImage:(id)sender {
	NSOpenPanel *op = NSOpenPanel.openPanel;
	op.allowedFileTypes = @[@"public.image"];
	[op beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
		if (returnCode != NSModalResponseOK) return;
		[self setPopDistImage:[NSImage.alloc initWithContentsOfURL:op.URL]];
	}];
}
- (IBAction)saveImage:(id)sender {
	NSSavePanel *sp = NSSavePanel.savePanel;
	sp.allowedFileTypes = @[@"jpg", @"jpeg", @"png"];
	NSImage *image = imgView.image;
	[sp beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
		if (returnCode != NSModalResponseOK) return;
		NSBitmapImageRep *imgBm = nil;
		for (NSImageRep *imgRep in image.representations)
			if ([imgRep isKindOfClass:NSBitmapImageRep.class])
				{ imgBm = (NSBitmapImageRep *)imgRep; break; }
		if (imgBm == nil) imgBm = make_bm_with_image(image);
		NSData *data = [imgBm representationUsingType:[sp.URL.pathExtension hasPrefix:@"jp"]?
			NSBitmapImageFileTypeJPEG : NSBitmapImageFileTypePNG properties:@{}];
		if (data == nil) error_msg(@"Couldn't make data of image.", self.window, NO);
		else [data writeToURL:sp.URL atomically:NO];
	}];
}
- (IBAction)dropImage:(id)sender {
	[self setPopDistImage:imgView.image];
}
- (IBAction)ok:(id)sender {
	[self.window.sheetParent endSheet:self.window returnCode:NSModalResponseOK];
}
- (IBAction)cancel:(id)sender {
	[self.window.sheetParent endSheet:self.window returnCode:NSModalResponseCancel];
}
@end
