/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Original compiler policy and native type assertions only. */
#ifndef VINIX_CPU_POLICY_FIXTURE_H
#define VINIX_CPU_POLICY_FIXTURE_H
#include "../policytransport/contract.h"
#define u64 vpp_linux_u64
#define timezone vpp_linux_timezone
#define ffs vpp_linux_ffs
#define fls vpp_linux_fls
#include <asm/cpufeature.h>
typedef volatile u32 vpp_volatile_u32;
_Static_assert(NCAPINTS == 22, "pinned capability word count");
_Static_assert(X86_FEATURE_SHSTK == 519 && X86_FEATURE_LA57 == 528, "original feature identities");
_Static_assert(!cpu_feature_enabled(X86_FEATURE_OSPKE), "PKEY service is not configured");
_Static_assert(!cpu_feature_enabled(X86_FEATURE_PKU), "PKEY service is not configured");
_Static_assert(!cpu_feature_enabled(X86_FEATURE_USER_SHSTK), "user CET service is not configured");
_Static_assert(!cpu_feature_enabled(X86_FEATURE_IBT), "kernel IBT service is not configured");
_Static_assert(!DISABLED_MASK_BIT_SET(X86_FEATURE_SHSTK), "raw SHSTK is independent of user CET configuration");
_Static_assert(!DISABLED_MASK_BIT_SET(X86_FEATURE_LA57), "native four/five-level paging is configured");
#undef u64
#undef timezone
#undef ffs
#undef fls
#endif
