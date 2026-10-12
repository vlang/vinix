/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ASM_MSR_H
#define VINIX_ASM_MSR_H
#include <asm/msr-index.h>
#ifndef __ASSEMBLY__
#include <linux/types.h>
#include <uapi/asm/msr.h>
#include <asm/shared/msr.h>
/* Raw, unordered cycle access. Ordered TSC and MSR services need separate
 * native implementations; no alternative-patching fallback is exposed. */
unsigned long long rdtsc(void);
#endif
#endif
