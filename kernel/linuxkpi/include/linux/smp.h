/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SMP_H
#define VINIX_LINUX_SMP_H
#include <linux/preempt.h>
#include <vinix/runtime.h>
unsigned int raw_smp_processor_id(void);
unsigned int vinix_get_cpu(void);
#define smp_processor_id() raw_smp_processor_id()
#define get_cpu vinix_get_cpu
#define put_cpu() preempt_enable()
/* CPU masks, hotplug and remote function dispatch are not implemented. */
#endif
