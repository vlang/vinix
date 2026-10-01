/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <linux/atomic.h>
#include <linux/err.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/kref.h>
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
static atomic_t refcount_warnings = ATOMIC_INIT(0);

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
void vinix_linuxkpi_refcount_warning(int kind)
{
    assert(kind >= REFCOUNT_ADD_NOT_ZERO_OVF && kind <= REFCOUNT_DEC_LEAK);
    atomic_inc(&refcount_warnings);
}

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

static void atomic_api_tests(void)
{
    atomic_t value = ATOMIC_INIT(INT_MAX);
    assert(atomic_fetch_inc_relaxed(&value) == INT_MAX);
    assert(atomic_read(&value) == INT_MIN);
    int old = 7;
    assert(!atomic_try_cmpxchg_acquire(&value, &old, 4) && old == INT_MIN);
    assert(atomic_try_cmpxchg_release(&value, &old, 4));
    assert(atomic_fetch_andnot(1, &value) == 4 && atomic_read(&value) == 4);
    atomic_or(3, &value);
    assert(atomic_fetch_xor_acquire(2, &value) == 7 && atomic_read(&value) == 5);
    assert(atomic_add_unless(&value, -1, 0) && atomic_read(&value) == 4);
    atomic_set(&value, 0);
    assert(!atomic_inc_not_zero(&value));
    atomic64_t big = ATOMIC64_INIT(S64_MAX);
    assert(atomic64_add_return_relaxed(1, &big) == S64_MIN);
    s64 previous = 0;
    assert(!atomic64_try_cmpxchg_relaxed(&big, &previous, 0) && previous == S64_MIN);
    assert(atomic64_try_cmpxchg(&big, &previous, 0));
    atomic_long_t wide = ATOMIC_LONG_INIT(1L << 40);
    assert(atomic_long_fetch_add_release(1L << 40, &wide) == 1L << 40);
    assert(atomic_long_read_acquire(&wide) == 1L << 41);
    unsigned long bits = 7;
    assert(xchg(&bits, 9) == 7);
    assert(cmpxchg_acquire(&bits, 9, 11) == 9 && bits == 11);
    unsigned long expected = 0;
    assert(!try_cmpxchg_release(&bits, &expected, 0) && expected == 11);
    assert(try_cmpxchg(&bits, &expected, 0) && bits == 0);
}

static atomic_t published = ATOMIC_INIT(0);
static u64 message[2];

static void *message_writer(void *unused)
{
    (void)unused;
    for (u64 i = 1; i <= 20000; i++) {
        atomic_cond_read_acquire(&published, VAL == 0);
        message[0] = i;
        message[1] = ~i;
        atomic_set_release(&published, 1);
    }
    return NULL;
}

static void *message_reader(void *unused)
{
    (void)unused;
    for (u64 i = 1; i <= 20000; i++) {
        atomic_cond_read_acquire(&published, VAL == 1);
        assert(message[0] == i && message[1] == ~i);
        atomic_set_release(&published, 0);
    }
    return NULL;
}

struct shared_object {
    struct kref refs;
    unsigned int completed[4];
};
struct reference_worker { struct shared_object *object; unsigned int index; };
static atomic_t releases = ATOMIC_INIT(0);

static void release_object(struct kref *refs)
{
    struct shared_object *object = container_of(refs, struct shared_object, refs);
    /* Each worker publishes this before dropping its final reference. The
     * final release must acquire all prior writes and happen exactly once. */
    for (size_t i = 0; i < ARRAY_SIZE(object->completed); i++) assert(object->completed[i] == i + 1);
    assert(atomic_fetch_inc(&releases) == 0);
    kfree(object);
}

static void *reference_worker(void *argument)
{
    struct reference_worker *worker = argument;
    struct shared_object *object = worker->object;
    for (int i = 0; i < 30000; i++) {
        kref_get(&object->refs);
        assert(!kref_put(&object->refs, release_object));
    }
    object->completed[worker->index] = worker->index + 1;
    kref_put(&object->refs, release_object);
    return NULL;
}

static void reference_tests(void)
{
    refcount_t refs = REFCOUNT_INIT(0);
    assert(!refcount_inc_not_zero(&refs) && atomic_read(&refcount_warnings) == 0);
    refcount_inc(&refs);
    assert(refcount_read(&refs) == (unsigned)REFCOUNT_SATURATED);
    assert(!refcount_dec_and_test(&refs));
    refcount_set(&refs, 1);
    refcount_add(INT_MAX, &refs);
    assert(refcount_read(&refs) == (unsigned)REFCOUNT_SATURATED);
    refcount_set(&refs, 1);
    assert(!refcount_sub_and_test(2, &refs));
    assert(refcount_read(&refs) == (unsigned)REFCOUNT_SATURATED);
    assert(atomic_read(&refcount_warnings) == 4);
    refcount_set(&refs, 1);
    assert(refcount_dec_if_one(&refs) && !refcount_dec_if_one(&refs));
    spinlock_t lock;
    spin_lock_init(&lock);
    unsigned long flags = 0;
    refcount_set(&refs, 2);
    assert(!refcount_dec_and_lock_irqsave(&refs, &lock, &flags));
    assert(interrupts && preempt_depth == 0 && refcount_read(&refs) == 1);
    assert(refcount_dec_and_lock_irqsave(&refs, &lock, &flags));
    assert(!interrupts && preempt_depth == 1 && refcount_read(&refs) == 0);
    spin_unlock_irqrestore(&lock, flags);
    assert(interrupts && preempt_depth == 0);
    struct shared_object *object = kzalloc(sizeof(*object), GFP_KERNEL);
    assert(object);
    kref_init(&object->refs);
    struct reference_worker workers[4];
    pthread_t threads[4];
    for (size_t i = 0; i < ARRAY_SIZE(workers); i++) {
        workers[i] = (struct reference_worker){ object, (unsigned)i };
        kref_get(&object->refs);
        assert(!pthread_create(&threads[i], NULL, reference_worker, &workers[i]));
    }
    kref_put(&object->refs, release_object);
    for (size_t i = 0; i < ARRAY_SIZE(threads); i++) assert(!pthread_join(threads[i], NULL));
    assert(atomic_read(&releases) == 1 && live_pages == 0);
    pthread_t writer, reader;
    assert(!pthread_create(&writer, NULL, message_writer, NULL));
    assert(!pthread_create(&reader, NULL, message_reader, NULL));
    assert(!pthread_join(writer, NULL) && !pthread_join(reader, NULL));
}

int main(void)
{
    allocation_tests();
    list_tests();
    tree_tests();
    concurrency_tests();
    atomic_api_tests();
    reference_tests();
    assert(live_pages == 0);
    puts("LinuxKPI: PASS (unmodified Linux helpers, allocation/OOM, tree/list invariants, SMP locks)");
    return 0;
}
