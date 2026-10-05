// SPDX-License-Identifier: GPL-2.0-or-later
// Independent declarations for the public API subset used by iOS-2048.
#pragma once
#import "../../../ios-calculator/api/Foundation.h"
typedef unsigned int uint32_t;
typedef double NSTimeInterval;
#define NSAssert(condition, ...) do { if (!(condition)) __builtin_trap(); } while (0)
@protocol NSObject
- (Class)class;
@end
@interface NSObject (VinixDeclarations) <NSObject>
+ (Class)class;
- (Class)class;
- (id)copy;
@end
@interface NSString (VinixDeclarations)
+ (instancetype)stringWithFormat:(NSString *)format, ...;
- (const char *)UTF8String;
@end
NSString *NSStringFromClass(Class cls);
@interface NSNumber : NSObject
+ (instancetype)numberWithInteger:(NSInteger)value;
- (NSString *)stringValue;
@end
@interface NSIndexPath : NSObject
+ (instancetype)indexPathForRow:(NSInteger)row inSection:(NSInteger)section;
@property(readonly) NSInteger row;
@property(readonly) NSInteger section;
@end
struct NSFastEnumerationState {
    unsigned long state;
    id __unsafe_unretained *itemsPtr;
    unsigned long *mutationsPtr;
    unsigned long extra[5];
};
@protocol NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(struct NSFastEnumerationState *)state objects:(id __unsafe_unretained *)buffer count:(NSUInteger)count;
@end
@interface NSArray : NSObject <NSFastEnumeration>
+ (instancetype)array;
+ (instancetype)arrayWithObjects:(const id __unsafe_unretained *)objects count:(NSUInteger)count;
+ (instancetype)arrayWithArray:(NSArray *)array;
- (NSUInteger)count;
- (id)objectAtIndexedSubscript:(NSUInteger)index;
- (id)firstObject;
@end
@interface NSMutableArray : NSArray
+ (instancetype)arrayWithCapacity:(NSUInteger)capacity;
- (void)addObject:(id)object;
- (void)removeAllObjects;
- (void)removeObjectAtIndex:(NSUInteger)index;
- (void)setObject:(id)object atIndexedSubscript:(NSUInteger)index;
@end
@interface NSDictionary : NSObject <NSFastEnumeration>
- (id)objectForKeyedSubscript:(id)key;
@end
@interface NSMutableDictionary : NSDictionary
+ (instancetype)dictionary;
- (void)setObject:(id)object forKeyedSubscript:(id)key;
- (void)removeObjectForKey:(id)key;
- (void)removeAllObjects;
@end
@interface NSTimer : NSObject
+ (instancetype)scheduledTimerWithTimeInterval:(NSTimeInterval)interval target:(id)target selector:(SEL)selector userInfo:(id)info repeats:(BOOL)repeats;
- (void)invalidate;
- (BOOL)isValid;
@end
uint32_t arc4random_uniform(uint32_t bound);
float floorf(float value);
