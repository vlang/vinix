// SPDX-License-Identifier: GPL-2.0-or-later
typedef unsigned long NSUInteger;
typedef _Bool bool;
extern int puts(const char *);
extern void abort(void);
extern int setenv(const char *, const char *, int);
extern int strcmp(const char *, const char *);

__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)alloc;
+ (instancetype)new;
+ (Class)class;
- (instancetype)init;
- (bool)isKindOfClass:(Class)cls;
@end
@interface NSString : NSObject
- (const char *)UTF8String;
@end
@interface NSURL : NSObject
- (bool)isFileURL;
- (NSString *)path;
- (NSString *)absoluteString;
- (NSString *)scheme;
@end
@interface NSDictionary : NSObject
- (id)objectForKey:(id)key;
@end
extern NSString *const UIApplicationLaunchOptionsURLKey;
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
@interface UIOpenURLContext : NSObject
- (NSURL *)URL;
@end
@interface UIApplication : NSObject
+ (instancetype)sharedApplication;
- (id)delegate;
- (bool)isIdleTimerDisabled;
- (void)setIdleTimerDisabled:(bool)disabled;
@end
@interface UIWindowScene : NSObject @end
@interface UISceneSession : NSObject @end
@interface UISceneConnectionOptions : NSObject
- (NSSet *)URLContexts;
@end
@interface UIViewController : NSObject
- (NSUInteger)preferredScreenEdgesDeferringSystemGestures;
- (bool)prefersHomeIndicatorAutoHidden;
- (void)setNeedsUpdateOfScreenEdgesDeferringSystemGestures;
- (void)setNeedsUpdateOfHomeIndicatorAutoHidden;
@end
@interface UIWindow : NSObject
- (instancetype)initWithWindowScene:(UIWindowScene *)scene;
- (void)setRootViewController:(UIViewController *)controller;
- (void)makeKeyAndVisible;
@end
extern int UIApplicationMain(int, char **, NSString *, NSString *);

static int launched, connected;
static const char *launch_path;
static const char *launch_uri = "file:///opt/ios/launch%20name%23%C3%A9%25%3F.bin";
static __weak NSURL *launched_url;
static int edge_queries, indicator_queries;
@interface SceneFixtureController : UIViewController @end
@implementation SceneFixtureController
- (NSUInteger)preferredScreenEdgesDeferringSystemGestures { ++edge_queries; return 15; }
- (bool)prefersHomeIndicatorAutoHidden { ++indicator_queries; return 1; }
@end
@interface SceneFixtureAppDelegate : NSObject @end
@implementation SceneFixtureAppDelegate
- (bool)application:(UIApplication *)application didFinishLaunchingWithOptions:(id)options {
    if (application != [UIApplication sharedApplication] || application.delegate != self) abort();
    if ([application isIdleTimerDisabled]) abort();
    [application setIdleTimerDisabled:1];
    if (![application isIdleTimerDisabled]) abort();
    [application setIdleTimerDisabled:0];
    if ([application isIdleTimerDisabled]) abort();
    if (launch_path) {
        NSURL *url = [(NSDictionary *)options objectForKey:UIApplicationLaunchOptionsURLKey];
        if (!url.isFileURL || strcmp(url.path.UTF8String, launch_path) || strcmp(url.scheme.UTF8String, "file") ||
            strcmp(url.absoluteString.UTF8String, launch_uri)) abort();
        launched_url = url;
    } else if (options) abort();
    ++launched;
    return 1;
}
@end

@interface SceneFixtureDelegate : NSObject
@property (nonatomic, strong) UIWindow *window;
@end
@implementation SceneFixtureDelegate
- (void)scene:(UIWindowScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (!launched || !session || ![scene isKindOfClass:[UIWindowScene class]] ||
        [options.URLContexts count] != (launch_path ? 1 : 0)) abort();
    for (UIOpenURLContext *context in options.URLContexts) {
        if (context.URL != launched_url || strcmp(context.URL.path.UTF8String, launch_path)) abort();
    }
    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    UIViewController *controller = [SceneFixtureController new];
    [controller setNeedsUpdateOfScreenEdgesDeferringSystemGestures];
    [controller setNeedsUpdateOfHomeIndicatorAutoHidden];
    if (edge_queries != 1 || indicator_queries != 1) abort();
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    ++connected;
    puts("IOS-SCENE: native app delegate, manifest scene connection and window");
}
@end

int main(int argc, char **argv) {
    if (argc == 2 || argc == 3) {
        launch_path = argv[1];
        if (argc == 3) launch_uri = argv[2];
        if (setenv("VINIX_IOS_OPEN_FILE", launch_path, 1)) return 62;
    }
    @autoreleasepool {
        // The headless harness deliberately has no compositor descriptors.
        int status = UIApplicationMain(argc, argv, 0, @"SceneFixtureAppDelegate");
        if (status != 1 || launched != 1 || connected != 1) return 61;
    }
    if (launched_url) return 63;
    if (launch_path) puts("IOS-SCENE-FILE: launch options, scene URL contexts, percent encoding and ARC lifetime");
    return 0;
}
