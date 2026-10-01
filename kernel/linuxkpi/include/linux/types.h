/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_TYPES_H
#define VINIX_LINUX_TYPES_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <linux/compiler.h>
#include <asm/bitsperlong.h>
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef unsigned long long u64;
typedef int8_t s8;
typedef int16_t s16;
typedef int32_t s32;
typedef long long s64;
typedef u8 __u8;
typedef u16 __u16;
typedef u32 __u32;
typedef u64 __u64;
typedef s8 __s8;
typedef s16 __s16;
typedef s32 __s32;
typedef s64 __s64;
typedef u16 __le16;
typedef u32 __le32;
typedef u64 __le64;
typedef u16 __be16;
typedef u32 __be32;
typedef u64 __be64;
typedef unsigned int gfp_t;
typedef u64 phys_addr_t;
typedef u64 dma_addr_t;
typedef u64 resource_size_t;
typedef long ssize_t;
#define __aligned_u64 __u64 __aligned(8)
#define __aligned_s64 __s64 __aligned(8)
typedef unsigned long kernel_ulong_t;
typedef unsigned long __kernel_ulong_t;
typedef long __kernel_long_t;
typedef int __kernel_pid_t;
typedef unsigned int __kernel_uid32_t;
typedef unsigned long __kernel_size_t;
struct list_head { struct list_head *next, *prev; };
struct hlist_head { struct hlist_node *first; };
struct hlist_node { struct hlist_node *next, **pprev; };
typedef void (*swap_r_func_t)(void *, void *, int, const void *);
typedef void (*swap_func_t)(void *, void *, int);
typedef int (*cmp_r_func_t)(const void *, const void *, const void *);
typedef int (*cmp_func_t)(const void *, const void *);
typedef struct { int counter; } atomic_t;
typedef struct { s64 counter; } atomic64_t;
#endif
