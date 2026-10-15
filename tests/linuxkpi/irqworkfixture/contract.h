/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_IRQWORK_HOST_CONTRACT_H
#define VINIX_IRQWORK_HOST_CONTRACT_H
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sched.h>
#include <stdint.h>
/* Existing host namespace contract reconciles libc errno/atomic spellings
 * before importing the unchanged original IRQ-work headers. */
#include "linuxkpi_common_v_contract.h"
#include <linux/irq_work.h>
#include "linuxkpi_irq_work_v_primitives.h"
#include "linuxkpi_smp_masks_v_primitives.h"
typedef const char *iwh_const_charp;
#define iwh_load(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define iwh_store(p,v) __atomic_store_n((p),(v), __ATOMIC_RELEASE)
#define iwh_add(p,v) __atomic_fetch_add((p),(v), __ATOMIC_ACQ_REL)
#define iwh_exchange(p,v) __atomic_exchange_n((p),(v), __ATOMIC_ACQ_REL)
#define iwh_line(v) ((v).str)
#define iwh_flags(w) ((uint32_t)atomic_read(&(w)->node.a_flags))
#define iwh_set_flags(w,v) atomic_set(&(w)->node.a_flags,(v))
#define iwh_init(w,f,flags) (*(w)=__IRQ_WORK_INIT((f),(flags)))
#define iwh_next(w) ((uintptr_t)(w)->node.llist.next)
#define iwh_set_next(w,p) ((w)->node.llist.next=(void *)(uintptr_t)(p))
_Static_assert(sizeof(struct irq_work)==32 && _Alignof(struct irq_work)==8 && offsetof(struct irq_work,func)==16 && offsetof(struct irq_work,irqwait)==24,"original irq work record");
#endif
