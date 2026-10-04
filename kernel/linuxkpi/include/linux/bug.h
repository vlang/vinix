/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_BUG_H
#define VINIX_LINUX_BUG_H
#include <linux/types.h>
#include <linux/compiler.h>
#include <linux/build_bug.h>
#include <vinix/printk.h>
void vinix_linuxkpi_bug(const char *, int) __noreturn;
void vinix_linuxkpi_warn(const char *, int);
#define BUG() vinix_linuxkpi_bug(__FILE__, __LINE__)
#define BUG_ON(condition) do { if (unlikely(condition)) BUG(); } while (0)
#define WARN_ON(condition) ({ \
    bool __vinix_warning = !!(condition); \
    if (unlikely(__vinix_warning)) vinix_linuxkpi_warn(__FILE__, __LINE__); \
    __vinix_warning; \
})
#define WARN_ON_ONCE(condition) ({ \
    static bool __vinix_warned; \
    bool __vinix_warning = !!(condition); \
    if (unlikely(__vinix_warning) && !__atomic_exchange_n(&__vinix_warned, true, __ATOMIC_RELAXED)) \
        vinix_linuxkpi_warn(__FILE__, __LINE__); \
    __vinix_warning; \
})
#define WARN(condition, format, ...) ({ \
    bool __vinix_warning = !!(condition); \
    if (unlikely(__vinix_warning)) \
        vinix_linuxkpi_warn_format(__FILE__, __LINE__, format, ##__VA_ARGS__); \
    __vinix_warning; \
})
#define WARN_ONCE(condition, format, ...) ({ \
    static bool __vinix_warned; \
    bool __vinix_warning = !!(condition); \
    if (unlikely(__vinix_warning) && !__atomic_exchange_n(&__vinix_warned, true, __ATOMIC_RELAXED)) \
        vinix_linuxkpi_warn_format(__FILE__, __LINE__, format, ##__VA_ARGS__); \
    __vinix_warning; \
})
#endif
