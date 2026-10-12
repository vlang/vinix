/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Compiler/ABI metadata only; runtime fixtures and instruction spies are V. */
#ifndef VINIX_RAW_TSC_FIXTURE_H
#define VINIX_RAW_TSC_FIXTURE_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "linuxkpi_tsc_v_contract.h"
/* The native V u64 C spelling is independent of Linux's original ULL alias. */
#define u64 vrt_linux_u64
#define timezone vrt_linux_timezone
#define ffs vrt_linux_ffs
#define fls vrt_linux_fls
#ifdef VRT_MSR_FIRST
#include <asm/msr.h>
#include <asm/processor.h>
#else
#include <asm/processor.h>
#include <asm/msr.h>
#endif
#include <asm/tsc.h>
#define VRT_TSC_CONFIGURED IS_ENABLED(CONFIG_X86_TSC)
typedef struct vrt_calls {
    unsigned long long (*counter)(void);
    cycles_t (*cycles)(void);
    uint64_t (*raw)(void);
} vrt_calls;
_Static_assert(X86_FEATURE_TSC == 4, "original TSC feature identity");
_Static_assert(__builtin_types_compatible_p(cycles_t, unsigned long long), "original cycle type");
_Static_assert(__builtin_types_compatible_p(__typeof__(&rdtsc), unsigned long long (*)(void)), "original raw TSC ABI");
_Static_assert(__builtin_types_compatible_p(__typeof__(&get_cycles), cycles_t (*)(void)), "original get_cycles ABI");
_Static_assert(__builtin_types_compatible_p(__typeof__(&vinix_linuxkpi_raw_tsc), uint64_t (*)(void)), "native bridge ABI");
_Static_assert(sizeof(struct msr) == 8 && __builtin_offsetof(struct msr, l) == 0 && __builtin_offsetof(struct msr, h) == 4 && __builtin_offsetof(struct msr, q) == 0, "original shared MSR storage");
_Static_assert(_IOC_SIZE(X86_IOC_RDMSR_REGS) == 32 && _IOC_SIZE(X86_IOC_WRMSR_REGS) == 32, "original UAPI MSR register transport size");
#undef u64
#undef timezone
#undef ffs
#undef fls
#endif
