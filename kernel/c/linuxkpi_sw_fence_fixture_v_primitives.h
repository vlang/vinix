/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_SW_FENCE_FIXTURE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_SW_FENCE_FIXTURE_V_PRIMITIVES_H
#include "linuxkpi_dma_fence_fixture_v_primitives.h"
struct i915_sw_fence;
/* The generic V blob cannot include Linux headers. Preserve the original
 * enum tag and values there so callback instrumentation sees the same type. */
#ifdef VINIX_V_RUNTIME
enum i915_sw_fence_notify { FENCE_COMPLETE, FENCE_FREE };
#endif
typedef enum i915_sw_fence_notify vswf_notify;
typedef int (*vswf_callback)(struct i915_sw_fence *, vswf_notify);
struct vinix_swfence_fixture {
    uintptr_t wait[3];
    vswf_callback fn;
    int32_t pending, error;
};
struct vinix_swfence_wait_fixture { uintptr_t storage[5]; };
struct vinix_swfence_dma_fixture { struct vinix_dmafence_cb base; void *fence; };
uint32_t vinix_linuxkpi_swf_bytes(uint32_t);
void vinix_linuxkpi_swf_init(void *, vswf_callback);
void vinix_linuxkpi_swf_fini(void *);
void vinix_linuxkpi_swf_reinit(void *);
bool vinix_linuxkpi_swf_await(void *);
void vinix_linuxkpi_swf_complete(void *);
void vinix_linuxkpi_swf_commit(void *);
void vinix_linuxkpi_swf_wait(void *);
void vinix_linuxkpi_swf_error(void *, int32_t);
int32_t vinix_linuxkpi_swf_state(void *, uint32_t);
uint32_t vinix_linuxkpi_swf_waiters(void *);
int32_t vinix_linuxkpi_swf_sw(void *, void *, void *, uint32_t);
int32_t vinix_linuxkpi_swf_dma(void *, void *, void *, uint64_t, uint32_t);
int32_t vinix_linuxkpi_swf_resv(void *, void *, bool, uint64_t, uint32_t);
void *vinix_linuxkpi_swf_timed(void *, void *);
uint64_t vinix_linuxkpi_swf_timed_value(void *, uint32_t);
void vinix_linuxkpi_swf_timed_sync(void *);
uint64_t vinix_linuxkpi_swf_now(void);
size_t vinix_linuxkpi_timer_active(void);
#endif
