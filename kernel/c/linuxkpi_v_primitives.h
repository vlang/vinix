/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_V_PRIMITIVES_H
#define VINIX_LINUXKPI_V_PRIMITIVES_H
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
/* Opaque Linux header primitives. Algorithms and ownership live in V. */
void *kmalloc(size_t, unsigned int);
void *kzalloc(size_t, unsigned int);
void *kmalloc_array(size_t, size_t, unsigned int);
void kfree(const void *);
#ifdef VINIX_V_RUNTIME
void vinix_linuxkpi_bug(char *, int);
#else
void vinix_linuxkpi_bug(const char *, int);
#endif
size_t vinix_linuxkpi_page_size(void);
bool vinix_linuxkpi_may_sleep(void);
bool vinix_linuxkpi_gfp_supported(unsigned int);
void *vinix_linuxkpi_alloc_gfp_pages(size_t, unsigned int);
void vinix_linuxkpi_free_pages(void *, size_t);
void vkp_spin_init(void *);
void vkp_spin_lock(void *);
void vkp_spin_unlock(void *);
unsigned long vkp_spin_lock_irqsave(void *);
void vkp_spin_unlock_irqrestore(void *, unsigned long);
void vkp_mutex_lock(void *);
void vkp_mutex_unlock(void *);
bool vkp_refcount_dec_and_test(void *);
void vkp_cache_ctor_warning(bool);
void *vkp_current(void);
void *vkp_iowait_field(void *);
void vkp_schedule(void);
long vkp_schedule_timeout(long);
bool vkp_signal_pending(int);
unsigned long vkp_jiffies(void);
unsigned long vkp_bit_timeout(void *);
unsigned int vinix_linuxkpi_iowait_count(unsigned int);
void vkp_warn(const char *, int);
void vkp_refcount_warning(int);
void vkp_warn_note(const char *, int);
void vkp_refcount_note(int);
void *vkp_percpu_offsets(void);
void *vkp_percpu_begin(void);
void *vkp_percpu_end(void);
#endif
