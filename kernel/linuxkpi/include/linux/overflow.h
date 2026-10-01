/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_OVERFLOW_H
#define VINIX_LINUX_OVERFLOW_H
#include <linux/types.h>
#define check_add_overflow(a, b, d) __builtin_add_overflow((a), (b), (d))
#define check_sub_overflow(a, b, d) __builtin_sub_overflow((a), (b), (d))
#define check_mul_overflow(a, b, d) __builtin_mul_overflow((a), (b), (d))
#define is_signed_type(t) (((t)-1) < (t)1)
#define type_max(t) ((t)((((t)1 << (sizeof(t) * 8 - 1 - is_signed_type(t))) - 1) * 2 + 1))
static inline size_t array_size(size_t a, size_t b) {
    size_t result;
    return check_mul_overflow(a, b, &result) ? SIZE_MAX : result;
}
static inline size_t size_add(size_t a, size_t b) {
    size_t result;
    return check_add_overflow(a, b, &result) ? SIZE_MAX : result;
}
static inline size_t size_mul(size_t a, size_t b) { return array_size(a, b); }
#endif
