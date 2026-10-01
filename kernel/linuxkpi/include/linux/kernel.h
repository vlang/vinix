/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_KERNEL_H
#define VINIX_LINUX_KERNEL_H
#include <linux/types.h>
#include <linux/string.h>
#include <linux/minmax.h>
#include <linux/math.h>
#include <linux/jump_label.h>
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#include <linux/container_of.h>
#define container_of_safe(ptr, type, member) \
    ((ptr) ? container_of((ptr), type, member) : NULL)
#define IS_ALIGNED(x, a) (((x) & ((__typeof__(x))(a) - 1)) == 0)
#define ALIGN(x, a) (((x) + ((__typeof__(x))(a) - 1)) & ~((__typeof__(x))(a) - 1))
#endif
