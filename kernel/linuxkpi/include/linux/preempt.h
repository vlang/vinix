/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_PREEMPT_H
#define VINIX_LINUX_PREEMPT_H
#include <linux/irqflags.h>
#include <vinix/runtime.h>
/* Original preempt/thread-info imports expose the native CPU spin hint. */
#include <asm/processor.h>
/* Native scheduler pins. IRQ/NMI/softirq context accounting is not implemented
 * here: in_interrupt()/in_atomic() remain unavailable. The NMI query is
 * declared for unchanged SRCU inlines but remains unresolved at link time. */
bool in_nmi(void);
/* Exact Linux bit positions needed by unchanged vtime's disabled-accounting
 * inlines. Native preempt_count does not encode IRQ/BH context in these bits. */
#define SOFTIRQ_OFFSET (1UL << 8)
#define HARDIRQ_OFFSET (1UL << 16)
/* Parsing unchanged BH inlines supplies declarations, not a working BH
 * service. Context-bit mutation remains unresolved at link time. */
#define SOFTIRQ_DISABLE_OFFSET (2 * SOFTIRQ_OFFSET)
void preempt_count_add(int value);
#define preempt_disable() vinix_linuxkpi_preempt_disable()
#define preempt_enable() vinix_linuxkpi_preempt_enable()
#define preempt_enable_no_resched() vinix_linuxkpi_preempt_enable_no_resched()
#define sched_preempt_enable_no_resched() preempt_enable_no_resched()
#define preempt_disable_notrace() preempt_disable()
#define preempt_enable_notrace() preempt_enable()
#define preempt_enable_no_resched_notrace() preempt_enable_no_resched()
#define preempt_count() vinix_linuxkpi_preempt_count()
#include <vinix/integer_policy.h>
#define preempt_check_resched() vinix_linuxkpi_preempt_check_resched()
/* Task-owned nesting permits preemption and sleep on the same CPU. Ordinary
 * task calls and balanced active-task maskable IRQ pairs are supported;
 * idle, NMI, CPU hotplug and Linux's blocking affinity API remain unsupported. */
void migrate_disable(void);
void migrate_enable(void);
#endif
