#ifndef _PTHREAD_H
#define _PTHREAD_H

#include <stddef.h>

struct __thread_data {
    void *ptr;
};

struct __threadattr {
    void *ptr;
};

typedef struct __thread_data *pthread_t;
typedef struct __threadattr pthread_attr_t;

// V's generated thread runtime declares objects of these types and calls the
// functions below. `-target-libc-headers` leaves the declaring to us.
//
// The implementations are V functions in lib/stubs exported under these names.
// V's builtin pthread declarations and opaque-handle exports use `void *`.
// Match that spelling at the C boundary; every caller still passes a pointer.
//
// The attribute calls are accepted and ignored: a kernel thread's stack is chosen
// by the scheduler, not by the caller.
int pthread_create(void *thread, void *attr, void *start_routine, void *arg);
int pthread_join(void *thread, void *retval);
int pthread_detach(void *thread);
void pthread_exit(void *retval);
int pthread_equal(void *a, void *b);

int pthread_attr_init(void *attr);
int pthread_attr_setstacksize(void *attr, size_t stacksize);
int pthread_attr_destroy(void *attr);

#endif
