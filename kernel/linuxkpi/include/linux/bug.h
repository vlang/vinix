/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_BUG_H
#define VINIX_LINUX_BUG_H
#include <linux/compiler.h>
#include <linux/build_bug.h>
void vinix_linuxkpi_bug(const char *, int) __noreturn;
#define BUG() vinix_linuxkpi_bug(__FILE__, __LINE__)
#define BUG_ON(condition) do { if (unlikely(condition)) BUG(); } while (0)
#endif
