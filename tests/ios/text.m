// SPDX-License-Identifier: GPL-2.0-or-later
#import "../../examples/ios-calculator/api/UIKit.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

@interface NSString (TextFixture)
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)length encoding:(NSUInteger)encoding;
- (const char *)UTF8String;
@end
@interface NSDictionary : NSObject
+ (instancetype)dictionaryWithObjects:(const id *)objects forKeys:(const id *)keys count:(NSUInteger)count;
@end
@interface NSURL : NSObject
+ (instancetype)fileURLWithPath:(NSString *)path;
@end
@interface NSBundle : NSObject
+ (instancetype)mainBundle;
- (NSURL *)URLForResource:(NSString *)name withExtension:(NSString *)extension;
@end
@interface NSAttributedString : NSObject
- (instancetype)initWithString:(NSString *)string attributes:(NSDictionary *)attributes;
@end
@interface UIColor (TextFixture)
@property(readonly) void *CGColor;
@end
extern void *CTFontManagerCreateFontDescriptorsFromURL(void *);
extern unsigned char CTFontManagerRegisterFontsForURL(void *, unsigned, void **);
extern void *CTFontDescriptorCopyAttribute(void *, void *);
extern void *CTFontCreateWithName(void *, double, const void *);
extern void *CTFontCreateCopyWithSymbolicTraits(void *, double, const void *, unsigned, unsigned);
extern void *CTLineCreateWithAttributedString(void *);
extern double CTLineGetTypographicBounds(void *, double *, double *, double *);
extern void CTLineDraw(void *, void *);
extern void *CFStringCreateWithCString(void *, const char *, unsigned);
extern long CFArrayGetCount(void *);
extern void *CFArrayGetValueAtIndex(void *, long);
extern unsigned long CFGetTypeID(void *), CFStringGetTypeID(void);
extern void CFRelease(void *);
extern void *kCTFontNameAttribute, *kCTFontAttributeName, *kCTForegroundColorFromContextAttributeName, *kCFBooleanTrue;
extern void *CGColorSpaceCreateDeviceRGB(void);
extern void CGColorSpaceRelease(void *), CGContextRelease(void *);
extern void *CGBitmapContextCreate(void *, unsigned long, unsigned long, unsigned long, unsigned long, void *, unsigned);
extern void CGContextSetFillColorWithColor(void *, void *);
extern void CGContextSetStrokeColorWithColor(void *, void *);
extern void CGContextSetTextPosition(void *, double, double);

int main(void) {
    @autoreleasepool {
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"font" withExtension:@"ttf"];
        if (!url) abort();
        void *descriptors = CTFontManagerCreateFontDescriptorsFromURL((__bridge void *)url);
        if (!descriptors || CFArrayGetCount(descriptors) != 1) abort();
        void *name = CTFontDescriptorCopyAttribute(CFArrayGetValueAtIndex(descriptors, 0), kCTFontNameAttribute);
        if (!name || CFGetTypeID(name) != CFStringGetTypeID() ||
            strcmp([(__bridge NSString *)name UTF8String], "RobotoCondensed-Regular")) abort();
        if (!CTFontManagerRegisterFontsForURL((__bridge void *)url, 1, NULL) ||
            CTFontManagerRegisterFontsForURL((__bridge void *)url, 1, NULL)) abort();
        for (unsigned iteration = 0; iteration < 128; ++iteration) {
            @autoreleasepool {
                void *string = CFStringCreateWithCString(NULL, "RobotoCondensed-Regular", 0x08000100);
                void *base = CTFontCreateWithName(string, 24, NULL);
                CFRelease(string);
                if (!base) abort();
                void *family = CFStringCreateWithCString(NULL, "Roboto Condensed", 0x08000100);
                void *family_font = CTFontCreateWithName(family, 24, NULL);
                if (!family_font) abort();
                CFRelease(family_font); CFRelease(family);
                void *font = CTFontCreateCopyWithSymbolicTraits(base, 24, NULL, 0, 3);
                if (!font || CTFontCreateCopyWithSymbolicTraits(base, 24, NULL, 3, 3)) abort();
                CFRelease(base);
                NSDictionary *attributes = @{(__bridge id)kCTFontAttributeName:(__bridge id)font,
                    (__bridge id)kCTForegroundColorFromContextAttributeName:(__bridge id)kCFBooleanTrue};
                CFRelease(font);
                NSString *text = [[NSString alloc] initWithBytes:"Vinix AV" length:8 encoding:4];
                unsigned char invalid[] = {0xc0, 0x80};
                if ([[NSString alloc] initWithBytes:invalid length:2 encoding:4]) abort();
                NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:text attributes:attributes];
                void *line = CTLineCreateWithAttributedString((__bridge void *)attributed);
                double ascent, descent, leading;
                double width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
                if (width < 40 || width > 200 || ascent <= 10 || descent < 0 || leading < 0) abort();
                unsigned char *pixels = calloc(128 * 64, 4);
                if (!pixels) abort();
                void *space = CGColorSpaceCreateDeviceRGB();
                void *context = CGBitmapContextCreate(pixels, 128, 64, 8, 512, space, 1);
                CGColorSpaceRelease(space);
                if (!context || CGBitmapContextCreate(pixels, 128, 64, 8, 1, space, 1)) abort();
                UIColor *color = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.5];
                CGContextSetFillColorWithColor(context, color.CGColor);
                CGContextSetStrokeColorWithColor(context, color.CGColor);
                CGContextSetTextPosition(context, -2, 30);
                CTLineDraw(line, context);
                unsigned painted = 0;
                for (unsigned index = 0; index < 128 * 64 * 4; index += 4) {
                    if (pixels[index + 1] || pixels[index + 2] || pixels[index] != pixels[index + 3] || pixels[index + 3] > 128) abort();
                    if (pixels[index + 3]) ++painted;
                }
                if (painted < 50 || painted > 2000) abort();
                CGContextRelease(context); CFRelease(line); free(pixels);
            }
        }
        CFRelease(name); CFRelease(descriptors);
    }
    puts("IOS-TEXT: registered font, traits, UTF-8, real metrics and clipped premultiplied glyph pixels");
    return 0;
}
