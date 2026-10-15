// SPDX-License-Identifier: GPL-2.0-only
// Original fence storage is shared directly with unchanged Linux consumers.
@[translated]
module compatcore

#include "linuxkpi_dma_fence_v_primitives.h"

struct C.dma_fence {}
struct C.dma_fence_cb {}
@[typedef]
struct C.vdf_const_char_p {}
@[typedef]
struct C.vdf_ktime_t {}
struct C.vdf_list {
mut:
	next &C.vdf_list
	prev &C.vdf_list
}
struct C.vdf_ops {
	get_driver_name fn (&C.dma_fence) C.vdf_const_char_p
	get_timeline_name fn (&C.dma_fence) C.vdf_const_char_p
	enable_signaling fn (&C.dma_fence) bool
	signaled fn (&C.dma_fence) bool
	@wait fn (&C.dma_fence, bool, isize) isize
	release fn (&C.dma_fence)
	set_deadline fn (&C.dma_fence, C.vdf_ktime_t)
}
struct C.vdf_fence {
mut:
	@lock voidptr
	ops &C.vdf_ops
	cb_list C.vdf_list
	context u64
	seqno u64
	flags u64
	refcount u32
	error i32
}
struct C.vdf_cb {
mut:
	node C.vdf_list
	func fn (&C.dma_fence, &C.dma_fence_cb)
}
struct C.vdf_wait_cb {
mut:
	base C.vdf_cb
	task voidptr
}
fn C.vdf_load_flags(&u64) u64
fn C.vdf_or_flags(&u64, u64) u64
fn C.vdf_fetch_context(&u64, u64) u64
fn C.vdf_stub_storage() voidptr
fn C.vdf_stub_lock() voidptr
fn C.vdf_stub_ops() voidptr
fn C.vdf_fence_get(voidptr) voidptr
fn C.vdf_current_get() voidptr
fn C.vdf_task_put(voidptr)
fn C.vdf_wake(voidptr)
fn C.vkr_kvfree_call_rcu(voidptr, voidptr)

@[cinit]
__global vdf_context_counter u64 = 1

fn fence_list_init(node &C.vdf_list) {
	unsafe { node.next = node; node.prev = node }
}
fn fence_list_empty(node &C.vdf_list) bool { return unsafe { usize(node.next) == usize(node) } }
fn fence_list_add(node &C.vdf_list, previous &C.vdf_list, next &C.vdf_list) {
	unsafe { next.prev = node; node.next = next; node.prev = previous; previous.next = node }
}
fn fence_list_remove(node &C.vdf_list) {
	unsafe { node.next.prev = node.prev; node.prev.next = node.next; fence_list_init(node) }
}
fn fence_signaled(fence &C.vdf_fence) bool {
	return unsafe { (C.vdf_load_flags(&fence.flags) & 1) != 0 }
}
fn fence_sleepable() bool {
	return C.vinix_linuxkpi_may_sleep() && C.vinix_linuxkpi_smp_task_present()
		&& C.vinix_linuxkpi_maskable_irq_depth() == 0
		&& C.vinix_linuxkpi_preempt_count() == 0
		&& (C.vinix_linuxkpi_irq_flags() & 512) != 0
}
fn fence_is_signaled(fence &C.vdf_fence, locked bool) bool {
	unsafe {
		if fence_signaled(fence) { return true }
		if !is_null(voidptr(fence.ops.signaled)) && fence.ops.signaled(&C.dma_fence(fence)) {
			if locked { dma_fence_signal_locked(fence) } else { dma_fence_signal(fence) }
			return true
		}
		return false
	}
}
fn fence_enable_locked(fence &C.vdf_fence) bool {
	unsafe {
		old := C.vdf_or_flags(&fence.flags, 4)
		if fence_signaled(fence) { return false }
		if (old & 4) == 0 && !is_null(voidptr(fence.ops.enable_signaling))
			&& !fence.ops.enable_signaling(&C.dma_fence(fence)) {
			dma_fence_signal_locked(fence)
			return false
		}
		return true
	}
}
@[export: 'vdf_context_alloc']
pub fn dma_fence_context_alloc(count u32) u64 {
	if count == 0 { C.vkp_warn(c'dma_fence_context_alloc zero count', 0) }
	return unsafe { C.vdf_fetch_context(&vdf_context_counter, u64(count)) }
}
@[export: 'vdf_init']
pub fn dma_fence_init(storage voidptr, ops_storage voidptr, guard voidptr, context u64, seqno u64) {
	unsafe {
		require(!is_null(storage) && !is_null(guard) && !is_null(ops_storage))
		fence := &C.vdf_fence(storage)
		ops := &C.vdf_ops(ops_storage)
		require(!is_null(voidptr(ops.get_driver_name)) && !is_null(voidptr(ops.get_timeline_name)))
		fence.refcount = 1
		fence.ops = ops
		fence_list_init(&fence.cb_list)
		fence.@lock = guard
		fence.context = context
		fence.seqno = seqno
		fence.flags = 0
		fence.error = 0
	}
}
@[export: 'vdf_signal_timestamp_locked']
pub fn dma_fence_signal_timestamp_locked(storage voidptr, timestamp i64) i32 {
	unsafe {
		fence := &C.vdf_fence(storage)
		if (C.vdf_or_flags(&fence.flags, 1) & 1) != 0 { return -22 }
		// Detach into a genuine stack sentinel before overwriting the union.
		mut callbacks := C.vdf_list{}
		sentinel := &callbacks
		fence_list_init(sentinel)
		if !fence_list_empty(&fence.cb_list) {
			sentinel.next = fence.cb_list.next
			sentinel.prev = fence.cb_list.prev
			sentinel.next.prev = sentinel
			sentinel.prev.next = sentinel
		}
		C.memcpy(&fence.cb_list, &timestamp, sizeof(timestamp))
		C.vdf_or_flags(&fence.flags, 2)
		mut node := sentinel.next
		for usize(node) != usize(sentinel) {
			cb := &C.vdf_cb(node)
			next := node.next
			callback := cb.func
			fence_list_init(node)
			callback(&C.dma_fence(storage), &C.dma_fence_cb(cb))
			// A callback may immediately free its own enclosing allocation.
			node = next
		}
		return 0
	}
}
@[export: 'vdf_signal_timestamp']
pub fn dma_fence_signal_timestamp(storage voidptr, timestamp i64) i32 {
	unsafe {
		if is_null(storage) { return -22 }
		fence := &C.vdf_fence(storage)
		guard := fence.@lock
		flags := C.vkp_spin_lock_irqsave(guard)
		result := dma_fence_signal_timestamp_locked(storage, timestamp)
		C.vkp_spin_unlock_irqrestore(guard, flags)
		return result
	}
}
@[export: 'vdf_signal_locked']
pub fn dma_fence_signal_locked(storage voidptr) i32 {
	return dma_fence_signal_timestamp_locked(storage, time_ktime_get())
}
@[export: 'vdf_signal']
pub fn dma_fence_signal(storage voidptr) i32 {
	unsafe {
		if is_null(storage) { return -22 }
		guard := (&C.vdf_fence(storage)).@lock
		flags := C.vkp_spin_lock_irqsave(guard)
		result := dma_fence_signal_timestamp_locked(storage, time_ktime_get())
		C.vkp_spin_unlock_irqrestore(guard, flags)
		return result
	}
}
@[export: 'vdf_enable_sw_signaling']
pub fn dma_fence_enable_sw_signaling(storage voidptr) {
	unsafe {
		fence := &C.vdf_fence(storage)
		guard := fence.@lock
		flags := C.vkp_spin_lock_irqsave(guard)
		fence_enable_locked(fence)
		C.vkp_spin_unlock_irqrestore(guard, flags)
	}
}
@[export: 'vdf_add_callback']
pub fn dma_fence_add_callback(storage voidptr, callback_storage voidptr, callback fn (&C.dma_fence, &C.dma_fence_cb)) i32 {
	unsafe {
		if is_null(storage) || is_null(voidptr(callback)) {
			C.vkp_warn(c'dma_fence_add_callback invalid argument', 0)
			return -22
		}
		fence := &C.vdf_fence(storage)
		cb := &C.vdf_cb(callback_storage)
		if fence_signaled(fence) { fence_list_init(&cb.node); return -2 }
		guard := fence.@lock
		flags := C.vkp_spin_lock_irqsave(guard)
		mut result := i32(0)
		if fence_enable_locked(fence) {
			cb.func = callback
			fence_list_add(&cb.node, fence.cb_list.prev, &fence.cb_list)
		} else { fence_list_init(&cb.node); result = -2 }
		C.vkp_spin_unlock_irqrestore(guard, flags)
		return result
	}
}
@[export: 'vdf_remove_callback']
pub fn dma_fence_remove_callback(storage voidptr, callback_storage voidptr) bool {
	unsafe {
		fence := &C.vdf_fence(storage)
		cb := &C.vdf_cb(callback_storage)
		guard := fence.@lock
		flags := C.vkp_spin_lock_irqsave(guard)
		result := !fence_list_empty(&cb.node)
		if result { fence_list_remove(&cb.node) }
		C.vkp_spin_unlock_irqrestore(guard, flags)
		return result
	}
}
@[export: 'vdf_get_status']
pub fn dma_fence_get_status(storage voidptr) i32 {
	unsafe {
		fence := &C.vdf_fence(storage)
		guard := fence.@lock
		flags := C.vkp_spin_lock_irqsave(guard)
		mut result := i32(0)
		if fence_is_signaled(fence, true) { result = if fence.error != 0 { fence.error } else { i32(1) } }
		C.vkp_spin_unlock_irqrestore(guard, flags)
		return result
	}
}
fn fence_wait_callback(fence &C.dma_fence, cb &C.dma_fence_cb) {
	unsafe { task := (&C.vdf_wait_cb(cb)).task; C.vdf_wake(task) }
}
@[export: 'vdf_default_wait']
pub fn dma_fence_default_wait(storage voidptr, intr bool, timeout i64) i64 {
	unsafe {
		// The original direct default wait has non-sleeping fast returns even
		// for positive timeouts. Capture caller context before taking the lock;
		// only an actual sleeping callback publication requires that context.
		can_sleep := timeout <= 0 || fence_sleepable()
		fence := &C.vdf_fence(storage)
		guard := fence.@lock
		mut ret := if timeout != 0 { timeout } else { i64(1) }
		mut flags := C.vkp_spin_lock_irqsave(guard)
		if fence_signaled(fence) { C.vkp_spin_unlock_irqrestore(guard, flags); return ret }
		if intr && C.vkp_signal_pending(1) { C.vkp_spin_unlock_irqrestore(guard, flags); return -512 }
		if timeout == 0 { C.vkp_spin_unlock_irqrestore(guard, flags); return 0 }
		if timeout > 0 { require(can_sleep) }
		mut cb := C.vdf_wait_cb{}
		cb.base.func = fence_wait_callback
		cb.task = C.vdf_current_get()
		fence_list_add(&cb.base.node, &fence.cb_list, fence.cb_list.next)
		for !fence_signaled(fence) && ret > 0 {
			set_task_state(if intr { u32(1) } else { u32(2) })
			C.vkp_spin_unlock_irqrestore(guard, flags)
			ret = C.vkp_schedule_timeout(ret)
			flags = C.vkp_spin_lock_irqsave(guard)
			if ret > 0 && intr && C.vkp_signal_pending(1) { ret = -512 }
		}
		if !fence_list_empty(&cb.base.node) { fence_list_remove(&cb.base.node) }
		set_task_state(0)
		C.vkp_spin_unlock_irqrestore(guard, flags)
		C.vdf_task_put(cb.task)
		return ret
	}
}
@[export: 'vdf_wait_timeout']
pub fn dma_fence_wait_timeout(storage voidptr, intr bool, timeout i64) i64 {
	if timeout < 0 { C.vkp_warn(c'dma_fence_wait_timeout negative timeout', 0); return -22 }
	require(fence_sleepable())
	dma_fence_enable_sw_signaling(storage)
	unsafe {
		fence := &C.vdf_fence(storage)
		custom_wait := fence.ops.@wait
		if !is_null(voidptr(custom_wait)) { return i64(custom_wait(&C.dma_fence(storage), intr, isize(timeout))) }
	}
	return dma_fence_default_wait(storage, intr, timeout)
}
fn fence_any_signaled(fences &voidptr, count u32, index &u32) bool {
	unsafe {
		for i := u32(0); i < count; i++ {
			if fence_signaled(&C.vdf_fence(fences[i])) { if !is_null(index) { *index = i }; return true }
		}
		return false
	}
}
@[export: 'vdf_wait_any_timeout']
pub fn dma_fence_wait_any_timeout(storage voidptr, count u32, intr bool, timeout i64, index &u32) i64 {
	unsafe {
		if is_null(storage) || count == 0 || timeout < 0 {
			C.vkp_warn(c'dma_fence_wait_any_timeout invalid argument', 0)
			return -22
		}
		fences := &voidptr(storage)
		if timeout == 0 {
			for i := u32(0); i < count; i++ {
				if fence_is_signaled(&C.vdf_fence(fences[i]), false) { if !is_null(index) { *index = i }; return 1 }
			}
			return 0
		}
		require(fence_sleepable())
		// Checked allocation precedes registration and already-signaled checks.
		callbacks := &C.vdf_wait_cb(C.kmalloc_array(usize(count), sizeof(C.vdf_wait_cb), 3264 | 0x100))
		if is_null(callbacks) { return -12 }
		task := C.vdf_current_get()
		mut registered := u32(0)
		mut ret := timeout
		for registered < count {
			callbacks[registered].task = task
			if dma_fence_add_callback(fences[registered], &callbacks[registered].base, fence_wait_callback) != 0 {
				if !is_null(index) { *index = registered }
				break
			}
			registered++
		}
		if registered == count {
			for ret > 0 {
				set_task_state(if intr { u32(1) } else { u32(2) })
				if fence_any_signaled(fences, count, index) { break }
				ret = C.vkp_schedule_timeout(ret)
				if ret > 0 && intr && C.vkp_signal_pending(1) { ret = -512 }
			}
			set_task_state(0)
		}
		for registered > 0 { registered--; dma_fence_remove_callback(fences[registered], &callbacks[registered].base) }
		C.vdf_task_put(task)
		C.kfree(callbacks)
		return ret
	}
}
@[export: 'vdf_set_deadline']
pub fn dma_fence_set_deadline(storage voidptr, deadline i64) {
	unsafe {
		fence := &C.vdf_fence(storage)
		if !is_null(voidptr(fence.ops.set_deadline)) && !fence_is_signaled(fence, false) {
			mut native := C.vdf_ktime_t{}
			C.memcpy(&native, &deadline, sizeof(deadline))
			fence.ops.set_deadline(&C.dma_fence(storage), native)
		}
	}
}
@[export: 'vdf_free']
pub fn dma_fence_free(storage voidptr) {
	unsafe { C.vkr_kvfree_call_rcu(voidptr(usize(storage) + 16), storage) }
}
@[export: 'vdf_release']
pub fn dma_fence_release(refcount voidptr) {
	unsafe {
		fence := &C.vdf_fence(usize(refcount) - 56)
		if !fence_signaled(fence) && !fence_list_empty(&fence.cb_list) {
			driver := fence.ops.get_driver_name(&C.dma_fence(fence))
			timeline := fence.ops.get_timeline_name(&C.dma_fence(fence))
			C.vkp_warn(c'dma_fence_release pending callbacks', 0)
			C._printk(c'\x01\x34linuxkpi: Fence %s:%s:%llx:%llx released with pending signals!\n',
				voidptr(driver), voidptr(timeline), voidptr(fence.context), voidptr(fence.seqno))
			guard := fence.@lock
			flags := C.vkp_spin_lock_irqsave(guard)
			fence.error = -35
			dma_fence_signal_locked(fence)
			C.vkp_spin_unlock_irqrestore(guard, flags)
		}
		release := fence.ops.release
		if !is_null(voidptr(release)) { release(&C.dma_fence(fence)) }
		else { dma_fence_free(fence) }
		// The release hook may have freed the complete fence allocation.
	}
}
@[export: 'vdf_get_stub']
pub fn dma_fence_get_stub() voidptr {
	unsafe {
		storage := C.vdf_stub_storage()
		guard := C.vdf_stub_lock()
		C.vkp_spin_lock(guard)
		fence := &C.vdf_fence(storage)
		if is_null(fence.ops) {
			dma_fence_init(storage, C.vdf_stub_ops(), guard, 0, 0)
			C.vdf_or_flags(&fence.flags, 4)
			dma_fence_signal_locked(storage)
		}
		C.vkp_spin_unlock(guard)
		return C.vdf_fence_get(storage)
	}
}
@[export: 'vdf_allocate_private_stub']
pub fn dma_fence_allocate_private_stub(timestamp i64) voidptr {
	unsafe {
		storage := C.kzalloc(sizeof(C.vdf_fence), 3264)
		if is_null(storage) { return nil }
		dma_fence_init(storage, C.vdf_stub_ops(), C.vdf_stub_lock(), 0, 0)
		C.vdf_or_flags(&(&C.vdf_fence(storage)).flags, 4)
		dma_fence_signal_timestamp(storage, timestamp)
		return storage
	}
}
