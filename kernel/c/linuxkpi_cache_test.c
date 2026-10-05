/* SPDX-License-Identifier: GPL-2.0-only */
#if defined(VINIX_LINUXKPI) && !defined(VINIX_LINUXKPI_HOST_TEST)
#include <linux/kernel.h>
#include <linux/slab.h>
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <vinix/runtime.h>
#include <vinix/gfp.h>
#include <pthread.h>

#define NATIVE_CACHE_MAGIC 0x6b70692d63616368ULL
struct native_cache_object {
    u64 magic;
    unsigned int generation;
    unsigned char payload[85];
};
static unsigned int native_cache_ctor_calls;
static void native_cache_ctor(void *object)
{
    struct native_cache_object *value = object;
    value->magic = NATIVE_CACHE_MAGIC;
    value->generation = 0;
    memset(value->payload, 0x3c, sizeof(value->payload));
    __atomic_add_fetch(&native_cache_ctor_calls, 1, __ATOMIC_RELAXED);
}

static int native_cache_basic(void)
{
    int result = 0;
    /* Invalid page requests must not even consume the native one-shot fault,
     * so the next ordinary valid request still fails at the bridge. */
    vinix_linuxkpi_test_alloc_oom(0);
    if (vinix_linuxkpi_alloc_gfp_pages(0, GFP_KERNEL)) result = -EIO;
    if (vinix_linuxkpi_alloc_gfp_pages(SIZE_MAX / vinix_linuxkpi_page_size() + 1,
                                     GFP_KERNEL)) result = -EIO;
    void *unsupported_page = vinix_linuxkpi_alloc_gfp_pages(1, GFP_KERNEL | __GFP_DMA32);
    if (unsupported_page) {
        vinix_linuxkpi_free_pages(unsupported_page, 1);
        result = -EIO;
    }
    void *page_probe = vinix_linuxkpi_alloc_gfp_pages(1, GFP_KERNEL);
    vinix_linuxkpi_test_alloc_oom(-1);
    if (page_probe) { vinix_linuxkpi_free_pages(page_probe, 1); result = -EIO; }
    const slab_flags_t rejected[] = { SLAB_TYPESAFE_BY_RCU, SLAB_RECLAIM_ACCOUNT,
        SLAB_CACHE_DMA, SLAB_CACHE_DMA32, SLAB_PANIC, SLAB_POISON };
    for (unsigned int i = 0; i < ARRAY_SIZE(rejected); i++) {
        struct kmem_cache *unexpected = kmem_cache_create("native-rejected", 97,
            0, rejected[i], NULL);
        if (unexpected) { kmem_cache_destroy(unexpected); result = -EIO; }
    }
    unsigned long irq = vinix_linuxkpi_irq_save();
    struct kmem_cache *unexpected = kmem_cache_create("native-atomic-create", 97, 0, 0, NULL);
    vinix_linuxkpi_irq_restore(irq);
    if (unexpected) { kmem_cache_destroy(unexpected); result = -EIO; }
    for (int stage = 0; stage < 2; stage++) {
        vinix_linuxkpi_test_alloc_oom(stage);
        struct kmem_cache *failed = kmem_cache_create("native-create-rollback", 97, 0, 0, NULL);
        vinix_linuxkpi_test_alloc_oom(-1);
        if (failed) { kmem_cache_destroy(failed); result = -EIO; }
    }
    const unsigned int alignment[] = {0, 64, 256, 8192};
    for (unsigned int i = 0; i < ARRAY_SIZE(alignment); i++) {
        struct kmem_cache *cache = kmem_cache_create("native-alignment", 97,
            alignment[i], SLAB_HWCACHE_ALIGN, NULL);
        if (!cache) return -ENOMEM;
        unsigned long refill_irq = 0;
        if (!i) refill_irq = vinix_linuxkpi_irq_save();
        unsigned char *object = kmem_cache_zalloc(cache, GFP_KERNEL);
        if (!i && ((vinix_linuxkpi_irq_flags() & (1UL << 9)) ||
                   vinix_linuxkpi_preempt_count())) result = -EIO;
        if (!i) vinix_linuxkpi_irq_restore(refill_irq);
        if (!object) { kmem_cache_destroy(cache); return -ENOMEM; }
        if (kmem_cache_size(cache) != 97 ||
            ((uintptr_t)object & (max(alignment[i], 64U) - 1)) ||
            memchr_inv(object, 0, 97)) result = -EIO;
        memset(object, 0x79, 97);
        if (kmem_cache_shrink(cache) != 1 || memchr_inv(object, 0x79, 97)) result = -EIO;
        kmem_cache_free(cache, object);
        kmem_cache_free(cache, NULL);
        if (kmem_cache_shrink(cache)) result = -EIO;
        kmem_cache_destroy(cache);
    }

    struct native_cache_object *objects[128] = {0};
    unsigned int count = 0;
    struct kmem_cache *cache = kmem_cache_create("native-constructor",
        sizeof(*objects[0]), 0, SLAB_HWCACHE_ALIGN, native_cache_ctor);
    if (!cache) return -ENOMEM;
    vinix_linuxkpi_test_alloc_oom(0);
    struct native_cache_object *failed = kmem_cache_alloc(cache, GFP_KERNEL);
    vinix_linuxkpi_test_alloc_oom(-1);
    if (failed) { kmem_cache_free(cache, failed); result = -EIO; }
    if (kmem_cache_shrink(cache)) result = -EIO;
    objects[0] = kmem_cache_alloc(cache, GFP_KERNEL);
    if (!objects[0]) { kmem_cache_destroy(cache); return -ENOMEM; }
    count = 1;
    unsigned int constructors = __atomic_load_n(&native_cache_ctor_calls, __ATOMIC_ACQUIRE);
    vinix_linuxkpi_test_alloc_oom(0);
    while (count < ARRAY_SIZE(objects)) {
        objects[count] = kmem_cache_alloc(cache, GFP_ATOMIC);
        if (!objects[count]) break;
        count++;
    }
    if (count <= 1 || count == ARRAY_SIZE(objects) ||
        __atomic_load_n(&native_cache_ctor_calls, __ATOMIC_ACQUIRE) != constructors)
        result = -EIO;
    for (unsigned int i = 0; i < count; i++) {
        if (objects[i]->magic != NATIVE_CACHE_MAGIC || objects[i]->generation) result = -EIO;
        objects[i]->generation = i + 17;
        memset(objects[i]->payload, 0xb7, sizeof(objects[i]->payload));
        for (unsigned int j = 0; j < i; j++)
            if (objects[j] == objects[i]) result = -EIO;
    }
    struct native_cache_object *only_free = objects[0];
    kmem_cache_free(cache, only_free);
    objects[0] = NULL;
    vinix_linuxkpi_test_alloc_oom(0);
    const gfp_t rejected_gfp[] = { GFP_KERNEL | __GFP_DMA32,
        GFP_KERNEL | __GFP_NOFAIL, GFP_KERNEL | __GFP_ACCOUNT };
    for (unsigned int i = 0; i < ARRAY_SIZE(rejected_gfp); i++) {
        struct native_cache_object *bad = kmem_cache_alloc(cache, rejected_gfp[i]);
        if (bad) { kmem_cache_free(cache, bad); result = -EIO; }
    }
    irq = vinix_linuxkpi_irq_save();
    objects[0] = kmem_cache_alloc(cache, GFP_KERNEL);
    if ((vinix_linuxkpi_irq_flags() & (1UL << 9)) || vinix_linuxkpi_preempt_count()) result = -EIO;
    vinix_linuxkpi_irq_restore(irq);
    if (objects[0] != only_free || !objects[0] ||
        objects[0]->magic != NATIVE_CACHE_MAGIC || objects[0]->generation != 17 ||
        memchr_inv(objects[0]->payload, 0xb7, sizeof(objects[0]->payload))) result = -EIO;
    if (kmem_cache_shrink(cache) != 1) result = -EIO;
    for (unsigned int i = 0; i < count; i++) kmem_cache_free(cache, objects[i]);
    if (kmem_cache_shrink(cache)) result = -EIO;
    vinix_linuxkpi_test_alloc_oom(0);
    failed = kmem_cache_alloc(cache, GFP_NOWAIT);
    if (failed) { kmem_cache_free(cache, failed); result = -EIO; }
    vinix_linuxkpi_test_alloc_oom(-1);
    struct native_cache_object *zeroed = kmem_cache_zalloc(cache, GFP_KERNEL);
    if (!zeroed || memchr_inv(zeroed, 0, sizeof(*zeroed))) result = -EIO;
    kmem_cache_free(cache, zeroed);
    kmem_cache_destroy(cache);
    return result;
}

struct native_cache_worker {
    struct kmem_cache *cache;
    pthread_t thread;
    struct completion entered, go, held, release, done;
    unsigned int cpu, cancel;
    int result;
    bool initialized, started;
};
static void *native_cache_thread(void *argument)
{
    struct native_cache_worker *test = argument;
    test->result = vinix_linuxkpi_worker_bind(test->cpu);
    complete(&test->entered);
    wait_for_completion(&test->go);
    for (unsigned int repeat = 0; !test->result && repeat < 64 &&
        !__atomic_load_n(&test->cancel, __ATOMIC_ACQUIRE); repeat++) {
        struct native_cache_object *objects[16] = {0};
        unsigned int count = 0;
        for (; count < ARRAY_SIZE(objects); count++) {
            unsigned long irq = 0;
            if (repeat & 1) irq = vinix_linuxkpi_irq_save();
            objects[count] = kmem_cache_alloc(test->cache, (repeat & 1) ? GFP_ATOMIC : GFP_KERNEL);
            if (!!(vinix_linuxkpi_irq_flags() & (1UL << 9)) != !(repeat & 1) ||
                vinix_linuxkpi_preempt_count()) test->result = -EIO;
            if (repeat & 1) vinix_linuxkpi_irq_restore(irq);
            if (!objects[count]) { test->result = -ENOMEM; break; }
            if (objects[count]->magic != NATIVE_CACHE_MAGIC) test->result = -EIO;
            objects[count]->generation = test->cpu + 1;
            memset(objects[count]->payload, test->cpu, sizeof(objects[count]->payload));
        }
        if (!repeat) {
            complete(&test->held);
            wait_for_completion(&test->release);
        }
        for (unsigned int i = 0; i < count; i++) {
            if (objects[i]->generation != test->cpu + 1 ||
                memchr_inv(objects[i]->payload, test->cpu, sizeof(objects[i]->payload)))
                test->result = -EIO;
            kmem_cache_free(test->cache, objects[i]);
        }
        cond_resched();
        if (vinix_linuxkpi_cpu_id() != test->cpu || !vinix_linuxkpi_may_sleep()) test->result = -EIO;
    }
    complete(&test->done);
    pthread_exit(NULL);
    return NULL;
}

int vinix_linuxkpi_cache_native_selftest(void)
{
    int result = native_cache_basic();
    struct kmem_cache *cache = kmem_cache_create("native-concurrent",
        sizeof(struct native_cache_object), 0, SLAB_HWCACHE_ALIGN, native_cache_ctor);
    if (!cache) return -ENOMEM;
    struct native_cache_worker tests[4] = {0};
    unsigned int cpus = vinix_linuxkpi_percpu_count();
    if (!cpus || cpus > 64) { result = -EOPNOTSUPP; goto out; }
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) {
        tests[i].cache = cache;
        tests[i].cpu = i % cpus;
        init_completion(&tests[i].entered); init_completion(&tests[i].go);
        init_completion(&tests[i].held); init_completion(&tests[i].release);
        init_completion(&tests[i].done);
        tests[i].initialized = true;
        if (pthread_create(&tests[i].thread, NULL, native_cache_thread, &tests[i])) {
            result = -ENOMEM;
            goto out;
        }
        tests[i].started = true;
        if (!wait_for_completion_timeout(&tests[i].entered, 1000)) { result = -EIO; goto out; }
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) complete(&tests[i].go);
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++)
        if (!wait_for_completion_timeout(&tests[i].held, 1000)) { result = -EIO; goto out; }
    if (kmem_cache_shrink(cache) != 1) result = -EIO;
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) complete(&tests[i].release);
    for (unsigned int i = 0; i < 128; i++) {
        int left = kmem_cache_shrink(cache);
        if (left != 0 && left != 1) result = -EIO;
        cond_resched();
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++)
        if (!wait_for_completion_timeout(&tests[i].done, 1000)) { result = -EIO; goto out; }
out:
    /* Open every initialized gate before joining, including partial startup.
     * The pthread join owns worker lifetime; the shared cache survives them. */
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++) {
        __atomic_store_n(&tests[i].cancel, 1, __ATOMIC_RELEASE);
        if (tests[i].initialized) { complete_all(&tests[i].go); complete_all(&tests[i].release); }
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(tests); i++)
        if (tests[i].started && (pthread_join(tests[i].thread, NULL) || tests[i].result)) result = -EIO;
    if (kmem_cache_shrink(cache)) result = -EIO;
    kmem_cache_destroy(cache);
    return result;
}
#endif
