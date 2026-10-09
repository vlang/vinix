/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_SMP_FIXTURE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_SMP_FIXTURE_V_PRIMITIVES_H
#include "linuxkpi_smp_call_v_primitives.h"
uint32_t vinix_linuxkpi_smp_fixture_csd_bytes(void);
int32_t vinix_linuxkpi_smp_fixture_single(int32_t, vks_smp_call_fn, void *, int32_t);
void vinix_linuxkpi_smp_fixture_many(vks_smp_call_fn, void *, bool, vks_smp_cond_fn);
#endif
