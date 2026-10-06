/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_X86_IRQ_V_CONTRACT_H
#define VINIX_X86_IRQ_V_CONTRACT_H

#include <stdint.h>

/* Native x86 maskable-vector accounting, active from each CPU's setup.
 * Entry/exit require kernel GS and IF=0. Depth preserves the caller's IF and
 * requires initialized kernel GS. No Linux IRQ/NMI/BH bit encoding is implied. */
void vinix_x86_maskable_irq_enter(uint32_t vector, uint64_t saved_cs);
void vinix_x86_maskable_irq_exit(uint32_t vector);
uint32_t vinix_x86_maskable_irq_depth(void);

#endif
