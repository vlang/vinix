/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_CONST_STRING_V_PRIMITIVES_H
#define VINIX_LINUXKPI_CONST_STRING_V_PRIMITIVES_H
#include <stdbool.h>
#include <stdint.h>

/* Native image interval query: no candidate dereference or ownership registry. */
bool vinix_linuxkpi_is_kernel_rodata(const void *);

/* Raw pointer views; the public facade preserves original Linux qualifiers. */
void vkc_kfree_const(void *);
void *vkc_kstrdup_const(void *, uint32_t);
#endif
