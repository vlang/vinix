/* SPDX-License-Identifier: GPL-2.0-only */
/* Plain Linux 6.6.157 cache semantics on reusable native page slabs.
 * SLAB_TYPESAFE_BY_RCU and reclaim/accounting flags require native services
 * which are not implemented here and therefore fail cache creation. */
#ifdef VINIX_LINUXKPI
#include <linux/slab.h>
#include <linux/list.h>
#include <linux/spinlock.h>
#include <linux/string.h>
#include <linux/bug.h>
#include <vinix/gfp.h>
#include <vinix/runtime.h>

#define NATIVE_CACHE_MIN_ALIGN 16UL
#define NATIVE_CACHE_LINE 64UL

struct native_cache_slab;

/* Allocator links stay outside the payload: constructors initialize fresh
 * slots once, and freeing/reusing an object preserves its contents. */
struct native_cache_slot {
    struct native_cache_slab *slab;
    struct native_cache_slot *free_next;
    size_t index;
    bool allocated;
};

struct native_cache_slab {
    struct kmem_cache *owner;
    struct list_head all_node;
    struct list_head available_node;
    struct native_cache_slot *free_slots;
    void *objects;
    size_t capacity;
    size_t live;
    size_t pages;
};

struct kmem_cache {
    spinlock_t lock;
    struct list_head slabs;
    struct list_head available;
    char *name;
    unsigned int object_size;
    size_t alignment;
    size_t stride;
    size_t pages_per_slab;
    size_t live_objects;
    size_t active_refills;
    void (*ctor)(void *);
    bool closing;
};

static bool native_cache_geometry(unsigned int size, unsigned int requested,
                                  slab_flags_t flags, size_t *alignment,
                                  size_t *stride, size_t *pages)
{
    if (!size || (requested && (requested & (requested - 1)))) return false;
    size_t align = requested;
    if (flags & SLAB_HWCACHE_ALIGN) {
        size_t hardware = NATIVE_CACHE_LINE;
        while (size <= hardware / 2) hardware /= 2;
        if (align < hardware) align = hardware;
    }
    if (align < NATIVE_CACHE_MIN_ALIGN) align = NATIVE_CACHE_MIN_ALIGN;
    size_t step, minimum;
    if (__builtin_add_overflow(sizeof(struct native_cache_slot), (size_t)size, &step) ||
        __builtin_add_overflow(step, align - 1, &step)) return false;
    step &= ~(align - 1);
    if (__builtin_add_overflow(sizeof(struct native_cache_slab),
                               sizeof(struct native_cache_slot), &minimum) ||
        __builtin_add_overflow(minimum, align - 1, &minimum) ||
        __builtin_add_overflow(minimum, (size_t)size, &minimum)) return false;
    size_t page_size = vinix_linuxkpi_page_size();
    if (!page_size || (page_size & (page_size - 1)) ||
        __builtin_add_overflow(minimum, page_size - 1, &minimum)) return false;
    *alignment = align;
    *stride = step;
    *pages = minimum / page_size;
    return *pages != 0;
}

struct kmem_cache *kmem_cache_create(const char *name, unsigned int size,
                                    unsigned int alignment, slab_flags_t flags,
                                    void (*ctor)(void *))
{
    size_t actual_alignment, stride, pages, name_size;
    if (!name || !vinix_linuxkpi_may_sleep() || (flags & ~SLAB_HWCACHE_ALIGN) ||
        !native_cache_geometry(size, alignment, flags, &actual_alignment, &stride, &pages) ||
        __builtin_add_overflow(strlen(name), (size_t)1, &name_size)) return NULL;
    struct kmem_cache *cache = kzalloc(sizeof(*cache), GFP_KERNEL);
    if (!cache) return NULL;
    cache->name = kmalloc(name_size, GFP_KERNEL);
    if (!cache->name) {
        kfree(cache);
        return NULL;
    }
    memcpy(cache->name, name, name_size);
    spin_lock_init(&cache->lock);
    INIT_LIST_HEAD(&cache->slabs);
    INIT_LIST_HEAD(&cache->available);
    cache->object_size = size;
    cache->alignment = actual_alignment;
    cache->stride = stride;
    cache->pages_per_slab = pages;
    cache->ctor = ctor;
    return cache;
}

/* Called with no cache lock held. The refilling API call retains the cache;
 * its owner must stop all API users before destroying the descriptor. */
static struct native_cache_slab *native_cache_refill(struct kmem_cache *cache,
                                                    gfp_t flags)
{
    /* Linux SLUB new_slab warns at refill, even if backing allocation then
     * fails. Reusing an existing slot does not run this warning site. */
    WARN_ON_ONCE(cache->ctor && (flags & __GFP_ZERO));
    void *base = vinix_linuxkpi_alloc_gfp_pages(cache->pages_per_slab, flags);
    if (!base) return NULL;
    uintptr_t start, end;
    size_t bytes;
    if (__builtin_mul_overflow(cache->pages_per_slab, vinix_linuxkpi_page_size(), &bytes) ||
        __builtin_add_overflow((uintptr_t)base, bytes, &end) ||
        __builtin_add_overflow((uintptr_t)base, sizeof(struct native_cache_slab), &start) ||
        __builtin_add_overflow(start, sizeof(struct native_cache_slot), &start) ||
        __builtin_add_overflow(start, cache->alignment - 1, &start)) {
        vinix_linuxkpi_free_pages(base, cache->pages_per_slab);
        return NULL;
    }
    start &= ~(cache->alignment - 1);
    BUG_ON(start > end || cache->object_size > end - start);
    struct native_cache_slab *slab = base;
    slab->owner = cache;
    INIT_LIST_HEAD(&slab->all_node);
    INIT_LIST_HEAD(&slab->available_node);
    slab->objects = (void *)start;
    slab->capacity = 1 + (end - start - cache->object_size) / cache->stride;
    slab->live = 0;
    slab->pages = cache->pages_per_slab;
    slab->free_slots = NULL;
    for (size_t index = slab->capacity; index; index--) {
        void *object = (void *)(start + (index - 1) * cache->stride);
        struct native_cache_slot *slot = (struct native_cache_slot *)object - 1;
        slot->slab = slab;
        slot->free_next = slab->free_slots;
        slot->index = index - 1;
        slot->allocated = false;
        slab->free_slots = slot;
        /* Caller context is preserved: an atomic caller's ctor must not
         * sleep. No object is published until every ctor has returned. */
        if (cache->ctor) cache->ctor(object);
    }
    return slab;
}

static void *native_cache_take_locked(struct kmem_cache *cache,
                                      struct native_cache_slab *slab)
{
    struct native_cache_slot *slot = slab->free_slots;
    BUG_ON(!slot || slot->allocated || slot->slab != slab ||
           slab->live >= slab->capacity || cache->live_objects == (size_t)-1);
    slab->free_slots = slot->free_next;
    slot->free_next = NULL;
    slot->allocated = true;
    slab->live++;
    cache->live_objects++;
    if (!slab->free_slots) list_del_init(&slab->available_node);
    return slot + 1;
}

void *kmem_cache_alloc(struct kmem_cache *cache, gfp_t flags)
{
    /* Validate even reused slots: a fast path cannot silently honor an
     * unsupported zone, NOFAIL or accounting promise. */
    if (!cache || !vinix_linuxkpi_gfp_supported(flags)) return NULL;
    unsigned long irq;
    void *object;
    spin_lock_irqsave(&cache->lock, irq);
    BUG_ON(cache->closing);
    if (!list_empty(&cache->available)) {
        struct native_cache_slab *slab = list_entry(cache->available.next,
                                                   struct native_cache_slab,
                                                   available_node);
        object = native_cache_take_locked(cache, slab);
        spin_unlock_irqrestore(&cache->lock, irq);
    } else {
        BUG_ON(cache->active_refills == (size_t)-1);
        cache->active_refills++;
        spin_unlock_irqrestore(&cache->lock, irq);
        struct native_cache_slab *slab = native_cache_refill(cache, flags);
        spin_lock_irqsave(&cache->lock, irq);
        BUG_ON(!cache->active_refills || cache->closing);
        cache->active_refills--;
        if (!slab) {
            spin_unlock_irqrestore(&cache->lock, irq);
            return NULL;
        }
        list_add_tail(&slab->all_node, &cache->slabs);
        list_add_tail(&slab->available_node, &cache->available);
        object = native_cache_take_locked(cache, slab);
        spin_unlock_irqrestore(&cache->lock, irq);
    }
    if (flags & __GFP_ZERO) memset(object, 0, cache->object_size);
    return object;
}

void kmem_cache_free(struct kmem_cache *cache, void *object)
{
    if (!object) return;
    BUG_ON(!cache || (uintptr_t)object < sizeof(struct native_cache_slot));
    /* A live object pins this slab until its free operation drops live.
     * Wrong pointers, concurrent double free and access after free remain
     * invalid caller behavior, just as with the original slab API. */
    struct native_cache_slot *slot = (struct native_cache_slot *)object - 1;
    struct native_cache_slab *slab = slot->slab;
    unsigned long irq;
    spin_lock_irqsave(&cache->lock, irq);
    BUG_ON(slab->owner != cache || slot->index >= slab->capacity ||
           (uintptr_t)object != (uintptr_t)slab->objects + slot->index * cache->stride ||
           !slot->allocated || !slab->live || !cache->live_objects);
    bool was_full = slab->free_slots == NULL;
    slot->allocated = false;
    slot->free_next = slab->free_slots;
    slab->free_slots = slot;
    slab->live--;
    cache->live_objects--;
    if (was_full) list_add_tail(&slab->available_node, &cache->available);
    spin_unlock_irqrestore(&cache->lock, irq);
    /* Shrink may now release the last empty slab. No payload, slot or slab
     * field is read after unlocking. */
}

static void native_cache_release_slabs(struct list_head *slabs)
{
    while (!list_empty(slabs)) {
        struct native_cache_slab *slab = list_entry(slabs->next,
                                                   struct native_cache_slab,
                                                   all_node);
        size_t pages = slab->pages;
        list_del(&slab->all_node);
        vinix_linuxkpi_free_pages(slab, pages);
    }
}

int kmem_cache_shrink(struct kmem_cache *cache)
{
    /* The ordinary Linux implementation flushes CPU caches under sleeping
     * locks; preserve that API context even without native per-CPU slabs. */
    BUG_ON(!cache || !vinix_linuxkpi_may_sleep());
    LIST_HEAD(detached);
    unsigned long irq;
    spin_lock_irqsave(&cache->lock, irq);
    BUG_ON(cache->closing);
    struct list_head *node, *next;
    list_for_each_safe(node, next, &cache->slabs) {
        struct native_cache_slab *slab = list_entry(node, struct native_cache_slab,
                                                   all_node);
        if (slab->live) continue;
        list_del_init(&slab->available_node);
        list_move_tail(&slab->all_node, &detached);
    }
    int remaining = !list_empty(&cache->slabs) || cache->active_refills != 0;
    spin_unlock_irqrestore(&cache->lock, irq);
    native_cache_release_slabs(&detached);
    return remaining;
}

void kmem_cache_destroy(struct kmem_cache *cache)
{
    if (!cache) return;
    BUG_ON(!vinix_linuxkpi_may_sleep());
    LIST_HEAD(detached);
    unsigned long irq;
    spin_lock_irqsave(&cache->lock, irq);
    /* Destruction is quiescent: caller stops allocators, freers and all
     * other API users before releasing the last descriptor ownership. */
    BUG_ON(cache->closing || cache->live_objects || cache->active_refills);
    cache->closing = true;
    while (!list_empty(&cache->slabs)) {
        struct native_cache_slab *slab = list_entry(cache->slabs.next,
                                                   struct native_cache_slab,
                                                   all_node);
        BUG_ON(slab->live);
        list_del_init(&slab->available_node);
        list_move_tail(&slab->all_node, &detached);
    }
    spin_unlock_irqrestore(&cache->lock, irq);
    native_cache_release_slabs(&detached);
    kfree(cache->name);
    kfree(cache);
}

unsigned int kmem_cache_size(struct kmem_cache *cache)
{
    BUG_ON(!cache);
    return cache->object_size;
}
#endif
