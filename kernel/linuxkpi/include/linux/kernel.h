/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_KERNEL_H
#define VINIX_LINUX_KERNEL_H
#include <linux/types.h>
#include <linux/limits.h>
#include <linux/kstrtox.h>
#include <linux/typecheck.h>
#include <linux/bug.h>
#include <vinix/runtime.h>
#include <vinix/integer_policy.h>
#include <linux/string.h>
#include <linux/log2.h>
#include <linux/minmax.h>
#include <linux/math.h>
#include <linux/align.h>
#include <linux/jump_label.h>
#include <linux/container_of.h>
#include <linux/panic.h>
#include <linux/printk.h>
#include <linux/sprintf.h>
/* Original split shifts also accept a 32-bit operand without shifting by 32. */
#define upper_32_bits(n) ((u32)(((n) >> 16) >> 16))
#define lower_32_bits(n) ((u32)((n) & 0xffffffff))
#define u64_to_user_ptr(x) (		\
{					\
	typecheck(u64, (x));		\
	(void __user *)(uintptr_t)(x);	\
}					\
)
#define container_of_safe(ptr, type, member) \
    ((ptr) ? container_of((ptr), type, member) : NULL)
#define might_sleep() BUG_ON(!vinix_linuxkpi_may_sleep())
#define might_sleep_if vinix_might_sleep_if
#endif
