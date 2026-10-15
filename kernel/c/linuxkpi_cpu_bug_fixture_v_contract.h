/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_CPU_BUG_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_CPU_BUG_FIXTURE_V_CONTRACT_H
/* Preserve the original ULL type independently of V's LP64 alias. */
#undef va_arg
#define u64 vcb_linux_u64
#include <asm/cpufeature.h>
#include <linux/sched.h>
#undef u64
#include "linuxkpi_cpu_bug_fixture_v_primitives.h"
/* Original constant and actual public query, with no independent policy. */
#define vcb_original_l1tf_bit() X86_BUG_L1TF
#define vcb_original_l1tf_query() boot_cpu_has_bug(X86_BUG_L1TF)
_Static_assert(X86_BUG_L1TF == 722, "pinned original L1TF bug identity");
_Static_assert(sizeof(long) == sizeof(int64_t), "native timeout width");
#endif
