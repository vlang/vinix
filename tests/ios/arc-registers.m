// SPDX-License-Identifier: GPL-2.0-or-later
// Manual ownership isolates the register-entry ABI from the compiler's ARC calls.
typedef unsigned long Word;
extern int puts(const char *), printf(const char *, ...), snprintf(char *, Word, const char *, ...);
extern void abort(void);
extern id objc_initWeak(id *, id);
extern void objc_destroyWeak(id *);
#ifdef IOS_ARC_REFERENCE
extern void *dlsym(void *, const char *);
#else
#define DECLARE(n) extern void objc_retain_x##n(void), objc_release_x##n(void);
DECLARE(0) DECLARE(1) DECLARE(2) DECLARE(3) DECLARE(4) DECLARE(5)
DECLARE(6) DECLARE(7) DECLARE(8) DECLARE(9) DECLARE(10) DECLARE(11)
DECLARE(12) DECLARE(13) DECLARE(14) DECLARE(15) DECLARE(19) DECLARE(20)
DECLARE(21) DECLARE(22) DECLARE(23) DECLARE(24) DECLARE(25) DECLARE(26)
DECLARE(27) DECLARE(28)
#endif
extern void arc_register_probe(void *, void *, Word, Word *);
__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)new;
- (void)dealloc;
@end
static unsigned destroyed;
@interface RegisterOwnedObject : NSObject @end
@implementation RegisterOwnedObject
- (void)dealloc { destroyed++; [super dealloc]; }
@end
#define CHECK(c) do { if (!(c)) { puts("IOS-ARC-REGISTERS FAIL: " #c); abort(); } } while (0)
static void *entry(unsigned reg, int release) {
#ifdef IOS_ARC_REFERENCE
    char name[40];
    snprintf(name, sizeof(name), "objc_%s_x%u", release ? "release" : "retain", reg);
    return dlsym((void *)-2, name); // Darwin RTLD_DEFAULT; no dylib extraction.
#else
    switch (reg) {
#define ENTRY(n) case n: return release ? (void *)objc_release_x##n : (void *)objc_retain_x##n;
    ENTRY(0) ENTRY(1) ENTRY(2) ENTRY(3) ENTRY(4) ENTRY(5) ENTRY(6) ENTRY(7)
    ENTRY(8) ENTRY(9) ENTRY(10) ENTRY(11) ENTRY(12) ENTRY(13) ENTRY(14) ENTRY(15)
    ENTRY(19) ENTRY(20) ENTRY(21) ENTRY(22) ENTRY(23) ENTRY(24) ENTRY(25) ENTRY(26)
    ENTRY(27) ENTRY(28)
    default: return (void *)0;
    }
#endif
}
static void invoke(id object, void *function, unsigned reg, int release) {
    Word result[48] = {0}; CHECK(function);
    arc_register_probe((void *)object, function, reg, result);
    // These use the ordinary caller/callee clobber rules. Retain takes its
    // argument from xN and returns the object in x0; release has no result.
    if (!release) CHECK(result[0] == (Word)object);
    for (unsigned i = 19; i <= 28; i++) {
        Word expected = i == reg ? (Word)object : 0x100 + i;
        if (result[i] != expected) { printf("IOS-ARC-REGISTERS FAIL: x%u entry changed x%u: %lx expected %lx\n", reg, i, result[i], expected); abort(); }
    }
    for (unsigned i = 0; i < 8; i++) {
        Word expected = (Word)(0x18 + i) * 0x0101010101010101UL;
        CHECK(result[32 + i] == expected); // ABI-preserved low 64 bits of v8-v15.
    }
}
int main(void) { @autoreleasepool {
    const unsigned registers[] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,19,20,21,22,23,24,25,26,27,28};
    for (unsigned i = 0; i < sizeof(registers) / sizeof(registers[0]); i++) {
        unsigned reg = registers[i]; void *retain = entry(reg, 0), *release = entry(reg, 1);
        invoke((id)0, retain, reg, 0); invoke((id)0, release, reg, 1);
        invoke(@"immortal constant", retain, reg, 0); invoke(@"immortal constant", release, reg, 1);
        for (unsigned iteration = 0; iteration < 20; iteration++) {
            id object = [RegisterOwnedObject new], weak = (id)0;
            objc_initWeak(&weak, object);
            unsigned previous = destroyed;
            invoke(object, retain, reg, 0); invoke(object, release, reg, 1);
            CHECK(weak == object && destroyed == previous);
            invoke(object, release, reg, 1); CHECK(!weak && destroyed == previous + 1);
            objc_destroyWeak(&weak);
        }
    }
    CHECK(destroyed == 520);
    puts("IOS-ARC-REGISTERS: 52 retain/release entry points, nil/constants, x0 results, callee register preservation and real weak/dealloc ownership");
} return 0; }
