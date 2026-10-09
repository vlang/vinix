// SPDX-License-Identifier: GPL-2.0-or-later
// One independently declared ABI fixture runs against Mac CoreGraphics and
// unchanged ARM64 iOS machine code in the V runner.
typedef unsigned long Word;
typedef _Bool Bool;
typedef struct { double x,y,width,height; } Rect;
typedef void (*Release)(void *,const void *,Word);
extern int puts(const char *), printf(const char *,...);
extern void *malloc(Word), free(void *), *memcpy(void *,const void *,Word);
extern int memcmp(const void *,const void *,Word);
extern void *CGDataProviderCreateWithData(void *,const void *,Word,Release);
extern void *CGDataProviderCreateWithCFData(void *), *CGDataProviderRetain(void *), *CGDataProviderCopyData(void *);
extern void CGDataProviderRelease(void *);
extern void *CGColorSpaceCreateDeviceRGB(void);
extern void CGColorSpaceRelease(void *), CGContextRelease(void *), CGImageRelease(void *);
extern void *CGImageCreate(Word,Word,Word,Word,Word,void *,unsigned,void *,const double *,Bool,unsigned);
extern void *CGImageGetDataProvider(void *), *CGImageGetColorSpace(void *);
extern Word CGImageGetWidth(void *), CGImageGetHeight(void *), CGImageGetBitsPerPixel(void *), CGImageGetBitsPerComponent(void *), CGImageGetBytesPerRow(void *);
extern unsigned CGImageGetBitmapInfo(void *), CGImageGetAlphaInfo(void *), CGImageGetRenderingIntent(void *);
extern const double *CGImageGetDecode(void *);
extern Bool CGImageGetShouldInterpolate(void *);
extern void *CGBitmapContextCreate(void *,Word,Word,Word,Word,void *,unsigned);
extern void CGContextDrawImage(void *,Rect,void *), CGContextFlush(void *);
extern void *CFDataCreate(void *,const unsigned char *,long);
extern const unsigned char *CFDataGetBytePtr(void *);
extern long CFDataGetLength(void *);
extern void CFRelease(void *);
extern Word CFGetTypeID(void *), CGDataProviderGetTypeID(void), CGImageGetTypeID(void);
#define CHECK(x) do { if (!(x)) { printf("IOS-PROVIDER-IMAGES FAIL line %d: %s\n",__LINE__,#x); return 1; } } while(0)
struct Owner { const void *bytes; Word size; int calls,error; };
static void released(void *info,const void *bytes,Word size) {
    struct Owner *owner = info;
    owner->calls++;
    if (bytes != owner->bytes || size != owner->size || owner->calls != 1) owner->error = 1;
    // App release callbacks may reenter the runtime and use another provider.
    const unsigned char value[] = {9,8,7};
    void *p = CGDataProviderCreateWithData(0,value,sizeof value,0);
    void *d = CGDataProviderCopyData(p);
    if (!d || CFDataGetLength(d) != 3 || memcmp(CFDataGetBytePtr(d),value,3)) owner->error = 1;
    if (d) CFRelease(d);
    CGDataProviderRelease(p);
    free((void *)bytes);
}
static int test_format(unsigned info) {
    unsigned alpha = info & 31, bits = alpha ? 32 : 24, bytes = bits / 8;
    Bool first = alpha == 2 || alpha == 4 || alpha == 6;
    Bool little = (info & 0x7000) == 0x2000;
    Bool opaque = alpha == 0 || alpha == 5 || alpha == 6;
    Bool premult = alpha == 1 || alpha == 2;
    unsigned char rgba[16] = {255,0,0,128, 0,255,0,255, 0,0,255,255, 255,255,255,128};
    unsigned char *raw = malloc(32);
    CHECK(raw);
    for (unsigned i=0;i<32;i++) raw[i] = 0xa5; // Padding is data too.
    unsigned char expected[16];
    for (unsigned i=0;i<4;i++) {
        unsigned char *pixel = raw + (i/2)*16 + (i%2)*bytes;
        unsigned a = opaque ? 255 : rgba[i*4+3];
        expected[i*4+3] = a;
        for (unsigned c=0;c<3;c++) {
            unsigned v = rgba[i*4+c];
            expected[i*4+c] = (v*a+127)/255;
            unsigned pos = c + first;
            pixel[little ? 3-pos : pos] = premult ? (v*a+127)/255 : v;
        }
        if (alpha) {
            unsigned pos = first ? 0 : 3;
            pixel[little ? 3-pos : pos] = opaque ? 0xa5 : a;
        }
    }
    // The final row need not include trailing padding (measured on Mac).
    struct Owner owner = {raw,16+2*bytes,0,0};
    unsigned char first_byte = raw[0];
    void *space = CGColorSpaceCreateDeviceRGB();
    void *provider = CGDataProviderCreateWithData(&owner,raw,owner.size,released);
    CHECK(space && provider && CFGetTypeID(provider) == CGDataProviderGetTypeID());
    void *image = CGImageCreate(2,2,8,bits,16,space,info,provider,0,1,3);
    CHECK(image && CFGetTypeID(image) == CGImageGetTypeID());
    CHECK(CGImageGetWidth(image) == 2 && CGImageGetHeight(image) == 2);
    CHECK(CGImageGetBitsPerComponent(image) == 8 && CGImageGetBitsPerPixel(image) == bits);
    CHECK(CGImageGetBytesPerRow(image) == 16 && CGImageGetAlphaInfo(image) == alpha && CGImageGetBitmapInfo(image) == info);
    CHECK(CGImageGetDataProvider(image) == provider && CGImageGetColorSpace(image) == space);
    CHECK(CGImageGetDecode(image) == 0 && CGImageGetShouldInterpolate(image) && CGImageGetRenderingIntent(image) == 3);
    CHECK(CGDataProviderRetain(provider) == provider);
    CGDataProviderRelease(provider); CGDataProviderRelease(provider);
    CHECK(owner.calls == 0); // Image owns the provider and space.
    unsigned char result[16] = {0};
    void *context = CGBitmapContextCreate(result,2,2,8,8,space,1);
    CHECK(context);
    CGColorSpaceRelease(space);
    void *copy = CGDataProviderCopyData(CGImageGetDataProvider(image));
    CHECK(copy && CFDataGetLength(copy) == (long)owner.size && !memcmp(CFDataGetBytePtr(copy),raw,owner.size));
    CGContextDrawImage(context,(Rect){0,0,2,2},image);
    CGContextFlush(context);
    CHECK(!memcmp(result,expected,16));
    CGContextRelease(context); CGImageRelease(image);
    CHECK(owner.calls == 0); // CopyData also keeps the provider alive.
    CHECK(CFDataGetLength(copy) == (long)owner.size && CFDataGetBytePtr(copy)[0] == first_byte);
    CFRelease(copy);
    CHECK(owner.calls == 1 && !owner.error);
    return 0;
}
int main(void) {
    struct Owner invalid = {0,0,0,0};
    unsigned char raw[] = {255,0,0, 0,255,0};
    CHECK(!CGDataProviderCreateWithData(&invalid,0,6,released));
    CHECK(!CGDataProviderCreateWithData(&invalid,raw,0,released) && invalid.calls == 0);
    CHECK(!CGDataProviderCreateWithCFData(0));
    void *empty = CFDataCreate(0,0,0);
    CHECK(empty && !CGDataProviderCreateWithCFData(empty)); CFRelease(empty);
    const unsigned formats[] = {0,1,2,3,4,5,6,0x2001,0x2002,0x2003,0x2004,0x2005,0x2006,0x4001,0x4002,0x4003,0x4004,0x4005,0x4006};
    for (unsigned i=0;i<sizeof formats/sizeof *formats;i++) CHECK(!test_format(formats[i]));
    for (unsigned repeat=0;repeat<200;repeat++) {
        void *data = CFDataCreate(0,raw,sizeof raw);
        void *provider = CGDataProviderCreateWithCFData(data);
        void *space = CGColorSpaceCreateDeviceRGB();
        CHECK(provider && space);
        CFRelease(data); // The provider retains its CFData backing.
        double decode[] = {1,0,1,0,1,0};
        void *image = CGImageCreate(2,1,8,24,6,space,0,provider,decode,0,0);
        CHECK(image && !CGImageGetShouldInterpolate(image) && CGImageGetRenderingIntent(image) == 0);
        decode[0] = 0.25;
        CHECK(CGImageGetDecode(image)[0] == 1 && CGImageGetDecode(image) != decode);
        CGDataProviderRelease(provider);
        unsigned char result[8] = {0}, expected[] = {0,255,255,255,255,0,255,255};
        void *context = CGBitmapContextCreate(result,2,1,8,8,space,1);
        CHECK(context); CGColorSpaceRelease(space);
        CGContextDrawImage(context,(Rect){0,0,2,1},image); CGContextFlush(context);
        CHECK(!memcmp(result,expected,sizeof result));
        CGContextRelease(context); CGImageRelease(image);
    }
    unsigned char overlap[] = {255,0,0,255,0,255,0,255,0,0,255,255};
    unsigned char shifted[] = {255,0,0,255,255,0,0,255,0,255,0,255};
    void *rgb = CGColorSpaceCreateDeviceRGB();
    void *p = CGDataProviderCreateWithData(0,overlap,sizeof overlap,0);
    void *image = CGImageCreate(2,1,8,32,12,rgb,1,p,0,0,0);
    void *context = CGBitmapContextCreate(overlap,3,1,8,12,rgb,1);
    CHECK(image && context);
    CGContextDrawImage(context,(Rect){1,0,2,1},image); CGContextFlush(context);
    CHECK(!memcmp(overlap,shifted,sizeof overlap));
    CGContextRelease(context); CGImageRelease(image); CGDataProviderRelease(p);
    p = CGDataProviderCreateWithData(0,raw,sizeof raw,0);
    CHECK(!CGImageCreate(2,2,8,24,6,rgb,0,p,0,0,0)); // Insufficient backing.
    CHECK(!CGImageCreate(0,1,8,24,6,rgb,0,p,0,0,0));
    CHECK(!CGImageCreate(2,1,8,24,5,rgb,0,p,0,0,0)); // Short row.
    CGDataProviderRelease(p); CGColorSpaceRelease(rgb);
    puts("IOS-PROVIDER-IMAGES: borrowed bytes, native release callbacks, retained CFData, RGB formats/decode, packed stack ABI and real pixels");
    return 0;
}
