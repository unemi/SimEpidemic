//
//  Agent.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CommonTypes.h"
#define AGENT_RADIUS .75
#define AGENT_SIZE .665

typedef enum {
	AgntDrwCircle, AgntDrwOctagon, AgntDrwSquire, AgntDrwPoint
} AgentDrawType;

@class Document;
extern BOOL was_hit(WorldParams *wp, CGFloat prob);
extern void reset_agent(Agent *a, RuntimeParams *rp, WorldParams *wp);
extern void reset_for_step(Agent *a);
extern void remove_from_list(Agent *a, Agent **list);
extern void add_agent(Agent *a, WorldParams *wp, Agent **Pop);
extern void remove_agent(Agent *a, WorldParams *p, Agent **Pop);
extern void interacts(Agent *a, Agent *b, RuntimeParams *rp, WorldParams *wp);
extern void step_agent(Agent *a, RuntimeParams *rp, WorldParams *wp, Document *doc);
extern BOOL warp_step(Agent *a, WorldParams *wp, Document *doc, WarpType mode, CGPoint goal);
extern void step_agent_in_quarantine(Agent *a, WorldParams *p, Document *doc);
extern void warp_show(Agent *a, WarpType mode, CGPoint goal,
	NSRect dirtyRect, NSArray<NSBezierPath *> *paths);
extern void show_agent(Agent *a, AgentDrawType type,
	NSRect dirtyRect, NSArray<NSBezierPath *> *paths);
