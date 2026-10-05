// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#import <UIKit/UIKit.h>
typedef struct { CGFloat a,b,c,d,tx,ty; } CGAffineTransform;
static inline CGAffineTransform CGAffineTransformMakeScale(CGFloat x, CGFloat y) {
    return (CGAffineTransform){x,0,0,y,0,0};
}
extern const CGAffineTransform CGAffineTransformIdentity;
@interface CALayer (VinixDeclarations)
@property(nonatomic) CGAffineTransform affineTransform;
@end
