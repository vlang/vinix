/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ASM_CPUFEATURE_H
#define VINIX_ASM_CPUFEATURE_H
#include <asm/cpufeatures.h>
#include <vinix/runtime.h>
#define boot_cpu_has(feature) vinix_linuxkpi_cpu_has(feature)
#define static_cpu_has(feature) vinix_linuxkpi_cpu_has(feature)
#endif
