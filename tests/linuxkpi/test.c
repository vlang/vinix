/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <linux/atomic.h>
#include <linux/err.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/bits.h>
#include <linux/list.h>
#include <linux/list_sort.h>
#include <linux/rbtree_augmented.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/string.h>
#include <vinix/runtime.h>

static size_t live_pages;
static bool fail_allocation;
static bool last_reclaim;
static _Thread_local bool interrupts = true;
static _Thread_local unsigned int preempt_depth;

void *vinix_linuxkpi_alloc_pages(size_t pages, bool reclaim)
{
    last_reclaim = reclaim;
    if (fail_allocation) return NULL;
    void *ptr = NULL;
    if (posix_memalign(&ptr, 4096, pages * 4096)) return NULL;
    memset(ptr, 0xa5, pages * 4096);
    live_pages += pages;
    return ptr;
}

void vinix_linuxkpi_free_pages(void *base, size_t pages)
{
    assert(live_pages >= pages);
    live_pages -= pages;
    free(base);
}

size_t vinix_linuxkpi_page_size(void) { return 4096; }
void vinix_linuxkpi_bug(const char *file, int line)
{
    fprintf(stderr, "Linux compatibility BUG at %s:%d\n", file, line);
    abort();
}

unsigned long vinix_linuxkpi_irq_save(void)
{
    unsigned long flags = interrupts ? 1UL << 9 : 0;
    interrupts = false;
    return flags;
}

void vinix_linuxkpi_irq_restore(unsigned long flags) { interrupts = !!(flags & (1UL << 9)); }
void vinix_linuxkpi_spin_wait(void) { __asm__ volatile("" ::: "memory"); }
void vinix_linuxkpi_preempt_disable(void) { preempt_depth++; }
void vinix_linuxkpi_preempt_enable(void) { assert(preempt_depth); preempt_depth--; }
bool vinix_linuxkpi_may_sleep(void) { return interrupts && !preempt_depth; }

static void allocation_tests(void)
{
    assert(type_max(s8) == 127 && type_max(u8) == 255);
    assert(type_max(s64) == 0x7fffffffffffffffLL && type_max(u64) == ~0ULL);
    assert(GENMASK_ULL(39, 21) == 0x000000ffffe00000ULL);
    assert(vinix_linuxkpi_selftest() == 0);
    assert(live_pages == 0);
    assert(kmalloc(0, GFP_KERNEL) == ZERO_SIZE_PTR);
    assert(ksize(ZERO_SIZE_PTR) == 0);
    kfree(NULL);
    kfree(ZERO_SIZE_PTR);
    assert(kmalloc(SIZE_MAX, GFP_KERNEL) == NULL);
    assert(kmalloc_array(SIZE_MAX, 2, GFP_KERNEL) == NULL);
    assert(kcalloc(2, SIZE_MAX, GFP_KERNEL) == NULL);
    const gfp_t non_reclaiming[] = { GFP_ATOMIC, GFP_NOWAIT, GFP_NOFS, GFP_NOIO };
    for (size_t i = 0; i < ARRAY_SIZE(non_reclaiming); i++) {
        void *ptr = kmalloc(32, non_reclaiming[i]);
        assert(ptr && !last_reclaim);
        kfree(ptr);
    }
    interrupts = false;
    void *atomic_ptr = kmalloc(32, GFP_KERNEL);
    assert(atomic_ptr && !last_reclaim);
    kfree(atomic_ptr);
    interrupts = true;
    assert(kmalloc(32, GFP_KERNEL | __GFP_DMA32) == NULL);
    assert(kmalloc(32, GFP_KERNEL | __GFP_NOFAIL) == NULL);
    assert(kmalloc(32, GFP_KERNEL | __GFP_ACCOUNT) == NULL);
    for (size_t n = 16; n <= 16384; n *= 2) {
        void *ptr = kmalloc(n, GFP_KERNEL);
        assert(ptr && (uintptr_t)ptr % n == 0 && last_reclaim);
        kfree(ptr);
    }
    for (size_t n = 1; n < 25000; n = n * 2 + 1) {
        unsigned char *ptr = kcalloc(n, 1, GFP_KERNEL);
        assert(ptr && (uintptr_t)ptr % 16 == 0 && ksize(ptr) == n);
        for (size_t i = 0; i < n; i++) assert(ptr[i] == 0);
        memset(ptr, 0x6f, n);
        fail_allocation = true;
        assert(krealloc(ptr, n + 17, GFP_KERNEL) == NULL);
        for (size_t i = 0; i < n; i++) assert(ptr[i] == 0x6f);
        fail_allocation = false;
        unsigned char *grown = krealloc(ptr, n + 17, GFP_KERNEL | __GFP_ZERO);
        assert(grown && ksize(grown) == n + 17);
        for (size_t i = 0; i < n + 17; i++) assert(grown[i] == (i < n ? 0x6f : 0));
        unsigned char *duplicate = kmemdup(grown, n + 17, GFP_KERNEL);
        assert(duplicate && !memcmp(duplicate, grown, n + 17));
        kfree(duplicate);
        assert(krealloc(grown, 0, GFP_KERNEL) == ZERO_SIZE_PTR);
        assert(live_pages == 0);
    }
    assert(PTR_ERR(ERR_PTR(-ENOMEM)) == -ENOMEM);
    assert(IS_ERR(ERR_PTR(-ENOMEM)) && IS_ERR_OR_NULL(NULL));
    assert(!IS_ERR((void *)4096) && PTR_ERR_OR_ZERO((void *)4096) == 0);
}

struct entry { int key, order; struct list_head link; struct rb_node tree; };
#define COUNT 4096
static struct entry entries[COUNT];

static int compare_list(void *priv, const struct list_head *a, const struct list_head *b)
{
    (void)priv;
    const struct entry *x = list_entry(a, struct entry, link);
    const struct entry *y = list_entry(b, struct entry, link);
    return (x->key > y->key) - (x->key < y->key);
}

static void list_tests(void)
{
    LIST_HEAD(head);
    list_sort(NULL, &head, compare_list);
    assert(list_empty(&head));
    for (int i = 0; i < COUNT; i++) {
        entries[i].key = (i * 73) % 127;
        entries[i].order = i;
        list_add_tail(&entries[i].link, &head);
    }
    list_sort(NULL, &head, compare_list);
    int count = 0;
    struct entry *entry, *previous = NULL;
    list_for_each_entry(entry, &head, link) {
        assert(entry->link.next->prev == &entry->link && entry->link.prev->next == &entry->link);
        if (previous) {
            assert(previous->key <= entry->key);
            if (previous->key == entry->key) assert(previous->order < entry->order);
        }
        previous = entry;
        count++;
    }
    assert(count == COUNT);
    struct entry *next;
    list_for_each_entry_safe(entry, next, &head, link) list_del_init(&entry->link);
    assert(list_empty(&head));
}

static int tree_height(const struct rb_node *node)
{
    if (!node) return 1;
    if (node->rb_left) assert(rb_parent(node->rb_left) == node);
    if (node->rb_right) assert(rb_parent(node->rb_right) == node);
    bool black = node->__rb_parent_color & 1;
    if (!black) {
        assert(!node->rb_left || (node->rb_left->__rb_parent_color & 1));
        assert(!node->rb_right || (node->rb_right->__rb_parent_color & 1));
    }
    int left = tree_height(node->rb_left), right = tree_height(node->rb_right);
    assert(left == right);
    return left + black;
}

static void tree_tests(void)
{
    struct rb_root root = RB_ROOT;
    for (int i = 0; i < COUNT; i++) {
        entries[i].key = (i * 73) % COUNT;
        struct rb_node **link = &root.rb_node, *parent = NULL;
        while (*link) {
            parent = *link;
            struct entry *other = rb_entry(parent, struct entry, tree);
            link = entries[i].key < other->key ? &parent->rb_left : &parent->rb_right;
        }
        rb_link_node(&entries[i].tree, parent, link);
        rb_insert_color(&entries[i].tree, &root);
        assert(root.rb_node->__rb_parent_color & 1);
        tree_height(root.rb_node);
    }
    int expected = 0;
    for (struct rb_node *p = rb_first(&root); p; p = rb_next(p)) {
        assert(rb_entry(p, struct entry, tree)->key == expected++);
    }
    assert(expected == COUNT);
    for (int i = 0; i < COUNT; i++) {
        rb_erase(&entries[(i * 61) % COUNT].tree, &root);
        tree_height(root.rb_node);
    }
    assert(RB_EMPTY_ROOT(&root));
}

static atomic_t counter = ATOMIC_INIT(0);
static spinlock_t lock = __SPIN_LOCK_UNLOCKED(lock);
static unsigned int locked_count;

static void *concurrent_worker(void *arg)
{
    (void)arg;
    for (int i = 0; i < 50000; i++) {
        unsigned long flags;
        atomic_inc(&counter);
        spin_lock_irqsave(&lock, flags);
        assert(!interrupts && preempt_depth == 1);
        locked_count++;
        spin_unlock_irqrestore(&lock, flags);
        assert(interrupts && preempt_depth == 0);
    }
    return NULL;
}

static void concurrency_tests(void)
{
    pthread_t threads[4];
    for (size_t i = 0; i < ARRAY_SIZE(threads); i++) assert(!pthread_create(&threads[i], NULL, concurrent_worker, NULL));
    for (size_t i = 0; i < ARRAY_SIZE(threads); i++) assert(!pthread_join(threads[i], NULL));
    assert(atomic_read(&counter) == 200000 && locked_count == 200000);
    assert(atomic_cmpxchg(&counter, 0, 7) == 200000);
    assert(atomic_cmpxchg(&counter, 200000, 7) == 200000);
    assert(atomic_xchg(&counter, 1) == 7 && atomic_dec_and_test(&counter));
    atomic64_t big = ATOMIC64_INIT(1LL << 40);
    assert(atomic64_inc_return(&big) == (1LL << 40) + 1);
    spinlock_t outer, inner;
    spin_lock_init(&outer);
    spin_lock_init(&inner);
    unsigned long outer_flags, inner_flags;
    spin_lock_irqsave(&outer, outer_flags);
    assert(!spin_trylock(&outer) && preempt_depth == 1);
    spin_lock_irqsave(&inner, inner_flags);
    assert(preempt_depth == 2 && !interrupts);
    spin_unlock_irqrestore(&inner, inner_flags);
    assert(preempt_depth == 1 && !interrupts);
    spin_unlock_irqrestore(&outer, outer_flags);
    assert(preempt_depth == 0 && interrupts);
}

int main(void)
{
    allocation_tests();
    list_tests();
    tree_tests();
    concurrency_tests();
    assert(live_pages == 0);
    puts("LinuxKPI: PASS (unmodified Linux helpers, allocation/OOM, tree/list invariants, SMP locks)");
    return 0;
}
