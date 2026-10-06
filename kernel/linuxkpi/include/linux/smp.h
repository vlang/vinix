/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SMP_H
#define VINIX_LINUX_SMP_H
#include <linux/preempt.h>
#include <vinix/runtime.h>
/* Original CSD records, masks and SMP dispatch declarations have one owner. */
#include_next <linux/smp.h>

/* Keep the native scheduler pin; CPU queries use the asm/smp.h bridge. */
unsigned int vinix_get_cpu(void);
#undef get_cpu
#define get_cpu vinix_get_cpu
/* Linux masks, hotplug, smp_ops and remote dispatch remain unresolved. */
#endif
