/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_RCU_FIXTURE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_RCU_FIXTURE_V_PRIMITIVES_H
#include "linuxkpi_rcu_v_primitives.h"
/* Opaque original-head storage; the typed facade checks every field offset. */
struct vinix_rcu_fixture_head { void *next; void *func; };
uint32_t vinix_linuxkpi_rcu_fixture_head_bytes(void);
void vinix_linuxkpi_rcu_fixture_read_lock(void);
void vinix_linuxkpi_rcu_fixture_read_unlock(void);
uint64_t vinix_linuxkpi_rcu_fixture_get_state(void);
uint64_t vinix_linuxkpi_rcu_fixture_start_poll(void);
bool vinix_linuxkpi_rcu_fixture_poll(uint64_t);
void vinix_linuxkpi_rcu_fixture_synchronize(bool);
void vinix_linuxkpi_rcu_fixture_barrier(void);
void vinix_linuxkpi_rcu_fixture_call(void *, vkr_rcu_callback_fn);
uint64_t vinix_linuxkpi_rcu_test_force_count(void);
int32_t vinix_linuxkpi_rcu_test_irq_off_probe(void);
bool vinix_linuxkpi_rcu_fixture_task_sleeping(void *);
#endif
