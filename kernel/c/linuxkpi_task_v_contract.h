/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_TASK_V_CONTRACT_H
#define VINIX_LINUXKPI_TASK_V_CONTRACT_H
#include "linuxkpi_common_v_contract.h"
#include <linux/vtime.h>
#include <linux/time64.h>
#include <linux/completion.h>
#include <pthread.h>
#include "linuxkpi_task_v_primitives.h"
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

_Static_assert(sizeof(pthread_t) <= sizeof(uint64_t), "V pthread storage");
_Static_assert(INITIAL_JIFFIES == 4294667296UL && SMP_CACHE_BYTES == 64, "native jiffies data contract");
#endif
