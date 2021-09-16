//
//  MyView.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/05/05.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "MyView.h"
#import "Document.h"
#import "Agent.h"
#import "Gatherings.h"
#define LV_FONT_SIZE 11.

//static void grade_color(CGFloat grade, CGFloat *rgb) {
//	static CGFloat keyColor[7][3] = {
//		{0., 0., 0.},	// black
//		{0., 0., 1.},	// blue
//		{0., 1., 1.},	// cyan
//		{0., 1., 0.},	// green
//		{1., 1., 0.},	// yellow
//		{1., 0., 0.},	// red
//		{1., 1., 1.}	// white
//	};
//	if (grade >= 1.) memcpy(rgb, keyColor[6], sizeof(CGFloat) * 3);
//	else if (grade <= 0.) memcpy(rgb, keyColor[0], sizeof(CGFloat) * 3);
//	else {
//		NSInteger idx = floor(grade * 6.);
//		CGFloat a = grade - idx;
//		for (NSInteger i = 0; i < 3; i ++)
//			rgb[i] = keyColor[idx][i] * (1. - a) + keyColor[idx + 1][i] * a;
//	}
//}
@interface MyView () {
	NSInteger nVaxen, nVariants;
	NSArray<NSColor *> *vaxStColors, *varStColors, *vaxWpColors, *varWpColors;
}
@end

@implementation MyView
- (void)awakeFromNib {
	frameSize = self.frame.size;
	self.bounds = (NSRect){0, 0, 100, 80};
	_scale = 1.;
	attr = NSMutableDictionary.new;
}
static BOOL should_draw_rect(NSRect rect, NSRect dRect) {
	return NSIntersectsRect(NSInsetRect(rect, -AGENT_SIZE, -AGENT_SIZE), dRect);
}
- (void)resetCursorRects {
	[self addCursorRect:self.frame cursor:
		(_scale > 1.)? NSCursor.openHandCursor : NSCursor.arrowCursor];
}
- (void)enableMagDownButton { magDownBtn.enabled = YES; }
- (void)drawRect:(NSRect)dirtyRect {
	if (imgRep != nil) {
		[imgRep drawInRect:self.bounds];
		if (!liveResizeEnded) return;
	}
	NSSize fSize = self.frame.size;
	if (!NSEqualSizes(fSize, frameSize)) {
		self.bounds = (NSRect){0, 0, 100, 80};
		frameSize = fSize;
		return;
	} else if (liveResizeEnded) { imgRep = nil; liveResizeEnded = NO; }
	NSInteger m = _world.worldParamsP->mesh, wSize = _world.worldParamsP->worldSize;
	if (wSize != worldSize) {
		fontSize = LV_FONT_SIZE * wSize / 500;
		attr[NSFontAttributeName] = [NSFont userFontOfSize:fontSize];
		worldSize = wSize;
	}
	[NSGraphicsContext saveGraphicsState];
	CGFloat cellSize = (CGFloat)wSize / m;
	NSRect fieldRect = {0, 0, wSize, wSize};
	NSRect hospitalRect = {wSize, wSize / 2, wSize / 4, wSize / 2};
	NSRect cemeteryRect = {wSize, 0, wSize / 4, wSize / 2};
	CGFloat scale = 80. / wSize * _scale;
	NSAffineTransform *trans = NSAffineTransform.transform;
	[trans scaleBy:scale];
	[trans translateXBy:_offset.x yBy:_offset.y];
	[trans concat];
	NSRect dRect = {dirtyRect.origin.x / scale - _offset.x,
		dirtyRect.origin.y / scale - _offset.y,
		dirtyRect.size.width / scale, dirtyRect.size.height / scale};
	[_world popLock];
	Agent **pop = _world.Pop;
	AgentDrawType dType = (wSize / _scale < 250)? AgntDrwCircle : AgntDrwSquire;
	NSMutableArray<NSBezierPath *> *pathsI = NSMutableArray.new, *pathsW = NSMutableArray.new;
	NSInteger nColors, (^pathIdx)(Agent *);
	switch (_colorType) {
		case ColNormal: nColors = NHealthTypes;
		pathIdx = ^(Agent *a){ return (NSInteger)a->health; }; break;
		case ColAntiVax: nColors = 3;
		pathIdx = ^(Agent *a){ return (NSInteger)a->forVcn; }; break;
		case ColVaxVariant: nColors = _world.vaccineList.count + _world.variantList.count + 1;
		NSInteger nVaxen = _world.vaccineList.count;
		pathIdx = ^(Agent *a){
			switch (a->health) {
				case Susceptible: return 0L;
				case Vaccinated: return (NSInteger)a->vaccineType + 1;
				default: return nVaxen + 1 + a->virusVariant; }};
	}
	for (NSInteger i = 0; i < nColors; i ++)
		{ [pathsI addObject:NSBezierPath.new]; [pathsW addObject:NSBezierPath.new]; }
	NSRect cellRect = {0., 0., cellSize, cellSize};
	if (NSIntersectsRect(fieldRect, dRect)) {
		[stateColors[ColBackground] setFill];
		[NSBezierPath fillRect:(NSRect){0, 0, wSize, wSize}];
		for (NSInteger i = 0; i < m * m; i ++) {
			cellRect.origin = (NSPoint){(i % m) * cellSize, (i / m) * cellSize};
			if (should_draw_rect(cellRect, dRect)) for (Agent *a = pop[i]; a; a = a->next)
				show_agent(a, dType, dRect, pathsI[pathIdx(a)]);
		}
		if (_showGatherings) {
			CGFloat rgb[3];
			[stateColors[ColGathering] getRed:rgb green:rgb+1 blue:rgb+2 alpha:NULL];
			for (Gathering *gat = _world.gatherings; gat != NULL; gat = gat->next)
				draw_gathering(gat, rgb, dRect);
	}}
	attr[NSForegroundColorAttributeName] = stateColors[ColText];
	if (NSIntersectsRect(cemeteryRect, dRect)) {
		[stateColors[ColCemetery] setFill];
		[NSBezierPath fillRect:cemeteryRect];
		for (Agent *a = _world.CList; a; a = a->next)
			if (!a->isWarping) show_agent(a, dType, dRect, pathsI[pathIdx(a)]);
		[NSLocalizedString(@"Cemetery", nil) drawAtPoint:(NSPoint){
			NSMinX(cemeteryRect) + fontSize * .2, NSMaxY(cemeteryRect) - fontSize * 1.2}
			withAttributes:attr];
	}
	if (NSIntersectsRect(hospitalRect, dRect)) {
		[stateColors[ColHospital] setFill];
		[NSBezierPath fillRect:hospitalRect];
		for (Agent *a = _world.QList; a; a = a->next)
			if (!a->isWarping) show_agent(a, dType, dRect, pathsI[pathIdx(a)]);
		[NSLocalizedString(@"Hospital", nil) drawAtPoint:(NSPoint){
			NSMinX(hospitalRect) + fontSize * .2, NSMaxY(hospitalRect) - fontSize * 1.2}
			withAttributes:attr];
	}
	for (NSValue *value in _world.WarpList.objectEnumerator) {
		WarpInfo item = value.warpInfoValue;
		warp_show(item.agent, item.mode, item.goal, dRect, pathsW[pathIdx(item.agent)]);
	}
	[_world popUnlock];
	if (_colorType != ColVaxVariant) for (NSInteger i = 0; i < nColors; i ++) {
		[stateColors[i] setFill]; [pathsI[i] fill];
		[warpColors[i] setFill]; [pathsW[i] fill];
	} else {
		NSInteger nvx = _world.vaccineList.count, nvr = _world.variantList.count;
		if (nvx != nVaxen) {
			NSColor *stCols[nvx], *wpCols[nvx];
			for (NSInteger i = 0; i < nvx; i ++) {
				CGFloat hue = (nvx <= 1)? .667 : i * .333 / (nvx - 1) + .5; 
				stCols[i] = [NSColor colorWithHue:hue saturation:0.75 brightness:0.75 alpha:1.];
				wpCols[i] = [NSColor colorWithHue:hue
					saturation:0.75 brightness:0.75 alpha:warpOpacity];
			}
			vaxStColors = [NSArray arrayWithObjects:stCols count:nvx];
			vaxWpColors = [NSArray arrayWithObjects:wpCols count:nvx];
			nVaxen = nvx;
		}
		if (nvr != nVariants) {
			NSColor *stCols[nvr], *wpCols[nvr];
			for (NSInteger i = 0; i < nvr; i ++) {
				CGFloat hue = (nvr <= 1)? .0833 : i * .1667 / (nvr - 1); 
				stCols[i] = [NSColor colorWithHue:hue saturation:0.75 brightness:0.75 alpha:1.];
				wpCols[i] = [NSColor colorWithHue:hue
					saturation:0.75 brightness:0.75 alpha:warpOpacity];
			}
			varStColors = [NSArray arrayWithObjects:stCols count:nvr];
			varWpColors = [NSArray arrayWithObjects:wpCols count:nvr];
			nVariants = nvr;
		}
		[stateColors[0] setFill]; [pathsI[0] fill];
		[warpColors[0] setFill]; [pathsW[0] fill];
		for (NSInteger i = 0; i < nvx; i ++) {
			[vaxStColors[i] setFill]; [pathsI[i + 1] fill];
			[vaxWpColors[i] setFill]; [pathsW[i + 1] fill];
		}
		for (NSInteger i = 0; i < nvr; i ++) {
			[varStColors[i] setFill]; [pathsI[i + nvx + 1] fill];
			[varWpColors[i] setFill]; [pathsW[i + nvx + 1] fill];
		}
	}
	[NSGraphicsContext restoreGraphicsState];
}
-(void)adjustOffset:(NSPoint)newOffset {
	CGFloat a = _world.worldParamsP->worldSize / -80. * (1. - 1. / _scale);
	NSSize size = self.bounds.size;
	_offset = (NSPoint){
		fmin(0., fmax(size.width * a, newOffset.x)),
		fmin(0., fmax(size.height * a, newOffset.y))};
}
- (void)shiftView:(NSEvent *)event bias:(CGFloat)bias {
	if (_scale <= 1.) return;
	[self adjustOffset:(NSPoint){
		_offset.x + event.deltaX * bias / _scale,
		_offset.y - event.deltaY * bias / _scale }];
	self.needsDisplay = YES;
}
- (void)mouseDragged:(NSEvent *)event {
	[self shiftView:event bias:2.];
}
- (void)scrollWheel:(NSEvent *)event {
	[self shiftView:event bias:10.];
}
- (void)setNewScale:(CGFloat)newScale {
	CGFloat a = _world.worldParamsP->worldSize * (1./newScale - 1./_scale) / 2.;
	_scale = newScale;
	[self adjustOffset:(NSPoint){_offset.x + 1.25 * a, _offset.y + a}];
}
- (IBAction)magnifyMore:(id)sender {
	if (_scale <= 1.) {
		magDownBtn.enabled = YES;
		[self.window invalidateCursorRectsForView:self];
	}
	[self setNewScale:_scale * M_SQRT2];
	self.needsDisplay = YES;
}
- (IBAction)magnifyLess:(id)sender {
	CGFloat newScale = (_scale >= M_SQRT2)? _scale / M_SQRT2 : 1.;
	if (newScale < 1.1) {
		newScale = 1.; magDownBtn.enabled = NO;
		[self.window invalidateCursorRectsForView:self];
	}
	[self setNewScale:newScale];
	self.needsDisplay = YES;
}
- (void)startLiveResize {
	NSBitmapImageRep *bm = [self bitmapImageRepForCachingDisplayInRect:self.bounds];
	[self cacheDisplayInRect:self.bounds toBitmapImageRep:bm];
	imgRep = bm;
}
- (void)endLiveResize { liveResizeEnded = YES; self.needsDisplay = YES; }
@end

@implementation Document (WindowResizeExtension)
- (void)windowWillStartLiveResize:(NSNotification *)notification { [view startLiveResize]; }
- (void)windowDidEndLiveResize:(NSNotification *)notification { [view endLiveResize]; }
@end

@implementation LegendView
- (void)awakeFromNib {
	NSFont *dgtFont = [NSFont userFixedPitchFontOfSize:LV_FONT_SIZE];
	NSSize mySz = self.frame.size, dgtSz = [@"999,999" sizeWithAttributes:
		@{NSFontAttributeName:dgtFont}];
	label = [NSTextField.alloc initWithFrame:(NSRect){
		mySz.height, 0., mySz.width - mySz.height - dgtSz.width, mySz.height}];
	digits = [NSTextField.alloc initWithFrame:(NSRect){
		mySz.width - dgtSz.width, 0., dgtSz}];
	label.bordered = label.editable = label.selectable = NO;
	label.drawsBackground = NO;
	label.font = [NSFont userFontOfSize:LV_FONT_SIZE];
	digits.drawsBackground = NO;
	digits.bordered = digits.editable = NO;
	digits.font = dgtFont;
	[self addSubview:label];
	[self addSubview:digits];
}
- (void)setColor:(NSColor *)col { color = col; }
- (void)setName:(NSString *)nm {
	CGFloat orgWidth = label.frame.size.width;
	label.stringValue = nm;
	[label sizeToFit];
	CGFloat wDelta = label.frame.size.width - orgWidth;
	NSPoint dgtOrigin = digits.frame.origin;
	[digits setFrameOrigin:(NSPoint){dgtOrigin.x + wDelta, dgtOrigin.y}];
	NSSize frmSz = self.frame.size;
	[self setFrameSize:(NSSize){frmSz.width + wDelta, frmSz.height}];
}
- (void)setIntegerValue:(NSInteger)value { digits.integerValue = value; }
- (void)drawRect:(NSRect)dirtyRect {
	[super drawRect:dirtyRect];
	NSRect rect = self.bounds;
	rect.size.width = rect.size.height;
	[color setFill];
	[[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 1., 1.)] fill];
}
@end

@implementation FillView
- (void)drawRect:(NSRect)rect {
	[stateColors[ColBackground] setFill];
	[NSBezierPath fillRect:rect];
}
@end
