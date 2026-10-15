/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_RWSEM_V_CONTRACT_H
#define VINIX_LINUXKPI_RWSEM_V_CONTRACT_H
#include "linuxkpi_common_v_contract.h"
#include <linux/rwsem.h>
#include "linuxkpi_rwsem_v_primitives.h"

#if defined(CONFIG_PREEMPT_RT) || defined(CONFIG_RWSEM_SPIN_ON_OWNER) || \
    defined(CONFIG_DEBUG_RWSEMS) || defined(CONFIG_DEBUG_LOCK_ALLOC)
#error "Native V rwsem requires the non-RT, non-debug, non-optimistic-spin profile"
#endif
_Static_assert(BITS_PER_LONG == 64, "native rwsem word width");
_Static_assert(sizeof(struct rw_semaphore) == 40 && _Alignof(struct rw_semaphore) == 8,
               "original supported rwsem size/alignment");
_Static_assert(sizeof(struct vrs_rwsem) == sizeof(struct rw_semaphore) &&
               _Alignof(struct vrs_rwsem) == _Alignof(struct rw_semaphore),
               "native rwsem view size/alignment");
_Static_assert(offsetof(struct rw_semaphore, count) == 0 &&
               offsetof(struct rw_semaphore, owner) == 8 &&
               offsetof(struct rw_semaphore, wait_lock) == 16 &&
               offsetof(struct rw_semaphore, wait_list) == 24,
               "original supported rwsem offsets");
#define VRS_MATCH_FIELD(field) \
    _Static_assert(offsetof(struct vrs_rwsem, field) == offsetof(struct rw_semaphore, field), \
                   "native rwsem " #field " offset")
VRS_MATCH_FIELD(count);
VRS_MATCH_FIELD(owner);
VRS_MATCH_FIELD(wait_lock);
VRS_MATCH_FIELD(wait_list);
_Static_assert(sizeof(((struct rw_semaphore *)0)->count) == sizeof(long) &&
               sizeof(((struct rw_semaphore *)0)->owner) == sizeof(long) &&
               sizeof(((struct rw_semaphore *)0)->wait_lock) == sizeof(unsigned int) &&
               sizeof(((struct rw_semaphore *)0)->wait_list) == sizeof(struct vkw_list),
               "original supported rwsem field widths");
#undef VRS_MATCH_FIELD
#endif
