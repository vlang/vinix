// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module dmafencefixture

#include "linuxkpi_dma_fence_fixture_v_contract.h"
struct C.dma_fence {
mut:
	@lock voidptr
	cb_list C.list_head
}
struct C.list_head {
mut:
	next &C.list_head
	prev &C.list_head
}
struct C.task_struct {
mut:
	__state u32
}
struct C.dma_fence_cb {}
struct C.dma_fence_ops {}
type Callback = fn (&C.dma_fence, &C.dma_fence_cb)
fn C.dma_fence_init(&C.dma_fence, &C.dma_fence_ops, voidptr, u64, u64)
fn C.dma_fence_get(&C.dma_fence) &C.dma_fence
fn C.dma_fence_get_rcu(&C.dma_fence) &C.dma_fence
fn C.dma_fence_get_rcu_safe(&&C.dma_fence) &C.dma_fence
fn C.dma_fence_put(&C.dma_fence)
fn C.dma_fence_free(&C.dma_fence)
fn C.dma_fence_signal(&C.dma_fence) i32
fn C.dma_fence_signal_locked(&C.dma_fence) i32
fn C.dma_fence_signal_timestamp(&C.dma_fence, i64) i32
fn C.dma_fence_signal_timestamp_locked(&C.dma_fence, i64) i32
fn C.dma_fence_get_status(&C.dma_fence) i32
fn C.dma_fence_is_signaled(&C.dma_fence) bool
fn C.dma_fence_is_signaled_locked(&C.dma_fence) bool
fn C.dma_fence_set_error(&C.dma_fence, i32)
fn C.dma_fence_timestamp(&C.dma_fence) i64
fn C.dma_fence_enable_sw_signaling(&C.dma_fence)
fn C.dma_fence_add_callback(&C.dma_fence, &C.dma_fence_cb, Callback) i32
fn C.dma_fence_remove_callback(&C.dma_fence, &C.dma_fence_cb) bool
fn C.dma_fence_wait(&C.dma_fence, bool) i64
fn C.dma_fence_wait_timeout(&C.dma_fence, bool, i64) i64
fn C.dma_fence_default_wait(&C.dma_fence, bool, i64) i64
fn C.dma_fence_wait_any_timeout(&&C.dma_fence, u32, bool, i64, &u32) i64
fn C.dma_fence_get_stub() &C.dma_fence
fn C.dma_fence_allocate_private_stub(i64) &C.dma_fence
fn C.dma_fence_context_alloc(u32) u64
fn C.dma_fence_set_deadline(&C.dma_fence, i64)
fn C.dma_fence_is_later(&C.dma_fence, &C.dma_fence) bool
fn C.dma_fence_is_later_or_same(&C.dma_fence, &C.dma_fence) bool
fn C.dma_fence_later(&C.dma_fence, &C.dma_fence) &C.dma_fence
fn C.spin_lock_irqsave(voidptr, u64)
fn C.spin_unlock_irqrestore(voidptr, u64)
fn C.__atomic_load_n(&u32, i32) u32

@[export: 'vinix_linuxkpi_dmafence_fixture_bytes']
pub fn bytes(kind u32) u32 {
	return if kind == 0 { u32(sizeof(C.dma_fence)) } else if kind == 1 { u32(sizeof(C.dma_fence_cb)) } else { u32(sizeof(C.dma_fence_ops)) }
}
@[export: 'vinix_linuxkpi_dmafence_fixture_init']
pub fn init(storage voidptr, ops voidptr, guard voidptr, context u64, seqno u64) {
	unsafe { C.dma_fence_init(&C.dma_fence(storage), &C.dma_fence_ops(ops), guard, context, seqno) }
}
@[export: 'vinix_linuxkpi_dmafence_fixture_get']
pub fn get(storage voidptr, mode u32) voidptr {
	unsafe {
		mut fence := &C.dma_fence(storage)
		if mode == 0 { return C.dma_fence_get(fence) }
		if mode == 1 { return C.dma_fence_get_rcu(fence) }
		return C.dma_fence_get_rcu_safe(&fence)
	}
}
@[export: 'vinix_linuxkpi_dmafence_fixture_put']
pub fn put(storage voidptr) { unsafe { C.dma_fence_put(&C.dma_fence(storage)) } }
@[export: 'vinix_linuxkpi_dmafence_fixture_free']
pub fn free(storage voidptr) { unsafe { C.dma_fence_free(&C.dma_fence(storage)) } }
@[export: 'vinix_linuxkpi_dmafence_fixture_signal']
pub fn signal(storage voidptr, mode u32, timestamp i64) i32 {
	unsafe {
		fence := &C.dma_fence(storage)
		mut flags := u64(0)
		if mode & 1 != 0 { C.spin_lock_irqsave(fence.@lock, flags) }
		ret := if mode == 0 { C.dma_fence_signal(fence) } else if mode == 1 { C.dma_fence_signal_locked(fence) }
			else if mode == 2 { C.dma_fence_signal_timestamp(fence, timestamp) } else { C.dma_fence_signal_timestamp_locked(fence, timestamp) }
		if mode & 1 != 0 { C.spin_unlock_irqrestore(fence.@lock, flags) }
		return ret
	}
}
@[export: 'vinix_linuxkpi_dmafence_fixture_status']
pub fn status(storage voidptr) i32 { unsafe { return C.dma_fence_get_status(&C.dma_fence(storage)) } }
@[export: 'vinix_linuxkpi_dmafence_fixture_signaled']
pub fn signaled(storage voidptr, locked bool) bool {
	unsafe {
		fence := &C.dma_fence(storage)
		mut flags := u64(0)
		if locked { C.spin_lock_irqsave(fence.@lock, flags) }
		ret := if locked { C.dma_fence_is_signaled_locked(fence) } else { C.dma_fence_is_signaled(fence) }
		if locked { C.spin_unlock_irqrestore(fence.@lock, flags) }
		return ret
	}
}
@[export: 'vinix_linuxkpi_dmafence_fixture_error']
pub fn set_error(storage voidptr, error i32) { unsafe { C.dma_fence_set_error(&C.dma_fence(storage), error) } }
@[export: 'vinix_linuxkpi_dmafence_fixture_timestamp']
pub fn timestamp(storage voidptr) i64 { unsafe { return C.dma_fence_timestamp(&C.dma_fence(storage)) } }
@[export: 'vinix_linuxkpi_dmafence_fixture_enable']
pub fn enable(storage voidptr) { unsafe { C.dma_fence_enable_sw_signaling(&C.dma_fence(storage)) } }
@[export: 'vinix_linuxkpi_dmafence_fixture_add']
pub fn add(storage voidptr, cb voidptr, callback Callback) i32 { unsafe { return C.dma_fence_add_callback(&C.dma_fence(storage), &C.dma_fence_cb(cb), callback) } }
@[export: 'vinix_linuxkpi_dmafence_fixture_remove']
pub fn remove(storage voidptr, cb voidptr) bool { unsafe { return C.dma_fence_remove_callback(&C.dma_fence(storage), &C.dma_fence_cb(cb)) } }
@[export: 'vinix_linuxkpi_dmafence_fixture_wait']
pub fn wait(storage voidptr, mode u32, intr bool, timeout i64) i64 {
	unsafe { fence := &C.dma_fence(storage)
		return if mode == 0 { C.dma_fence_default_wait(fence, intr, timeout) }
			else if mode == 1 { C.dma_fence_wait_timeout(fence, intr, timeout) } else { C.dma_fence_wait(fence, intr) }
	}
}
@[export: 'vinix_linuxkpi_dmafence_fixture_any']
pub fn wait_any(fences &voidptr, count u32, intr bool, timeout i64, index &u32) i64 {
	unsafe { return C.dma_fence_wait_any_timeout(&&C.dma_fence(fences), count, intr, timeout, index) }
}
@[export: 'vinix_linuxkpi_dmafence_fixture_stub']
pub fn stub(private bool, time i64) voidptr { return if private { C.dma_fence_allocate_private_stub(time) } else { C.dma_fence_get_stub() } }
@[export: 'vinix_linuxkpi_dmafence_fixture_context']
pub fn context(count u32) u64 { return C.dma_fence_context_alloc(count) }
@[export: 'vinix_linuxkpi_dmafence_fixture_deadline']
pub fn deadline(storage voidptr, time i64) { unsafe { C.dma_fence_set_deadline(&C.dma_fence(storage), time) } }
@[export: 'vinix_linuxkpi_dmafence_fixture_compare']
pub fn compare(first voidptr, second voidptr, mode u32) bool {
	unsafe { a := &C.dma_fence(first); b := &C.dma_fence(second)
		return if mode == 0 { C.dma_fence_is_later(a, b) } else if mode == 1 { C.dma_fence_is_later_or_same(a, b) } else { usize(C.dma_fence_later(a, b)) == usize(a) }
	}
}
@[export: 'vinix_linuxkpi_dmafence_fixture_callbacks']
pub fn callbacks(storage voidptr) u32 {
	unsafe {
		fence := &C.dma_fence(storage)
		mut flags := u64(0)
		C.spin_lock_irqsave(fence.@lock, flags)
		mut count := u32(0)
		if !C.dma_fence_is_signaled_locked(fence) {
			head := &fence.cb_list
			for entry := head.next; usize(entry) != usize(head); entry = entry.next { count++ }
		}
		C.spin_unlock_irqrestore(fence.@lock, flags)
		return count
	}
}
@[export: 'vinix_linuxkpi_dmafence_fixture_task_state']
pub fn task_state(storage voidptr) u32 {
	unsafe { return C.__atomic_load_n(&(&C.task_struct(storage)).__state, 2) }
}
