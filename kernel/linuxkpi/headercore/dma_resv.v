// SPDX-License-Identifier: MIT
// Original typed reservation API and one genuine mutable Wait-Die class.
@[translated]
module headercore

#include "linuxkpi_dma_resv_v_contract.h"

struct C.dma_resv {}

struct C.dma_resv_iter {}

@[typedef]
struct C.vdr_usage {}

@[typedef]
struct C.vdr_const_char_p {}

@[typedef]
struct C.vdr_class_type {
	acquire_name C.vdr_const_char_p
	mutex_name   C.vdr_const_char_p
	is_wait_die  u32
}

@[c_extern]
__global C.vdr_acquire_name C.vdr_const_char_p

@[c_extern]
__global C.vdr_mutex_name C.vdr_const_char_p

@[export: 'reservation_ww_class']
@[cinit]
__global vdr_reservation_class C.vdr_class_type = C.vdr_class_type{
	acquire_name: C.vdr_acquire_name
	mutex_name:   C.vdr_mutex_name
	is_wait_die:  1
}

fn C.vdr_init(voidptr)
fn C.vdr_fini(voidptr)
fn C.vdr_reserve(voidptr, u32) i32
fn C.vdr_add(voidptr, voidptr, u32)
fn C.vdr_replace(voidptr, u64, voidptr, u32)
fn C.vdr_iter_first_unlocked(voidptr) voidptr
fn C.vdr_iter_next_unlocked(voidptr) voidptr
fn C.vdr_iter_first(voidptr) voidptr
fn C.vdr_iter_next(voidptr) voidptr
fn C.vdr_copy(voidptr, voidptr) i32
fn C.vdr_get_fences(voidptr, u32, &u32, &voidptr) i32
fn C.vdr_get_singleton(voidptr, u32, &voidptr) i32
fn C.vdr_wait(voidptr, u32, bool, u64) i64
fn C.vdr_deadline(voidptr, u32, i64)
fn C.vdr_test_signaled(voidptr, u32) bool
fn C.ww_mutex_init(voidptr, voidptr)
fn C.ww_mutex_destroy(voidptr)
fn C.dma_fence_get_rcu(&C.dma_fence) &C.dma_fence
fn C.dma_fence_is_later_or_same(&C.dma_fence, &C.dma_fence) bool

fn resv_usage(value C.vdr_usage) u32 {
	mut bits := u32(0)
	unsafe { C.memcpy(&bits, &value, 4) }
	return bits
}

@[export: 'dma_resv_init']
pub fn dma_resv_init(obj &C.dma_resv) { C.vdr_init(obj) }

@[export: 'dma_resv_fini']
pub fn dma_resv_fini(obj &C.dma_resv) { C.vdr_fini(obj) }

@[export: 'dma_resv_reserve_fences']
pub fn dma_resv_reserve_fences(obj &C.dma_resv, count u32) i32 { return C.vdr_reserve(obj, count) }

@[export: 'dma_resv_add_fence']
pub fn dma_resv_add_fence(obj &C.dma_resv, fence &C.dma_fence, usage C.vdr_usage) {
	C.vdr_add(obj, fence, resv_usage(usage))
}

@[export: 'dma_resv_replace_fences']
pub fn dma_resv_replace_fences(obj &C.dma_resv, context u64, fence &C.dma_fence, usage C.vdr_usage) {
	C.vdr_replace(obj, context, fence, resv_usage(usage))
}

@[export: 'dma_resv_iter_first_unlocked']
pub fn dma_resv_iter_first_unlocked(cursor &C.dma_resv_iter) &C.dma_fence {
	return unsafe { &C.dma_fence(C.vdr_iter_first_unlocked(cursor)) }
}

@[export: 'dma_resv_iter_next_unlocked']
pub fn dma_resv_iter_next_unlocked(cursor &C.dma_resv_iter) &C.dma_fence {
	return unsafe { &C.dma_fence(C.vdr_iter_next_unlocked(cursor)) }
}

@[export: 'dma_resv_iter_first']
pub fn dma_resv_iter_first(cursor &C.dma_resv_iter) &C.dma_fence {
	return unsafe { &C.dma_fence(C.vdr_iter_first(cursor)) }
}

@[export: 'dma_resv_iter_next']
pub fn dma_resv_iter_next(cursor &C.dma_resv_iter) &C.dma_fence {
	return unsafe { &C.dma_fence(C.vdr_iter_next(cursor)) }
}

@[export: 'dma_resv_copy_fences']
pub fn dma_resv_copy_fences(dst &C.dma_resv, src &C.dma_resv) i32 { return C.vdr_copy(dst, src) }

@[export: 'dma_resv_get_fences']
pub fn dma_resv_get_fences(obj &C.dma_resv, usage C.vdr_usage, count &u32, fences &&&C.dma_fence) i32 {
	return unsafe { C.vdr_get_fences(obj, resv_usage(usage), count, &voidptr(fences)) }
}

@[export: 'dma_resv_get_singleton']
pub fn dma_resv_get_singleton(obj &C.dma_resv, usage C.vdr_usage, fence &&C.dma_fence) i32 {
	return unsafe { C.vdr_get_singleton(obj, resv_usage(usage), &voidptr(fence)) }
}

@[export: 'dma_resv_wait_timeout']
pub fn dma_resv_wait_timeout(obj &C.dma_resv, usage C.vdr_usage, intr bool, timeout usize) isize {
	return isize(C.vdr_wait(obj, resv_usage(usage), intr, u64(timeout)))
}

@[export: 'dma_resv_set_deadline']
pub fn dma_resv_set_deadline(obj &C.dma_resv, usage C.vdr_usage, deadline C.vdf_ktime_t) {
	C.vdr_deadline(obj, resv_usage(usage), fence_time_bits(deadline))
}

@[export: 'dma_resv_test_signaled']
pub fn dma_resv_test_signaled(obj &C.dma_resv, usage C.vdr_usage) bool {
	return C.vdr_test_signaled(obj, resv_usage(usage))
}

@[export: 'vdr_class']
pub fn dma_resv_class() voidptr { return unsafe { &vdr_reservation_class } }

@[export: 'vdr_lock_init']
pub fn dma_resv_lock_init(storage voidptr) {
	unsafe { C.ww_mutex_init(storage, &vdr_reservation_class) }
}

@[export: 'vdr_lock_fini']
pub fn dma_resv_lock_fini(storage voidptr) { C.ww_mutex_destroy(storage) }

@[export: 'vdr_get']
pub fn dma_resv_get(fence voidptr) voidptr {
	return unsafe { C.dma_fence_get(&C.dma_fence(fence)) }
}

@[export: 'vdr_put']
pub fn dma_resv_put(fence voidptr) {
	unsafe { C.dma_fence_put(&C.dma_fence(fence)) }
}

@[export: 'vdr_get_rcu']
pub fn dma_resv_get_rcu(fence voidptr) voidptr {
	return unsafe { C.dma_fence_get_rcu(&C.dma_fence(fence)) }
}

@[export: 'vdr_later_or_same']
pub fn dma_resv_later_or_same(fence voidptr, old voidptr) bool {
	return unsafe { C.dma_fence_is_later_or_same(&C.dma_fence(fence), &C.dma_fence(old)) }
}

@[export: 'vdr_container']
pub fn dma_resv_container(fence voidptr) bool {
	return unsafe { C.dma_fence_is_container(&C.dma_fence(fence)) }
}

@[export: 'vdr_read_lock']
pub fn dma_resv_read_lock() { C.rcu_read_lock() }

@[export: 'vdr_read_unlock']
pub fn dma_resv_read_unlock() { C.rcu_read_unlock() }
