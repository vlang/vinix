/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ASM_FPU_API_H
#define VINIX_ASM_FPU_API_H
#include <asm/cpufeature.h>
static __always_inline void kernel_fpu_begin(void)
{
    vinix_linuxkpi_fpu_begin();
    unsigned int mxcsr = 0x1f80;
    __asm__ volatile("fninit; ldmxcsr %0" : : "m"(mxcsr) : "memory");
}
static __always_inline void kernel_fpu_end(void) { vinix_linuxkpi_fpu_end(); }
#endif
