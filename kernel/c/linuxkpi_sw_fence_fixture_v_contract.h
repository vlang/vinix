/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_SW_FENCE_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_SW_FENCE_FIXTURE_V_CONTRACT_H
#include "linuxkpi_dma_resv_v_contract.h"
#define u64 vkh_linux_u64
#include <linux/irq_work.h>
#include <linux/timer.h>
#include "i915_sw_fence.h"
#undef u64
#include "linuxkpi_sw_fence_fixture_v_primitives.h"
/* Exact private original record, data only; no imported algorithm is copied. */
struct i915_sw_dma_fence_cb_timer {
    struct i915_sw_dma_fence_cb base;
    struct dma_fence *dma;
    struct timer_list timer;
    struct irq_work work;
    struct rcu_head rcu;
};
#define vswf_pending(p) atomic_read(&(p)->pending)
#define vswf_timed_fence(p) READ_ONCE((p)->base.fence)
#define vswf_timed_flags(p) atomic_read(&(p)->work.node.a_flags)
_Static_assert(sizeof(struct i915_sw_fence) == 40 && _Alignof(struct i915_sw_fence) == 8 &&
    sizeof(struct vinix_swfence_fixture) == 40 && _Alignof(struct vinix_swfence_fixture) == 8 &&
    offsetof(struct i915_sw_fence, wait) == 0 && offsetof(struct i915_sw_fence, fn) == 24 &&
    offsetof(struct i915_sw_fence, pending) == 32 && offsetof(struct i915_sw_fence, error) == 36,
    "original SW-fence storage");
_Static_assert(sizeof(wait_queue_entry_t) == sizeof(struct vinix_swfence_wait_fixture) &&
    _Alignof(wait_queue_entry_t) == _Alignof(struct vinix_swfence_wait_fixture) &&
    sizeof(struct i915_sw_dma_fence_cb) == sizeof(struct vinix_swfence_dma_fixture) &&
    offsetof(struct i915_sw_dma_fence_cb, fence) == 24, "original dependency records");
_Static_assert(sizeof(struct i915_sw_dma_fence_cb_timer) == 128 &&
    offsetof(struct i915_sw_dma_fence_cb_timer, dma) == 32 &&
    offsetof(struct i915_sw_dma_fence_cb_timer, timer) == 40 &&
    offsetof(struct i915_sw_dma_fence_cb_timer, work) == 80 &&
    offsetof(struct i915_sw_dma_fence_cb_timer, rcu) == 112, "original timed DMA owner");
_Static_assert(__builtin_types_compatible_p(vswf_notify, enum i915_sw_fence_notify) &&
    __builtin_types_compatible_p(vswf_callback, i915_sw_fence_notify_t) &&
    FENCE_COMPLETE == 0 && FENCE_FREE == 1 && NOTIFY_DONE == 0 && TIMER_IRQSAFE == 0x200000,
    "original notify and timer ABI");
#endif
