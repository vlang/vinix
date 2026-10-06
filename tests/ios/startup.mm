// SPDX-License-Identifier: GPL-2.0-or-later
#include <string>
#include <cstdlib>
#include <cstring>
extern "C" int puts(const char *);
extern "C" int strcmp(const char *, const char *);
extern "C" void *objc_getClass(const char *);

__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)new;
+ (Class)class;
- (void)dealloc;
- (bool)isKindOfClass:(Class)cls;
- (bool)respondsToSelector:(SEL)selector;
@end
@class NSString;
extern NSString *const GCControllerDidConnectNotification __attribute__((weak_import));
extern NSString *const GCControllerDidDisconnectNotification __attribute__((weak_import));
@interface NSNotification : NSObject
- (NSString *)name;
- (id)object;
@end
@interface NSNotificationCenter : NSObject
+ (instancetype)defaultCenter;
- (void)addObserver:(id)observer selector:(SEL)selector name:(NSString *)name object:(id)object;
- (void)removeObserver:(id)observer;
- (void)postNotificationName:(NSString *)name object:(id)object;
@end
@interface NSString : NSObject
- (const char *)UTF8String;
- (unsigned long)length;
- (NSString *)stringByAppendingString:(NSString *)string;
- (bool)isEqualToString:(NSString *)string;
@end
@interface NSOperationQueue : NSObject
@property (copy) NSString *name;
@property long maxConcurrentOperationCount;
@end
@interface CLLocationManager : NSObject
@property (nonatomic, weak) id delegate;
@end
@interface StartupLocationManager : CLLocationManager @end
@implementation StartupLocationManager @end
@interface NSUserDefaults : NSObject
+ (instancetype)standardUserDefaults;
- (NSString *)stringForKey:(NSString *)key;
- (long)integerForKey:(NSString *)key;
- (void)setObject:(id)object forKey:(NSString *)key;
- (void)setInteger:(long)number forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;
- (bool)synchronize;
@end

@interface NSData : NSObject
+ (instancetype)dataWithBytes:(const void *)bytes length:(unsigned long)length;
+ (instancetype)dataWithBytesNoCopy:(void *)bytes length:(unsigned long)length freeWhenDone:(bool)freeBytes;
- (const void *)bytes;
- (unsigned long)length;
@end
@interface NSNumber : NSObject
- (bool)boolValue;
- (long)integerValue;
@end
@interface NSDictionary : NSObject
- (id)objectForKeyedSubscript:(id)key;
@end
@interface NSPropertyListSerialization : NSObject
+ (id)propertyListWithData:(NSData *)data options:(unsigned long)options format:(unsigned long *)format error:(void *)error;
@end

static int events[32], initialized, constructed, destroyed, deallocated;
static volatile int count;
static int delivered;
static void record(int event) { events[count++] = event; }

struct Tracker {
    std::string value;
    Tracker() : value("native Objective-C++ constructor") { ++constructed; }
    ~Tracker() { ++destroyed; }
};

@interface StartupBase : NSObject { @public Tracker base; }
- (int)value;
@end

@interface NotificationTarget : NSObject
- (void)receive:(NSNotification *)note;
@end
@implementation NotificationTarget
- (void)receive:(NSNotification *)note {
    if (strcmp([[note name] UTF8String], "native-notification")) std::abort();
    ++delivered;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end
@implementation StartupBase
+ (void)load { record(1); }
+ (void)initialize { ++initialized; (void)[self value]; }
+ (int)value { return 7; }
- (int)value { return 10; }
- (void)dealloc { ++deallocated; }
@end

@interface StartupChild : StartupBase { @public Tracker child; }
@end
@implementation StartupChild
+ (void)load { record(2); }
@end

@interface StartupChild (Extra)
- (int)value;
@end
@implementation StartupChild (Extra)
+ (void)load { record(3); }
- (int)value { return 42; }
@end

__attribute__((constructor)) static void after_load(void) { record(4); }

int main(int argc, char **argv) {
    (void)argv;
    if (count != 4 || events[0] != 1 || events[1] != 2 || events[2] != 3 || events[3] != 4) return 21;
    if (initialized) return 22; // +load itself must not invoke +initialize.
    @autoreleasepool {
        if (!GCControllerDidConnectNotification || !GCControllerDidDisconnectNotification ||
            strcmp([GCControllerDidConnectNotification UTF8String], "GCControllerDidConnectNotification") ||
            strcmp([GCControllerDidDisconnectNotification UTF8String], "GCControllerDidDisconnectNotification")) return 41;
        NSOperationQueue *queue = [NSOperationQueue new];
        if (queue.name || queue.maxConcurrentOperationCount != -1) return 42;
        queue.name = @"AccelerometerQueue";
        queue.maxConcurrentOperationCount = 1;
        if (![queue.name isEqualToString:@"AccelerometerQueue"] || queue.maxConcurrentOperationCount != 1) return 43;
        queue.maxConcurrentOperationCount = -1;
        queue.name = 0;
        if (queue.name || queue.maxConcurrentOperationCount != -1) return 44;
        CLLocationManager *location = [StartupLocationManager new];
        NSObject *locationDelegate = [NSObject new];
        location.delegate = locationDelegate;
        if (location.delegate != locationDelegate || ![location respondsToSelector:@selector(setDelegate:)]) return 45;
        locationDelegate = 0;
        if (location.delegate) return 46;
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if (argc > 1) {
            if (![[defaults stringForKey:@"vinix-persistence"] isEqualToString:@"&<✅🚀>"] || [defaults integerForKey:@"vinix-number"] != -42) return 37;
            [defaults removeObjectForKey:@"vinix-persistence"];
            [defaults removeObjectForKey:@"vinix-number"];
            if ([defaults stringForKey:@"vinix-persistence"]) return 38;
            puts("IOS-STARTUP: preferences persisted across native Mach-O executions");
            return 0;
        }
        [defaults setObject:@"&<✅🚀>" forKey:@"vinix-persistence"];
        [defaults setInteger:-42 forKey:@"vinix-number"];
        if (![defaults synchronize] || ![[defaults stringForKey:@"vinix-persistence"] isEqualToString:@"&<✅🚀>"]) return 39;
        if (objc_getClass("StartupChild") != (__bridge void *)[StartupChild class]) return 23;
        if (initialized != 2) return 24; // Reentrant inherited +initialize, once per class.
        StartupChild *object = [StartupChild new];
        if (constructed != 2 || [object value] != 42) return 25;
        if (object->base.value != "native Objective-C++ constructor" || object->child.value != object->base.value) return 26;
        if (strcmp([@"✅🚀" UTF8String], "\xe2\x9c\x85\xf0\x9f\x9a\x80")) return 27;
        if ([@"✅🚀" length] != 3 || ![[@"native" stringByAppendingString:@"-arm64"] isEqualToString:@"native-arm64"]) return 40;
        const char xml[] = "<plist><dict><key>feature</key><true/><key>number</key><integer>-42</integer></dict></plist>";
        NSData *data = [NSData dataWithBytes:xml length:sizeof(xml) - 1];
        if ([data length] != sizeof(xml) - 1 || std::memcmp([data bytes], xml, sizeof(xml) - 1)) return 29;
        unsigned long format = 0;
        NSDictionary *dictionary = [NSPropertyListSerialization propertyListWithData:data options:0 format:&format error:0];
        if (!dictionary || format != 100 || ![(NSNumber *)dictionary[@"feature"] boolValue] || [(NSNumber *)dictionary[@"number"] integerValue] != -42) return 30;
        void *owned = std::malloc(4);
        if (!owned) return 31;
        std::memcpy(owned, "data", 4);
        NSData *noCopy = [NSData dataWithBytesNoCopy:owned length:4 freeWhenDone:true];
        if ([noCopy bytes] != owned || [noCopy length] != 4) return 32;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        NotificationTarget *target = [NotificationTarget new];
        NSObject *filter = [NSObject new];
        if (![target isKindOfClass:[NSObject class]] || ![target respondsToSelector:@selector(receive:)]) return 33;
        [center addObserver:target selector:@selector(receive:) name:@"native-notification" object:filter];
        [center postNotificationName:@"other-notification" object:filter];
        [center postNotificationName:@"native-notification" object:target];
        if (delivered) return 34;
        [center postNotificationName:@"native-notification" object:filter];
        [center postNotificationName:@"native-notification" object:filter];
        if (delivered != 1) return 35; // Callback unregisters itself safely.
        [center addObserver:target selector:@selector(receive:) name:@"native-notification" object:filter];
        filter = 0;
        [center postNotificationName:@"native-notification" object:0];
        if (delivered != 1) return 36; // A dead filter must not become a wildcard.
        target = 0;
        [center postNotificationName:@"native-notification" object:0];
        object = 0;
        if (destroyed != 2 || deallocated != 1) return 28;
    }
    puts("IOS-STARTUP: NSData and XML property lists");
    puts("IOS-STARTUP: operation queue configuration and weak location delegate");
    puts("IOS-STARTUP: notifications, filtering, weak observers and reentrant removal");
    puts("IOS-STARTUP: load, categories, initialize, ObjC++ lifetime and UTF-16");
    return 0;
}
