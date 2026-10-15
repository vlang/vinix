/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_MIGRATION_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_MIGRATION_FIXTURE_V_CONTRACT_H
#include "linuxkpi_common_v_contract.h"
#define u64 vkh_linux_u64
#include <linux/preempt.h>
#include <linux/completion.h>
#include <linux/sched.h>
#undef u64
#include "linuxkpi_migration_fixture_v_primitives.h"
_Static_assert(sizeof(struct completion) == sizeof(struct vinix_migration_completion) &&
    _Alignof(struct completion) == _Alignof(struct vinix_migration_completion),
    "original completion storage");
_Static_assert(sizeof(long) == sizeof(int64_t), "native Linux timeout width");
#endif
