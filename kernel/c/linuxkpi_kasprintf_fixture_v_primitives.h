/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_KASPRINTF_FIXTURE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_KASPRINTF_FIXTURE_V_PRIMITIVES_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
void *vinix_linuxkpi_kasprintf_fixture_run(uint32_t,uint32_t,void *,uint32_t *);
bool vinix_linuxkpi_kasprintf_fixture_overflow(uint32_t,uint32_t *);
void vinix_linuxkpi_kasprintf_fixture_free(void *);
void *vinix_linuxkpi_kasprintf_fixture_alloc(size_t);
uint32_t vinix_linuxkpi_kasprintf_fixture_gfp(void);
void *vinix_linuxkpi_kasprintf_fixture_literal(void);
bool vinix_linuxkpi_kasprintf_fixture_rodata(void *);
#endif
