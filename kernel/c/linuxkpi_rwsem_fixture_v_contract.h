/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_RWSEM_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_RWSEM_FIXTURE_V_CONTRACT_H
#include "linuxkpi_common_v_contract.h"
#define u64 vkh_linux_u64
#include <linux/rwsem.h>
#include <linux/completion.h>
#include <linux/slab.h>
#undef u64
#include "linuxkpi_rwsem_fixture_v_primitives.h"
_Static_assert(sizeof(struct rw_semaphore) == sizeof(struct vinix_rwsem_fixture) &&
    _Alignof(struct rw_semaphore) == _Alignof(struct vinix_rwsem_fixture),
    "original non-RT debug-off rwsem storage");
_Static_assert(offsetof(struct rw_semaphore, count) == 0 &&
    offsetof(struct rw_semaphore, owner) == 8 &&
    offsetof(struct rw_semaphore, wait_lock) == 16 &&
    offsetof(struct rw_semaphore, wait_list) == 24,
    "original rwsem field ABI");
_Static_assert(sizeof(struct completion) == sizeof(struct vinix_rwsem_completion) &&
    _Alignof(struct completion) == _Alignof(struct vinix_rwsem_completion),
    "original completion storage");
static DECLARE_RWSEM(vinix_rwsem_fixture_static);
#endif
