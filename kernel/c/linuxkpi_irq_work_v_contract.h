/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_IRQ_WORK_V_CONTRACT_H
#define VINIX_LINUXKPI_IRQ_WORK_V_CONTRACT_H
#include "linuxkpi_common_v_contract.h"
#include <linux/irq_work.h>
#include "linuxkpi_irq_work_v_primitives.h"
_Static_assert(sizeof(struct irq_work) == 32 && _Alignof(struct irq_work) == 8 &&
               offsetof(struct irq_work, node.llist.next) == 0 &&
               offsetof(struct irq_work, node.a_flags) == 8 &&
               offsetof(struct irq_work, func) == 16 &&
               offsetof(struct irq_work, irqwait) == 24 &&
               sizeof(struct vkiw_work) == sizeof(struct irq_work) &&
               _Alignof(struct vkiw_work) == _Alignof(struct irq_work) &&
               offsetof(struct vkiw_work, next) == 0 &&
               offsetof(struct vkiw_work, flags) == 8 &&
               offsetof(struct vkiw_work, func) == 16 &&
               offsetof(struct vkiw_work, irqwait) == 24,
               "original IRQ-work intrusive record ABI");
_Static_assert(IRQ_WORK_PENDING == 1 && IRQ_WORK_BUSY == 2 &&
               IRQ_WORK_LAZY == 4 && IRQ_WORK_HARD_IRQ == 8 &&
               IRQ_WORK_CLAIMED == 3 && CSD_TYPE_IRQ_WORK == 0x20 &&
               CSD_FLAG_TYPE_MASK == 0xf0,
               "original IRQ-work claim, dispatch and classification bits");
_Static_assert(__builtin_types_compatible_p(vkiw_callback_fn,
               __typeof__(((struct irq_work *)0)->func)),
               "original IRQ-work callback signature");
#endif
