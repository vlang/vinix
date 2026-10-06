/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_OVERFLOW_H
#define VINIX_LINUX_OVERFLOW_H
#include <linux/types.h>
#include <linux/compiler.h>
#include <linux/const.h>
#include <vinix/integer_policy.h>

size_t array_size(size_t, size_t);
size_t size_add(size_t, size_t);
size_t size_mul(size_t, size_t);
#endif
