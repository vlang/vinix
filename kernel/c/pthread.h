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
// The parameter spellings follow what V emits for each: a single pointer to a
// struct it knows stays typed, while a double pointer or an opaque attribute
// lowers to `void *`. A prototype that disagreed would be a conflicting
// declaration, and every caller passes a pointer either way.
//
// The attribute calls are accepted and ignored: a kernel thread's stack is chosen
// by the scheduler, not by the caller.
int pthread_create(void *thread, void *attr, void *start_routine, void *arg);
int pthread_join(void *thread, void *retval);
int pthread_detach(struct __thread_data *thread);
void pthread_exit(void *retval);
int pthread_equal(struct __thread_data *a, struct __thread_data *b);

int pthread_attr_init(void *attr);
int pthread_attr_setstacksize(void *attr, size_t stacksize);
int pthread_attr_destroy(void *attr);

#endif
