// SPDX-License-Identifier: GPL-2.0-or-later
typedef unsigned long uintptr_t;
extern int puts(const char *);
extern int pthread_create(uintptr_t *, const void *, void *(*)(void *), void *);
extern int pthread_join(uintptr_t, void **);
extern int __cxa_atexit(void (*)(void *), void *, void *);

static _Thread_local volatile int initialized_tls = 17;
static _Thread_local volatile int zero_tls;
static volatile int constructed;
static volatile int destroyed;

static void cleanup(void *argument) {
    if (argument != &destroyed || destroyed++) {
        puts("iOS FAIL: image destructor called twice or with wrong argument");
        return;
    }
    puts("IOS-LIFECYCLE: destructor");
}

__attribute__((constructor)) static void initialize(void) {
    constructed = 123;
    initialized_tls = 29;
    if (__cxa_atexit(cleanup, (void *)&destroyed, 0)) constructed = 0;
    puts("IOS-LIFECYCLE: constructor");
}

static void *worker(void *argument) {
    if (initialized_tls != 17 || zero_tls || constructed != 123) return (void *)1;
    initialized_tls = 53;
    zero_tls = (int)(uintptr_t)argument;
    return (void *)(uintptr_t)(initialized_tls + zero_tls);
}

int main(void) {
    if (constructed != 123 || initialized_tls != 29 || zero_tls) return 10;
    for (uintptr_t i = 1; i <= 8; i++) {
        uintptr_t thread;
        void *result;
        if (pthread_create(&thread, 0, worker, (void *)i) || pthread_join(thread, &result)) return 11;
        if ((uintptr_t)result != 53 + i || initialized_tls != 29 || zero_tls) return 12;
    }
    puts("IOS-LIFECYCLE: constructors and eight isolated TLS threads");
    return 0;
}
