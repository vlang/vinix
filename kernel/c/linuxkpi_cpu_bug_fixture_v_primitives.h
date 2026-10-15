/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_CPU_BUG_FIXTURE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_CPU_BUG_FIXTURE_V_PRIMITIVES_H
#include <stdint.h>
#include <stdbool.h>
bool vinix_linuxkpi_cpu_bug_fixture_l1tf(void);
uint32_t vinix_linuxkpi_cpu_bug_fixture_bit(void);
int64_t vinix_linuxkpi_cpu_bug_fixture_sleep(int64_t);
#endif
