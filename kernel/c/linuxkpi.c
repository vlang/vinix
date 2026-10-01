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
#include <vinix/runtime.h>
#include <drm/i915_pciids.h>

/* kmalloc uses contiguous physical pages. This first backend deliberately
 * trades space for an honest, fallible allocation path; no vmalloc fallback
 * may masquerade as DMA-capable kmalloc memory. */
struct allocation {
    size_t requested;
    size_t pages;
    void *base;
} __aligned(16);

static bool supported_gfp(gfp_t flags)
{
    /* Zone constraints, NOFAIL and memory-cgroup accounting need native
     * support. Flags promising those behaviors are never silently ignored. */
    const gfp_t supported = GFP_KERNEL | __GFP_HIGH | __GFP_ZERO | __GFP_NOWARN |
        __GFP_NORETRY | __GFP_RETRY_MAYFAIL;
    return !(flags & ~supported);
}

void *kmalloc(size_t size, gfp_t flags)
{
    if (!size) return ZERO_SIZE_PTR;
    if (!supported_gfp(flags)) return NULL;
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
    bool reclaim = (flags & GFP_KERNEL) == GFP_KERNEL && vinix_linuxkpi_may_sleep();
    void *base = vinix_linuxkpi_alloc_pages(pages, reclaim);
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
    spinlock_t lock;
    spin_lock_init(&lock);
    unsigned long flags;
    spin_lock_irqsave(&lock, flags);
    if (vinix_linuxkpi_may_sleep()) result = -EIO;
    void *atomic = kzalloc(48, GFP_ATOMIC);
    if (!atomic) result = -ENOMEM;
    kfree(atomic);
    spin_unlock_irqrestore(&lock, flags);
    if (!vinix_linuxkpi_tigerlake_id(0x8086, 0x9a49, 0x030000) ||
        vinix_linuxkpi_tigerlake_id(0x8086, 0x9a49, 0x020000) ||
        vinix_linuxkpi_tigerlake_id(0x1234, 0x9a49, 0x030000)) result = -EIO;
    return result;
}
#endif
