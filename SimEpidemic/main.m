//
//  main.m
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//
#import <Cocoa/Cocoa.h>

int main(int argc, const char * argv[]) {
#ifndef DEBUG
	srand48(time(0) + getpid());
#endif
	return NSApplicationMain(argc, argv);
}
