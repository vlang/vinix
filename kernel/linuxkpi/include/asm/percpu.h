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
#endif
