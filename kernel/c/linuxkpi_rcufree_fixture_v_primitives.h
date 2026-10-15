/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_RCUFREE_FIXTURE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_RCUFREE_FIXTURE_V_PRIMITIVES_H
#include "linuxkpi_rcu_fixture_v_primitives.h"
void *vinix_linuxkpi_rcufree_fixture_new(uint32_t);
bool vinix_linuxkpi_rcufree_fixture_check(uint32_t, void *);
void vinix_linuxkpi_rcufree_fixture_enqueue(uint32_t, void *);
void vinix_linuxkpi_rcufree_fixture_headless(void *);
void vinix_linuxkpi_rcufree_fixture_immediate(void *);
uint32_t vinix_linuxkpi_rcufree_fixture_head_offset(uint32_t);
#endif
