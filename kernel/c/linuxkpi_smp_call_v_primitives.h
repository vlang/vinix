/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_SMP_CALL_V_PRIMITIVES_H
#define VINIX_LINUXKPI_SMP_CALL_V_PRIMITIVES_H
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#define VKS_SMP_CPU_LIMIT 256U
#define VKS_SMP_CSD_BYTES 32U
#define VKS_SMP_CSD_ALIGN 32U
#define VKS_SMP_LOCK 1U
#define VKS_SMP_SYNC 16U
#define VKS_SMP_TYPE_MASK 240U
#define VKS_SMP_GFP_KERNEL 3264U
typedef void (*vks_smp_call_fn)(void *);
typedef bool (*vks_smp_cond_fn)(int32_t, void *);
typedef const void *vks_smp_const_void;

/* Original CSD field views. The header module borrows genuine Linux records;
 * neither the backend nor the native bridge owns a replacement layout. */
uint32_t *vks_smp_csd_flags(void *);
void *vks_smp_csd_next(void *);
void vks_smp_csd_set_next(void *, void *);
vks_smp_call_fn vks_smp_csd_function(void *);
void *vks_smp_csd_info(void *);
void vks_smp_csd_set_callback(void *, vks_smp_call_fn, void *);
bool vks_smp_mask_has(vks_smp_const_void, uint32_t);
vks_smp_const_void vks_smp_online_mask(void);

/* One boot owner installs the native vector before publishing this service.
 * Owners are permanent: there is no reset, teardown, hotplug or mixed
 * IRQ_WORK/TTWU queue entry API. Failed allocation retains no block. */
int32_t vks_smp_bootstrap(uint32_t count);
bool vks_smp_ready(void);
void vks_smp_drain(uint32_t cpu);
int32_t vks_smp_single(uint32_t wait, int32_t cpu, vks_smp_call_fn,
                     void *info, void *sync_stack_csd);
int32_t vks_smp_async(int32_t cpu, void *caller_csd);
void vks_smp_many(vks_smp_const_void mask, vks_smp_call_fn, void *info,
                  bool wait, bool run_local, vks_smp_cond_fn);

/* Native transport is a real maskable IPI. It must not poll or drain any
 * callback on the producer, nor consult the already-published CSD. */
void vinix_linuxkpi_smp_send_ipi(uint32_t cpu);
bool vinix_linuxkpi_smp_boot_context(void);
bool vinix_linuxkpi_smp_task_present(void);
uint32_t vinix_linuxkpi_maskable_irq_depth(void);
uint32_t vinix_linuxkpi_cpu_id(void);
uint32_t vinix_linuxkpi_preempt_count(void);
void vinix_linuxkpi_preempt_disable(void);
void vinix_linuxkpi_preempt_enable(void);
unsigned long vinix_linuxkpi_irq_save(void);
unsigned long vinix_linuxkpi_irq_flags(void);
void vinix_linuxkpi_irq_restore(unsigned long);
void vinix_linuxkpi_spin_wait(void);

/* Compiler atomics only; all queue, dispatch and ownership algorithms are V. */
#define vks_smp_load32(p, order) __atomic_load_n((p), (order))
#define vks_smp_store32(p, v, order) __atomic_store_n((p), (v), (order))
#define vks_smp_load_word(p, order) __atomic_load_n((p), (order))
#define vks_smp_exchange_word(p, v, order) __atomic_exchange_n((p), (v), (order))
#define vks_smp_compare_word(p, old, v, success, failure) \
    __atomic_compare_exchange_n((p), (old), (v), false, (success), (failure))
#define vks_smp_fence(order) __atomic_thread_fence(order)
#endif
