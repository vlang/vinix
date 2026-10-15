/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_IRQ_WORK_FIXTURE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_IRQ_WORK_FIXTURE_V_PRIMITIVES_H
#include "linuxkpi_rcu_fixture_v_primitives.h"
struct irq_work;
struct vinix_irqwork_fixture { void *next; uint32_t flags; uint16_t src, dst; void *func; void *task; };
uint32_t vinix_linuxkpi_irqwork_fixture_bytes(void);
int32_t vinix_linuxkpi_irqwork_fixture_init(void *, void (*)(struct irq_work *), uint32_t);
bool vinix_linuxkpi_irqwork_fixture_queue(void *, int32_t);
void vinix_linuxkpi_irqwork_fixture_sync(void *);
bool vinix_linuxkpi_irqwork_fixture_pending(void *);
bool vinix_linuxkpi_irqwork_fixture_busy(void *);
void vinix_linuxkpi_irqwork_fixture_defer(void *, void *);
uint64_t vinix_linuxkpi_irqwork_tick_count(void);
uint64_t vinix_linuxkpi_irqwork_ipi_count(uint32_t);
#endif
