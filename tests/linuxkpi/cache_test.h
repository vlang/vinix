/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_CACHE_TEST_H
#define VINIX_LINUXKPI_CACHE_TEST_H
#include <vinix/gfp.h>

static void cache_test_page_policy(void)
{
    size_t before = live_pages;
    __atomic_store_n(&last_reclaim, false, __ATOMIC_RELAXED);
    __atomic_store_n(&allocation_failure_after, 1, __ATOMIC_RELAXED);
    assert(!vinix_linuxkpi_alloc_gfp_pages(0, GFP_KERNEL));
    assert(!vinix_linuxkpi_alloc_gfp_pages(SIZE_MAX / vinix_linuxkpi_page_size() + 1, GFP_KERNEL));
    assert(!vinix_linuxkpi_alloc_gfp_pages(1, GFP_KERNEL | __GFP_DMA32));
    assert(__atomic_load_n(&allocation_failure_after, __ATOMIC_RELAXED) == 1);
    assert(!__atomic_load_n(&last_reclaim, __ATOMIC_RELAXED) && live_pages == before);
    __atomic_store_n(&allocation_failure_after, -1, __ATOMIC_RELAXED);
    const gfp_t flags[] = {GFP_KERNEL, GFP_ATOMIC, GFP_NOWAIT, GFP_NOFS, GFP_NOIO};
    for (unsigned int i = 0; i < ARRAY_SIZE(flags); i++) {
        void *pages = vinix_linuxkpi_alloc_gfp_pages(1, flags[i]);
        assert(pages && __atomic_load_n(&last_reclaim, __ATOMIC_RELAXED) == (i == 0));
        vinix_linuxkpi_free_pages(pages, 1);
    }
    assert(live_pages == before);
}

struct cache_test_object {
    u64 magic;
    unsigned int generation;
    unsigned char payload[85];
};
#define CACHE_TEST_MAGIC 0x6b70692d63616368ULL
static unsigned int cache_test_ctor_calls;
static unsigned int cache_test_irq_ctor_calls, cache_test_preempt_ctor_calls;

static void cache_test_ctor(void *object)
{
    struct cache_test_object *value = object;
    value->magic = CACHE_TEST_MAGIC;
    value->generation = 0;
    memset(value->payload, 0x3c, sizeof(value->payload));
    __atomic_add_fetch(&cache_test_ctor_calls, 1, __ATOMIC_RELAXED);
    if (!interrupts) __atomic_add_fetch(&cache_test_irq_ctor_calls, 1, __ATOMIC_RELAXED);
    if (preempt_depth) __atomic_add_fetch(&cache_test_preempt_ctor_calls, 1, __ATOMIC_RELAXED);
}

static void cache_test_geometry_boundaries(void)
{
    const struct { unsigned int size, hardware_alignment; } cases[] = {
        {1, 16}, {7, 16}, {16, 16}, {17, 32}, {32, 32}, {33, 64},
        {64, 64}, {65, 64}, {4095, 64}, {4096, 64}, {4097, 64}, {8193, 64},
    };
    size_t before = live_pages;
    for (unsigned int hardware = 0; hardware < 2; hardware++) {
        for (unsigned int index = 0; index < ARRAY_SIZE(cases); index++) {
            unsigned int size = cases[index].size;
            unsigned int alignment = hardware ? cases[index].hardware_alignment : 16;
            struct kmem_cache *cache = kmem_cache_create("geometry-boundary", size,
                0, hardware ? SLAB_HWCACHE_ALIGN : 0, NULL);
            assert(cache && kmem_cache_size(cache) == size);
            unsigned char *objects[4];
            objects[0] = kmem_cache_zalloc(cache, GFP_KERNEL);
            assert(objects[0]);
            size_t populated = live_pages;
            /* Several small objects fit in already allocated backing: an
             * allocation fault must not turn cached capacity into failure. */
            if (size <= 65) __atomic_store_n(&allocation_failure_after, 0, __ATOMIC_RELAXED);
            for (unsigned int i = 1; i < ARRAY_SIZE(objects); i++) {
                objects[i] = kmem_cache_zalloc(cache, GFP_KERNEL);
                assert(objects[i]);
            }
            __atomic_store_n(&allocation_failure_after, -1, __ATOMIC_RELAXED);
            if (size <= 65) assert(live_pages == populated);
            for (unsigned int i = 0; i < ARRAY_SIZE(objects); i++) {
                assert(!((uintptr_t)objects[i] & (alignment - 1)));
                assert(!memchr_inv(objects[i], 0, size));
                for (unsigned int j = 0; j < i; j++) assert(objects[i] != objects[j]);
                memset(objects[i], i + 1, size);
            }
            assert(kmem_cache_shrink(cache) == 1);
            for (unsigned int i = 0; i < ARRAY_SIZE(objects); i++) {
                assert(!memchr_inv(objects[i], i + 1, size));
                kmem_cache_free(cache, objects[i]);
            }
            assert(!kmem_cache_shrink(cache));
            kmem_cache_destroy(cache);
            assert(live_pages == before);
        }
    }
}

static void cache_test_basic(void)
{
    size_t before = live_pages;
    cache_test_page_policy();
    cache_test_geometry_boundaries();
    const slab_flags_t rejected[] = {
        SLAB_TYPESAFE_BY_RCU, SLAB_RECLAIM_ACCOUNT, SLAB_CACHE_DMA,
        SLAB_CACHE_DMA32, SLAB_PANIC, SLAB_RED_ZONE, SLAB_POISON,
        SLAB_STORE_USER, SLAB_TRACE, SLAB_NO_MERGE, SLAB_NO_USER_FLAGS,
    };
    for (unsigned int i = 0; i < ARRAY_SIZE(rejected); i++)
        assert(!kmem_cache_create("unsupported", 97, 0, rejected[i], NULL));
    assert(!kmem_cache_create(NULL, 97, 0, 0, NULL));
    assert(!kmem_cache_create("empty", 0, 0, 0, NULL));
    assert(!kmem_cache_create("unaligned", 97, 3, 0, NULL));
    unsigned long irq = vinix_linuxkpi_irq_save();
    assert(!kmem_cache_create("atomic-create", 97, 0, 0, NULL));
    vinix_linuxkpi_irq_restore(irq);
    for (int stage = 0; stage < 2; stage++) {
        __atomic_store_n(&allocation_failure_after, stage, __ATOMIC_RELAXED);
        assert(!kmem_cache_create("create-rollback", 97, 0, 0, NULL));
        __atomic_store_n(&allocation_failure_after, -1, __ATOMIC_RELAXED);
        assert(live_pages == before);
    }

    const unsigned int alignments[] = {0, 16, 64, 256, 4096, 8192};
    for (unsigned int i = 0; i < ARRAY_SIZE(alignments); i++) {
        struct kmem_cache *cache = kmem_cache_create("alignment", 97,
            alignments[i], SLAB_HWCACHE_ALIGN, NULL);
        assert(cache && kmem_cache_size(cache) == 97);
        unsigned char *object = kmem_cache_zalloc(cache, GFP_KERNEL);
        assert(object && !((uintptr_t)object & (max(alignments[i], 64U) - 1)));
        assert(!memchr_inv(object, 0, 97));
        memset(object, 0xe1, 97);
        assert(kmem_cache_shrink(cache) == 1);
        assert(!memchr_inv(object, 0xe1, 97));
        kmem_cache_free(cache, object);
        kmem_cache_free(cache, NULL);
        assert(!kmem_cache_shrink(cache));
        kmem_cache_destroy(cache);
        assert(live_pages == before);
    }
    struct kmem_cache *atomic_cache = kmem_cache_create("atomic-refill",
        sizeof(struct cache_test_object), 0, 0, cache_test_ctor);
    assert(atomic_cache);
    unsigned int calls_before = cache_test_ctor_calls;
    unsigned int irq_calls_before = cache_test_irq_ctor_calls;
    irq = vinix_linuxkpi_irq_save();
    struct cache_test_object *atomic_object = kmem_cache_alloc(atomic_cache, GFP_KERNEL);
    assert(atomic_object && atomic_object->magic == CACHE_TEST_MAGIC);
    assert(!interrupts && !preempt_depth && !__atomic_load_n(&last_reclaim, __ATOMIC_RELAXED));
    vinix_linuxkpi_irq_restore(irq);
    assert(cache_test_ctor_calls > calls_before);
    assert(cache_test_ctor_calls - calls_before == cache_test_irq_ctor_calls - irq_calls_before);
    kmem_cache_free(atomic_cache, atomic_object);
    assert(!kmem_cache_shrink(atomic_cache));
    calls_before = cache_test_ctor_calls;
    unsigned int pinned_calls_before = cache_test_preempt_ctor_calls;
    vinix_linuxkpi_preempt_disable();
    atomic_object = kmem_cache_alloc(atomic_cache, GFP_KERNEL);
    assert(atomic_object && interrupts && preempt_depth == 1);
    assert(!__atomic_load_n(&last_reclaim, __ATOMIC_RELAXED));
    vinix_linuxkpi_preempt_enable();
    assert(cache_test_ctor_calls > calls_before);
    assert(cache_test_ctor_calls - calls_before == cache_test_preempt_ctor_calls - pinned_calls_before);
    kmem_cache_free(atomic_cache, atomic_object);
    kmem_cache_destroy(atomic_cache);
    assert(live_pages == before);

    struct cache_test_object *objects[256];
    struct kmem_cache *cache = kmem_cache_create("constructor", sizeof(*objects[0]),
        0, SLAB_HWCACHE_ALIGN, cache_test_ctor);
    assert(cache && kmem_cache_size(cache) == sizeof(*objects[0]));
    size_t descriptor_pages = live_pages;
    __atomic_store_n(&allocation_failure_after, 0, __ATOMIC_RELAXED);
    assert(!kmem_cache_alloc(cache, GFP_KERNEL));
    assert(live_pages == descriptor_pages && !kmem_cache_shrink(cache));
    __atomic_store_n(&allocation_failure_after, -1, __ATOMIC_RELAXED);
    objects[0] = kmem_cache_alloc(cache, GFP_KERNEL);
    assert(objects[0]);
    unsigned int constructors = __atomic_load_n(&cache_test_ctor_calls, __ATOMIC_ACQUIRE);
    __atomic_store_n(&allocation_failure_after, 0, __ATOMIC_RELAXED);
    unsigned int count = 1;
    while (count < ARRAY_SIZE(objects)) {
        objects[count] = kmem_cache_alloc(cache, GFP_ATOMIC);
        if (!objects[count]) break;
        count++;
    }
    assert(count > 1 && count < ARRAY_SIZE(objects));
    assert(!__atomic_load_n(&last_reclaim, __ATOMIC_RELAXED));
    assert(__atomic_load_n(&cache_test_ctor_calls, __ATOMIC_ACQUIRE) == constructors);
    for (unsigned int i = 0; i < count; i++) {
        assert(objects[i]->magic == CACHE_TEST_MAGIC && !objects[i]->generation);
        objects[i]->generation = i + 17;
        memset(objects[i]->payload, 0xb7, sizeof(objects[i]->payload));
        for (unsigned int j = 0; j < i; j++) assert(objects[j] != objects[i]);
    }
    struct cache_test_object *only_free = objects[0];
    kmem_cache_free(cache, only_free);
    const gfp_t bad_gfp[] = { GFP_KERNEL | __GFP_DMA32, GFP_KERNEL | __GFP_NOFAIL,
                             GFP_KERNEL | __GFP_ACCOUNT, GFP_KERNEL | __GFP_HIGHMEM };
    for (unsigned int i = 0; i < ARRAY_SIZE(bad_gfp); i++)
        assert(!kmem_cache_alloc(cache, bad_gfp[i]));
    irq = vinix_linuxkpi_irq_save();
    objects[0] = kmem_cache_alloc(cache, GFP_KERNEL);
    assert(objects[0] == only_free && !interrupts && !preempt_depth);
    vinix_linuxkpi_irq_restore(irq);
    assert(objects[0]->magic == CACHE_TEST_MAGIC && objects[0]->generation == 17);
    assert(!memchr_inv(objects[0]->payload, 0xb7, sizeof(objects[0]->payload)));
    assert(kmem_cache_shrink(cache) == 1);
    for (unsigned int i = 0; i < count; i++) kmem_cache_free(cache, objects[i]);
    assert(live_pages > descriptor_pages);
    assert(!kmem_cache_shrink(cache) && live_pages == descriptor_pages);
    assert(!kmem_cache_alloc(cache, GFP_NOWAIT));
    __atomic_store_n(&allocation_failure_after, -1, __ATOMIC_RELAXED);

    int warnings = atomic_read(&time_warnings);
    struct cache_test_object *zeroed = kmem_cache_zalloc(cache, GFP_KERNEL);
    assert(zeroed && !memchr_inv(zeroed, 0, sizeof(*zeroed)));
    assert(atomic_read(&time_warnings) == warnings + 1);
    kmem_cache_free(cache, zeroed);
    zeroed = kmem_cache_zalloc(cache, GFP_ATOMIC);
    assert(zeroed && !memchr_inv(zeroed, 0, sizeof(*zeroed)));
    assert(atomic_read(&time_warnings) == warnings + 1);
    kmem_cache_free(cache, zeroed);
    kmem_cache_destroy(cache);
    assert(live_pages == before);
    kmem_cache_destroy(NULL);
}

struct cache_test_gate {
    pthread_mutex_t lock;
    pthread_cond_t changed;
    bool entered, release;
    unsigned int claimed;
};
static struct cache_test_gate *cache_test_ctor_gate;
static void cache_test_gated_ctor(void *object)
{
    cache_test_ctor(object);
    struct cache_test_gate *gate = cache_test_ctor_gate;
    unsigned int expected = 0;
    if (!gate || !__atomic_compare_exchange_n(&gate->claimed, &expected, 1, false,
                                              __ATOMIC_ACQ_REL, __ATOMIC_RELAXED)) return;
    assert(interrupts && !preempt_depth && !pthread_mutex_lock(&gate->lock));
    gate->entered = true;
    assert(!pthread_cond_broadcast(&gate->changed));
    while (!gate->release) assert(!pthread_cond_wait(&gate->changed, &gate->lock));
    assert(!pthread_mutex_unlock(&gate->lock));
}
struct cache_test_refill {
    struct kmem_cache *cache;
    struct cache_test_object *object;
    unsigned int done;
};
static void *cache_test_refill_thread(void *argument)
{
    struct cache_test_refill *test = argument;
    test->object = kmem_cache_alloc(test->cache, GFP_KERNEL);
    assert(test->object && test->object->magic == CACHE_TEST_MAGIC);
    __atomic_store_n(&test->done, 1, __ATOMIC_RELEASE);
    return NULL;
}
static void cache_test_private_refill(void)
{
    size_t before = live_pages;
    struct cache_test_gate gate = { .lock = PTHREAD_MUTEX_INITIALIZER,
                                   .changed = PTHREAD_COND_INITIALIZER };
    struct kmem_cache *cache = kmem_cache_create("private-refill", sizeof(struct cache_test_object),
        0, 0, cache_test_gated_ctor);
    assert(cache);
    cache_test_ctor_gate = &gate;
    struct cache_test_refill tests[2] = { { .cache = cache }, { .cache = cache } };
    pthread_t threads[2];
    assert(!pthread_create(&threads[0], NULL, cache_test_refill_thread, &tests[0]));
    assert(!pthread_mutex_lock(&gate.lock));
    while (!gate.entered) assert(!pthread_cond_wait(&gate.changed, &gate.lock));
    assert(!pthread_mutex_unlock(&gate.lock));
    assert(kmem_cache_shrink(cache) == 1);
    assert(!pthread_create(&threads[1], NULL, cache_test_refill_thread, &tests[1]));
    for (unsigned int spin = 0; !__atomic_load_n(&tests[1].done, __ATOMIC_ACQUIRE); spin++) {
        assert(spin < 1000000);
        sched_yield();
    }
    assert(tests[1].object->magic == CACHE_TEST_MAGIC && !tests[0].done);
    assert(kmem_cache_shrink(cache) == 1);
    assert(!pthread_mutex_lock(&gate.lock));
    gate.release = true;
    assert(!pthread_cond_broadcast(&gate.changed));
    assert(!pthread_mutex_unlock(&gate.lock));
    for (unsigned int i = 0; i < 2; i++) assert(!pthread_join(threads[i], NULL));
    cache_test_ctor_gate = NULL;
    assert(tests[0].object != tests[1].object && tests[0].object->magic == CACHE_TEST_MAGIC);
    for (unsigned int i = 0; i < 2; i++) kmem_cache_free(cache, tests[i].object);
    assert(!kmem_cache_shrink(cache));
    kmem_cache_destroy(cache);
    assert(!pthread_cond_destroy(&gate.changed) && !pthread_mutex_destroy(&gate.lock));
    assert(live_pages == before);
}

struct cache_test_stress {
    struct kmem_cache *cache;
    unsigned int index, *go;
};
static void *cache_test_stress_thread(void *argument)
{
    struct cache_test_stress *test = argument;
    current_cpu = test->index;
    while (!__atomic_load_n(test->go, __ATOMIC_ACQUIRE)) sched_yield();
    for (unsigned int repeat = 0; repeat < 100; repeat++) {
        struct cache_test_object *objects[16];
        for (unsigned int i = 0; i < ARRAY_SIZE(objects); i++) {
            unsigned long irq = 0;
            if (repeat & 1) irq = vinix_linuxkpi_irq_save();
            objects[i] = kmem_cache_alloc(test->cache, (repeat & 1) ? GFP_ATOMIC : GFP_KERNEL);
            assert(objects[i] && objects[i]->magic == CACHE_TEST_MAGIC);
            assert(interrupts == !(repeat & 1) && !preempt_depth);
            if (repeat & 1) vinix_linuxkpi_irq_restore(irq);
            objects[i]->generation = test->index + 1;
            memset(objects[i]->payload, test->index, sizeof(objects[i]->payload));
        }
        for (unsigned int i = 0; i < ARRAY_SIZE(objects); i++) {
            assert(objects[i]->generation == test->index + 1);
            assert(!memchr_inv(objects[i]->payload, test->index, sizeof(objects[i]->payload)));
            kmem_cache_free(test->cache, objects[i]);
        }
        sched_yield();
    }
    return NULL;
}
static void cache_tests(void)
{
    size_t before = live_pages;
    cache_test_basic();
    cache_test_private_refill();
    struct kmem_cache *cache = kmem_cache_create("concurrent", sizeof(struct cache_test_object),
        0, SLAB_HWCACHE_ALIGN, cache_test_ctor);
    assert(cache);
    struct cache_test_stress tests[4];
    pthread_t threads[4];
    unsigned int go = 0;
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) {
        tests[i] = (struct cache_test_stress){ .cache = cache, .index = i, .go = &go };
        assert(!pthread_create(&threads[i], NULL, cache_test_stress_thread, &tests[i]));
    }
    __atomic_store_n(&go, 1, __ATOMIC_RELEASE);
    for (unsigned int i = 0; i < 1000; i++) {
        int left = kmem_cache_shrink(cache);
        assert(left == 0 || left == 1);
        sched_yield();
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) assert(!pthread_join(threads[i], NULL));
    assert(!kmem_cache_shrink(cache));
    kmem_cache_destroy(cache);
    assert(live_pages == before && interrupts && !preempt_depth);
}
#endif
