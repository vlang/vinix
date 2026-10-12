/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native metadata only; all executable checks live in the maintained V module. */
#ifndef VINIX_RESOURCE_V_CONTRACT_H
#define VINIX_RESOURCE_V_CONTRACT_H
#include "../scalarfixture/scalar_host_resource.h"
#include <linux/resource.h>
#include <asm/resource.h>
#include <assert.h>
#include <stdio.h>
_Static_assert(sizeof(RLIM_INFINITY) == 8 && __builtin_types_compatible_p(__typeof__(RLIM_INFINITY), unsigned long), "original unsigned-long infinity");
_Static_assert(sizeof(struct rlimit) == 16 && sizeof(struct rlimit64) == 16, "original public resource records");
_Static_assert(__builtin_offsetof(struct rlimit, rlim_max) == 8 && __builtin_offsetof(struct rlimit64, rlim_max) == 8, "original public resource field offsets");
#endif
