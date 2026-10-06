// SPDX-License-Identifier: GPL-2.0-or-later
#import "../../examples/ios-calculator/api/Foundation.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface NSString (ThreadFixture)
- (const char *)UTF8String;
@end
static unsigned ready, release_owner, destroyed;
static __weak id weak_owner;
@interface ThreadOwner : NSObject @end
@implementation ThreadOwner
- (void)dealloc { __atomic_fetch_add(&destroyed, 1, __ATOMIC_RELAXED); }
@end

static void *worker(void *argument) {
    (void)argument;
    @autoreleasepool {
        __unsafe_unretained NSString *text = [NSString stringWithUTF8String:"thread-private pool"];
        // Other threads drain nested pools while this autoreleased return is
        // still in this thread's pool. Shared pools would free it prematurely.
        __atomic_fetch_add(&ready, 1, __ATOMIC_RELEASE);
        while (__atomic_load_n(&ready, __ATOMIC_ACQUIRE) < 8) {}
        for (unsigned iteration = 0; iteration < 2000; ++iteration) {
            @autoreleasepool {
                id owner = weak_owner;
                if (!owner) abort();
                NSString *temporary = [NSString stringWithUTF8String:"nested"];
                if (strcmp(temporary.UTF8String, "nested")) abort();
            }
        }
        if (strcmp(text.UTF8String, "thread-private pool")) abort();
    }
    __atomic_fetch_add(&ready, 1, __ATOMIC_RELEASE);
    while (!__atomic_load_n(&release_owner, __ATOMIC_ACQUIRE)) {}
    for (unsigned iteration = 0; iteration < 2000; ++iteration) {
        @autoreleasepool { id owner = weak_owner; (void)owner; }
    }
    // No explicit pool: the pthread TLS destructor must drain this return.
    (void)[NSString stringWithUTF8String:"implicit thread-exit pool"];
    return NULL;
}

int main(void) {
    @autoreleasepool {
        id owner = [ThreadOwner new];
        weak_owner = owner;
        pthread_t threads[8];
        for (unsigned i = 0; i < 8; ++i) if (pthread_create(&threads[i], NULL, worker, NULL)) abort();
        while (__atomic_load_n(&ready, __ATOMIC_ACQUIRE) < 16) {}
        __atomic_store_n(&release_owner, 1, __ATOMIC_RELEASE);
        owner = nil;
        for (unsigned i = 0; i < 8; ++i) if (pthread_join(threads[i], NULL)) abort();
        if (weak_owner || destroyed != 1) abort();
        weak_owner = nil;
    }
    puts("IOS-ARC: eight threads, weak/deallocation races and isolated autorelease pools");
    return 0;
}
