/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef VINIX_LINUXKPI
#include <linux/kernel.h>
#include <linux/string.h>
#include <linux/slab.h>
#include <linux/errno.h>
#include <linux/list.h>
#include <linux/list_sort.h>
#include <linux/rbtree.h>
#include <linux/sort.h>
#include <linux/spinlock.h>
#include <linux/kref.h>
#include <linux/bitmap.h>
#include <asm/unaligned.h>
#include <linux/percpu.h>
#include <vinix/runtime.h>
#include <vinix/gfp.h>
#include <drm/i915_pciids.h>
#ifndef VINIX_LINUXKPI_HOST_TEST
#include <asm/fpu/api.h>
#include "i915_memcpy.h"
#endif

/* kmalloc uses contiguous physical pages. This first backend deliberately
 * trades space for an honest, fallible allocation path; no vmalloc fallback
 * may masquerade as DMA-capable kmalloc memory. */
struct allocation {
    size_t requested;
    size_t pages;
    void *base;
} __aligned(16);

bool vinix_linuxkpi_gfp_supported(gfp_t flags)
{
    /* Zone constraints, NOFAIL and memory-cgroup accounting need native
     * support. Flags promising those behaviors are never silently ignored. */
    const gfp_t supported = GFP_KERNEL | __GFP_HIGH | __GFP_ZERO | __GFP_NOWARN |
        __GFP_NORETRY | __GFP_RETRY_MAYFAIL;
    return !(flags & ~supported);
}

void *vinix_linuxkpi_alloc_gfp_pages(size_t pages, gfp_t flags)
{
    if (!pages || !vinix_linuxkpi_gfp_supported(flags)) return NULL;
    size_t page_size = vinix_linuxkpi_page_size();
    if (!page_size || pages > (size_t)-1 / page_size) return NULL;
    /* Only unrestricted sleepable requests may invoke native reclaimers.
     * Cache refills and kmalloc share this policy, including atomic callers. */
    bool reclaim = (flags & GFP_KERNEL) == GFP_KERNEL && vinix_linuxkpi_may_sleep();
    return vinix_linuxkpi_alloc_pages(pages, reclaim);
}

void *kmalloc(size_t size, gfp_t flags)
{
    if (!size) return ZERO_SIZE_PTR;
    if (!vinix_linuxkpi_gfp_supported(flags)) return NULL;
    size_t page_size = vinix_linuxkpi_page_size();
    /* kmalloc guarantees at least the largest power-of-two divisor of size;
     * power-of-two requests must be aligned to the complete request size. */
    size_t alignment = size & -size;
    if (alignment < 16) alignment = 16;
    size_t total;
    if (__builtin_add_overflow(size, sizeof(struct allocation), &total) ||
        __builtin_add_overflow(total, alignment - 1, &total) ||
        __builtin_add_overflow(total, page_size - 1, &total)) return NULL;
    size_t pages = total / page_size;
    /* GFP_ATOMIC/NOWAIT, GFP_NOFS/NOIO and IRQ/preempt-disabled callers take
     * the non-reclaiming PMM path. Only unrestricted sleepable requests may
     * invoke Vinix's reclaimers, which can recurse into filesystem code. */
    void *base = vinix_linuxkpi_alloc_gfp_pages(pages, flags);
    if (!base) return NULL;
    void *result = (void *)ALIGN((uintptr_t)base + sizeof(struct allocation), alignment);
    struct allocation *allocation = (struct allocation *)result - 1;
    allocation->requested = size;
    allocation->pages = pages;
    allocation->base = base;
    if (flags & __GFP_ZERO) memset(result, 0, size);
    return result;
}

void *kzalloc(size_t size, gfp_t flags) { return kmalloc(size, flags | __GFP_ZERO); }

void *kmalloc_array(size_t count, size_t size, gfp_t flags)
{
    size_t total;
    return __builtin_mul_overflow(count, size, &total) ? NULL : kmalloc(total, flags);
}

void *kcalloc(size_t count, size_t size, gfp_t flags)
{
    return kmalloc_array(count, size, flags | __GFP_ZERO);
}

size_t ksize(const void *ptr)
{
    if (ZERO_OR_NULL_PTR(ptr)) return 0;
    return ((const struct allocation *)ptr - 1)->requested;
}

void kfree(const void *ptr)
{
    if (ZERO_OR_NULL_PTR(ptr)) return;
    struct allocation *allocation = (struct allocation *)ptr - 1;
    size_t pages = allocation->pages;
    vinix_linuxkpi_free_pages(allocation->base, pages);
}

void *krealloc(const void *old, size_t size, gfp_t flags)
{
    if (!size) { kfree(old); return ZERO_SIZE_PTR; }
    void *result = kmalloc(size, flags);
    if (!result) return NULL;
    size_t previous = ksize(old);
    if (previous) memcpy(result, old, previous < size ? previous : size);
    kfree(old);
    return result;
}

void *kmemdup(const void *src, size_t size, gfp_t flags)
{
    void *result = kmalloc(size, flags);
    if (result && size) memcpy(result, src, size);
    return result;
}

struct pci_match {
    u32 vendor, device, subvendor, subdevice, class_code, class_mask;
    unsigned long data;
};
static const struct pci_match tigerlake[] = { INTEL_TGL_12_GT2_IDS(0) };

bool vinix_linuxkpi_tigerlake_id(u16 vendor, u16 device, u32 class_code)
{
    /* 9a49 is Tiger Lake-LP GT2 on the i5-1135G7. The upstream table is also
     * checked, so widening a match never silently invents supported hardware. */
    if (device != 0x9a49) return false;
    for (size_t i = 0; i < ARRAY_SIZE(tigerlake); i++) {
        const struct pci_match *id = &tigerlake[i];
        if (vendor == id->vendor && device == id->device &&
            (class_code & id->class_mask) == id->class_code) return true;
    }
    return false;
}

static int compare_int(const void *a, const void *b)
{
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}

struct test_node { int key; struct list_head list; struct rb_node tree; };
static DEFINE_PER_CPU_ALIGNED(unsigned long, percpu_probe) = 17;

static int compare_test_node(void *priv, const struct list_head *a, const struct list_head *b)
{
    (void)priv;
    const struct test_node *x = list_entry(a, struct test_node, list);
    const struct test_node *y = list_entry(b, struct test_node, list);
    return (x->key > y->key) - (x->key < y->key);
}

int vinix_linuxkpi_selftest(void)
{
    unsigned char *ptr = kzalloc(8193, GFP_KERNEL);
    if (!ptr) return -ENOMEM;
    for (size_t i = 0; i < 8193; i++) {
        if (ptr[i]) { kfree(ptr); return -EIO; }
        ptr[i] = (unsigned char)i;
    }
    void *grown = krealloc(ptr, 16385, GFP_KERNEL | __GFP_ZERO);
    if (!grown) { kfree(ptr); return -ENOMEM; }
    ptr = grown;
    int result = 0;
    unsigned long *local_probe = get_cpu_ptr(&percpu_probe);
    if (*local_probe != 17 || !preempt_count()) result = -EIO;
    this_cpu_add(percpu_probe, 5);
    if (this_cpu_read(percpu_probe) != 22) result = -EIO;
    this_cpu_write(percpu_probe, 17);
    put_cpu_ptr(local_probe);
    unsigned long *slots = alloc_percpu(unsigned long);
    if (!slots) result = -ENOMEM;
    else {
        unsigned int count = vinix_linuxkpi_percpu_count();
        for (unsigned int index = 0; index < count; index++) {
            unsigned long *slot = per_cpu_ptr(slots, index);
            if (*slot || per_cpu(percpu_probe, index) != 17) result = -EIO;
            *slot = 0x12345678UL + index;
        }
        for (unsigned int index = 0; index < count; index++) {
            if (*per_cpu_ptr(slots, index) != 0x12345678UL + index) result = -EIO;
        }
        free_percpu(slots);
    }
    for (size_t i = 0; i < 16385; i++) {
        unsigned char expected = i < 8193 ? (unsigned char)i : 0;
        if (ptr[i] != expected) result = -EIO;
    }
    kfree(ptr);
    int numbers[] = { 7, -1, 2, 0, 8, 2, -10 };
    sort(numbers, ARRAY_SIZE(numbers), sizeof(numbers[0]), compare_int, NULL);
    for (size_t i = 1; i < ARRAY_SIZE(numbers); i++) {
        if (numbers[i - 1] > numbers[i]) result = -EIO;
    }
    LIST_HEAD(head);
    struct rb_root root = RB_ROOT;
    struct test_node nodes[16];
    for (size_t i = 0; i < ARRAY_SIZE(nodes); i++) {
        nodes[i].key = (int)(i * 7 % ARRAY_SIZE(nodes));
        list_add_tail(&nodes[i].list, &head);
        struct rb_node **link = &root.rb_node, *parent = NULL;
        while (*link) {
            parent = *link;
            struct test_node *other = rb_entry(parent, struct test_node, tree);
            link = nodes[i].key < other->key ? &parent->rb_left : &parent->rb_right;
        }
        rb_link_node(&nodes[i].tree, parent, link);
        rb_insert_color(&nodes[i].tree, &root);
    }
    list_sort(NULL, &head, compare_test_node);
    size_t index = 0;
    struct test_node *node;
    list_for_each_entry(node, &head, list) {
        if (node->key != (int)index++) result = -EIO;
    }
    index = 0;
    for (struct rb_node *p = rb_first(&root); p; p = rb_next(p)) {
        if (rb_entry(p, struct test_node, tree)->key != (int)index++) result = -EIO;
    }
    for (size_t i = 0; i < ARRAY_SIZE(nodes); i++) rb_erase(&nodes[i].tree, &root);
    if (!RB_EMPTY_ROOT(&root)) result = -EIO;
    refcount_t refs = REFCOUNT_INIT(1);
    refcount_inc(&refs);
    if (refcount_dec_and_test(&refs) || !refcount_dec_and_test(&refs) ||
        refcount_inc_not_zero(&refs)) result = -EIO;
    atomic_long_t wide = ATOMIC_LONG_INIT(1L << 40);
    long expected = 1L << 40;
    if (!atomic_long_try_cmpxchg(&wide, &expected, expected + 1) ||
        atomic_long_read(&wide) != (1L << 40) + 1) result = -EIO;
    spinlock_t lock;
    spin_lock_init(&lock);
    unsigned long flags;
    spin_lock_irqsave(&lock, flags);
    if (vinix_linuxkpi_may_sleep()) result = -EIO;
    void *atomic = kzalloc(48, GFP_ATOMIC);
    if (!atomic) result = -ENOMEM;
    kfree(atomic);
    spin_unlock_irqrestore(&lock, flags);
    raw_spinlock_t raw;
    raw_spin_lock_init(&raw);
    raw_spin_lock(&raw);
    if (raw_spin_trylock_irqsave(&raw, flags)) {
        raw_spin_unlock_irqrestore(&raw, flags);
        result = -EIO;
    }
    raw_spin_unlock(&raw);
    if (!vinix_linuxkpi_may_sleep()) result = -EIO;
    DECLARE_BITMAP(bits, 129);
    bitmap_zero(bits, 129);
    set_bit(64, bits);
    set_bit(128, bits);
    if (find_first_bit(bits, 129) != 64 || find_next_bit(bits, 129, 65) != 128 ||
        find_next_bit(bits, 129, 129) != 129 || find_last_bit(bits, 129) != 128 ||
        find_nth_bit(bits, 129, 1) != 128 || hweight_long(bits[1]) != 1) result = -EIO;
    unsigned char encoded[10];
    put_unaligned_be64(0x123456789abcdef0ULL, encoded + 1);
    if (encoded[1] != 0x12 || encoded[8] != 0xf0 ||
        get_unaligned_be64(encoded + 1) != 0x123456789abcdef0ULL) result = -EIO;
    char text[8];
    if (strscpy_pad(text, "i915", sizeof(text)) != 4 ||
        memchr_inv(text + 4, 0, sizeof(text) - 4) ||
        strscpy(text, "truncated", 4) != -E2BIG || memcmp(text, "tru\0", 4)) result = -EIO;
    char *name = kstrndup("Tiger Lake", 5, GFP_KERNEL);
    if (!name) result = -ENOMEM;
    else if (strcmp(name, "Tiger")) result = -EIO;
    kfree(name);
    if (!vinix_linuxkpi_tigerlake_id(0x8086, 0x9a49, 0x030000) ||
        vinix_linuxkpi_tigerlake_id(0x8086, 0x9a49, 0x020000) ||
        vinix_linuxkpi_tigerlake_id(0x1234, 0x9a49, 0x030000)) result = -EIO;
    return result;
}

#ifndef VINIX_LINUXKPI_HOST_TEST
int vinix_linuxkpi_wc_selftest(void)
{
    _Alignas(16) u64 original[2], pattern[2] = { 0x1122334455667788ULL, 0xffeeddccbbaa0099ULL };
    _Alignas(16) u64 observed[2];
    _Alignas(16) unsigned char source[96], destination[96];
    unsigned int original_csr, observed_csr;
    int result = 0;
    /* Compatibility C is built with general registers only, like the native
     * kernel. Explicit SIMD use here verifies preservation of live state. */
    __asm__ volatile("movdqu %%xmm0, %0; stmxcsr %1" : "=m"(original), "=m"(original_csr) : : "memory");
    unsigned int test_csr = (original_csr & ~0x6000U) | 0x2000;
    __asm__ volatile("movdqu %0, %%xmm0; ldmxcsr %1" : : "m"(pattern), "m"(test_csr) : "memory");
    kernel_fpu_begin();
    __asm__ volatile("pxor %%xmm0, %%xmm0" : : : "memory");
    kernel_fpu_end();
    __asm__ volatile("movdqu %%xmm0, %0; stmxcsr %1" : "=m"(observed), "=m"(observed_csr) : : "memory");
    if (observed[0] != pattern[0] || observed[1] != pattern[1] || observed_csr != test_csr) result |= 1;
    for (size_t i = 0; i < sizeof(source); i++) source[i] = (unsigned char)i;
    memset(destination, 0xa5, sizeof(destination));
    bool accelerated = i915_has_memcpy_from_wc();
    if (i915_memcpy_from_wc(destination + 1, source, 32)) result |= 2;
    if (i915_memcpy_from_wc(destination, source, 64) != accelerated) result |= 4;
    if (accelerated) {
        if (memcmp(destination, source, 64)) result |= 8;
        i915_unaligned_memcpy_from_wc(destination + 3, source + 1, 33);
        if (memcmp(destination + 3, source + 1, 33)) result |= 16;
        __asm__ volatile("movdqu %%xmm0, %0; stmxcsr %1" : "=m"(observed), "=m"(observed_csr) : : "memory");
        if (observed[0] != pattern[0] || observed[1] != pattern[1] || observed_csr != test_csr) result |= 32;
    } else {
        for (size_t i = 0; i < sizeof(destination); i++) if (destination[i] != 0xa5) result |= 64;
    }
    __asm__ volatile("movdqu %0, %%xmm0; ldmxcsr %1" : : "m"(original), "m"(original_csr) : "memory");
    extern int kprintf(const char *, ...);
    if (!result) {
        kprintf("linuxkpi: unmodified i915 WC copy (%s) and FPU preservation passed\n",
                accelerated ? "SSE4.1" : "safe fallback");
    } else {
        kprintf("linuxkpi: WC copy failed checks 0x%x; XMM0 %llx:%llx, MXCSR %x (expected %x)\n",
                result, observed[1], observed[0], observed_csr, test_csr);
    }
    return result ? -EIO : 0;
}
#endif
#endif
