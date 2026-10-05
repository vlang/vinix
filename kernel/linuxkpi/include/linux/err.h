/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_ERR_H
#define VINIX_LINUX_ERR_H
#include <linux/types.h>
#define MAX_ERRNO 4095
static inline void *ERR_PTR(long error) { return (void *)(intptr_t)error; }
static inline long PTR_ERR(const void *ptr) { return (long)(intptr_t)ptr; }
static inline bool IS_ERR(const void *ptr) { return (uintptr_t)ptr >= (uintptr_t)-MAX_ERRNO; }
static inline bool IS_ERR_OR_NULL(const void *ptr) { return !ptr || IS_ERR(ptr); }
static inline int PTR_ERR_OR_ZERO(const void *ptr) { return IS_ERR(ptr) ? (int)PTR_ERR(ptr) : 0; }
#endif
