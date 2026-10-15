// SPDX-License-Identifier: GPL-2.0-only
// Original typed API, inline adapters and one immutable public ops identity.
@[translated]
module headercore

#include "linuxkpi_dma_fence_array_v_contract.h"

struct C.dma_fence_array {}

@[typedef]
struct C.vfa_const_char_p {}

@[typedef]
struct C.vfa_ktime_t {}

@[typedef]
struct C.vfa_u64 {}

@[typedef]
struct C.vfa_const_ops {
	get_driver_name   fn (&C.dma_fence) C.vfa_const_char_p
	get_timeline_name fn (&C.dma_fence) C.vfa_const_char_p
	enable_signaling  fn (&C.dma_fence) bool
	signaled          fn (&C.dma_fence) bool
	release           fn (&C.dma_fence)
	set_deadline      fn (&C.dma_fence, C.vfa_ktime_t)
}

fn C.vfa_driver_name(&C.dma_fence) C.vfa_const_char_p
fn C.vfa_timeline_name(&C.dma_fence) C.vfa_const_char_p
fn C.vfa_enable_signaling(&C.dma_fence) bool
fn C.vfa_signaled(&C.dma_fence) bool
fn C.vfa_release(&C.dma_fence)
fn C.vfa_set_deadline(&C.dma_fence, C.vfa_ktime_t)

@[export: 'dma_fence_array_ops']
@[cinit]
__global vfa_public_ops C.vfa_const_ops = C.vfa_const_ops{
	get_driver_name:   C.vfa_driver_name
	get_timeline_name: C.vfa_timeline_name
	enable_signaling:  C.vfa_enable_signaling
	signaled:          C.vfa_signaled
	release:           C.vfa_release
	set_deadline:      C.vfa_set_deadline
}

fn C.vfa_create(i32, voidptr, u64, u32, bool) voidptr
fn C.vfa_match_context(voidptr, u64) bool
fn C.vfa_first(voidptr) voidptr
fn C.vfa_next(voidptr, u32) voidptr
fn C.dma_fence_put(&C.dma_fence)
fn C.dma_fence_is_container(&C.dma_fence) bool
fn C.init_irq_work(&C.irq_work, fn (&C.irq_work))

fn array_context_bits(value C.vfa_u64) u64 {
	mut result := u64(0)
	unsafe { C.memcpy(&result, &value, 8) }
	return result
}

@[export: 'dma_fence_array_create']
pub fn dma_fence_array_create(count i32, fences &&C.dma_fence, context C.vfa_u64, seqno u32, any bool) &C.dma_fence_array {
	return unsafe { &C.dma_fence_array(C.vfa_create(count, fences, array_context_bits(context), seqno, any)) }
}

@[export: 'dma_fence_match_context']
pub fn dma_fence_match_context(fence &C.dma_fence, context C.vfa_u64) bool {
	return C.vfa_match_context(fence, array_context_bits(context))
}

@[export: 'dma_fence_array_first']
pub fn dma_fence_array_first(fence &C.dma_fence) &C.dma_fence {
	return unsafe { &C.dma_fence(C.vfa_first(fence)) }
}

@[export: 'dma_fence_array_next']
pub fn dma_fence_array_next(fence &C.dma_fence, index u32) &C.dma_fence {
	return unsafe { &C.dma_fence(C.vfa_next(fence, index)) }
}

@[export: 'vfa_ops']
pub fn dma_fence_array_ops_identity() voidptr { return unsafe { &vfa_public_ops } }

@[export: 'vfa_fence_put']
pub fn dma_fence_array_ref_put(fence voidptr) {
	unsafe { C.dma_fence_put(&C.dma_fence(fence)) }
}

@[export: 'vfa_is_container']
pub fn dma_fence_array_is_container(fence voidptr) bool {
	return unsafe { C.dma_fence_is_container(&C.dma_fence(fence)) }
}

@[export: 'vfa_init_work']
pub fn dma_fence_array_init_work(work voidptr, callback fn (&C.irq_work)) {
	unsafe { C.init_irq_work(&C.irq_work(work), callback) }
}
