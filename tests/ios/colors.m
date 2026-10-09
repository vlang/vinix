// SPDX-License-Identifier: GPL-2.0-or-later
// Independently declared ABI, shared between installed Catalyst/CoreGraphics
// and an unchanged ARM64 iOS fixture.
typedef unsigned long Word;
typedef struct { double x,y,width,height; } Rect;
typedef _Bool BOOL;
extern int printf(const char *,...), puts(const char *);
extern void *CGColorSpaceCreateDeviceRGB(void), *CGColorSpaceCreateDeviceGray(void);
extern void CGColorSpaceRelease(void *), CGColorRelease(void *), CGContextRelease(void *);
extern Word CGColorSpaceGetNumberOfComponents(void *), CGColorGetNumberOfComponents(void *);
extern int CGColorSpaceGetModel(void *);
extern void *CGColorCreate(void *,const double *), *CGColorCreateCopyWithAlpha(void *,double), *CGColorRetain(void *), *CGColorGetColorSpace(void *);
extern const double *CGColorGetComponents(void *);
extern double CGColorGetAlpha(void *);
extern BOOL CGColorEqualToColor(void *,void *);
extern void *CGBitmapContextCreate(void *,Word,Word,Word,Word,void *,unsigned);
extern void CGContextSetFillColorSpace(void *,void *), CGContextSetFillColor(void *,const double *);
extern void CGContextSetFillColorWithColor(void *,void *), CGContextSetRGBFillColor(void *,double,double,double,double);
extern void CGContextSetBlendMode(void *,unsigned), CGContextFlush(void *), CGContextFillRect(void *,Rect);
extern void CGContextSaveGState(void *), CGContextRestoreGState(void *);
__attribute__((objc_root_class))
@interface NSObject { Class isa; }
@end
@interface UIColor : NSObject
+ (instancetype)colorWithRed:(double)red green:(double)green blue:(double)blue alpha:(double)alpha;
+ (instancetype)whiteColor;
@property(readonly) void *CGColor;
@end
#define CHECK(x) do { if (!(x)) { printf("IOS-COLORS FAIL line %d: %s\n",__LINE__,#x); return 1; } } while(0)
int main(void) { @autoreleasepool {
    CHECK(CGColorEqualToColor(0,0) && CGColorGetAlpha(0) == 0);
    void *rgb = CGColorSpaceCreateDeviceRGB(), *gray = CGColorSpaceCreateDeviceGray();
    CHECK(rgb && gray && CGColorSpaceGetModel(rgb) == 1 && CGColorSpaceGetModel(gray) == 0);
    CHECK(CGColorSpaceGetNumberOfComponents(rgb) == 3 && CGColorSpaceGetNumberOfComponents(gray) == 1);
    double values[] = {0.2,0.4,0.6,0.5}, near[] = {0.20001,0.4,0.6,0.5};
    void *a = CGColorCreate(rgb,values), *b = CGColorCreate(rgb,values), *different = CGColorCreate(rgb,near);
    CHECK(a && b && different && CGColorEqualToColor(a,b) && !CGColorEqualToColor(a,different) && !CGColorEqualToColor(a,0));
    values[0] = 0.9;
    CHECK(CGColorGetComponents(a)[0] == 0.2 && CGColorGetNumberOfComponents(a) == 4 && CGColorGetAlpha(a) == 0.5);
    CHECK(CGColorGetColorSpace(a) == rgb);
    void *alpha = CGColorCreateCopyWithAlpha(a,0.75);
    CHECK(alpha && CGColorGetAlpha(alpha) == 0.75 && CGColorGetComponents(alpha)[0] == 0.2 && !CGColorEqualToColor(a,alpha));
    double clipped[] = {1.2,-0.2,0.5,2};
    void *clip = CGColorCreate(rgb,clipped);
    const double *components = CGColorGetComponents(clip);
    CHECK(components[0] == 1 && components[1] == 0 && components[2] == 0.5 && components[3] == 1);
    double mono[] = {0.5,1};
    void *g = CGColorCreate(gray,mono);
    CHECK(CGColorGetNumberOfComponents(g) == 2 && CGColorGetComponents(g)[0] == 0.5);
    CGColorSpaceRelease(gray); CGColorSpaceRelease(rgb); // Colors retain their spaces.
    CHECK(CGColorSpaceGetModel(CGColorGetColorSpace(g)) == 0);
    void *retained = CGColorRetain(a); CGColorRelease(a); a = retained;
    CHECK(CGColorEqualToColor(a,b));
    UIColor *ui = [UIColor colorWithRed:0.20001 green:0.4 blue:0.6 alpha:0.5];
    UIColor *ui_near = [UIColor colorWithRed:0.20002 green:0.4 blue:0.6 alpha:0.5];
    CHECK(ui.CGColor == ui.CGColor && CGColorGetComponents(ui.CGColor)[0] == 0.20001);
    CHECK(!CGColorEqualToColor(ui.CGColor,ui_near.CGColor));
    CHECK(CGColorGetNumberOfComponents([UIColor whiteColor].CGColor) == 2);
    unsigned char pixels[32] = {0};
    void *context = CGBitmapContextCreate(pixels,4,2,8,16,CGColorGetColorSpace(a),1);
    CHECK(context);
    CGContextSetFillColorSpace(context,CGColorGetColorSpace(a));
    double red[] = {1,0,0,1};
    CGContextSetFillColor(context,red);
    CGContextFillRect(context,(Rect){0,0,1,2});
    CGContextSaveGState(context);
    CGContextSetFillColorSpace(context,CGColorGetColorSpace(g));
    CGContextSetFillColor(context,mono); // Gray becomes RGB raster pixels.
    CGContextFillRect(context,(Rect){1,0,1,2});
    CGContextRestoreGState(context);
    double blue[] = {0,0,1,1};
    CGContextSetFillColor(context,blue);
    CGContextSetBlendMode(context,0);
    CGContextFillRect(context,(Rect){2,0,1,2});
    CGContextSetFillColorWithColor(context,clip);
    CGContextFillRect(context,(Rect){3,0,1,2});
    CGColorRelease(clip);
    CGContextFlush(context);
    CHECK(pixels[0] == 255 && pixels[1] == 0 && pixels[2] == 0 && pixels[3] == 255);
    CHECK(pixels[4] == 128 && pixels[5] == 128 && pixels[6] == 128 && pixels[7] == 255);
    CHECK(pixels[8] == 0 && pixels[9] == 0 && pixels[10] == 255 && pixels[11] == 255);
    CHECK(pixels[12] == 255 && pixels[13] == 0 && pixels[14] == 128 && pixels[15] == 255);
    CGContextRelease(context);
    CGColorRelease(a); CGColorRelease(b); CGColorRelease(different); CGColorRelease(alpha); CGColorRelease(g);
    puts("IOS-COLORS: precise components/equality, owned color spaces, UIKit caches, gray/RGB fill state and real pixels");
    return 0;
} }
