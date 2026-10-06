// SPDX-License-Identifier: GPL-2.0-or-later
#import "../../examples/ios-calculator/api/UIKit.h"
#include <GLES3/gl3.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

@interface NSString (FormattingFixture)
+ (instancetype)stringWithFormat:(NSString *)format, ...;
- (const char *)UTF8String;
@end

@interface EAGLContext : NSObject
- (instancetype)initWithAPI:(NSUInteger)api;
@end
@interface GLKView : UIView
- (instancetype)initWithFrame:(CGRect)frame context:(EAGLContext *)context;
- (void)display;
@property(nonatomic, weak) id delegate;
@end
@interface NSRunLoop : NSObject
+ (instancetype)mainRunLoop;
@end
extern NSString *const NSDefaultRunLoopMode;
@interface CADisplayLink : NSObject
+ (instancetype)displayLinkWithTarget:(id)target selector:(SEL)selector;
- (void)addToRunLoop:(NSRunLoop *)loop forMode:(NSString *)mode;
- (void)invalidate;
@property(nonatomic) NSInteger preferredFramesPerSecond;
@property(nonatomic, getter=isPaused) BOOL paused;
@property(readonly) double timestamp, duration, targetTimestamp;
@end
extern void dispatch_async(void *, void (^)(void));
extern void *dispatch_get_main_queue(void);

static NSUInteger ticks, draws;
static int queued;
static double previous;
static unsigned touches;
static __weak id delivered_touch;
typedef struct {
    unsigned long state;
    id __unsafe_unretained *itemsPtr;
    unsigned long *mutationsPtr;
    unsigned long extra[5];
} NSFastEnumerationState;
@interface NSSet : NSObject
- (NSUInteger)count;
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained *)objects count:(NSUInteger)count;
@end
@interface UITouch : NSObject
- (CGPoint)locationInView:(UIView *)view;
@property(readonly) NSUInteger phase;
@property(readonly) double timestamp;
@end
@interface UIEvent : NSObject
@property(readonly) NSSet *allTouches;
@end
@interface TouchController : UIViewController @end
@implementation TouchController
- (void)touchesBegan:(NSSet *)set withEvent:(UIEvent *)event {
    if (event.allTouches != set || set.count != 1 || touches) abort();
    for (UITouch *touch in set) {
        CGPoint point = [touch locationInView:self.view];
        if (point.x != 9 || point.y != 11 || touch.phase != 0 || touch.timestamp <= 0) abort();
        delivered_touch = touch;
        ++touches;
    }
}
- (void)touchesEnded:(NSSet *)set withEvent:(UIEvent *)event {
    if (event.allTouches != set || set.count != 1 || touches != 1) abort();
    for (UITouch *touch in set) {
        CGPoint point = [touch locationInView:self.view];
        if (touch != delivered_touch || point.x != 9 || point.y != 11 || touch.phase != 3) abort();
        ++touches;
    }
}
@end

@interface GraphicsDelegate : NSObject
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) GLKView *graphics;
@property(nonatomic, strong) CADisplayLink *link;
@end
@implementation GraphicsDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(id)options {
    (void)application; (void)options;
    NSString *formatted = [NSString stringWithFormat:@"(%d, %d) @%.1fx %@ %08x %s", -7, 24, 1.25, @"native", 42, "GLES"];
    if (strcmp(formatted.UTF8String, "(-7, 24) @1.2x native 0000002a GLES")) abort();
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 680)];
    UIViewController *controller = [TouchController new];
    self.window.rootViewController = controller;
    EAGLContext *context = [[EAGLContext alloc] initWithAPI:3];
    if (!context) abort();
    self.graphics = [[GLKView alloc] initWithFrame:CGRectMake(0, 0, 32, 24) context:context];
    self.graphics.delegate = self;
    [controller.view addSubview:self.graphics];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0, 40, 100, 32);
    [button setTitle:@"Pause/resume" forState:0];
    [button addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
    [controller.view addSubview:button];
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    self.link.preferredFramesPerSecond = 30;
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (ticks || queued) abort();
        if (self.link.preferredFramesPerSecond != 30) abort();
        queued = 1;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.link.preferredFramesPerSecond != 30) abort();
            queued = 2;
        });
    });
    [self.window makeKeyAndVisible];
    return YES;
}
- (void)tick:(CADisplayLink *)link {
    if ((ticks == 0 && queued != 1) || (ticks > 0 && queued != 2)) abort();
    if (link.timestamp <= previous || link.duration < 0.033 || link.duration > 0.034 ||
        link.targetTimestamp <= link.timestamp) abort();
    previous = link.timestamp;
    ++ticks;
    [self.graphics display];
}
- (void)toggle:(id)sender { (void)sender; self.link.paused = !self.link.isPaused; }
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    if (view != self.graphics || rect.size.width != 32 || rect.size.height != 24) abort();
    glClearColor(1, (float)(ticks & 1), 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    ++draws;
}
- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
    if (ticks < 3 || draws != ticks || queued != 2 || touches != 2 || delivered_touch) abort();
    [self.link invalidate];
    self.link = nil;
    puts("IOS-GLES-APP: main queue, display link timing/pause and native drawing callbacks");
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, @"GraphicsDelegate"); }
}
