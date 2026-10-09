// SPDX-License-Identifier: GPL-2.0-or-later
// One fixture for installed Catalyst UIKit/CoreGraphics and native Vinix.
typedef _Bool BOOL;
typedef unsigned long Word;
typedef struct { double width, height; } Size;
typedef struct { double x, y, width, height; } Rect;
typedef struct { double a, b, c, d, tx, ty; } Transform;
extern int puts(const char *), memcmp(const void *, const void *, Word);
extern void abort(void), free(void *);
extern int pthread_create(Word *, const void *, void *(*)(void *), void *), pthread_join(Word, void **);
extern void UIGraphicsBeginImageContext(Size), UIGraphicsBeginImageContextWithOptions(Size, BOOL, double);
extern void UIGraphicsEndImageContext(void), UIGraphicsPushContext(void *), UIGraphicsPopContext(void);
extern void *UIGraphicsGetCurrentContext(void), *UIGraphicsGetImageFromCurrentImageContext(void);
extern void *CGColorSpaceCreateDeviceRGB(void), *CGBitmapContextCreate(void *, Word, Word, Word, Word, void *, unsigned);
extern void CGColorSpaceRelease(void *), CGContextRelease(void *), CGImageRelease(void *);
extern Word CGBitmapContextGetWidth(void *), CGBitmapContextGetHeight(void *), CGBitmapContextGetBytesPerRow(void *);
extern Word CGImageGetWidth(void *), CGImageGetHeight(void *), CGImageGetBytesPerRow(void *);
extern unsigned CGBitmapContextGetBitmapInfo(void *), CGBitmapContextGetAlphaInfo(void *);
extern void *CGBitmapContextGetData(void *), *CGBitmapContextCreateImage(void *), *CGImageGetDataProvider(void *), *CGDataProviderCopyData(void *);
extern void CFRelease(void *);
extern Transform CGContextGetCTM(void *);
extern void CGContextSetRGBFillColor(void *, double, double, double, double);
extern void CGContextFillRect(void *, Rect), CGContextClearRect(void *, Rect), CGContextClipToRect(void *, Rect);
extern void CGContextDrawImage(void *, Rect, void *), CGContextSaveGState(void *), CGContextRestoreGState(void *);
extern void CGContextTranslateCTM(void *, double, double), CGContextScaleCTM(void *, double, double);
extern void CGContextSetAlpha(void *, double), CGContextSetInterpolationQuality(void *, unsigned);
__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)alloc;
- (BOOL)respondsToSelector:(SEL)selector;
@end
@interface NSData : NSObject
+ (instancetype)dataWithBytes:(const void *)bytes length:(Word)length;
@property(readonly) Word length;
@property(readonly) const void *bytes;
@end
@interface UIImage : NSObject
+ (instancetype)imageWithData:(NSData *)data;
+ (instancetype)imageWithCGImage:(void *)image;
- (instancetype)initWithData:(NSData *)data;
@property(readonly) Size size;
@property(readonly) double scale;
@property(readonly) long imageOrientation;
@property(readonly) void *CGImage;
- (void)drawInRect:(Rect)rect;
@end
extern NSData *UIImagePNGRepresentation(UIImage *), *UIImageJPEGRepresentation(UIImage *, double);
#define CHECK(c) do { if (!(c)) { puts("IOS-GRAPHICS FAIL: " #c); abort(); } } while (0)
static void rgba(UIImage *image, unsigned char *pixels, Word width, Word height) {
    void *space = CGColorSpaceCreateDeviceRGB();
    void *context = CGBitmapContextCreate(pixels, width, height, 8, width * 4, space, 1);
    CHECK(context); CGColorSpaceRelease(space);
    CGContextSetInterpolationQuality(context, 1);
    CGContextDrawImage(context, (Rect){0,0,(double)width,(double)height}, image.CGImage);
    CGContextRelease(context);
}
static void *thread_context(void *argument) { @autoreleasepool {
    CHECK(!UIGraphicsGetCurrentContext());
    UIGraphicsBeginImageContext((Size){4,4});
    void *context = UIGraphicsGetCurrentContext(); CHECK(context && context != argument);
    CGContextSetRGBFillColor(context, 0,1,0,1); CGContextFillRect(context,(Rect){0,0,4,4});
    UIImage *image = (__bridge UIImage *)UIGraphicsGetImageFromCurrentImageContext(); CHECK(image);
    UIGraphicsEndImageContext(); CHECK(!UIGraphicsGetCurrentContext());
    unsigned char pixels[64] = {0}; rgba(image,pixels,4,4);
    CHECK(pixels[0] == 0 && pixels[1] == 255 && pixels[2] == 0 && pixels[3] == 255);
    // A live context at thread exit must also be reclaimed by the TLS destructor.
    UIGraphicsBeginImageContext((Size){2,2});
} return (void *)0; }
int main(void) { @autoreleasepool {
    CHECK(!UIGraphicsGetCurrentContext() && !UIGraphicsGetImageFromCurrentImageContext());
    NSData *bad = [NSData dataWithBytes:"not an image" length:12];
    CHECK(![UIImage imageWithData:bad] && ![[UIImage alloc] initWithData:bad]);
    for (unsigned iteration = 0; iteration < 100; iteration++) { @autoreleasepool {
        UIGraphicsBeginImageContextWithOptions((Size){2.2,3.6},0,2);
        void *context = UIGraphicsGetCurrentContext(); CHECK(context);
        CHECK(CGBitmapContextGetWidth(context) == 5 && CGBitmapContextGetHeight(context) == 8);
        CHECK(CGBitmapContextGetBitmapInfo(context) == 0x2002 && CGBitmapContextGetAlphaInfo(context) == 2);
        Transform matrix = CGContextGetCTM(context);
        CHECK(matrix.a == 2 && matrix.b == 0 && matrix.c == 0 && matrix.d == -2 && matrix.tx == 0 && matrix.ty == 8);
        UIImage *empty = (__bridge UIImage *)UIGraphicsGetImageFromCurrentImageContext();
        CHECK(empty.size.width == 2.5 && empty.size.height == 4 && empty.scale == 2 && empty.imageOrientation == 0);
        CGContextSetRGBFillColor(context,1,0,0,0.5); CGContextFillRect(context,(Rect){0,0,1,1});
        const unsigned char *raw = CGBitmapContextGetData(context);
        CHECK(raw[0] == 0 && raw[1] == 0 && raw[2] == 128 && raw[3] == 128);
        UIImage *snapshot = (__bridge UIImage *)UIGraphicsGetImageFromCurrentImageContext();
        CHECK([snapshot respondsToSelector:@selector(CGImage)]);
        void *cg = CGBitmapContextCreateImage(context); CHECK(cg && CGImageGetWidth(cg) == 5 && CGImageGetHeight(cg) == 8);
        NSData *provider_bytes = (__bridge NSData *)CGDataProviderCopyData(CGImageGetDataProvider(cg));
        CHECK(provider_bytes.length == CGImageGetBytesPerRow(cg) * CGImageGetHeight(cg));
        CFRelease((__bridge void *)provider_bytes); CGImageRelease(cg);
        CGContextClearRect(context,(Rect){0,0,2.5,4}); CHECK(raw[2] == 0 && raw[3] == 0);
        UIGraphicsBeginImageContext((Size){2,2}); CHECK(UIGraphicsGetCurrentContext() != context);
        UIGraphicsEndImageContext(); CHECK(UIGraphicsGetCurrentContext() == context);
        UIGraphicsPushContext(context); CHECK(UIGraphicsGetCurrentContext() == context); UIGraphicsPopContext();
        UIGraphicsEndImageContext(); CHECK(!UIGraphicsGetCurrentContext());
        unsigned char pixels[5*8*4] = {0}; rgba(snapshot,pixels,5,8);
        CHECK(pixels[0] == 128 && pixels[1] == 0 && pixels[2] == 0 && pixels[3] == 128);
        CHECK(!pixels[7 * 5 * 4 + 3]);
        NSData *png = UIImagePNGRepresentation(snapshot); CHECK(png.length > 8);
        const unsigned char signature[] = {137,80,78,71,13,10,26,10}; CHECK(!memcmp(png.bytes,signature,8));
        UIImage *decoded = [UIImage imageWithData:png]; CHECK(decoded && decoded.size.width == 5 && decoded.size.height == 8 && decoded.scale == 1);
        unsigned char decoded_pixels[5*8*4] = {0}; rgba(decoded,decoded_pixels,5,8); CHECK(!memcmp(pixels,decoded_pixels,sizeof(pixels)));
        UIGraphicsBeginImageContextWithOptions((Size){16,16},0,1);
        context = UIGraphicsGetCurrentContext();
        CGContextSetRGBFillColor(context,1,0,0,0.5); CGContextFillRect(context,(Rect){0,0,16,16});
        UIImage *half_red = (__bridge UIImage *)UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
        NSData *jpeg = UIImageJPEGRepresentation(half_red,1); CHECK(jpeg.length > 4);
        const unsigned char *j = jpeg.bytes; CHECK(j[0] == 255 && j[1] == 216 && j[jpeg.length-2] == 255 && j[jpeg.length-1] == 217);
        UIImage *lossy = [UIImage imageWithData:jpeg]; CHECK(lossy && lossy.size.width == 16 && lossy.size.height == 16);
        unsigned char lossy_pixels[16*16*4] = {0}; rgba(lossy,lossy_pixels,16,16);
        CHECK(lossy_pixels[0] >= 253 && lossy_pixels[1] >= 125 && lossy_pixels[1] <= 129 && lossy_pixels[2] >= 124 && lossy_pixels[2] <= 129 && lossy_pixels[3] == 255);
        UIGraphicsBeginImageContextWithOptions((Size){4,4},1,1);
        context = UIGraphicsGetCurrentContext(); CHECK(CGBitmapContextGetBitmapInfo(context) == 0x2006);
        CGContextSetRGBFillColor(context,0,0,1,1); CGContextFillRect(context,(Rect){0,0,4,4});
        CGContextSaveGState(context); CGContextTranslateCTM(context,1,1); CGContextScaleCTM(context,2,2);
        CGContextClipToRect(context,(Rect){0,0,1,1}); CGContextSetRGBFillColor(context,1,0,0,1); CGContextSetAlpha(context,0.5);
        CGContextFillRect(context,(Rect){-5,-5,10,10}); CGContextRestoreGState(context);
        UIImage *painted = (__bridge UIImage *)UIGraphicsGetImageFromCurrentImageContext();
        unsigned char paint_pixels[64] = {0}; rgba(painted,paint_pixels,4,4);
        CHECK(paint_pixels[0] == 0 && paint_pixels[2] == 255 && paint_pixels[3] == 255);
        CHECK(paint_pixels[20] == 128 && paint_pixels[22] == 127 && paint_pixels[23] == 255);
        CGContextSetInterpolationQuality(context,1); [snapshot drawInRect:(Rect){0,0,2.5,4}];
        UIImage *drawn = (__bridge UIImage *)UIGraphicsGetImageFromCurrentImageContext();
        unsigned char draw_pixels[64] = {0}; rgba(drawn,draw_pixels,4,4); CHECK(draw_pixels[0] > 0 && draw_pixels[3] == 255);
        if (!iteration) { Word thread; CHECK(!pthread_create(&thread,0,thread_context,context)); CHECK(!pthread_join(thread,0)); CHECK(UIGraphicsGetCurrentContext() == context); }
        UIGraphicsEndImageContext();
    } }
    CHECK(!UIGraphicsGetCurrentContext());
    puts("IOS-GRAPHICS: scaled/nested/TLS contexts, BGRA pixels, state/clip, independent snapshots, image drawing and real PNG/JPEG round trips");
} return 0; }
