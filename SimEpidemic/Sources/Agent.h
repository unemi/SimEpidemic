//
//  Agent.h
//  SimEpidemic
//
//  Created by Tatsuo Unemi on 2020/04/28.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "World.h"
#import "CommonTypes.h"
#define AGENT_RADIUS .5
#define AGENT_SIZE .665
#define BIG_NUM 1e10
#define PopDistMapRes 512

typedef enum {
	AgntDrwCircle, AgntDrwOctagon, AgntDrwSquire, AgntDrwPoint
} AgentDrawType;

typedef struct {
	NSInteger moveFrom, moveTo;
	WarpType warpType; NSPoint warpTo;
	HistogramType histType; CGFloat histDays;
	TestType testType;
	VcnNowType vcnNowType;
} StepInfo;

@interface World (AgentExtension)
- (void)interactsA:(Agent *)a Bs:(Agent **)b n:(NSInteger)n;
- (void)avoidGatherings:(NSInteger)gIdx agents:(Agent **)a n:(NSInteger)n;
@end

extern CGFloat d_random(void);
extern CGFloat modified_prob(CGFloat x, DistInfo *p);
extern CGFloat my_random(DistInfo *p);
extern BOOL is_infected(Agent *a);
extern void reset_agent(Agent *a, CGFloat age, RuntimeParams *rp, WorldParams *wp);
extern NSBitmapImageRep *make_pop_dist_bm(void);
extern NSBitmapImageRep *make_bm_with_image(NSImage *image);
extern void make_lattice_postions(NSPoint *pts, NSInteger n);
extern void pop_dist_alloc(NSInteger x, NSInteger y, NSInteger w,
	NSPoint *pts, NSInteger n, float *pd, BOOL isRandom);
extern void reset_for_step(Agent *a);
extern NSInteger index_in_pop(CGFloat x, CGFloat y, WorldParams *p);
extern void add_to_list(Agent *a, Agent **list);
extern void remove_from_list(Agent *a, Agent **list);
extern void add_agent(Agent *a, WorldParams *wp, Agent **Pop);
extern void remove_agent(Agent *a, WorldParams *p, Agent **Pop);
extern void interacts(Agent *a, Agent **b, NSInteger n, RuntimeParams *rp, WorldParams *wp);
//extern void going_back_home(Agent *a);
extern void going_back_home(Agent *a, StepInfo *info, ParamsForStep prms);
extern void step_agent(Agent *a, ParamsForStep prms, BOOL goHomeBack, StepInfo *info);
extern BOOL warp_step(Agent *a, WorldParams *wp, World *world, WarpType mode, NSPoint goal);
extern void step_agent_in_quarantine(Agent *a, ParamsForStep prms, StepInfo *info);
extern void warp_show(Agent *a, WarpType mode, NSPoint goal, NSRect dirtyRect, NSBezierPath *path);
extern void show_agent(Agent *a, AgentDrawType type, NSRect dirtyRect, NSBezierPath *path);
