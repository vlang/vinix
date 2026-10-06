// SPDX-License-Identifier: GPL-2.0-or-later
typedef unsigned long NSUInteger;
typedef _Bool bool;
extern int puts(const char *);
extern void abort(void);

__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)alloc;
+ (instancetype)new;
+ (Class)class;
- (instancetype)init;
- (bool)isKindOfClass:(Class)cls;
@end
@interface NSString : NSObject @end
@interface NSSet : NSObject
- (NSUInteger)count;
@end
@interface UIApplication : NSObject
+ (instancetype)sharedApplication;
- (id)delegate;
@end
@interface UIWindowScene : NSObject @end
@interface UISceneSession : NSObject @end
@interface UISceneConnectionOptions : NSObject
- (NSSet *)URLContexts;
@end
@interface UIViewController : NSObject @end
@interface UIWindow : NSObject
- (instancetype)initWithWindowScene:(UIWindowScene *)scene;
- (void)setRootViewController:(UIViewController *)controller;
- (void)makeKeyAndVisible;
@end
extern int UIApplicationMain(int, char **, NSString *, NSString *);

static int launched, connected;
@interface SceneFixtureAppDelegate : NSObject @end
@implementation SceneFixtureAppDelegate
- (bool)application:(UIApplication *)application didFinishLaunchingWithOptions:(id)options {
    if (application != [UIApplication sharedApplication] || application.delegate != self || options) abort();
    ++launched;
    return 1;
}
@end

@interface SceneFixtureDelegate : NSObject
@property (nonatomic, strong) UIWindow *window;
@end
@implementation SceneFixtureDelegate
- (void)scene:(UIWindowScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (!launched || !session || ![scene isKindOfClass:[UIWindowScene class]] || [options.URLContexts count]) abort();
    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    ++connected;
    puts("IOS-SCENE: native app delegate, manifest scene connection and window");
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        // The headless harness deliberately has no compositor descriptors.
        int status = UIApplicationMain(argc, argv, 0, @"SceneFixtureAppDelegate");
        if (status != 1 || launched != 1 || connected != 1) return 61;
    }
    return 0;
}
