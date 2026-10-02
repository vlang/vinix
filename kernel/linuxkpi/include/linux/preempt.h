/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_PREEMPT_H
#define VINIX_LINUX_PREEMPT_H
#include <linux/irqflags.h>
#include <vinix/runtime.h>
/* Native scheduler pins. IRQ/NMI/softirq context accounting is not implemented
 * here: in_interrupt()/in_atomic() remain unavailable. The NMI query is
 * declared for unchanged SRCU inlines but remains unresolved at link time. */
bool in_nmi(void);
#define preempt_disable() vinix_linuxkpi_preempt_disable()
#define preempt_enable() vinix_linuxkpi_preempt_enable()
#define preempt_enable_no_resched() vinix_linuxkpi_preempt_enable_no_resched()
#define sched_preempt_enable_no_resched() preempt_enable_no_resched()
#define preempt_disable_notrace() preempt_disable()
#define preempt_enable_notrace() preempt_enable()
#define preempt_enable_no_resched_notrace() preempt_enable_no_resched()
#define preempt_count() vinix_linuxkpi_preempt_count()
#define preemptible() (!preempt_count() && !irqs_disabled())
#define preempt_check_resched() vinix_linuxkpi_preempt_check_resched()
#endif
