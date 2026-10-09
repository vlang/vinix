// SPDX-License-Identifier: GPL-2.0-or-later
// The same ABI/ownership fixture runs with installed libobjc and in Vinix.
// IMP is type-erased; each invocation casts it to the method's actual ABI.
#pragma clang diagnostic ignored "-Wcast-function-type-mismatch"
typedef _Bool BOOL;
typedef unsigned long Size;
typedef long Offset;
typedef id (*IMP)(id, SEL, ...);
typedef void *Method;
typedef void *Ivar;
typedef struct { double x, y, width, height; } Rect;
extern int puts(const char *), strcmp(const char *, const char *);
extern void abort(void), free(void *);
extern void *malloc(Size);
extern Class objc_lookUpClass(const char *), object_getClass(id), object_setClass(id, Class);
extern const char *class_getName(Class), *sel_getName(SEL), *method_getTypeEncoding(Method), *ivar_getTypeEncoding(Ivar), *ivar_getName(Ivar);
extern Ivar *class_copyIvarList(Class, unsigned *);
extern Class class_getSuperclass(Class), objc_allocateClassPair(Class, const char *, Size);
extern void objc_registerClassPair(Class), objc_disposeClassPair(Class);
extern Size class_getInstanceSize(Class);
extern BOOL class_isMetaClass(Class), class_addMethod(Class, SEL, IMP, const char *);
extern BOOL class_addIvar(Class, const char *, Size, unsigned char, const char *), sel_isEqual(SEL, SEL);
extern IMP class_replaceMethod(Class, SEL, IMP, const char *), class_getMethodImplementation(Class, SEL);
extern Method class_getInstanceMethod(Class, SEL), class_getClassMethod(Class, SEL);
extern SEL sel_registerName(const char *), sel_getUid(const char *), method_getName(Method);
extern IMP method_getImplementation(Method), method_setImplementation(Method, IMP);
extern Ivar class_getInstanceVariable(Class, const char *);
extern Offset ivar_getOffset(Ivar);
extern id object_getIvar(id, Ivar), objc_opt_self(id);
__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)new;
+ (instancetype)alloc;
- (instancetype)init;
- (id)self;
@end
@interface RuntimeBase : NSObject {
    id _compiledIvar;
}
- (long)value;
- (Rect)rect:(Rect)rect a:(long)a b:(long)b c:(long)c d:(long)d e:(long)e f:(long)f g:(long)g h:(long)h i:(long)i;
@end
@implementation RuntimeBase
- (long)value { return 7; }
- (Rect)rect:(Rect)r a:(long)a b:(long)b c:(long)c d:(long)d e:(long)e f:(long)f g:(long)g h:(long)h i:(long)i {
    r.x += a + b + c + d + e + f + g + h + i;
    return r;
}
@end
@interface RuntimeChild : RuntimeBase @end
@implementation RuntimeChild @end
@interface NSObject (RuntimeDynamic)
+ (long)answer;
- (long)value;
@end
#define CHECK(c) do { if (!(c)) { puts("IOS-OBJC-RUNTIME FAIL: " #c); abort(); } } while (0)
static long value42(id object, SEL selector) { (void)object; (void)selector; return 42; }
static long value99(id object, SEL selector) { (void)object; (void)selector; return 99; }
static IMP original_init;
static unsigned init_calls;
static id delegated_init(id object, SEL selector) {
    init_calls++;
    return ((id (*)(id, SEL))original_init)(object, selector);
}
static id custom_self(id object, SEL selector) { (void)object; (void)selector; return (id)0; }
int main(void) { @autoreleasepool {
    Class root = objc_lookUpClass("NSObject"), base = objc_lookUpClass("RuntimeBase"), child = objc_lookUpClass("RuntimeChild");
    CHECK(root && base && child && class_getSuperclass(child) == base && class_getSuperclass(base) == root);
    CHECK(!class_getSuperclass(root) && !class_isMetaClass(root) && class_isMetaClass(object_getClass(root)));
    CHECK(!strcmp(class_getName(base), "RuntimeBase") && !strcmp(class_getName((Class)0), "nil"));
    CHECK(!object_getClass((id)0) && class_getInstanceSize(root) == 8);
    CHECK(!strcmp(sel_getName((SEL)0), "<null selector>") && !sel_registerName((const char *)0));
    CHECK(!class_getInstanceMethod((Class)0, @selector(value)) && !method_getImplementation((Method)0));
    CHECK(!method_getTypeEncoding((Method)0) && !method_getName((Method)0));
    char *name = malloc(6); CHECK(name);
    name[0] = 'v'; name[1] = 'a'; name[2] = 'l'; name[3] = 'u'; name[4] = 'e'; name[5] = 0;
    SEL value = sel_registerName(name); free(name);
    CHECK(value == @selector(value) && value == sel_getUid("value") && sel_isEqual(value, @selector(value)));
    CHECK(!sel_isEqual(value, @selector(init)) && sel_isEqual((SEL)0, (SEL)0));
    Method inherited = class_getInstanceMethod(child, value), parent_method = class_getInstanceMethod(base, value);
    CHECK(inherited == parent_method && method_getName(inherited) == value);
    CHECK(!strcmp(method_getTypeEncoding(inherited), "q16@0:8"));
    RuntimeBase *parent = [RuntimeBase new]; RuntimeChild *sub = [RuntimeChild new];
    CHECK(parent.value == 7 && sub.value == 7);
    CHECK(!class_replaceMethod(child, value, (IMP)value42, "q@:"));
    CHECK(parent.value == 7 && sub.value == 42);
    Method own = class_getInstanceMethod(child, value);
    CHECK(own != inherited && !strcmp(method_getTypeEncoding(own), "q@:"));
    CHECK(class_replaceMethod(child, value, (IMP)value99, "v@:") == (IMP)value42);
    CHECK(own == class_getInstanceMethod(child, value) && !strcmp(method_getTypeEncoding(own), "q@:") && sub.value == 99);
    CHECK(method_setImplementation(own, (IMP)value42) == (IMP)value99 && sub.value == 42);
    CHECK(!class_addMethod(child, value, (IMP)value99, "q@:"));
    CHECK(class_getMethodImplementation(child, value) == (IMP)value42);
    CHECK(((long (*)(id, SEL))method_getImplementation(parent_method))(parent, value) == 7);
    Rect r = [parent rect:(Rect){1.5, -2.25, 3.75, 4.125} a:1 b:2 c:3 d:4 e:5 f:6 g:7 h:8 i:9];
    CHECK(r.x == 46.5 && r.y == -2.25 && r.width == 3.75 && r.height == 4.125);
    Ivar compiled = class_getInstanceVariable(child, "_compiledIvar");
    CHECK(compiled && !strcmp(ivar_getTypeEncoding(compiled), "@") && ivar_getOffset(compiled) == 8);
    unsigned ivar_count = 99;
    Ivar *list = class_copyIvarList((Class)0, &ivar_count); CHECK(!list && !ivar_count);
    list = class_copyIvarList(root, &ivar_count);
    CHECK(list && ivar_count == 1 && !list[1] && !strcmp(ivar_getName(list[0]), "isa") && !strcmp(ivar_getTypeEncoding(list[0]), "#")); free(list);
    list = class_copyIvarList(base, &ivar_count);
    CHECK(list && ivar_count == 1 && !list[1] && list[0] == compiled); free(list);
    list = class_copyIvarList(child, &ivar_count); CHECK(!list && !ivar_count);
    original_init = class_getMethodImplementation(root, @selector(init)); CHECK(original_init);
    for (unsigned iteration = 0; iteration < 200; iteration++) {
        Class dynamic = objc_allocateClassPair(root, "RuntimeAllocated", 16); CHECK(dynamic);
        CHECK(!objc_lookUpClass("RuntimeAllocated"));
        Class duplicate = objc_allocateClassPair(root, "RuntimeAllocated", 0); CHECK(duplicate);
        objc_disposeClassPair(duplicate);
        CHECK(class_addIvar(dynamic, "_payload", sizeof(id), 3, "@"));
        CHECK(!class_addIvar(dynamic, "_payload", sizeof(id), 3, "@"));
        CHECK(class_addMethod(dynamic, @selector(init), (IMP)delegated_init, "@16@0:8"));
        CHECK(class_addMethod(dynamic, value, (IMP)value42, "q16@0:8"));
        CHECK(class_addMethod(object_getClass(dynamic), @selector(answer), (IMP)value99, "q16@0:8"));
        objc_registerClassPair(dynamic);
        CHECK(objc_lookUpClass("RuntimeAllocated") == dynamic && class_getInstanceSize(dynamic) == 16);
        CHECK(!objc_allocateClassPair(root, "RuntimeAllocated", 0));
        CHECK(!class_addIvar(dynamic, "tooLate", 8, 3, "@"));
        list = class_copyIvarList(dynamic, &ivar_count);
        CHECK(list && ivar_count == 1 && !list[1] && !strcmp(ivar_getName(list[0]), "_payload")); free(list);
        CHECK([dynamic answer] == 99 && method_getImplementation(class_getClassMethod(dynamic, @selector(answer))) == (IMP)value99);
        @autoreleasepool {
            NSObject *object = [dynamic new]; CHECK(object && object_getClass(object) == dynamic);
            CHECK(object.value == 42 && objc_opt_self(object) == object);
            Ivar ivar = class_getInstanceVariable(dynamic, "_payload");
            CHECK(ivar && ivar_getOffset(ivar) == 8 && !strcmp(ivar_getTypeEncoding(ivar), "@"));
            // Non-owning test storage: the pointer is cleared before its owner dies.
            void **slot = (void **)((char *)(__bridge void *)object + ivar_getOffset(ivar));
            *slot = (__bridge void *)parent; CHECK(object_getIvar(object, ivar) == parent); *slot = (void *)0;
            CHECK(object_setClass(object, root) == dynamic && object_getClass(object) == root);
            CHECK(object_setClass(object, dynamic) == root && object.value == 42);
            CHECK(class_addMethod(dynamic, @selector(self), (IMP)custom_self, "@16@0:8"));
            CHECK(!objc_opt_self(object));
            object = (id)0;
        }
        objc_disposeClassPair(dynamic); CHECK(!objc_lookUpClass("RuntimeAllocated"));
    }
    CHECK(init_calls == 200);
    puts("IOS-OBJC-RUNTIME: canonical selectors, method encodings, inherited replacement, saved IMPs, HFA/stack ABI and dynamic class/ivar lifetimes");
} return 0; }
