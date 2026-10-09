// SPDX-License-Identifier: GPL-2.0-or-later
extern int puts(const char *), module_leaf(void), __cxa_atexit(void (*)(void *), void *, void *);
extern void abort(void);
__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)alloc;
- (instancetype)init;
@end
@interface ModuleCounter : NSObject { long _value; }
- (long)value;
@end
static volatile int loaded, initialized;
static _Thread_local volatile int tls = 7;
@implementation ModuleCounter
+ (void)load { loaded++; }
- (instancetype)init { self = [super init]; if (self) _value = 64; return self; }
- (long)value { return _value; }
@end
static void cleanup(void *value) {
    if (value != &initialized || module_leaf() != 152) abort();
    puts("IOS-MODULES: middle destructor");
}
__attribute__((constructor)) static void initialize(void) {
    if (loaded != 1 || module_leaf() != 152) abort();
    initialized = 222;
    tls = 31;
    if (__cxa_atexit(cleanup, (void *)&initialized, (void *)&initialized)) abort();
}
int module_middle(void) { return initialized + tls; }
void module_middle_set(int value) { tls = value; }
