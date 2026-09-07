// SPDX-License-Identifier: GPL-2.0-or-later
// Minimal declarations for the AppKit surface implemented by Vinix.
// This is intentionally declarations-only: the implementation lives in V.
#ifndef VINIX_COCOA_H
#define VINIX_COCOA_H

typedef signed long NSInteger;
typedef unsigned long NSUInteger;
typedef signed char BOOL;
typedef void *SEL;

#define YES ((BOOL)1)
#define NO ((BOOL)0)
#define nil ((id)0)

typedef struct NSPoint {
    double x;
    double y;
} NSPoint;

typedef struct NSSize {
    double width;
    double height;
} NSSize;

typedef struct NSRect {
    NSPoint origin;
    NSSize size;
} NSRect;

static inline NSRect NSMakeRect(double x, double y, double width, double height) {
    return (NSRect){{x, y}, {width, height}};
}

enum {
    NSWindowStyleMaskTitled = 1u << 0,
    NSWindowStyleMaskClosable = 1u << 1,
    NSBackingStoreBuffered = 2,
    NSTextAlignmentRight = 1,
};

@class NSString, NSView, NSWindow, NSButton, NSTextField, NSApplication;

@interface NSObject
+ (id)new;
+ (id)alloc;
- (id)init;
@end

@protocol NSApplicationDelegate
- (void)applicationDidFinishLaunching:(id)notification;
@end

@interface NSApplication : NSObject
+ (NSApplication *)sharedApplication;
- (void)setDelegate:(id<NSApplicationDelegate>)delegate;
- (void)run;
@end

@interface NSView : NSObject
- (void)addSubview:(NSView *)view;
@end

@interface NSWindow : NSObject
- (id)initWithContentRect:(NSRect)rect
                styleMask:(NSUInteger)style
                  backing:(NSUInteger)backing
                    defer:(BOOL)defer;
- (void)setTitle:(NSString *)title;
- (NSView *)contentView;
- (void)makeKeyAndOrderFront:(id)sender;
@end

@interface NSButton : NSView
+ (NSButton *)buttonWithTitle:(NSString *)title target:(id)target action:(SEL)action;
- (void)setFrame:(NSRect)frame;
- (void)setTag:(NSInteger)tag;
- (NSInteger)tag;
@end

@interface NSTextField : NSView
+ (NSTextField *)labelWithString:(NSString *)text;
- (void)setFrame:(NSRect)frame;
- (void)setAlignment:(NSInteger)alignment;
- (void)setIntegerValue:(NSInteger)value;
@end

#endif
