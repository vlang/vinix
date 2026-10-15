// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module resvfixture

#include "linuxkpi_resv_fixture_v_contract.h"

struct C.dma_fence {}
struct C.ww_class {}
struct C.ww_acquire_ctx {}
struct C.dma_resv {
mut:
	fences &C.dma_resv_list
}
struct C.dma_resv_list {
mut:
	num_fences u32
	max_fences u32
}
struct C.dma_resv_iter {
mut:
	num_fences u32
}
@[typedef]
struct C.vrf_usage {}
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.dma_resv_init(&C.dma_resv)
fn C.dma_resv_fini(&C.dma_resv)
fn C.dma_resv_lock(&C.dma_resv, &C.ww_acquire_ctx) i32
fn C.dma_resv_lock_interruptible(&C.dma_resv, &C.ww_acquire_ctx) i32
fn C.dma_resv_trylock(&C.dma_resv) bool
fn C.dma_resv_unlock(&C.dma_resv)
fn C.dma_resv_is_locked(&C.dma_resv) bool
fn C.dma_resv_reserve_fences(&C.dma_resv, u32) i32
fn C.dma_resv_add_fence(&C.dma_resv, &C.dma_fence, C.vrf_usage)
fn C.dma_resv_replace_fences(&C.dma_resv, u64, &C.dma_fence, C.vrf_usage)
fn C.dma_resv_copy_fences(&C.dma_resv, &C.dma_resv) i32
fn C.dma_resv_iter_begin(&C.dma_resv_iter, &C.dma_resv, C.vrf_usage)
fn C.dma_resv_iter_first(&C.dma_resv_iter) &C.dma_fence
fn C.dma_resv_iter_next(&C.dma_resv_iter) &C.dma_fence
fn C.dma_resv_iter_first_unlocked(&C.dma_resv_iter) &C.dma_fence
fn C.dma_resv_iter_next_unlocked(&C.dma_resv_iter) &C.dma_fence
fn C.dma_resv_iter_end(&C.dma_resv_iter)
fn C.dma_resv_iter_usage(&C.dma_resv_iter) C.vrf_usage
fn C.dma_resv_iter_is_restarted(&C.dma_resv_iter) bool
fn C.dma_resv_get_fences(&C.dma_resv, C.vrf_usage, &u32, &&&C.dma_fence) i32
fn C.dma_resv_get_singleton(&C.dma_resv, C.vrf_usage, &&C.dma_fence) i32
fn C.dma_resv_wait_timeout(&C.dma_resv, C.vrf_usage, bool, usize) i64
fn C.dma_resv_set_deadline(&C.dma_resv, C.vrf_usage, i64)
fn C.dma_resv_test_signaled(&C.dma_resv, C.vrf_usage) bool
fn C.vrf_list_entry(&C.dma_resv_list, u32) &C.dma_fence
fn C.vrf_list_load(&C.dma_resv) &C.dma_resv_list
fn C.vrf_cursor_index(&C.dma_resv_iter) u32
fn C.kmalloc_size_roundup(usize) usize
fn C.krealloc_array(voidptr, usize, usize, u32) voidptr

fn usage(value u32) C.vrf_usage {
	mut result := C.vrf_usage{}
	unsafe { C.memcpy(&result, &value, sizeof(u32)) }
	return result
}
@[export: 'vinix_linuxkpi_resv_fixture_bytes']
pub fn bytes(kind u32) u32 {
	return if kind == 0 { u32(sizeof(C.dma_resv)) }
		else if kind == 1 { u32(sizeof(C.dma_resv_iter)) }
		else if kind == 2 { u32(sizeof(C.ww_class)) }
		else { u32(sizeof(C.dma_resv_list)) }
}
@[export: 'vinix_linuxkpi_resv_fixture_init']
pub fn init(storage voidptr) { unsafe { C.dma_resv_init(&C.dma_resv(storage)) } }
@[export: 'vinix_linuxkpi_resv_fixture_fini']
pub fn fini(storage voidptr) { unsafe { C.dma_resv_fini(&C.dma_resv(storage)) } }
@[export: 'vinix_linuxkpi_resv_fixture_lock']
pub fn lock(storage voidptr, mode u32) i32 {
	unsafe { obj := &C.dma_resv(storage)
		if mode == 2 { return if C.dma_resv_trylock(obj) { 0 } else { -16 } }
		return if mode == 1 { C.dma_resv_lock_interruptible(obj, nil) } else { C.dma_resv_lock(obj, nil) }
	}
}
@[export: 'vinix_linuxkpi_resv_fixture_unlock']
pub fn unlock(storage voidptr) { unsafe { C.dma_resv_unlock(&C.dma_resv(storage)) } }
@[export: 'vinix_linuxkpi_resv_fixture_locked']
pub fn locked(storage voidptr) bool { unsafe { return C.dma_resv_is_locked(&C.dma_resv(storage)) } }
@[export: 'vinix_linuxkpi_resv_fixture_reserve']
pub fn reserve(storage voidptr, count u32) i32 { unsafe { return C.dma_resv_reserve_fences(&C.dma_resv(storage), count) } }
@[export: 'vinix_linuxkpi_resv_fixture_add']
pub fn add(storage voidptr, fence voidptr, value u32) { unsafe { C.dma_resv_add_fence(&C.dma_resv(storage), &C.dma_fence(fence), usage(value)) } }
@[export: 'vinix_linuxkpi_resv_fixture_replace']
pub fn replace(storage voidptr, context u64, fence voidptr, value u32) { unsafe { C.dma_resv_replace_fences(&C.dma_resv(storage), context, &C.dma_fence(fence), usage(value)) } }
@[export: 'vinix_linuxkpi_resv_fixture_copy']
pub fn copy(dst voidptr, src voidptr) i32 { unsafe { return C.dma_resv_copy_fences(&C.dma_resv(dst), &C.dma_resv(src)) } }
@[export: 'vinix_linuxkpi_resv_fixture_begin']
pub fn begin(cursor voidptr, storage voidptr, value u32) { unsafe { C.dma_resv_iter_begin(&C.dma_resv_iter(cursor), &C.dma_resv(storage), usage(value)) } }
@[export: 'vinix_linuxkpi_resv_fixture_step']
pub fn step(cursor voidptr, mode u32) voidptr {
	unsafe { iter := &C.dma_resv_iter(cursor)
		if mode == 0 { return C.dma_resv_iter_first(iter) }
		if mode == 1 { return C.dma_resv_iter_next(iter) }
		if mode == 2 { return C.dma_resv_iter_first_unlocked(iter) }
		return C.dma_resv_iter_next_unlocked(iter)
	}
}
@[export: 'vinix_linuxkpi_resv_fixture_end']
pub fn end(cursor voidptr) { unsafe { C.dma_resv_iter_end(&C.dma_resv_iter(cursor)) } }
@[export: 'vinix_linuxkpi_resv_fixture_cursor']
pub fn cursor_value(cursor voidptr, kind u32) u32 {
	unsafe { iter := &C.dma_resv_iter(cursor)
		if kind == 0 {
			value := C.dma_resv_iter_usage(iter)
			mut result := u32(0)
			C.memcpy(&result, &value, sizeof(u32))
			return result
		}
		if kind == 1 { return u32(C.dma_resv_iter_is_restarted(iter)) }
		return if kind == 2 { iter.num_fences } else { C.vrf_cursor_index(iter) }
	}
}
@[export: 'vinix_linuxkpi_resv_fixture_list']
pub fn list(storage voidptr) voidptr { unsafe { return C.vrf_list_load(&C.dma_resv(storage)) } }
@[export: 'vinix_linuxkpi_resv_fixture_list_value']
pub fn list_value(storage voidptr, kind u32, index u32) u64 {
	unsafe { list := &C.dma_resv_list(storage)
		if list == nil { return 0 }
		if kind == 0 { return list.num_fences }
		if kind == 1 { return list.max_fences }
		return u64(usize(C.vrf_list_entry(list, index)))
	}
}
@[export: 'vinix_linuxkpi_resv_fixture_get']
pub fn get(storage voidptr, value u32, count &u32, vector &voidptr) i32 { unsafe { return C.dma_resv_get_fences(&C.dma_resv(storage), usage(value), count, &&&C.dma_fence(vector)) } }
@[export: 'vinix_linuxkpi_resv_fixture_singleton']
pub fn singleton(storage voidptr, value u32, output &voidptr) i32 { unsafe { return C.dma_resv_get_singleton(&C.dma_resv(storage), usage(value), &&C.dma_fence(output)) } }
@[export: 'vinix_linuxkpi_resv_fixture_wait']
pub fn wait(storage voidptr, value u32, intr bool, timeout u64) i64 { unsafe { return C.dma_resv_wait_timeout(&C.dma_resv(storage), usage(value), intr, usize(timeout)) } }
@[export: 'vinix_linuxkpi_resv_fixture_deadline']
pub fn deadline(storage voidptr, value u32, time i64) { unsafe { C.dma_resv_set_deadline(&C.dma_resv(storage), usage(value), time) } }
@[export: 'vinix_linuxkpi_resv_fixture_signaled']
pub fn signaled(storage voidptr, value u32) bool { unsafe { return C.dma_resv_test_signaled(&C.dma_resv(storage), usage(value)) } }
@[export: 'vinix_linuxkpi_resv_fixture_roundup']
pub fn roundup(size usize) usize { return C.kmalloc_size_roundup(size) }
@[export: 'vinix_linuxkpi_resv_fixture_realloc']
pub fn realloc(storage voidptr, count usize, size usize) voidptr { return C.krealloc_array(storage, count, size, 3264) }
