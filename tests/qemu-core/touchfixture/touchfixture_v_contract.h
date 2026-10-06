#ifndef VINIX_QEMU_CORE_TOUCH_FIXTURE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_TOUCH_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/sysinfo.h>
#include <sys/wait.h>
#include <unistd.h>
#ifdef __APPLE__
/* Darwin lacks POSIX barriers. Host comparisons use a V provider over these
 * native mutex/condition fields; native guest builds use libc's actual type. */
typedef struct {
    pthread_mutex_t lock;
    pthread_cond_t changed;
    unsigned int participants, arrived, generation;
} pthread_barrier_t;
#define PTHREAD_BARRIER_SERIAL_THREAD (-1)
#define MAP_POPULATE 0x8000
int pthread_barrier_init(pthread_barrier_t *, const void *, unsigned int);
int pthread_barrier_wait(pthread_barrier_t *);
int pthread_barrier_destroy(pthread_barrier_t *);
#endif
struct vqt_volatile_word { volatile unsigned long value; };
_Static_assert(sizeof(unsigned long) == 8, "original volatile word width");
_Static_assert(sizeof(struct vqt_volatile_word) == 8, "native volatile word view");
_Static_assert(_Alignof(struct vqt_volatile_word) == _Alignof(unsigned long), "native volatile word alignment");
_Static_assert(sizeof(pthread_t) == 8, "native pthread identifier width");
_Static_assert(sizeof(pid_t) == 4, "native process identifier width");
int reap_ok(pid_t);
void *vqt_anonymous_touch(void *);
#endif
