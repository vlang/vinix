/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_KERNEL_H
#define VINIX_LINUX_KERNEL_H
#include <linux/types.h>
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#include <linux/container_of.h>
#define container_of_safe(ptr, type, member) \
    ((ptr) ? container_of((ptr), type, member) : NULL)
#define min(a, b) ({ __auto_type __a = (a); __auto_type __b = (b); __a < __b ? __a : __b; })
#define max(a, b) ({ __auto_type __a = (a); __auto_type __b = (b); __a > __b ? __a : __b; })
#define min_t(t, a, b) min((t)(a), (t)(b))
#define max_t(t, a, b) max((t)(a), (t)(b))
#define swap(a, b) do { __typeof__(a) __tmp = (a); (a) = (b); (b) = __tmp; } while (0)
#define IS_ALIGNED(x, a) (((x) & ((__typeof__(x))(a) - 1)) == 0)
#define ALIGN(x, a) (((x) + ((__typeof__(x))(a) - 1)) & ~((__typeof__(x))(a) - 1))
#endif
