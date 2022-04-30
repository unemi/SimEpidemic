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

@interface PopDist () {
	NSUndoManager *undoManager;
	NSInteger nPoints;
}
@end

@implementation PopDist
- (NSString *)windowNibName { return @"PopDist"; }
- (void)windowDidLoad {
    [super windowDidLoad];
    undoManager = NSUndoManager.new;
    nPoints = nPointsDgt.integerValue;
    if (_image != nil) imgView.image = _image;
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
typedef struct { CGFloat x, y, z; } PointInfo;
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
	CGFloat edgeEffect = edgeSld.doubleValue;
	CGFloat centerBias = centerSld.doubleValue;
	CGFloat intExp = intExpSld.doubleValue;
	CGFloat gamma = pow(2., gammaSld.doubleValue);
	PointInfo *pts = malloc(sizeof(PointInfo) * nPoints);
	for (NSInteger i = 0; i < nPoints; i ++) {
		PointInfo *p = pts + i;
		p->x = d_random();
		p->y = d_random();
		p->z = d_random() * (1. - pow(hypot(p->x - .5, p->y - .5), 10. / centerBias));
	}
	NSBitmapImageRep *imgRep = make_pop_dist_bm();
	float *pxMap = (float *)imgRep.bitmapData;
	for (NSInteger y = 0; y < imgRep.pixelsHigh; y ++)
	for (NSInteger x = 0; x < imgRep.pixelsWide; x ++) {
		CGFloat yy = (y + .5) / imgRep.pixelsHigh;
		CGFloat xx = (x + .5) / imgRep.pixelsWide;
		CGFloat s = 0., ws = 0.;
		for (NSInteger i = 0; i < nPoints; i ++) {
			PointInfo *p = pts + i;
			CGFloat dx = xx - p->x;
			CGFloat dy = yy - p->y;
			CGFloat w = pow(dx * dx + dy * dy, intExp / 2.);
			if (w < 1e-12) { s = p->z; ws = 1.; break; }
			s += p->z / w;
			ws += 1. / w;
		}
		CGFloat dw = fmin(fmin(xx, 1. - xx), fmin(yy, 1. - yy));
		pxMap[y * imgRep.bytesPerRow / sizeof(float) + x] =
			pow(pow(s / (ws + pow(dw, -2.) * edgeEffect), 2.), gamma);
	}
	NSImage *image = [NSImage.alloc initWithSize:imgRep.size];
	[image addRepresentation:imgRep];
	[self setPopDistImage:image];
	free(pts);
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
