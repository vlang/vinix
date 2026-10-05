// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#import "../../../ios-calculator/api/UIKit.h"
static inline CGPoint CGPointMake(CGFloat x, CGFloat y) { return (CGPoint){x,y}; }
typedef NSUInteger UIViewAnimationOptions;
typedef NSUInteger UISwipeGestureRecognizerDirection;
enum { NSTextAlignmentCenter = 1, UIViewAnimationOptionBeginFromCurrentState = 4,
       UISwipeGestureRecognizerDirectionRight = 1, UISwipeGestureRecognizerDirectionLeft = 2,
       UISwipeGestureRecognizerDirectionUp = 4, UISwipeGestureRecognizerDirectionDown = 8 };
@interface UIResponder : NSObject @end
@interface UIColor (VinixDeclarations)
+ (instancetype)whiteColor;
+ (instancetype)blackColor;
+ (instancetype)darkGrayColor;
+ (instancetype)lightGrayColor;
+ (instancetype)grayColor;
@end
@interface UIFont (VinixDeclarations)
+ (instancetype)fontWithName:(NSString *)name size:(CGFloat)size;
@end
@class UIGestureRecognizer;
@interface UIView (VinixDeclarations)
@property(nonatomic) BOOL userInteractionEnabled;
- (void)removeFromSuperview;
- (void)addGestureRecognizer:(UIGestureRecognizer *)recognizer;
+ (void)animateWithDuration:(NSTimeInterval)duration animations:(void(^)(void))animations completion:(void(^)(BOOL))completion;
+ (void)animateWithDuration:(NSTimeInterval)duration delay:(NSTimeInterval)delay options:(UIViewAnimationOptions)options animations:(void(^)(void))animations completion:(void(^)(BOOL))completion;
@end
@interface UIButton (VinixDeclarations)
@property(nonatomic) BOOL showsTouchWhenHighlighted;
@end
@interface UIViewController (VinixDeclarations)
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void(^)(void))completion;
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void(^)(void))completion;
@end
@interface UIGestureRecognizer : NSObject
- (instancetype)initWithTarget:(id)target action:(SEL)selector;
@end
@interface UISwipeGestureRecognizer : UIGestureRecognizer
@property(nonatomic) NSUInteger numberOfTouchesRequired;
@property(nonatomic) UISwipeGestureRecognizerDirection direction;
@end
@interface UIAlertView : UIView
- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message delegate:(id)delegate cancelButtonTitle:(NSString *)cancel otherButtonTitles:(NSString *)other, ...;
- (void)show;
@end
