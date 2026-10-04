/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_PERCPU_H
#define VINIX_LINUX_PERCPU_H
#include <asm/percpu.h>
#include <linux/gfp_types.h>
void *__alloc_percpu_gfp(size_t size, size_t align, gfp_t flags);
void *__alloc_percpu(size_t size, size_t align);
void free_percpu(void *ptr);
#define alloc_percpu(type) ((__typeof__(type) *)__alloc_percpu(sizeof(type), __alignof__(type)))
#define alloc_percpu_gfp(type, flags) \
    ((__typeof__(type) *)__alloc_percpu_gfp(sizeof(type), __alignof__(type), flags))
#endif
