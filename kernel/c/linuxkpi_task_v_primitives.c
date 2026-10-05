/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef VINIX_LINUXKPI
#include "linuxkpi_task_v_primitives.h"
#include <linux/sched.h>
#include <linux/timer.h>
#include <linux/vtime.h>
#include <linux/time64.h>
_Static_assert(sizeof(struct task_struct) == sizeof(struct vkt_task_view), "native task view size");
_Static_assert(sizeof(struct task_struct) <= 64 && _Alignof(struct task_struct) <= _Alignof(uint64_t), "native task view storage");
_Static_assert(offsetof(struct task_struct, vinix_thread) == offsetof(struct vkt_task_view, vinix_thread) && offsetof(struct task_struct, pid) == offsetof(struct vkt_task_view, pid) && offsetof(struct task_struct, tgid) == offsetof(struct vkt_task_view, tgid) && offsetof(struct task_struct, flags) == offsetof(struct vkt_task_view, flags) && offsetof(struct task_struct, comm) == offsetof(struct vkt_task_view, comm), "task public fields");
_Static_assert(offsetof(struct task_struct, __state) == offsetof(struct vkt_task_view, state), "task state offset");
_Static_assert(offsetof(struct task_struct, vinix_wait_lock) == offsetof(struct vkt_task_view, wait_lock), "task lock offset");
_Static_assert(offsetof(struct task_struct, vinix_initial_comm) == offsetof(struct vkt_task_view, initial_comm), "task name offset");
_Static_assert(offsetof(struct task_struct, in_iowait) == offsetof(struct vkt_task_view, in_iowait), "task I/O offset");
_Static_assert(sizeof(struct timespec64) == sizeof(struct vkt_timespec64), "timespec64 ABI");
_Static_assert(sizeof(struct timer_list) == sizeof(struct vkt_timer_view), "timer ABI size");
_Static_assert(offsetof(struct timer_list, entry) == 0 && offsetof(struct timer_list, expires) == offsetof(struct vkt_timer_view, expires) && offsetof(struct timer_list, function) == offsetof(struct vkt_timer_view, function) && offsetof(struct timer_list, flags) == offsetof(struct vkt_timer_view, flags), "timer ABI fields");
_Static_assert(HZ == 1000 && BITS_PER_LONG == 64 && SEC_JIFFIE_SC == 22 && NSEC_JIFFIE_SC == 51, "V time conversion configuration");
/* The two exported names own one cacheline-aligned word, including Darwin. */
unsigned long volatile jiffies __cacheline_aligned_in_smp = INITIAL_JIFFIES;
#if defined(VINIX_LINUXKPI_HOST_TEST) && defined(__APPLE__)
__asm__(".globl _jiffies_64\n.set _jiffies_64, _jiffies");
#else
extern u64 jiffies_64 __attribute__((alias("jiffies")));
#endif
uintptr_t vkt_jiffies_address(void) { return (uintptr_t)&jiffies; }
void vkt_guest_enter(void) { vtime_account_guest_enter(); }
void vkt_guest_exit(void) { vtime_account_guest_exit(); }
uint64_t vkt_max_sec_in_jiffies(void) { return MAX_SEC_IN_JIFFIES; }
unsigned int vkt_sec_conversion(void) { return SEC_CONVERSION; }
unsigned int vkt_nsec_conversion(void) { return NSEC_CONVERSION; }
#include <linux/completion.h>
static DECLARE_COMPLETION(vkt_worker_ready);
void *vkt_timer_worker_ready(void) { return &vkt_worker_ready; }
void vkt_completion_complete(void *p) { complete(p); }
void vkt_completion_wait(void *p) { wait_for_completion(p); }
#include <pthread.h>
_Static_assert(sizeof(pthread_t) <= sizeof(uint64_t), "V pthread storage");
int vkt_pthread_create(void *storage, void *(*function)(void *), void *argument) { return pthread_create(storage, NULL, function, argument); }
int vkt_pthread_detach(void *storage) { return pthread_detach(*(pthread_t *)storage); }
#endif
