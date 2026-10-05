/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef VINIX_LINUXKPI
#include <linux/bug.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/list.h>
#include <linux/percpu.h>
#include <linux/slab.h>
#include <linux/spinlock.h>

unsigned long __per_cpu_offset[NR_CPUS];
static unsigned int cpu_count;
static const unsigned char *template_begin;
static size_t template_size, static_stride;
static unsigned char *static_copies;
struct percpu_allocation {
    struct list_head link;
    unsigned char *data;
    size_t size, stride;
};
static LIST_HEAD(allocations);
static DEFINE_RAW_SPINLOCK(allocation_lock);

unsigned int vinix_linuxkpi_percpu_count(void)
{
    return __atomic_load_n(&cpu_count, __ATOMIC_ACQUIRE);
}

int vinix_linuxkpi_percpu_init(unsigned int count, const void *begin, const void *end)
{
    if (__atomic_load_n(&cpu_count, __ATOMIC_ACQUIRE)) return -EBUSY;
    if (!count || count > NR_CPUS || (uintptr_t)end < (uintptr_t)begin) return -EINVAL;
    size_t size = (uintptr_t)end - (uintptr_t)begin;
    size_t page = vinix_linuxkpi_page_size(), padded, total;
    if (check_add_overflow(size, page - 1, &padded)) return -EOVERFLOW;
    size_t stride = padded & ~(page - 1);
    if (check_mul_overflow(stride, count, &total)) return -EOVERFLOW;
    unsigned char *copies = size ? kzalloc(total, GFP_KERNEL) : NULL;
    if (size && !copies) return -ENOMEM;
    for (unsigned int cpu = 0; cpu < count; cpu++) {
        if (size) memcpy(copies + cpu * stride, begin, size);
        __per_cpu_offset[cpu] = size ? (uintptr_t)(copies + cpu * stride) - (uintptr_t)begin : 0;
    }
    template_begin = begin;
    template_size = size;
    static_stride = stride;
    static_copies = copies;
    /* Bootstrap is called once before any Linux driver/worker is started. */
    __atomic_store_n(&cpu_count, count, __ATOMIC_RELEASE);
    return 0;
}

#ifndef VINIX_LINUXKPI_HOST_TEST
extern const unsigned char __vinix_percpu_start[], __vinix_percpu_end[];
int vinix_linuxkpi_percpu_bootstrap(unsigned int count)
{
    return vinix_linuxkpi_percpu_init(count, __vinix_percpu_start, __vinix_percpu_end);
}
#endif

void *vinix_linuxkpi_percpu_ptr(const void *ptr, unsigned int cpu)
{
    if (!ptr) return NULL;
    BUG_ON(cpu >= __atomic_load_n(&cpu_count, __ATOMIC_ACQUIRE));
    uintptr_t offset = (uintptr_t)ptr - (uintptr_t)template_begin;
    if (offset < template_size) return static_copies + cpu * static_stride + offset;
    unsigned long flags;
    raw_spin_lock_irqsave(&allocation_lock, flags);
    struct percpu_allocation *allocation;
    void *result = NULL;
    list_for_each_entry(allocation, &allocations, link) {
        offset = (uintptr_t)ptr - (uintptr_t)allocation->data;
        if (offset < allocation->size) {
            result = allocation->data + cpu * allocation->stride + offset;
            break;
        }
    }
    raw_spin_unlock_irqrestore(&allocation_lock, flags);
    BUG_ON(!result);
    return result;
}

void *__alloc_percpu_gfp(size_t size, size_t align, gfp_t flags)
{
    unsigned int count = __atomic_load_n(&cpu_count, __ATOMIC_ACQUIRE);
    size_t page = vinix_linuxkpi_page_size(), padded, total;
    if (!count || !size || !align || (align & (align - 1)) || align > page) return NULL;
    size_t slot_alignment = max(align, (size_t)64);
    if (check_add_overflow(size, slot_alignment - 1, &padded)) return NULL;
    size_t stride = padded & ~(slot_alignment - 1);
    if (check_mul_overflow(stride, count, &total) ||
        check_add_overflow(total, sizeof(struct percpu_allocation), &total) ||
        check_add_overflow(total, slot_alignment - 1, &total)) return NULL;
    struct percpu_allocation *allocation = kzalloc(total, flags);
    if (!allocation) return NULL;
    allocation->data = PTR_ALIGN((unsigned char *)(allocation + 1), slot_alignment);
    allocation->size = size;
    allocation->stride = stride;
    unsigned long irq_flags;
    raw_spin_lock_irqsave(&allocation_lock, irq_flags);
    list_add(&allocation->link, &allocations);
    raw_spin_unlock_irqrestore(&allocation_lock, irq_flags);
    return allocation->data;
}

void *__alloc_percpu(size_t size, size_t align)
{
    return __alloc_percpu_gfp(size, align, GFP_KERNEL);
}

void free_percpu(void *ptr)
{
    if (!ptr) return;
    unsigned long flags;
    raw_spin_lock_irqsave(&allocation_lock, flags);
    struct percpu_allocation *allocation, *found = NULL;
    list_for_each_entry(allocation, &allocations, link) {
        if (allocation->data == ptr) { found = allocation; list_del(&found->link); break; }
    }
    raw_spin_unlock_irqrestore(&allocation_lock, flags);
    BUG_ON(!found);
    /* Linux callers own the lifetime: all local/remote CPU readers must have
     * stopped before free_percpu(). The registry lock does not grant a lease. */
    kfree(found);
}

#ifdef VINIX_LINUXKPI_HOST_TEST
void vinix_linuxkpi_percpu_destroy_for_test(void)
{
    BUG_ON(!list_empty(&allocations));
    kfree(static_copies);
    static_copies = NULL;
    __atomic_store_n(&cpu_count, 0, __ATOMIC_RELEASE);
}
#endif
#endif
