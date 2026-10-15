// SPDX-License-Identifier: GPL-2.0-only
// Original typed operations and immutable exported container identity.
@[translated]
module headercore

#include "linuxkpi_dma_fence_chain_v_contract.h"

struct C.dma_fence_chain { prev &C.dma_fence }
struct C.irq_work {}
@[typedef]
struct C.vfc_const_ops {
	use_64bit_seqno bool
	get_driver_name fn (&C.dma_fence) C.vdf_const_char_p
	get_timeline_name fn (&C.dma_fence) C.vdf_const_char_p
	enable_signaling fn (&C.dma_fence) bool
	signaled fn (&C.dma_fence) bool
	release fn (&C.dma_fence)
	set_deadline fn (&C.dma_fence, C.vdf_ktime_t)
}
fn C.vfc_ops_enable(&C.dma_fence) bool
fn C.vfc_ops_signaled(&C.dma_fence) bool
fn C.vfc_ops_release(&C.dma_fence)
fn C.vfc_ops_deadline(&C.dma_fence, C.vdf_ktime_t)
fn C.vfc_driver_name(&C.dma_fence) C.vdf_const_char_p
fn C.vfc_timeline_name(&C.dma_fence) C.vdf_const_char_p
fn C.vfc_irq_callback(&C.irq_work)
fn C.vfc_child_callback(&C.dma_fence, &C.dma_fence_cb)
@[export: 'dma_fence_chain_ops']
@[cinit]
__global vfc_chain_ops C.vfc_const_ops = C.vfc_const_ops{
	use_64bit_seqno: true
	get_driver_name: C.vfc_driver_name
	get_timeline_name: C.vfc_timeline_name
	enable_signaling: C.vfc_ops_enable
	signaled: C.vfc_ops_signaled
	release: C.vfc_ops_release
	set_deadline: C.vfc_ops_deadline
}
fn C.vfc_walk(voidptr) voidptr
fn C.vfc_find_seqno(&voidptr, u64) i32
fn C.vfc_init(voidptr, voidptr, voidptr, u64)
fn C.vfc_enable(voidptr) bool
fn C.vfc_signaled(voidptr) bool
fn C.vfc_release(voidptr)
fn C.vfc_deadline(voidptr, i64)
fn C.vfc_irq(voidptr)
fn C.vfc_callback(voidptr, voidptr)
fn C.dma_fence_put(&C.dma_fence)
fn C.dma_fence_get_rcu_safe(&&C.dma_fence) &C.dma_fence
fn C.dma_fence_is_signaled(&C.dma_fence) bool
fn C.kref_read(&C.kref) u32
fn C.rcu_read_lock()
fn C.rcu_read_unlock()
fn C.init_irq_work(&C.irq_work, fn (&C.irq_work))

@[export: 'dma_fence_chain_walk']
pub fn dma_fence_chain_walk(fence &C.dma_fence) &C.dma_fence {
	return unsafe { &C.dma_fence(C.vfc_walk(fence)) }
}
@[export: 'dma_fence_chain_find_seqno']
pub fn dma_fence_chain_find_seqno(fence &&C.dma_fence, seqno u64) i32 {
	return unsafe { C.vfc_find_seqno(&voidptr(fence), seqno) }
}
@[export: 'dma_fence_chain_init']
pub fn dma_fence_chain_init(chain &C.dma_fence_chain, prev &C.dma_fence, fence &C.dma_fence, seqno u64) {
	C.vfc_init(chain, prev, fence, seqno)
}
@[export: 'vfc_ops_identity']
pub fn chain_ops_identity() voidptr { return unsafe { &vfc_chain_ops } }
@[export: 'vfc_get']
pub fn chain_get(fence voidptr) voidptr { return unsafe { C.dma_fence_get(&C.dma_fence(fence)) } }
@[export: 'vfc_put']
pub fn chain_put(fence voidptr) { unsafe { C.dma_fence_put(&C.dma_fence(fence)) } }
@[export: 'vfc_get_prev']
pub fn chain_get_prev(storage voidptr) voidptr {
	C.rcu_read_lock()
	prev := unsafe { C.dma_fence_get_rcu_safe(&(&C.dma_fence_chain(storage)).prev) }
	C.rcu_read_unlock()
	return prev
}
@[export: 'vfc_is_signaled']
pub fn chain_is_signaled(fence voidptr) bool { return unsafe { C.dma_fence_is_signaled(&C.dma_fence(fence)) } }
@[export: 'vfc_refcount']
pub fn chain_refcount(fence voidptr) u32 { return unsafe { C.kref_read(&C.kref(&u8(fence) + 56)) } }
@[export: 'vfc_init_work']
pub fn chain_init_work(work voidptr) { unsafe { C.init_irq_work(&C.irq_work(work), C.vfc_irq_callback) } }
@[export: 'vfc_ops_enable']
pub fn chain_ops_enable(fence &C.dma_fence) bool { return C.vfc_enable(fence) }
@[export: 'vfc_ops_signaled']
pub fn chain_ops_signaled(fence &C.dma_fence) bool { return C.vfc_signaled(fence) }
@[export: 'vfc_ops_release']
pub fn chain_ops_release(fence &C.dma_fence) { C.vfc_release(fence) }
@[export: 'vfc_ops_deadline']
pub fn chain_ops_deadline(fence &C.dma_fence, deadline C.vdf_ktime_t) { C.vfc_deadline(fence, fence_time_bits(deadline)) }
@[export: 'vfc_driver_name']
pub fn chain_driver_name(fence &C.dma_fence) C.vdf_const_char_p {
	mut result := C.vdf_const_char_p{}
	text := unsafe { &char(c'dma_fence_chain') }
	unsafe { C.memcpy(&result, &text, sizeof(voidptr)) }
	return result
}
@[export: 'vfc_timeline_name']
pub fn chain_timeline_name(fence &C.dma_fence) C.vdf_const_char_p {
	mut result := C.vdf_const_char_p{}
	text := unsafe { &char(c'unbound') }
	unsafe { C.memcpy(&result, &text, sizeof(voidptr)) }
	return result
}
@[export: 'vfc_irq_callback']
pub fn chain_irq_callback(work &C.irq_work) { C.vfc_irq(work) }
@[export: 'vfc_child_callback']
pub fn chain_child_callback(fence &C.dma_fence, cb &C.dma_fence_cb) { C.vfc_callback(fence, cb) }
