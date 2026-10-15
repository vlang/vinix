// SPDX-License-Identifier: GPL-2.0-only
// Strongly typed original ABI and permanent storage; algorithms live in V.
@[translated]
module headercore

#include "linuxkpi_dma_fence_v_contract.h"

struct C.dma_fence {}
struct C.dma_fence_cb {}
struct C.kref {}
@[typedef]
struct C.vdf_const_ops_p {}
@[typedef]
struct C.vdf_const_char_p {}
@[typedef]
struct C.vdf_ktime_t {}
@[typedef]
struct C.vdf_u64 {}
struct C.dma_fence_ops {
	get_driver_name fn (&C.dma_fence) C.vdf_const_char_p
	get_timeline_name fn (&C.dma_fence) C.vdf_const_char_p
}
@[cinit]
__global vdf_permanent_stub C.dma_fence
@[cinit]
__global vdf_permanent_stub_lock C.spinlock_t
@[cinit]
__global vdf_permanent_stub_ops C.dma_fence_ops = C.dma_fence_ops{
	get_driver_name: C.vdf_stub_get_name
	get_timeline_name: C.vdf_stub_get_name
}
fn C.vdf_stub_get_name(&C.dma_fence) C.vdf_const_char_p
@[export: 'vdf_stub_get_name']
pub fn fence_stub_name(fence &C.dma_fence) C.vdf_const_char_p {
	mut name := C.vdf_const_char_p{}
	text := unsafe { &char(c'stub') }
	unsafe { C.memcpy(&name, &text, sizeof(voidptr)) }
	return name
}
fn C.vdf_get_stub() voidptr
fn C.vdf_allocate_private_stub(i64) voidptr
fn C.vdf_context_alloc(u32) u64
fn C.vdf_signal(voidptr) i32
fn C.vdf_signal_locked(voidptr) i32
fn C.vdf_signal_timestamp(voidptr, i64) i32
fn C.vdf_signal_timestamp_locked(voidptr, i64) i32
fn C.vdf_wait_timeout(voidptr, bool, isize) isize
fn C.vdf_release(voidptr)
fn C.vdf_free(voidptr)
fn C.vdf_enable_sw_signaling(voidptr)
fn C.vdf_add_callback(voidptr, voidptr, fn (&C.dma_fence, &C.dma_fence_cb)) i32
fn C.vdf_get_status(voidptr) i32
fn C.vdf_remove_callback(voidptr, voidptr) bool
fn C.vdf_default_wait(voidptr, bool, isize) isize
fn C.vdf_wait_any_timeout(voidptr, u32, bool, isize, &u32) isize
fn C.vdf_set_deadline(voidptr, i64)
fn C.vdf_init(voidptr, voidptr, voidptr, u64, u64)
fn C.dma_fence_get(&C.dma_fence) &C.dma_fence
fn C.wake_up_state(&C.task_struct, u32) i32
fn fence_time_bits(value C.vdf_ktime_t) i64 {
	mut result := i64(0)
	unsafe { C.memcpy(&result, &value, 8) }
	return result
}
fn fence_word_bits(value C.vdf_u64) u64 {
	mut result := u64(0)
	unsafe { C.memcpy(&result, &value, 8) }
	return result
}
fn fence_word_native(value u64) C.vdf_u64 {
	mut result := C.vdf_u64{}
	unsafe { C.memcpy(&result, &value, 8) }
	return result
}

@[export: 'dma_fence_get_stub']
pub fn dma_fence_get_stub() &C.dma_fence { return unsafe { &C.dma_fence(C.vdf_get_stub()) } }
@[export: 'dma_fence_allocate_private_stub']
pub fn dma_fence_allocate_private_stub(timestamp C.vdf_ktime_t) &C.dma_fence {
	return unsafe { &C.dma_fence(C.vdf_allocate_private_stub(fence_time_bits(timestamp))) }
}
@[export: 'dma_fence_context_alloc']
pub fn dma_fence_context_alloc(count u32) C.vdf_u64 {
	// Linux u64 is distinct from the generated V word; preserve its exact ABI.
	return fence_word_native(C.vdf_context_alloc(count))
}
@[export: 'dma_fence_signal']
pub fn dma_fence_signal(fence &C.dma_fence) i32 { return C.vdf_signal(fence) }
@[export: 'dma_fence_signal_locked']
pub fn dma_fence_signal_locked(fence &C.dma_fence) i32 { return C.vdf_signal_locked(fence) }
@[export: 'dma_fence_signal_timestamp']
pub fn dma_fence_signal_timestamp(fence &C.dma_fence, timestamp C.vdf_ktime_t) i32 { return C.vdf_signal_timestamp(fence, fence_time_bits(timestamp)) }
@[export: 'dma_fence_signal_timestamp_locked']
pub fn dma_fence_signal_timestamp_locked(fence &C.dma_fence, timestamp C.vdf_ktime_t) i32 { return C.vdf_signal_timestamp_locked(fence, fence_time_bits(timestamp)) }
@[export: 'dma_fence_wait_timeout']
pub fn dma_fence_wait_timeout(fence &C.dma_fence, intr bool, timeout isize) isize { return C.vdf_wait_timeout(fence, intr, timeout) }
@[export: 'dma_fence_release']
pub fn dma_fence_release(refcount &C.kref) { C.vdf_release(refcount) }
@[export: 'dma_fence_free']
pub fn dma_fence_free(fence &C.dma_fence) { C.vdf_free(fence) }
@[export: 'dma_fence_enable_sw_signaling']
pub fn dma_fence_enable_sw_signaling(fence &C.dma_fence) { C.vdf_enable_sw_signaling(fence) }
@[export: 'dma_fence_add_callback']
pub fn dma_fence_add_callback(fence &C.dma_fence, cb &C.dma_fence_cb, callback fn (&C.dma_fence, &C.dma_fence_cb)) i32 {
	return C.vdf_add_callback(fence, cb, callback)
}
@[export: 'dma_fence_get_status']
pub fn dma_fence_get_status(fence &C.dma_fence) i32 { return C.vdf_get_status(fence) }
@[export: 'dma_fence_remove_callback']
pub fn dma_fence_remove_callback(fence &C.dma_fence, cb &C.dma_fence_cb) bool { return C.vdf_remove_callback(fence, cb) }
@[export: 'dma_fence_default_wait']
pub fn dma_fence_default_wait(fence &C.dma_fence, intr bool, timeout isize) isize { return C.vdf_default_wait(fence, intr, timeout) }
@[export: 'dma_fence_wait_any_timeout']
pub fn dma_fence_wait_any_timeout(fences &&C.dma_fence, count u32, intr bool, timeout isize, index &u32) isize {
	return C.vdf_wait_any_timeout(fences, count, intr, timeout, index)
}
@[export: 'dma_fence_set_deadline']
pub fn dma_fence_set_deadline(fence &C.dma_fence, deadline C.vdf_ktime_t) { C.vdf_set_deadline(fence, fence_time_bits(deadline)) }
@[export: 'dma_fence_init']
pub fn dma_fence_init(fence &C.dma_fence, ops C.vdf_const_ops_p, guard &C.spinlock_t, context C.vdf_u64, seqno C.vdf_u64) {
	C.vdf_init(fence, voidptr(ops), guard, fence_word_bits(context), fence_word_bits(seqno))
}
@[export: 'vdf_stub_storage']
pub fn dma_fence_stub_storage() voidptr { return unsafe { &vdf_permanent_stub } }
@[export: 'vdf_stub_lock']
pub fn dma_fence_stub_lock() voidptr { return unsafe { &vdf_permanent_stub_lock } }
@[export: 'vdf_stub_ops']
pub fn dma_fence_stub_ops() voidptr { return unsafe { &vdf_permanent_stub_ops } }
@[export: 'vdf_fence_get']
pub fn dma_fence_ref_get(fence voidptr) voidptr { return unsafe { C.dma_fence_get(&C.dma_fence(fence)) } }
@[export: 'vdf_current_get']
pub fn dma_fence_current_get() voidptr { return C.get_task_struct(C.current) }
@[export: 'vdf_task_put']
pub fn dma_fence_task_put(task voidptr) { unsafe { C.put_task_struct(&C.task_struct(task)) } }
@[export: 'vdf_wake']
pub fn dma_fence_wake(task voidptr) { unsafe { C.wake_up_state(&C.task_struct(task), 3) } }
