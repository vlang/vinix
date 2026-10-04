/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ASM_BITOPS_H
#define VINIX_ASM_BITOPS_H
/* Linux's generic atomic bit operations delegate to our atomic_long backend;
 * no Linux alternative-instruction patching or per-CPU segment state is used. */
#include <asm-generic/bitops.h>
#endif
