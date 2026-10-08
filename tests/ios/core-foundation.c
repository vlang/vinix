// SPDX-License-Identifier: GPL-2.0-or-later
// The same independently declared ABI fixture runs against Apple's installed
// CoreFoundation and the V implementation in an ARM64 Vinix guest.
typedef long Index;
typedef unsigned long Type;
typedef unsigned char Boolean;
typedef const void *Object;
typedef struct { Index location, length; } Range;
typedef struct {
    Index version;
    Object (*retain)(Object, Object);
    void (*release)(Object, Object);
    Object (*description)(Object);
    Boolean (*equal)(Object, Object);
} Callbacks;
typedef struct { Callbacks base; Type (*hash)(Object); } KeyCallbacks;
extern const Callbacks kCFTypeArrayCallBacks, kCFTypeDictionaryValueCallBacks;
extern const KeyCallbacks kCFTypeDictionaryKeyCallBacks;
extern const Object kCFBooleanTrue, kCFBooleanFalse, kCFAllocatorSystemDefault;
extern const double kCFAbsoluteTimeIntervalSince1970;
extern const char __kCFBooleanTrue[], __kCFBooleanFalse[];
extern Object CFRetain(Object);
extern void CFRelease(Object);
extern Type CFGetTypeID(Object), CFStringGetTypeID(void), CFArrayGetTypeID(void);
extern Type CFDictionaryGetTypeID(void), CFDataGetTypeID(void), CFNumberGetTypeID(void), CFBooleanGetTypeID(void);
extern Boolean CFEqual(Object, Object), CFBooleanGetValue(Object);
extern Type CFHash(Object);
extern Object CFAllocatorGetDefault(void);
extern double CFAbsoluteTimeGetCurrent(void);
extern Object CFStringCreateWithCString(Object, const char *, unsigned);
extern Object CFStringCreateWithBytes(Object, const unsigned char *, Index, unsigned, Boolean);
extern Index CFStringGetLength(Object);
extern Index CFStringGetBytes(Object, Range, unsigned, unsigned char, Boolean, unsigned char *, Index, Index *);
extern Boolean CFStringGetCString(Object, char *, Index, unsigned);
extern Object CFArrayCreate(Object, const Object *, Index, const Callbacks *);
extern Index CFArrayGetCount(Object);
extern Object CFArrayGetValueAtIndex(Object, Index);
extern Object CFDictionaryCreate(Object, const Object *, const Object *, Index, const KeyCallbacks *, const Callbacks *);
extern Object CFDictionaryCreateMutable(Object, Index, const KeyCallbacks *, const Callbacks *);
extern void CFDictionarySetValue(Object, Object, Object);
extern Object CFDictionaryGetValue(Object, Object);
extern Index CFDictionaryGetCount(Object);
extern Object CFDataCreate(Object, const unsigned char *, Index), CFDataCreateMutable(Object, Index);
extern Index CFDataGetLength(Object);
extern const unsigned char *CFDataGetBytePtr(Object);
extern unsigned char *CFDataGetMutableBytePtr(Object);
extern void CFDataSetLength(Object, Index);
extern Object CFNumberCreate(Object, Index, const void *);
extern int puts(const char *), memcmp(const void *, const void *, unsigned long);
#define UTF8 0x08000100u
#define ASCII 0x0600u
#define CHECK(condition) do { if (!(condition)) { puts("IOS-CF FAIL: " #condition); return 1; } } while (0)

static Object custom_retain(Object allocator, Object value) { (void)allocator; return value; }
int main(int argc, char **argv) {
    if (argc > 1 && argv[1][0] == 'c') {
        Callbacks custom = {0, custom_retain, 0, 0, 0};
        Object value = (Object)123;
        CFRelease(CFArrayCreate(0, &value, 1, &custom));
        return 2;
    }
    const unsigned char bytes[] = {'A',0xc3,0xa9,0xf0,0x9f,0x98,0x80,0,'Z'};
    Object string = CFStringCreateWithBytes(kCFAllocatorSystemDefault, bytes, 9, UTF8, 0);
    CHECK(string && CFGetTypeID(string) == CFStringGetTypeID() && CFStringGetLength(string) == 6);
    unsigned char out[32] = {0};
    Index used = -1;
    CHECK(CFStringGetBytes(string, (Range){0,6}, UTF8, 0, 0, out, 32, &used) == 6);
    CHECK(used == 9 && !memcmp(out, bytes, 9));
    CHECK(CFStringGetBytes(string, (Range){0,6}, UTF8, 0, 0, out, 5, &used) == 2 && used == 3);
    CHECK(CFStringGetBytes(string, (Range){0,6}, UTF8, 0, 0, 0, 1, &used) == 6 && used == 9);
    out[0] = 0xab;
    CHECK(CFStringGetBytes(string, (Range){0,6}, UTF8, 0, 0, out, 0, &used) == 6 && used == 9 && out[0] == 0xab);
    CHECK(CFStringGetBytes(string, (Range){0,6}, ASCII, 0, 0, out, 32, &used) == 1 && used == 1);
    CHECK(CFStringGetBytes(string, (Range){0,6}, ASCII, '?', 0, out, 32, &used) == 6);
    CHECK(used == 6 && !memcmp(out, "A???\0Z", 6));
    CHECK(CFStringGetBytes(string, (Range){2,1}, UTF8, '?', 0, out, 32, &used) == 0 && used == 0);
    CHECK(CFStringGetBytes(string, (Range){3,1}, UTF8, '?', 0, out, 32, &used) == 0 && used == 0);
    CHECK(CFStringGetBytes(string, (Range){2,2}, UTF8, 0, 0, out, 32, &used) == 2 && used == 4);
    CHECK(!memcmp(out, bytes + 3, 4));
    CHECK(CFStringGetBytes(string, (Range){3,1}, ASCII, '?', 0, out, 32, &used) == 1 && used == 1 && out[0] == '?');
    CHECK(CFStringGetCString(string, (char *)out, 10, UTF8) && !memcmp(out, bytes, 9) && out[9] == 0);
    CHECK(!CFStringGetCString(string, (char *)out, 9, UTF8));
    CHECK(!CFStringCreateWithBytes(0, (const unsigned char *)"\xc0\xaf", 2, UTF8, 0));
    const unsigned char extended[] = {0x80,0xe9,0xff};
    Object ascii = CFStringCreateWithBytes(0, extended, 3, ASCII, 0);
    CHECK(ascii && CFStringGetLength(ascii) == 3);
    CHECK(CFStringGetBytes(ascii, (Range){0,3}, UTF8, 0, 0, out, 32, &used) == 3 && used == 6);
    CHECK(!memcmp(out, "\xc2\x80\xc3\xa9\xc3\xbf", 6));
    CHECK(CFStringGetBytes(ascii, (Range){0,3}, ASCII, 0, 0, out, 32, &used) == 0 && used == 0);
    CFRelease(ascii);
    for (int external = 0; external < 2; external++) {
        Object bom = CFStringCreateWithBytes(0, (const unsigned char *)"\xef\xbb\xbf" "A", 4, UTF8, (Boolean)external);
        CHECK(CFStringGetLength(bom) == 1);
        CHECK(CFStringGetBytes(bom, (Range){0,1}, UTF8, 0, 1, out, 32, &used) == 1 && used == 1 && out[0] == 'A');
        CFRelease(bom);
    }
    Object empty = CFStringCreateWithBytes(0, 0, 0, UTF8, 0);
    CHECK(empty && CFStringGetLength(empty) == 0 && CFStringGetCString(empty, (char *)out, 1, UTF8) && out[0] == 0);
    CFRelease(empty);

    const Object values[] = {string, kCFBooleanTrue};
    Callbacks copied = kCFTypeArrayCallBacks;
    Object array = CFArrayCreate(CFAllocatorGetDefault(), values, 2, &copied);
    CHECK(CFGetTypeID(array) == CFArrayGetTypeID() && CFArrayGetCount(array) == 2);
    Object array_copy = CFArrayCreate(0, values, 2, &kCFTypeArrayCallBacks);
    CHECK(CFEqual(array, array_copy) && CFHash(array) == CFHash(array_copy));
    CFRelease(array_copy);
    CHECK(copied.retain(0, string) == string && copied.equal(string, string));
    copied.release(0, string);
    Object description = copied.description(string);
    CHECK(description && CFGetTypeID(description) == CFStringGetTypeID() && CFStringGetLength(description) >= CFStringGetLength(string));
    CFRelease(description);
    CFRelease(string);
    string = CFArrayGetValueAtIndex(array, 0); // Array owns the only live reference.
    CHECK(CFStringGetLength(string) == 6 && CFBooleanGetValue(CFArrayGetValueAtIndex(array, 1)));
    const Object raw[] = {(Object)1, (Object)2, (Object)0};
    Object pointers = CFArrayCreate(0, raw, 3, 0);
    CHECK(CFArrayGetValueAtIndex(pointers, 0) == (Object)1 && CFArrayGetValueAtIndex(pointers, 2) == 0);
    CFRelease(pointers); // Must never send Objective-C release to raw pointers.

    Object key1 = CFStringCreateWithCString(0, "a separately owned dictionary key", UTF8);
    Object key2 = CFStringCreateWithCString(0, "a separately owned dictionary key", UTF8);
    Object dictionary = CFDictionaryCreateMutable(0, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(dictionary, key1, string);
    CFDictionarySetValue(dictionary, key2, kCFBooleanFalse);
    CHECK(CFDictionaryGetCount(dictionary) == 1 && CFDictionaryGetValue(dictionary, key1) == kCFBooleanFalse);
    CFDictionarySetValue(dictionary, key1, string);
    CFDictionarySetValue(dictionary, key1, string); // Retain before releasing the old value.
    CFRelease(key1);
    CHECK(CFGetTypeID(dictionary) == CFDictionaryGetTypeID() && CFStringGetLength(CFDictionaryGetValue(dictionary, key2)) == 6);
    const Object keys[] = {key2};
    Object immutable = CFDictionaryCreate(0, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CHECK(CFEqual(immutable, dictionary) && CFHash(immutable) == CFHash(dictionary));
    CFRelease(key2);
    CHECK(CFDictionaryGetCount(immutable) == 1);
    Object raw_dictionary = CFDictionaryCreateMutable(0, 0, 0, 0);
    CFDictionarySetValue(raw_dictionary, (Object)1, (Object)2);
    CFDictionarySetValue(raw_dictionary, (Object)1, (Object)3);
    CHECK(CFDictionaryGetValue(raw_dictionary, (Object)1) == (Object)3 && CFDictionaryGetCount(raw_dictionary) == 1);
    CFRelease(raw_dictionary);
    CFRelease(dictionary);
    CFRelease(immutable);
    CFRelease(array);

    unsigned char source[] = {1,2,0,4};
    Object data = CFDataCreate(0, source, 4);
    source[0] = 99;
    CHECK(CFGetTypeID(data) == CFDataGetTypeID() && CFDataGetLength(data) == 4 && CFDataGetBytePtr(data)[0] == 1);
    Object data_copy = CFDataCreate(0, (const unsigned char *)"\1\2\0\4", 4);
    CHECK(CFEqual(data, data_copy) && CFHash(data) == CFHash(data_copy));
    CFRelease(data_copy);
    CFRelease(data);
    Object mutable_data = CFDataCreateMutable(0, 0);
    CHECK(CFDataGetLength(mutable_data) == 0);
    CFDataSetLength(mutable_data, 4096);
    unsigned char *contents = CFDataGetMutableBytePtr(mutable_data);
    for (int i = 0; i < 4096; i++) CHECK(contents[i] == 0);
    contents[0] = 42; contents[20] = 7;
    CFDataSetLength(mutable_data, 1);
    CFDataSetLength(mutable_data, 32);
    CHECK(CFDataGetBytePtr(mutable_data)[0] == 42 && CFDataGetBytePtr(mutable_data)[20] == 0);
    CFRelease(mutable_data);
    for (Index type = 1; type <= 16; type++) {
        union { signed char c; short s; int i; long l; float f; double d; } value = {0};
        if (type == 1 || type == 7) value.c = -42;
        else if (type == 2 || type == 8) value.s = -42;
        else if (type == 3 || type == 9) value.i = -42;
        else if (type == 5 || type == 12) value.f = -42;
        else if (type == 6 || type == 13 || type == 16) value.d = -42;
        else value.l = -42;
        long integer = -42;
        Object number = CFNumberCreate(0, type, &value), other = CFNumberCreate(0, 4, &integer);
        CHECK(CFGetTypeID(number) == CFNumberGetTypeID() && CFEqual(number, other) && CFHash(number) == CFHash(other));
        CFRelease(number); CFRelease(other);
    }
    CHECK(CFGetTypeID(kCFBooleanTrue) == CFBooleanGetTypeID() && CFBooleanGetTypeID() != CFNumberGetTypeID());
    CHECK(CFBooleanGetValue(kCFBooleanTrue) && !CFBooleanGetValue(kCFBooleanFalse));
    CHECK((Object)__kCFBooleanTrue == kCFBooleanTrue && (Object)__kCFBooleanFalse == kCFBooleanFalse);
    CHECK(kCFAbsoluteTimeIntervalSince1970 == 978307200.0 && CFAbsoluteTimeGetCurrent() > 700000000.0);
    puts("IOS-CF: Unicode ranges, binary strings, collections, raw pointers, data growth, numbers and ownership");
    return 0;
}
