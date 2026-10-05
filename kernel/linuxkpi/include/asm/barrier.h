/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_BARRIER_H
#define VINIX_LINUX_BARRIER_H
#include <linux/compiler.h>
#include <vinix/runtime.h>
#define smp_mb() __atomic_thread_fence(__ATOMIC_SEQ_CST)
#define smp_rmb() __atomic_thread_fence(__ATOMIC_ACQUIRE)
#define smp_wmb() __atomic_thread_fence(__ATOMIC_RELEASE)
#define smp_store_release(p, v) __atomic_store_n((p), (v), __ATOMIC_RELEASE)
#define smp_load_acquire(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define smp_mb__before_atomic() smp_mb()
#define smp_mb__after_atomic() smp_mb()
#define smp_mb__after_spinlock() smp_mb()
#define smp_acquire__after_ctrl_dep() __atomic_thread_fence(__ATOMIC_ACQUIRE)
#define smp_cond_load_relaxed(ptr, condition) ({ \
    __auto_type __ptr = (ptr); __typeof__(*__ptr) VAL; \
    for (;;) { VAL = __atomic_load_n(__ptr, __ATOMIC_RELAXED); \
        if (condition) break; vinix_linuxkpi_spin_wait(); } VAL; \
})
#define smp_cond_load_acquire(ptr, condition) ({ \
    __auto_type __ptr = (ptr); __typeof__(*__ptr) VAL; \
    for (;;) { VAL = __atomic_load_n(__ptr, __ATOMIC_ACQUIRE); \
        if (condition) break; vinix_linuxkpi_spin_wait(); } VAL; \
})
#endif
