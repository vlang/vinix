/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_TSC_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_TSC_FIXTURE_V_CONTRACT_H
#include "linuxkpi_tsc_v_contract.h"
/* Generated V uses LP64 uint64_t; preserve Linux's separate ULL alias. */
#define u64 vkt_original_u64
#include <asm/tsc.h>
#include <string.h>
#undef u64
_Static_assert(__builtin_types_compatible_p(cycles_t, vkt_cycles),
    "The original cycle accessor preserves its unsigned long long ABI");
_Static_assert(__builtin_types_compatible_p(__typeof__(&rdtsc), vkt_cycles (*)(void)),
    "The raw accessor returns the original Linux cycle type");
int vinix_linuxkpi_tsc_fixture_queries(void);
#endif
