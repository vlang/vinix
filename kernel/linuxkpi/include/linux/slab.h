/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SLAB_H
#define VINIX_LINUX_SLAB_H
#include <linux/types.h>
/* Use the actual upstream flag definitions, including their numeric values. */
#include <linux/gfp_types.h>
#define ZERO_SIZE_PTR ((void *)16UL)
#define ZERO_OR_NULL_PTR(p) ((uintptr_t)(p) <= 16UL)
void *kmalloc(size_t, gfp_t) __must_check;
void *kzalloc(size_t, gfp_t) __must_check;
void *kmalloc_array(size_t, size_t, gfp_t) __must_check;
void *kcalloc(size_t, size_t, gfp_t) __must_check;
void *krealloc(const void *, size_t, gfp_t) __must_check;
void *kmemdup(const void *, size_t, gfp_t) __must_check;
size_t ksize(const void *);
void kfree(const void *);
#endif
