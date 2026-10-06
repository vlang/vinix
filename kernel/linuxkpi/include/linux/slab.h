/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SLAB_H
#define VINIX_LINUX_SLAB_H
#include <linux/types.h>
/* Use the actual upstream flag definitions, including their numeric values. */
#include <linux/gfp_types.h>
#ifdef __CHECKER__
typedef unsigned int __attribute__((bitwise)) slab_flags_t;
#else
typedef unsigned int slab_flags_t;
#endif
struct kmem_cache;

/* Linux 6.6.157 flag values. Disabled diagnostic/accounting facilities use
 * exactly the conditional definitions from that version; native caches
 * reject every remaining flag except SLAB_HWCACHE_ALIGN. */
#define SLAB_CONSISTENCY_CHECKS ((slab_flags_t __force)0x00000100U)
#define SLAB_RED_ZONE          ((slab_flags_t __force)0x00000400U)
#define SLAB_POISON            ((slab_flags_t __force)0x00000800U)
#define SLAB_KMALLOC           ((slab_flags_t __force)0x00001000U)
#define SLAB_HWCACHE_ALIGN     ((slab_flags_t __force)0x00002000U)
#define SLAB_CACHE_DMA         ((slab_flags_t __force)0x00004000U)
#define SLAB_CACHE_DMA32       ((slab_flags_t __force)0x00008000U)
#define SLAB_STORE_USER        ((slab_flags_t __force)0x00010000U)
#define SLAB_PANIC             ((slab_flags_t __force)0x00040000U)
#define SLAB_TYPESAFE_BY_RCU    ((slab_flags_t __force)0x00080000U)
#define SLAB_MEM_SPREAD        ((slab_flags_t __force)0x00100000U)
#define SLAB_TRACE             ((slab_flags_t __force)0x00200000U)
#ifdef CONFIG_DEBUG_OBJECTS
#define SLAB_DEBUG_OBJECTS     ((slab_flags_t __force)0x00400000U)
#else
#define SLAB_DEBUG_OBJECTS     0
#endif
#define SLAB_NOLEAKTRACE       ((slab_flags_t __force)0x00800000U)
#define SLAB_NO_MERGE          ((slab_flags_t __force)0x01000000U)
#ifdef CONFIG_FAILSLAB
#define SLAB_FAILSLAB          ((slab_flags_t __force)0x02000000U)
#else
#define SLAB_FAILSLAB          0
#endif
#ifdef CONFIG_MEMCG_KMEM
#define SLAB_ACCOUNT           ((slab_flags_t __force)0x04000000U)
#else
#define SLAB_ACCOUNT           0
#endif
#ifdef CONFIG_KASAN_GENERIC
#define SLAB_KASAN             ((slab_flags_t __force)0x08000000U)
#else
#define SLAB_KASAN             0
#endif
#define SLAB_NO_USER_FLAGS     ((slab_flags_t __force)0x10000000U)
#ifdef CONFIG_KFENCE
#define SLAB_SKIP_KFENCE       ((slab_flags_t __force)0x20000000U)
#else
#define SLAB_SKIP_KFENCE       0
#endif
#ifndef CONFIG_SLUB_TINY
#define SLAB_RECLAIM_ACCOUNT   ((slab_flags_t __force)0x00020000U)
#else
#define SLAB_RECLAIM_ACCOUNT   ((slab_flags_t __force)0)
#endif
#define SLAB_TEMPORARY SLAB_RECLAIM_ACCOUNT

struct kmem_cache *kmem_cache_create(const char *, unsigned int, unsigned int,
                                   slab_flags_t, void (*)(void *));
void kmem_cache_destroy(struct kmem_cache *);
int kmem_cache_shrink(struct kmem_cache *);
void *kmem_cache_alloc(struct kmem_cache *, gfp_t) __must_check;
void kmem_cache_free(struct kmem_cache *, void *);
unsigned int kmem_cache_size(struct kmem_cache *);
#define KMEM_CACHE(__struct, __flags) \
    kmem_cache_create(#__struct, sizeof(struct __struct), \
                     __alignof__(struct __struct), (__flags), NULL)
void *kmem_cache_zalloc(struct kmem_cache *, gfp_t);

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
