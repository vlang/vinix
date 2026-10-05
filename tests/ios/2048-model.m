/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <Foundation/Foundation.h>
@interface F3HModelTests : NSObject
- (void)testModelMerge1;
- (void)testModelMerge2;
- (void)testModelMerge3;
- (void)testModelMerge4;
- (void)testModelMerge5;
- (void)testModelMerge6;
- (void)testModelMerge7;
- (void)testModelMerge8;
@end
int puts(const char *text);
int strcmp(const char *left, const char *right);
int main(void) {
    @autoreleasepool {
        __weak NSObject *weak = nil;
        @autoreleasepool {
            NSObject *object = [NSObject new];
            weak = object;
            NSAssert(weak == object, @"weak load must retain its referent");
        }
        NSAssert(weak == nil, @"release must zero weak slots");
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        NSIndexPath *key = [NSIndexPath indexPathForRow:2 inSection:3];
        dictionary[key] = @"tile";
        NSAssert(dictionary[[NSIndexPath indexPathForRow:2 inSection:3]] != nil, @"index path keys compare by value");
        NSUInteger enumerated = 0;
        for (NSIndexPath *item in dictionary) {
            NSAssert(item.row == 2 && item.section == 3, @"dictionary enumeration returns keys");
            enumerated++;
        }
        NSAssert(enumerated == 1, @"enumeration count");
        [dictionary removeAllObjects];
        NSAssert(dictionary[key] == nil, @"dictionary removal");
        NSString *formatted = [NSString stringWithFormat:@"%d %ld %@", -7, (long)-12, @"ok"];
        NSAssert(strcmp(formatted.UTF8String, "-7 -12 ok") == 0, @"Darwin stack varargs widths");
        void (^copied)(void) = nil;
        __weak NSArray *weakArray = nil;
        @autoreleasepool {
            NSArray *array = @[key, key];
            weakArray = array;
            copied = [^{ NSAssert([array count] == 2, @"copied block retains its capture"); } copy];
        }
        NSAssert(weakArray != nil, @"block owns array after pool drains");
        copied();
        copied = nil;
        NSAssert(weakArray == nil, @"block disposal releases its capture");
        puts("iOS PASS: collections, fast enumeration, copied blocks and zeroing weak references");
        F3HModelTests *tests = [F3HModelTests new];
        [tests testModelMerge1]; [tests testModelMerge2];
        [tests testModelMerge3]; [tests testModelMerge4];
        [tests testModelMerge5]; [tests testModelMerge6];
        [tests testModelMerge7]; [tests testModelMerge8];
        puts("iOS PASS: upstream 2048 eight model merge tests");
    }
    return 0;
}
