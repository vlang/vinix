/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_RUNTIME_H
#define VINIX_LINUXKPI_RUNTIME_H
#include <linux/types.h>
/* The native backend owns physical pages; allocation never panics on OOM. */
void *vinix_linuxkpi_alloc_pages(size_t pages, bool reclaim);
void vinix_linuxkpi_free_pages(void *base, size_t pages);
size_t vinix_linuxkpi_page_size(void);
/* Return Linux IRQ flags, not a flags value stored in a shared lock. */
unsigned long vinix_linuxkpi_irq_save(void);
unsigned long vinix_linuxkpi_irq_flags(void);
void vinix_linuxkpi_irq_restore(unsigned long flags);
void vinix_linuxkpi_spin_wait(void);
void vinix_linuxkpi_preempt_disable(void);
void vinix_linuxkpi_preempt_enable(void);
void vinix_linuxkpi_preempt_enable_no_resched(void);
unsigned int vinix_linuxkpi_preempt_count(void);
void vinix_linuxkpi_preempt_check_resched(void);
unsigned int vinix_linuxkpi_cpu_id(void);
void *vinix_linuxkpi_percpu_ptr(const void *ptr, unsigned int cpu);
int vinix_linuxkpi_percpu_init(unsigned int count, const void *begin, const void *end);
unsigned int vinix_linuxkpi_percpu_count(void);
bool vinix_linuxkpi_may_sleep(void);
void vinix_linuxkpi_refcount_warning(int kind);
bool vinix_linuxkpi_cpu_has(unsigned int feature);
void vinix_linuxkpi_fpu_begin(void);
void vinix_linuxkpi_fpu_end(void);
bool vinix_linuxkpi_tigerlake_id(u16 vendor, u16 device, u32 class_code);
int vinix_linuxkpi_selftest(void);
#endif
