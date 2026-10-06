/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ASM_PERCPU_H
#define VINIX_ASM_PERCPU_H
#include <linux/irqflags.h>
#include <linux/preempt.h>
#include <vinix/runtime.h>
/* Linux's generic accessors disable preemption for reads and save IRQs for
 * read-modify-write operations. They use the Vinix pointer translation above. */
#include <asm-generic/percpu.h>
#define this_cpu_read_stable(var) this_cpu_read(var)

/* Exact Linux 6.6.157 early declarations; storage and early maps remain
 * separate unresolved services. Native per-CPU placement stays unchanged. */
#ifdef CONFIG_SMP
#define DECLARE_EARLY_PER_CPU_READ_MOSTLY(_type, _name)		\
	DECLARE_PER_CPU_READ_MOSTLY(_type, _name);		\
	extern __typeof__(_type) *_name##_early_ptr;		\
	extern __typeof__(_type)  _name##_early_map[]
#else
#define DECLARE_EARLY_PER_CPU_READ_MOSTLY(_type, _name)		\
	DECLARE_PER_CPU_READ_MOSTLY(_type, _name)
#endif
#endif
