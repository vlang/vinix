/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SMP_H
#define VINIX_LINUX_SMP_H
#include <linux/preempt.h>
#include <vinix/runtime.h>
static inline unsigned int raw_smp_processor_id(void) { return vinix_linuxkpi_cpu_id(); }
#define smp_processor_id() raw_smp_processor_id()
#define get_cpu() ({ preempt_disable(); smp_processor_id(); })
#define put_cpu() preempt_enable()
/* CPU masks, hotplug and remote function dispatch are not implemented. */
#endif
