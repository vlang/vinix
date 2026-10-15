// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module swfencefixture

#include "linuxkpi_sw_fence_fixture_v_contract.h"
struct C.list_head {
mut:
	next &C.list_head
}

struct C.wait_queue_head {
mut:
	@lock u32
	head  C.list_head
}

struct C.wait_queue_entry {}

struct C.i915_sw_fence {
mut:
	@wait C.wait_queue_head
	error i32
}

struct C.i915_sw_dma_fence_cb {
mut:
	fence &C.i915_sw_fence
}

struct C.i915_sw_dma_fence_cb_timer {
mut:
	dma   &C.dma_fence
	timer C.timer_list
	work  C.irq_work
}

struct C.timer_list {
mut:
	expires usize
	flags   u32
}

struct C.irq_work {}

struct C.dma_fence {
mut:
	@lock   voidptr
	cb_list C.list_head
	flags   usize
}

struct C.dma_resv {}

@[typedef]
struct C.vswf_notify {}

type Notify = fn (&C.i915_sw_fence, C.vswf_notify) i32

fn C.__i915_sw_fence_init(&C.i915_sw_fence, Notify, &char, voidptr)
fn C.i915_sw_fence_fini(&C.i915_sw_fence)
fn C.i915_sw_fence_reinit(&C.i915_sw_fence)
fn C.i915_sw_fence_await(&C.i915_sw_fence) bool
fn C.i915_sw_fence_complete(&C.i915_sw_fence)
fn C.i915_sw_fence_commit(&C.i915_sw_fence)
fn C.i915_sw_fence_wait(&C.i915_sw_fence)
fn C.i915_sw_fence_set_error_once(&C.i915_sw_fence, i32)
fn C.i915_sw_fence_signaled(&C.i915_sw_fence) bool
fn C.i915_sw_fence_done(&C.i915_sw_fence) bool
fn C.i915_sw_fence_await_sw_fence(&C.i915_sw_fence, &C.i915_sw_fence, &C.wait_queue_entry) i32
fn C.i915_sw_fence_await_sw_fence_gfp(&C.i915_sw_fence, &C.i915_sw_fence, u32) i32
fn C.i915_sw_fence_await_dma_fence(&C.i915_sw_fence, &C.dma_fence, usize, u32) i32
fn C.__i915_sw_fence_await_dma_fence(&C.i915_sw_fence, &C.dma_fence, &C.i915_sw_dma_fence_cb) i32
fn C.i915_sw_fence_await_reservation(&C.i915_sw_fence, &C.dma_resv, bool, usize, u32) i32
fn C.vswf_pending(&C.i915_sw_fence) i32
fn C.vswf_timed_fence(&C.i915_sw_dma_fence_cb_timer) &C.i915_sw_fence
fn C.vswf_timed_flags(&C.i915_sw_dma_fence_cb_timer) i32
fn C.timer_pending(&C.timer_list) bool
fn C.irq_work_sync(&C.irq_work)
fn C.spin_lock_irqsave(voidptr, u64)
fn C.spin_unlock_irqrestore(voidptr, u64)
fn C.BUG_ON(bool)
fn C.vkr_page_allocation_size(voidptr) usize

@[c_extern]
__global C.jiffies usize

@[export: 'vinix_linuxkpi_swf_bytes']
pub fn bytes(kind u32) u32 {
	return if kind == 0 {
		u32(sizeof(C.i915_sw_fence))
	} else if kind == 1 {
		u32(sizeof(C.wait_queue_entry))
	} else if kind == 2 {
		u32(sizeof(C.i915_sw_dma_fence_cb))
	} else {
		u32(sizeof(C.i915_sw_dma_fence_cb_timer))
	}
}

@[export: 'vinix_linuxkpi_swf_init']
pub fn init(storage voidptr, notify Notify) {
	C.BUG_ON(usize(voidptr(notify)) < 4096)
	unsafe { C.__i915_sw_fence_init(&C.i915_sw_fence(storage), notify, nil, nil) }
}

@[export: 'vinix_linuxkpi_swf_fini']
pub fn fini(storage voidptr) {
	unsafe { C.i915_sw_fence_fini(&C.i915_sw_fence(storage)) }
}

@[export: 'vinix_linuxkpi_swf_reinit']
pub fn reinit(storage voidptr) {
	unsafe { C.i915_sw_fence_reinit(&C.i915_sw_fence(storage)) }
}

@[export: 'vinix_linuxkpi_swf_await']
pub fn acquire(storage voidptr) bool {
	unsafe {
		return C.i915_sw_fence_await(&C.i915_sw_fence(storage))
	}
}

@[export: 'vinix_linuxkpi_swf_complete']
pub fn complete(storage voidptr) {
	unsafe { C.i915_sw_fence_complete(&C.i915_sw_fence(storage)) }
}

@[export: 'vinix_linuxkpi_swf_commit']
pub fn commit(storage voidptr) {
	unsafe { C.i915_sw_fence_commit(&C.i915_sw_fence(storage)) }
}

@[export: 'vinix_linuxkpi_swf_wait']
pub fn wait(storage voidptr) {
	unsafe { C.i915_sw_fence_wait(&C.i915_sw_fence(storage)) }
}

@[export: 'vinix_linuxkpi_swf_error']
pub fn error(storage voidptr, value i32) {
	unsafe { C.i915_sw_fence_set_error_once(&C.i915_sw_fence(storage), value) }
}

@[export: 'vinix_linuxkpi_swf_state']
pub fn state(storage voidptr, kind u32) i32 {
	unsafe {
		fence := &C.i915_sw_fence(storage)
		if kind == 0 { return C.vswf_pending(fence) }
		if kind == 1 { return fence.error }
		return if kind == 2 {
			i32(C.i915_sw_fence_signaled(fence))
		} else {
			i32(C.i915_sw_fence_done(fence))
		}
	}
}

@[export: 'vinix_linuxkpi_swf_waiters']
pub fn waiters(storage voidptr) u32 {
	unsafe {
		fence := &C.i915_sw_fence(storage)
		mut flags := u64(0)
		C.spin_lock_irqsave(&fence.@wait.@lock, flags)
		mut count := u32(0)
		head := &fence.@wait.head
		for entry := head.next; usize(entry) != usize(head); entry = entry.next { count++ }
		C.spin_unlock_irqrestore(&fence.@wait.@lock, flags)
		return count
	}
}

@[export: 'vinix_linuxkpi_swf_sw']
pub fn sw(storage voidptr, signaler voidptr, entry voidptr, gfp u32) i32 {
	unsafe {
		target := &C.i915_sw_fence(storage)
		source := &C.i915_sw_fence(signaler)
		return if entry != nil {
			C.i915_sw_fence_await_sw_fence(target, source, &C.wait_queue_entry(entry))
		} else {
			C.i915_sw_fence_await_sw_fence_gfp(target, source, gfp)
		}
	}
}

@[export: 'vinix_linuxkpi_swf_dma']
pub fn dma(storage voidptr, producer voidptr, callback voidptr, timeout u64, gfp u32) i32 {
	unsafe {
		target := &C.i915_sw_fence(storage)
		source := &C.dma_fence(producer)
		return if callback != nil {
			C.__i915_sw_fence_await_dma_fence(target, source, &C.i915_sw_dma_fence_cb(callback))
		} else {
			C.i915_sw_fence_await_dma_fence(target, source, usize(timeout), gfp)
		}
	}
}

@[export: 'vinix_linuxkpi_swf_resv']
pub fn resv(storage voidptr, reservation voidptr, write bool, timeout u64, gfp u32) i32 {
	unsafe {
		return C.i915_sw_fence_await_reservation(&C.i915_sw_fence(storage), &C.dma_resv(reservation), write, usize(timeout), gfp)
	}
}

@[export: 'vinix_linuxkpi_swf_timed']
pub fn timed(producer voidptr, target voidptr) voidptr {
	// Native test only: a dedicated producer has exactly one dynamically
	// allocated timed SW callback. Call before signal and retain remote RCU
	// protection until timed_sync and every private-owner observation finish.
	unsafe {
		fence := &C.dma_fence(producer)
		mut flags := u64(0)
		C.spin_lock_irqsave(fence.@lock, flags)
		head := &fence.cb_list
		mut found := voidptr(nil)
		if fence.flags & 1 == 0 && usize(head.next) != usize(head) && usize(head.next.next) == usize(head) {
			entry := head.next
			if C.vkr_page_allocation_size(entry) == 128 {
				owner := &C.i915_sw_dma_fence_cb_timer(entry)
				fence_target := C.vswf_timed_fence(owner)
				if usize(owner.dma) == usize(producer) && (usize(fence_target) == usize(target) || fence_target == nil) {
					found = entry
				}
			}
		}
		C.spin_unlock_irqrestore(fence.@lock, flags)
		return found
	}
}

@[export: 'vinix_linuxkpi_swf_timed_value']
pub fn timed_value(storage voidptr, kind u32) u64 {
	unsafe {
		owner := &C.i915_sw_dma_fence_cb_timer(storage)
		if kind == 0 { return u64(usize(C.vswf_timed_fence(owner))) }
		if kind == 1 { return u64(owner.timer.expires) }
		if kind == 2 { return u64(C.timer_pending(&owner.timer)) }
		return if kind == 3 { u64(owner.timer.flags) } else { u64(u32(C.vswf_timed_flags(owner))) }
	}
}

@[export: 'vinix_linuxkpi_swf_timed_sync']
pub fn timed_sync(storage voidptr) {
	unsafe { C.irq_work_sync(&(&C.i915_sw_dma_fence_cb_timer(storage)).work) }
}

@[export: 'vinix_linuxkpi_swf_now']
pub fn now() u64 { return u64(C.jiffies) }
