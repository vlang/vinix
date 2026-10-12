/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_TSC_V_CONTRACT_H
#define VINIX_LINUXKPI_TSC_V_CONTRACT_H

#include <stdint.h>
#include <stddef.h>

/* Preserve Linux's C type independently of the native LP64 V u64 spelling. */
typedef unsigned long long vkt_cycles;
_Static_assert(sizeof(vkt_cycles) == 8 && sizeof(uint64_t) == 8,
    "Raw TSC storage and Linux cycle results require eight bytes");

uint64_t vinix_linuxkpi_raw_tsc(void);
vkt_cycles rdtsc(void);

#endif
