/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ASM_FPU_API_H
#define VINIX_ASM_FPU_API_H
#include <asm/cpufeature.h>
void kernel_fpu_begin(void);
void kernel_fpu_end(void);
#endif
