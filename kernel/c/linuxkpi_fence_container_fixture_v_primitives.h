/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_FENCE_CONTAINER_FIXTURE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_FENCE_CONTAINER_FIXTURE_V_PRIMITIVES_H
#include <stdint.h>
#include <stdbool.h>
uint32_t vinix_linuxkpi_fct_bytes(uint32_t);
void *vinix_linuxkpi_fct_array(int32_t, void *, uint64_t, uint32_t, bool);
void *vinix_linuxkpi_fct_chain_alloc(void);
void vinix_linuxkpi_fct_chain_free(void *);
void vinix_linuxkpi_fct_chain_init(void *, void *, void *, uint64_t);
void *vinix_linuxkpi_fct_walk(void *);
int32_t vinix_linuxkpi_fct_find(void **, uint64_t);
void *vinix_linuxkpi_fct_first(void *);
void *vinix_linuxkpi_fct_next(void *, uint32_t);
bool vinix_linuxkpi_fct_match(void *, uint64_t);
uint32_t vinix_linuxkpi_fct_kind(void *);
uint32_t vinix_linuxkpi_fct_refs(void *);
uint64_t vinix_linuxkpi_fct_value(void *, uint32_t);
int32_t vinix_linuxkpi_fct_pending(void *);
#endif
