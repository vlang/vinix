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
/* Original UAPI/asm integer aliases, endian/Sparse annotations and aligned
 * ABI types have one owner, including when UAPI headers are included first. */
#include <uapi/linux/types.h>
/* Original Linux internal device number: 12 major and 20 minor bits.
 * Native Stat fields have a separate u64 encoding and need an explicit bridge. */
typedef u32 __kernel_dev_t;
typedef __kernel_dev_t dev_t;
typedef unsigned int gfp_t;
#define pgoff_t unsigned long
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
