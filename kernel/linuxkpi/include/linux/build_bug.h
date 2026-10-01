/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_BUILD_BUG_H
#define VINIX_LINUX_BUILD_BUG_H
#include <linux/compiler.h>
#include <linux/bug.h>
#define BUILD_BUG_ON_ZERO(e) (sizeof(struct { int : -!!(e); }))
#ifndef static_assert
#define static_assert(condition, ...) _Static_assert(condition, "" __VA_ARGS__)
#endif
#endif
