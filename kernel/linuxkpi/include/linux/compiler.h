/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_COMPILER_H
#define VINIX_LINUX_COMPILER_H
#include <stdbool.h>
#include <stddef.h>
#include <linux/kconfig.h>
#ifndef __always_inline
#define __always_inline inline __attribute__((always_inline))
#endif
#define __attribute_const__ __attribute__((const))
#ifndef __pure
#define __pure __attribute__((pure))
#endif
#define __must_check __attribute__((warn_unused_result))
#define __packed __attribute__((packed))
#define __aligned(n) __attribute__((aligned(n)))
#define __noreturn __attribute__((noreturn))
#ifndef __cold
#define __cold __attribute__((cold))
#endif
#define __maybe_unused __attribute__((unused))
#define __user
#define __iomem
#define __rcu
#define __force
#define __bitwise
#define likely(x) __builtin_expect(!!(x), 1)
#define unlikely(x) __builtin_expect(!!(x), 0)
#define barrier() __asm__ volatile("" ::: "memory")
#define READ_ONCE(x) (*(volatile __typeof__(x) *)&(x))
#define WRITE_ONCE(x, v) do { (*(volatile __typeof__(x) *)&(x)) = (v); } while (0)
#define __same_type(a, b) __builtin_types_compatible_p(__typeof__(a), __typeof__(b))
#define __PASTE(a, b) a##b
#define __PASTE_EXPAND(a, b) __PASTE(a, b)
#define __UNIQUE_ID(prefix) __PASTE_EXPAND(prefix, __COUNTER__)
#define __no_sanitize_or_inline __always_inline
#endif
