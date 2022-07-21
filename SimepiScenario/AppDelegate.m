//
//  AppDelegate.m
//  SimepiScenario
//
//  Created by Tatsuo Unemi on 2022/07/12.
//  Copyright © 2022 Tatsuo Unemi. All rights reserved.
//

#import "AppDelegate.h"
#import "MyController.h"

@interface AppDelegate () {
}
@property (strong) IBOutlet NSWindow *window;
@property IBOutlet MyController *controller;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	[_controller setup];
	[_window makeKeyAndOrderFront:self];
}
- (void)applicationWillTerminate:(NSNotification *)aNotification {
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
	return NO;
}
@end
