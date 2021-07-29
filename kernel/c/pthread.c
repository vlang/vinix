#include <stdbool.h>
#include <pthread.h>

__attribute__((noreturn)) void lib__kpanic(void *, const char *);
void *sched__new_kernel_thread(void *, void *, bool);
void *event__pthread_wait(void *);
__attribute__((noreturn)) void event__pthread_exit(void *);

int pthread_create(pthread_t *restrict thread,
                   const pthread_attr_t *restrict attr,
                   void *(*start_routine)(void *),
                   void *restrict arg) {
    if (attr != NULL) {
        lib__kpanic(NULL, "pthread_create() called with non-NULL attr");
    }

    void **ptr = (void **)thread;

    *ptr = sched__new_kernel_thread(start_routine, arg, true);

    return 0;
}

int pthread_detach(pthread_t thread) {
    return 0;
}

int pthread_join(pthread_t thread, void **retval) {
    *retval = event__pthread_wait((void *)thread);
    return 0;
}

int pthread_exit(void *retval) {
    event__pthread_exit(retval);
}
