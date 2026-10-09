// SPDX-License-Identifier: GPL-2.0-or-later
// Identical fixture for installed Catalyst UIKit and Vinix's V implementation.
typedef _Bool BOOL;
typedef unsigned long Traits;
typedef struct { double x, y; } Point;
typedef struct { double width, height; } Size;
typedef struct { Point origin; Size size; } Rect;
extern int puts(const char *), strcmp(const char *, const char *);
extern void abort(void);
extern BOOL UIAccessibilityIsVoiceOverRunning(void);
extern void UIAccessibilityPostNotification(unsigned, id);
extern void UIAccessibilityRegisterGestureConflictWithZoom(void);
extern const unsigned UIAccessibilityAnnouncementNotification, UIAccessibilityLayoutChangedNotification;
extern const Traits UIAccessibilityTraitButton, UIAccessibilityTraitNotEnabled;
__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)new;
+ (instancetype)alloc;
- (BOOL)respondsToSelector:(SEL)selector;
@property BOOL isAccessibilityElement;
@end
@interface NSString : NSObject
+ (instancetype)stringWithUTF8String:(const char *)text;
- (const char *)UTF8String;
@end
@interface UIResponder : NSObject @end
@interface UIAccessibilityElement : UIResponder
- (instancetype)initWithAccessibilityContainer:(id)container;
@property (weak) id accessibilityContainer;
@property BOOL isAccessibilityElement;
@property (strong) NSString *accessibilityLabel;
@property (strong) NSString *accessibilityHint;
@property (strong) NSString *accessibilityValue;
@property (copy) NSString *accessibilityIdentifier;
@property Traits accessibilityTraits;
@property Rect accessibilityFrame;
@property Rect accessibilityFrameInContainerSpace;
@end
#define CHECK(c) do { if (!(c)) { puts("IOS-ACCESSIBILITY FAIL: " #c); abort(); } } while (0)
int main(void) { @autoreleasepool {
    // Controlled reference environment has VoiceOver off, as does Vinix.
    CHECK(!UIAccessibilityIsVoiceOverRunning());
    UIAccessibilityRegisterGestureConflictWithZoom();
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"announcement without an active reader");
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, (id)0);
    for (unsigned iteration = 0; iteration < 200; iteration++) { @autoreleasepool {
        NSObject *container = [NSObject new];
        __weak NSObject *weak_container = container;
        UIAccessibilityElement *element = [[UIAccessibilityElement alloc] initWithAccessibilityContainer:container];
        CHECK(element.isAccessibilityElement && element.accessibilityTraits == 0);
        CHECK(!element.accessibilityLabel && !element.accessibilityHint && !element.accessibilityValue);
        @autoreleasepool { CHECK(element.accessibilityContainer == container); }
        Rect rect = element.accessibilityFrame;
        CHECK(rect.origin.x == 0 && rect.origin.y == 0 && rect.size.width == 0 && rect.size.height == 0);
        Rect container_rect = element.accessibilityFrameInContainerSpace;
        CHECK(container_rect.origin.x > 1e100 && container_rect.origin.y > 1e100 && container_rect.size.width == 0 && container_rect.size.height == 0);
        element.accessibilityFrame = (Rect){{12.5, -8.25}, {91.75, 42.125}};
        rect = element.accessibilityFrame;
        CHECK(rect.origin.x == 12.5 && rect.origin.y == -8.25 && rect.size.width == 91.75 && rect.size.height == 42.125);
        element.isAccessibilityElement = 0;
        element.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitNotEnabled;
        CHECK(!element.isAccessibilityElement && element.accessibilityTraits == 257);
        __weak NSString *weak_label;
        @autoreleasepool {
            NSString *label = [NSString stringWithUTF8String:"owned accessibility label outside a view"];
            weak_label = label;
            element.accessibilityLabel = label;
            element.accessibilityHint = @"hint";
            element.accessibilityValue = @"value";
            element.accessibilityIdentifier = @"identifier";
            label = (id)0;
            CHECK(weak_label != (id)0);
        }
        @autoreleasepool {
            CHECK(!strcmp(element.accessibilityLabel.UTF8String, "owned accessibility label outside a view"));
            CHECK(!strcmp(element.accessibilityHint.UTF8String, "hint") && !strcmp(element.accessibilityValue.UTF8String, "value"));
            CHECK(!strcmp(element.accessibilityIdentifier.UTF8String, "identifier"));
            CHECK([element respondsToSelector:@selector(accessibilityLabel)]);
        }
        container = (id)0;
        CHECK(!weak_container && !element.accessibilityContainer);
        NSObject *replacement = [NSObject new];
        element.accessibilityContainer = replacement;
        @autoreleasepool { CHECK(element.accessibilityContainer == replacement); }
        element = (id)0;
        CHECK(!weak_label);
        CHECK(!replacement.isAccessibilityElement && [replacement respondsToSelector:@selector(setIsAccessibilityElement:)]);
        replacement.isAccessibilityElement = 1;
        CHECK(replacement.isAccessibilityElement);
    } }
    puts("IOS-ACCESSIBILITY: disabled service queries, element metadata, HFA frames, weak containers and ARC ownership");
} return 0; }
