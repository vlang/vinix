/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_TYPES_H
#define VINIX_LINUX_TYPES_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef VINIX_LINUXKPI_HOST_TEST
/* Read libc types before Linux redefines compiler inline annotations. */
#include <sys/types.h>
#endif
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
#if defined(VINIX_LINUXKPI_HOST_TEST) && defined(__linux__)
/* libc uses a different C spelling for this ABI-identical host test type. */
#include <sys/types.h>
#else
typedef long long loff_t;
#endif
#define __aligned_u64 __u64 __aligned(8)
#define __aligned_s64 __s64 __aligned(8)
typedef unsigned long kernel_ulong_t;
typedef unsigned int uint;
typedef unsigned long ulong;
#define DECLARE_BITMAP(name, bits) unsigned long name[BITS_TO_LONGS(bits)]
#include <asm/posix_types.h>
#ifndef VINIX_LINUXKPI_HOST_TEST
typedef __kernel_pid_t pid_t;
typedef __kernel_clockid_t clockid_t;
typedef __kernel_clock_t clock_t;
typedef __kernel_uid32_t uid_t;
typedef __kernel_gid32_t gid_t;
typedef __kernel_mode_t mode_t;
#endif
struct callback_head {
    struct callback_head *next;
    void (*func)(struct callback_head *head);
} __aligned(sizeof(void *));
#define rcu_head callback_head
typedef void (*rcu_callback_t)(struct rcu_head *);
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
