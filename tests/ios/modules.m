// SPDX-License-Identifier: GPL-2.0-or-later
typedef unsigned long Word;
extern int puts(const char *), strcmp(const char *, const char *);
extern char *strstr(const char *, const char *);
extern void abort(void);
extern int pthread_create(Word *, const void *, void *(*)(void *), void *), pthread_join(Word, void **);
extern int module_leaf(void), module_middle(void);
extern void module_leaf_set(int), module_middle_set(int);
extern int module_value, *module_value_pointer;
extern int module_optional(void) __attribute__((weak_import));
extern void *dlopen(const char *, int), *dlsym(void *, const char *);
extern int dlclose(void *);
extern char *dlerror(void);
typedef struct { const char *filename; void *base; const char *symbol; void *address; } DlInfo;
extern int dladdr(const void *, DlInfo *);
extern unsigned char *getsectiondata(const void *, const char *, const char *, Word *);
__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)alloc;
- (instancetype)init;
@end
@interface ModuleCounter : NSObject
- (long)value;
@end
@interface ModuleSubclass : ModuleCounter
@end
@implementation ModuleSubclass
- (long)value { return [super value] + 1; }
@end
#define CHECK(c) do { if (!(c)) { puts("IOS-MODULES FAIL: " #c); abort(); } } while (0)
static _Thread_local volatile int tls = 3;
__attribute__((constructor)) static void initialize(void) {
    CHECK(module_leaf() == 152 && module_middle() == 253);
    tls = 9;
}
static void *worker(void *argument) { @autoreleasepool {
    CHECK(tls == 3 && module_leaf() == 140 && module_middle() == 229);
    module_leaf_set(55); module_middle_set(66); tls = 11;
    CHECK(module_leaf() == 178 && module_middle() == 288 && tls == 11);
    CHECK([[[ModuleSubclass alloc] init] value] == 65);
} return argument; }
int main(void) { @autoreleasepool {
    CHECK(tls == 9 && module_leaf() == 152 && module_middle() == 253);
    CHECK(module_value == 42 && module_value_pointer == &module_value && !module_optional);
    CHECK([[[ModuleSubclass alloc] init] value] == 65);
    void *handle = dlopen("@rpath/Middle.framework/Middle", 2); CHECK(handle);
    int (*middle)(void) = dlsym(handle,"module_middle"); CHECK(middle == module_middle && middle() == 253);
    CHECK(dlsym((void *)-2, "module_leaf") == module_leaf);
    CHECK(!dlsym(handle,"module_absent") && dlerror() && !dlerror());
    DlInfo info; CHECK(dladdr((const void *)middle,&info) && info.base && strstr(info.filename,"Middle.framework/Middle"));
    Word length = 0; CHECK(getsectiondata(info.base,"__TEXT","__text",&length) && length);
    CHECK(!dlclose(handle) && middle() == 253);
    for (Word i = 1; i <= 8; i++) {
        Word thread; void *result = 0;
        CHECK(!pthread_create(&thread,0,worker,(void *)i) && !pthread_join(thread,&result) && result == (void *)i);
        CHECK(tls == 9 && module_leaf() == 152 && module_middle() == 253);
    }
    puts("IOS-MODULES: bundled dylibs, runpaths, rebased exports, dependency constructors, Objective-C inheritance, independent TLS and dynamic lookup");
} return 0; }
