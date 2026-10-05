/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef VINIX_LINUXKPI
/* Bind header-only Linux primitives without copying their algorithms into V.
 * These wrappers retain upstream lock, scheduler and warning semantics. */
#include <linux/refcount.h>
#include <linux/spinlock.h>
#include <linux/mutex.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/wait_bit.h>
#include <linux/jiffies.h>
#include <linux/printk.h>
#include <vinix/printk.h>
_Static_assert(sizeof(spinlock_t) == 4, "V spinlock storage must match Linux");
_Static_assert(sizeof(refcount_t) == 4, "V refcount storage must match Linux");
_Static_assert(CONFIG_NR_CPUS == 256, "V per-CPU ABI storage must match Linux");
void vkp_spin_init(void *p) { spin_lock_init((spinlock_t *)p); }
void vkp_spin_lock(void *p) { spin_lock((spinlock_t *)p); }
void vkp_spin_unlock(void *p) { spin_unlock((spinlock_t *)p); }
unsigned long vkp_spin_lock_irqsave(void *p) { unsigned long f; spin_lock_irqsave((spinlock_t *)p, f); return f; }
void vkp_spin_unlock_irqrestore(void *p, unsigned long f) { spin_unlock_irqrestore((spinlock_t *)p, f); }
void vkp_mutex_lock(void *p) { mutex_lock(p); }
void vkp_mutex_unlock(void *p) { mutex_unlock(p); }
bool vkp_refcount_dec_and_test(void *p) { return refcount_dec_and_test(p); }
void vkp_cache_ctor_warning(bool value) { WARN_ON_ONCE(value); }
void *vkp_current(void) { return current; }
void *vkp_iowait_field(void *p) { return &((struct task_struct *)p)->in_iowait; }
void vkp_schedule(void) { schedule(); }
long vkp_schedule_timeout(long t) { return schedule_timeout(t); }
bool vkp_signal_pending(int mode) { return signal_pending_state(mode, current); }
unsigned long vkp_jiffies(void) { return READ_ONCE(jiffies); }
unsigned long vkp_bit_timeout(void *p) { return ((struct wait_bit_key *)p)->timeout; }
void vkp_warn(const char *file, int line) { vinix_linuxkpi_warn_format(file, line, NULL); }
void vkp_refcount_warning(int kind) { _printk(KERN_WARNING "linuxkpi: refcount saturated after invalid operation %d; retaining object\n", kind); }
#ifdef VINIX_LINUXKPI_HOST_TEST
void vinix_linuxkpi_test_warn_note(const char *, int);
void vinix_linuxkpi_test_refcount_note(int);
void vkp_warn_note(const char *file, int line) { vinix_linuxkpi_test_warn_note(file, line); }
void vkp_refcount_note(int kind) { vinix_linuxkpi_test_refcount_note(kind); }
#else
void vkp_warn_note(const char *file, int line) { (void)file; (void)line; }
void vkp_refcount_note(int kind) { (void)kind; }
#endif
unsigned long __per_cpu_offset[256];
void *vkp_percpu_offsets(void) { return __per_cpu_offset; }
#ifndef VINIX_LINUXKPI_HOST_TEST
extern const unsigned char __vinix_percpu_start[], __vinix_percpu_end[];
void *vkp_percpu_begin(void) { return (void *)__vinix_percpu_start; }
void *vkp_percpu_end(void) { return (void *)__vinix_percpu_end; }
#else
void *vkp_percpu_begin(void) { return NULL; }
void *vkp_percpu_end(void) { return NULL; }
#endif
#endif
