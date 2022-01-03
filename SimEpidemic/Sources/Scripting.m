//
//  Scripting.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/08/01.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "Scripting.h"
#import "Document.h"
#import "World.h"
#import "StatPanel.h"
#import "Scenario.h"
#import "MyView.h"
#import "VVPanel.h"

@implementation NSApplication (ScriptingExtension)
- (NSDictionary *)factoryDefaultsRuntime { return param_dict(&defaultRuntimeParams, NULL); }
- (NSDictionary *)userDefaultsRuntime { return param_dict(&userDefaultRuntimeParams, NULL); }
- (NSDictionary *)factoryDefaultsWorld { return param_dict(NULL, &defaultWorldParams); }
- (NSDictionary *)userDefaultsWorld { return param_dict(NULL, &userDefaultWorldParams); }
- (IBAction)openScriptingDictionary:(id)sender {
	NSWorkspace *ws = NSWorkspace.sharedWorkspace;
	NSURL *fileURL = [NSBundle.mainBundle URLForResource:@"SimEpidemic" withExtension:@"sdef"];
	NSURL *appURL = [ws URLForApplicationWithBundleIdentifier:@"com.apple.ScriptEditor2"];
	NSWorkspaceOpenConfiguration *config = NSWorkspaceOpenConfiguration.configuration;
	config.addsToRecentItems = NO;
	[ws openURLs:@[fileURL] withApplicationAtURL:appURL configuration:config completionHandler:nil];
}
@end

@implementation Document (ScriptingExtension)
// element
- (NSArray *)statPanels { return world.statInfo.statPanels; }
// property
- (NSDictionary *)runtimeParameter { return param_dict(world.runtimeParamsP, NULL); }
- (NSDictionary *)initialRuntimeParameter { return param_dict(world.initParamsP, NULL); }
- (NSDictionary *)currentWorldParameter { return param_dict(NULL, world.worldParamsP); }
- (NSDictionary *)temporaryWorldParameter { return param_dict(NULL, world.tmpWorldParamsP); }
- (void)setRuntimeParameter:(NSDictionary *)dict {
	set_params_from_dict(world.runtimeParamsP, NULL, dict);
}
- (void)setInitialRuntimeParameter:(NSDictionary *)dict {
	set_params_from_dict(world.initParamsP, NULL, dict);
}
- (void)setTemporaryWorldParameter:(NSDictionary *)dict {
	set_params_from_dict(NULL, world.tmpWorldParamsP, dict);
}
static NSAppleEventDescriptor *aeDesc(NSObject *obj) {
	if ([obj isKindOfClass:NSNumber.class]) {
		NSNumber *num = (NSNumber *)obj;
		const char *cType = num.objCType;
		if (strcmp(cType, @encode(int)) == 0)
			return [NSAppleEventDescriptor descriptorWithInt32:num.intValue];
		else return [NSAppleEventDescriptor descriptorWithDouble:num.doubleValue];
	} else if ([obj isKindOfClass:NSString.class])
		return [NSAppleEventDescriptor descriptorWithString:(NSString *)obj];
	else if ([obj isKindOfClass:NSArray.class]) {
		NSAppleEventDescriptor *list = NSAppleEventDescriptor.listDescriptor;
		for (NSInteger i = 0; i < ((NSArray *)obj).count; i ++)
			[list insertDescriptor:aeDesc(((NSArray *)obj)[i]) atIndex:i + 1];
		return list;
	} else return NSAppleEventDescriptor.nullDescriptor;
}
static NSObject *objFromAEDesc(NSAppleEventDescriptor *desc) {
	switch (desc.descriptorType) {
		case typeIEEE64BitFloatingPoint: return @(desc.doubleValue);
		case typeSInt32: return @(desc.int32Value);
		case typeUnicodeText: return desc.stringValue;
		case typeAEList: {
			NSInteger n = desc.numberOfItems;
			NSObject *elm[n];
			for (NSInteger i = 0; i < n; i ++)
				elm[i] = objFromAEDesc([desc descriptorAtIndex:i + 1]);
			return [NSArray arrayWithObjects:elm count:n];
		}
		default: { union { DescType d; char c[5]; } a =
			{.d = EndianS32_BtoN(desc.descriptorType)};
			a.c[4] = '\0';
			NSLog(@"%s", a.c);} return @0;
	}
	return @0;
}
- (NSAppleEventDescriptor *)scenarioPList { return aeDesc(world.scenarioPList); }
- (void)setScenarioPList:(NSAppleEventDescriptor *)list {
	NSArray *plist = (NSArray *)objFromAEDesc(list);
	if ([plist isKindOfClass:NSArray.class])
		[world setScenarioPList:plist];
}
- (NSArray *)vvListFrom:(MutableDictArray)orgList
	nameKey:(NSString *)nameKey efficacyKey:(NSString *)effKey keys:(NSArray *)keys {
	NSInteger nVar = world.variantList.count, nOrg = orgList.count;
	NSMutableDictionary *md = NSMutableDictionary.new;
	NSDictionary *elms[nOrg];
	NSString *varNames[nVar];
	NSNumber *eff[nVar];
	for (NSInteger j = 0; j < nVar; j ++) varNames[j] = world.variantList[j][@"name"];
	for (NSInteger i = 0; i < nOrg; i ++) {
		NSDictionary *elm = orgList[i];
		md[nameKey] = elm[@"name"];
		for (NSString *key in keys) md[key] = elm[key];
		for (NSInteger j = 0; j < nVar; j ++) {
			NSNumber *e = elm[varNames[j]];
			eff[j] = (e == nil)? @(1.) : e;
		}
		md[effKey] = [NSArray arrayWithObjects:eff count:nVar];
		elms[i] = [NSDictionary dictionaryWithDictionary:md];
	}
	return [NSArray arrayWithObjects:elms count:nOrg];
}
- (MutableDictArray)vvArrayFrom:(NSArray<NSDictionary *> *)vList nameList:(NSArray *)nameList {
	NSMutableArray *ma = NSMutableArray.new;
	NSInteger nVars = nameList.count;
	for (NSDictionary *elm in vList) {
		NSMutableDictionary *md = NSMutableDictionary.new;
		NSArray *eff = nil;
		for (NSString *key in elm) {
			if ([key hasSuffix:@"Name"]) md[@"name"] = elm[key];
			else if ([key hasSuffix:@"Efficacy"]) eff = md[key];
			else md[key] = elm[key];
		}
		NSInteger nEff = (eff == nil)? 0 : eff.count;
		for (NSInteger i = 0; i < nVars; i ++)
			md[nameList[i]] = (i < nEff)? eff[i] : @(1.);
		[ma addObject:md];
	}
	return ma;
}
static NSArray *object_array(NSArray<NSDictionary *> *array, NSString *key) {
	NSInteger n = array.count;
	NSObject *objects[n];
	for (NSInteger i = 0; i < n; i ++) {
		NSObject *obj = array[i][key];
		objects[i] = (obj == nil)? NSNull.null : obj;
	}
	return [NSArray arrayWithObjects:objects count:n];
}
- (NSArray *)variantList {
	return [self vvListFrom:world.variantList nameKey:@"variantName"
		efficacyKey:@"immunityEfficacy" keys:@[@"reproductivity", @"toxicity"]];
}
- (void)setVariantList:(NSArray<NSDictionary *> *)vList {
	world.variantList = [self vvArrayFrom:vList nameList:object_array(vList, @"variantName")];
	[NSNotificationCenter.defaultCenter postNotificationName:VariantListChanged object:world];
}
- (NSArray *)vaccineList {
	return [self vvListFrom:world.vaccineList
		nameKey:@"vaccineName" efficacyKey:@"vaccineEfficacy"
		keys:@[@"intervalOn", @"intervalDays"]];
}
- (void)setVaccineList:(MutableDictArray)vList {
	world.vaccineList = [self vvArrayFrom:vList nameList:object_array(world.variantList, @"name")];
	[NSNotificationCenter.defaultCenter postNotificationName:VaccineListChanged object:world];
}
- (BOOL)running { return world.loopMode == LoopRunning; }
- (void)setRunning:(BOOL)newValue {
	if ((world.loopMode == LoopRunning) != newValue)
		[self startStop:nil];
}
- (NSInteger)stopAt { return world.stopAtNDays; }
- (void)setStopAt:(NSInteger)newValue {
	NSControlStateValue on;
	if (newValue > 0) on = NSControlStateValueOn;
	else { on = NSControlStateValueOff;  newValue = -newValue; }
	if (stopAtNDaysDgt.integerValue != newValue) {
		stopAtNDaysDgt.integerValue = newValue;
		[stopAtNDaysDgt sendAction:stopAtNDaysDgt.action to:stopAtNDaysDgt.target];
	}
	if (stopAtNDaysCBox.state != on) {
		stopAtNDaysCBox.state = on;
		[stopAtNDaysCBox sendAction:stopAtNDaysCBox.action to:stopAtNDaysCBox.target];
	}
}
- (BOOL)showGatherings { return view.showGatherings; }
- (void)setShowGatherings:(BOOL)newValue {
	if (newValue == view.showGatherings) return;
	showGatheringsCBox.state = newValue;
	view.showGatherings = newValue;
}
- (BOOL)fullScreen { return fillView != nil; }
- (void)setFullScreen:(BOOL)newValue {
	if (newValue == (fillView == nil))
		[daysNum.window toggleFullScreen:nil];
}
// command
- (id)handleCloseCommand:(NSScriptCommand *)com {
	[daysNum.window performClose:nil];
	return nil;
}
- (id)handleResetCommand:(NSScriptCommand *)com {
	[self reset:nil];
	return nil;
}
- (id)handleOpenStatCommand:(NSScriptCommand *)com {
	return [world.statInfo openStatPanel:daysNum.window];
}
@end

@implementation StatPanel (ScriptingExtension)
- (NSScriptObjectSpecifier *)objectSpecifier {
	return [NSIndexSpecifier.alloc initWithContainerClassDescription:
		[NSScriptClassDescription classDescriptionForClass:Document.class]
		containerSpecifier:statInfo.doc.objectSpecifier
		key:@"statPanels" index:[statInfo.statPanels indexOfObject:self]];
}
//- (NSInteger)statType { return typePopUp.indexOfSelectedItem; }
- (void)setStatType:(NSInteger)newIdx {
	if (newIdx == typePopUp.indexOfSelectedItem
	 || newIdx < 0 || newIdx >= typePopUp.numberOfItems) return;
	[typePopUp selectItemAtIndex:newIdx];
	[typePopUp sendAction:typePopUp.action to:typePopUp.target];
}
static void switch_cbox(NSButton *cbox, BOOL newValue) {
	if (newValue == cbox.state) return;
	cbox.state = newValue;
	[cbox sendAction:cbox.action to:cbox.target];
}
#define IDX_PROP(g,s,n) - (BOOL)g { return indexCBoxes[n].state; }\
- (void)s:(BOOL)value { switch_cbox(indexCBoxes[n],value); }
IDX_PROP(susceptible,setSusceptible,0)
IDX_PROP(asymptomatic,setAsymptomatic,1)
IDX_PROP(symptomatic,setSymptomatic,2)
IDX_PROP(recovered,setRecovered,3)
IDX_PROP(died,setDied,4)
IDX_PROP(vaccinated,setVaccinated,5)
IDX_PROP(quarantineAsym,setQuarantineAsym,6)
IDX_PROP(quarantineSymp,setQuarantineSymp,7)
IDX_PROP(testsTotal,setTestsTotal,8)
IDX_PROP(testsAsSymptom,setTestsAsSymptom,9)
IDX_PROP(testsAsContact,setTestsAsContact,10)
IDX_PROP(testsAsSuspected,setTestsAsSuspected,11)
IDX_PROP(testPositive,setTestPositive,12)
IDX_PROP(testNegative,setTestNegative,13)
IDX_PROP(positiveRate,setPositiveRate,14)
#define CBOX_PROP(g,s,c) - (BOOL)g { return c.state; }\
- (void)s:(BOOL)value { switch_cbox(c,value); }
CBOX_PROP(daily,setDaily,transitCBox)
CBOX_PROP(reproductionNumber,setReproductionNumber,reproRateCBox)
- (NSInteger)windowExponent { return mvAvrgStp.integerValue; }
- (void)setWidnowExponent:(NSInteger)value {
	if (value == mvAvrgStp.integerValue || value < 0) return;
	mvAvrgStp.integerValue = value;
	[mvAvrgStp sendAction:mvAvrgStp.action to:mvAvrgStp.target];
}
//
- (id)handleCloseCommand:(NSScriptCommand *)com {
	[self.window performClose:nil];
	return nil;
}
@end
