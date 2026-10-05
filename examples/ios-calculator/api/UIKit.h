// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#import "Foundation.h"

typedef double CGFloat;
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct { CGFloat top, left, bottom, right; } UIEdgeInsets;
static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
    return (CGRect){{x, y}, {width, height}};
}
_Static_assert(sizeof(CGRect) == 32, "ARM64 CGRect ABI");

typedef NSInteger UIButtonType;
typedef NSInteger NSTextAlignment;
typedef NSUInteger UIControlState;
typedef NSUInteger UIControlEvents;
enum { UIButtonTypeSystem = 1, NSTextAlignmentRight = 2 };
enum { UIControlStateNormal = 0, UIControlEventTouchUpInside = 1 << 6 };

@interface UIColor : NSObject
+ (instancetype)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
@end

@interface UIFont : NSObject
+ (instancetype)systemFontOfSize:(CGFloat)size weight:(CGFloat)weight;
@end

@interface CALayer : NSObject
@property(nonatomic) CGFloat cornerRadius;
@end

@interface UIView : NSObject
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
@property(nonatomic) CGRect frame;
@property(nonatomic, readonly) CGRect bounds;
@property(nonatomic, readonly) UIEdgeInsets safeAreaInsets;
@property(nonatomic, strong) UIColor *backgroundColor;
@property(nonatomic, readonly) CALayer *layer;
@property(nonatomic, copy) NSString *accessibilityLabel;
@property(nonatomic) NSInteger tag;
@end

@interface UILabel : UIView
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) UIColor *textColor;
@property(nonatomic, strong) UIFont *font;
@property(nonatomic) NSTextAlignment textAlignment;
@property(nonatomic) BOOL adjustsFontSizeToFitWidth;
@property(nonatomic) CGFloat minimumScaleFactor;
@end

@interface UIControl : UIView
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)events;
@end

@interface UIButton : UIControl
+ (instancetype)buttonWithType:(UIButtonType)type;
- (void)setTitle:(NSString *)title forState:(UIControlState)state;
- (void)setTitleColor:(UIColor *)color forState:(UIControlState)state;
@property(nonatomic, readonly) UILabel *titleLabel;
@end

@interface UIViewController : NSObject
@property(nonatomic, strong) UIView *view;
- (void)viewDidLoad;
- (void)viewDidLayoutSubviews;
@end

@interface UIWindow : UIView
@property(nonatomic, strong) UIViewController *rootViewController;
- (void)makeKeyAndVisible;
@end

@interface UIScreen : NSObject
+ (instancetype)mainScreen;
@property(nonatomic, readonly) CGRect bounds;
@end

@class UIApplication;
@protocol UIApplicationDelegate
@optional
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options;
@end

int UIApplicationMain(int argc, char **argv, NSString *principalClassName, NSString *delegateClassName);
