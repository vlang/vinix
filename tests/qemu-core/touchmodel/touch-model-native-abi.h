/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef VINIX_QEMU_CORE_TOUCH_MODEL_NATIVE_ABI_H
#define VINIX_QEMU_CORE_TOUCH_MODEL_NATIVE_ABI_H
#include <touchfixture_v_contract.h>
#include <assert.h>
typedef const void *vqt_const_void_p;
int vqt_host_sysinfo(struct sysinfo *);
void *vqt_host_mmap(void *, size_t, int, int, int, off_t);
int vqt_host_munmap(void *, size_t);
int vqt_host_mprotect(void *, size_t, int);
int vqt_host_barrier_init(pthread_barrier_t *, const void *, unsigned int);
int vqt_host_barrier_wait(pthread_barrier_t *);
int vqt_host_barrier_destroy(pthread_barrier_t *);
int original_test_anonymous_first_touch(void);
int test_anonymous_first_touch(void);
int reap_ok(pid_t);
int original_reap_ok(pid_t);
#endif
