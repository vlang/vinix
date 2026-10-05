// SPDX-License-Identifier: GPL-2.0-or-later
// Narrow, independently written declarations for this example's ARM64 ABI.
// A real iOS SDK is used instead whenever one is installed.
#pragma once

typedef _Bool BOOL;
typedef long NSInteger;
typedef unsigned long NSUInteger;
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#define nil ((id)0)

__attribute__((objc_root_class))
@interface NSObject {
    // The object header must be represented even with nonfragile ivars.
    // Omitting this slot would place the subclass's first ivar over isa.
    Class isa;
}
+ (instancetype)alloc;
+ (instancetype)new;
- (instancetype)init;
@end

@interface NSString : NSObject
+ (instancetype)stringWithUTF8String:(const char *)text;
@end

@class NSDictionary;
