/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_CONSTSTRING_FIXTURE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_CONSTSTRING_FIXTURE_V_PRIMITIVES_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Pointer views only. The fixture calls the original const-qualified APIs. */
void *vinix_linuxkpi_conststring_fixture_dup(void *, uint32_t);
void vinix_linuxkpi_conststring_fixture_free(void *);
void *vinix_linuxkpi_conststring_fixture_alloc(size_t);
uint32_t vinix_linuxkpi_conststring_fixture_gfp(void);
void *vinix_linuxkpi_conststring_fixture_literal(void);
uintptr_t vinix_linuxkpi_conststring_fixture_address(uint32_t);
bool vinix_linuxkpi_conststring_fixture_rodata(void *);
#endif
