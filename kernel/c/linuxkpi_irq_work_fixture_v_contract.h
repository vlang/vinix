/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_IRQ_WORK_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_IRQ_WORK_FIXTURE_V_CONTRACT_H
#include "linuxkpi_irq_work_v_contract.h"
#include "linuxkpi_irq_work_fixture_v_primitives.h"
_Static_assert(sizeof(struct irq_work) == sizeof(struct vinix_irqwork_fixture) &&
               _Alignof(struct irq_work) == _Alignof(struct vinix_irqwork_fixture) &&
               offsetof(struct irq_work, node.llist) == offsetof(struct vinix_irqwork_fixture, next) &&
               offsetof(struct irq_work, node.u_flags) == offsetof(struct vinix_irqwork_fixture, flags) &&
               offsetof(struct irq_work, func) == offsetof(struct vinix_irqwork_fixture, func) &&
               offsetof(struct irq_work, irqwait) == offsetof(struct vinix_irqwork_fixture, task),
               "native IRQ work fixture retains original complete layout");
#endif
