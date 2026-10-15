// SPDX-License-Identifier: GPL-2.0-only
// Native algorithm over the unchanged dma_fence_array and appended callbacks.
@[translated]
module compatcore

#include "linuxkpi_dma_fence_array_v_primitives.h"

struct C.vfa_array {
mut:
	base        C.vdf_fence
	@lock       u32
	num_fences  u32
	num_pending i32
	fences      &voidptr
	work        C.vkiw_work
}

struct C.vfa_cb {
mut:
	cb    C.vdf_cb
	array &C.vfa_array
}

@[typedef]
struct C.vfa_const_char_p {}

@[typedef]
struct C.vfa_ktime_t {}

fn C.vfa_pending_load(&i32) i32
fn C.vfa_pending_dec(&i32) bool
fn C.vfa_error_compare(&i32, &i32, i32) bool
fn C.vfa_ops() voidptr
fn C.vfa_fence_put(voidptr)
fn C.vfa_is_container(voidptr) bool
fn C.vfa_init_work(voidptr, fn (&C.irq_work))

@[export: 'vfa_driver_name']
pub fn dma_fence_array_driver_name(fence &C.dma_fence) C.vfa_const_char_p {
	mut name := C.vfa_const_char_p{}
	text := unsafe { &char(c'dma_fence_array') }
	unsafe { C.memcpy(&name, &text, sizeof(voidptr)) }
	return name
}

@[export: 'vfa_timeline_name']
pub fn dma_fence_array_timeline_name(fence &C.dma_fence) C.vfa_const_char_p {
	mut name := C.vfa_const_char_p{}
	text := unsafe { &char(c'unbound') }
	unsafe { C.memcpy(&name, &text, sizeof(voidptr)) }
	return name
}

fn array_set_pending_error(aggregate &C.vfa_array, error i32) {
	if error == 0 { return }
	mut expected := i32(1)
	unsafe { C.vfa_error_compare(&aggregate.base.error, &expected, error) }
}

fn array_clear_pending_error(aggregate &C.vfa_array) {
	mut expected := i32(1)
	unsafe { C.vfa_error_compare(&aggregate.base.error, &expected, 0) }
}

fn array_irq_work(work &C.irq_work) {
	unsafe {
		aggregate := &C.vfa_array(usize(work) - 88)
		array_clear_pending_error(aggregate)
		dma_fence_signal(aggregate)
		C.vfa_fence_put(aggregate)
		// The final put can retire the entire aggregate. No object access follows.
	}
}

fn array_child_callback(fence &C.dma_fence, callback &C.dma_fence_cb) {
	unsafe {
		aggregate := (&C.vfa_cb(callback)).array
		array_set_pending_error(aggregate, (&C.vdf_fence(fence)).error)
		if C.vfa_pending_dec(&aggregate.num_pending) {
			irq_work_queue(&aggregate.work, -1)
			// The event's parent reference transfers to IRQ work. Publication can
			// complete and retire it before queueing returns on another CPU.
		} else {
			C.vfa_fence_put(aggregate)
		}
	}
}

@[export: 'vfa_enable_signaling']
pub fn dma_fence_array_enable_signaling(fence &C.dma_fence) bool {
	unsafe {
		aggregate := &C.vfa_array(fence)
		callbacks := &C.vfa_cb(usize(aggregate) + sizeof(C.vfa_array))
		for i := u32(0); i < aggregate.num_fences; i++ {
			callbacks[i].array = aggregate
			// ANY can complete while other registered children remain pending.
			// Each callback holds a parent reference until it has run.
			C.vdf_fence_get(aggregate)
			if dma_fence_add_callback(aggregate.fences[i], &callbacks[i].cb, array_child_callback) != 0 {
				array_set_pending_error(aggregate, (&C.vdf_fence(aggregate.fences[i])).error)
				C.vfa_fence_put(aggregate)
				if C.vfa_pending_dec(&aggregate.num_pending) {
					array_clear_pending_error(aggregate)
					return false
				}
			}
		}
		return true
	}
}

@[export: 'vfa_signaled']
pub fn dma_fence_array_signaled(fence &C.dma_fence) bool {
	unsafe {
		aggregate := &C.vfa_array(fence)
		// Acquire the pending count before ENABLE to avoid a partial-enable
		// observation. ANY's legitimate tail counts are negative.
		mut pending := C.vfa_pending_load(&aggregate.num_pending)
		if (C.vdf_load_flags(&aggregate.base.flags) & 4) != 0 {
			if pending > 0 { return false }
		} else {
			mut settled := false
			for i := u32(0); i < aggregate.num_fences; i++ {
				if fence_is_signaled(&C.vdf_fence(aggregate.fences[i]), false) {
					pending--
					if pending == 0 {
						settled = true
						break
					}
				}
			}
			if !settled { return false }
		}
		array_clear_pending_error(aggregate)
		return true
	}
}

@[export: 'vfa_release']
pub fn dma_fence_array_release(fence &C.dma_fence) {
	unsafe {
		aggregate := &C.vfa_array(fence)
		for i := u32(0); i < aggregate.num_fences; i++ { C.vfa_fence_put(aggregate.fences[i]) }
		C.kfree(aggregate.fences)
		dma_fence_free(fence)
	}
}

@[export: 'vfa_set_deadline']
pub fn dma_fence_array_set_deadline(fence &C.dma_fence, deadline C.vfa_ktime_t) {
	mut timestamp := i64(0)
	unsafe {
		C.memcpy(&timestamp, &deadline, sizeof(timestamp))
		aggregate := &C.vfa_array(fence)
		for i := u32(0); i < aggregate.num_fences; i++ {
			dma_fence_set_deadline(aggregate.fences[i], timestamp)
		}
	}
}

@[export: 'vfa_create']
pub fn dma_fence_array_create(count i32, storage voidptr, context u64, seqno u32, any bool) voidptr {
	unsafe {
		// Original callers must provide a positive count and valid children.
		// Reject malformed inputs without stealing the caller's vector/refs.
		if count <= 0 || is_null(storage) {
			C.vkp_warn(c'dma_fence_array_create invalid count or vector', 0)
			return nil
		}
		fences := &voidptr(storage)
		for i := i32(0); i < count; i++ {
			if is_null(fences[i]) {
				C.vkp_warn(c'dma_fence_array_create null child', 0)
				return nil
			}
		}
		if usize(count) > (usize(-1) - sizeof(C.vfa_array)) / sizeof(C.vfa_cb) { return nil }
		aggregate := &C.vfa_array(C.kzalloc(sizeof(C.vfa_array) + usize(count) * sizeof(C.vfa_cb), 3264))
		if is_null(aggregate) { return nil }
		C.vkp_spin_init(&aggregate.@lock)
		dma_fence_init(aggregate, C.vfa_ops(), &aggregate.@lock, context, u64(seqno))
		C.vfa_init_work(&aggregate.work, array_irq_work)
		aggregate.num_fences = u32(count)
		aggregate.num_pending = if any { i32(1) } else { count }
		aggregate.fences = fences
		aggregate.base.error = 1
		for i := count; i > 0; {
			i--
			if C.vfa_is_container(fences[i]) {
				C.vkp_warn(c'dma_fence_array_create nested container', 0)
			}
		}
		return aggregate
	}
}

fn array_from_fence(storage voidptr) &C.vfa_array {
	unsafe {
		if is_null(storage) || usize((&C.vdf_fence(storage)).ops) != usize(C.vfa_ops()) {
			return nil
		}
		return &C.vfa_array(storage)
	}
}

@[export: 'vfa_match_context']
pub fn dma_fence_array_match_context(storage voidptr, context u64) bool {
	unsafe {
		aggregate := array_from_fence(storage)
		if is_null(aggregate) { return (&C.vdf_fence(storage)).context == context }
		for i := u32(0); i < aggregate.num_fences; i++ {
			if (&C.vdf_fence(aggregate.fences[i])).context != context { return false }
		}
		return true
	}
}

@[export: 'vfa_first']
pub fn dma_fence_array_first(storage voidptr) voidptr {
	unsafe {
		if is_null(storage) { return nil }
		aggregate := array_from_fence(storage)
		if is_null(aggregate) { return storage }
		if aggregate.num_fences == 0 { return nil }
		return aggregate.fences[0]
	}
}

@[export: 'vfa_next']
pub fn dma_fence_array_next(storage voidptr, index u32) voidptr {
	unsafe {
		aggregate := array_from_fence(storage)
		if is_null(aggregate) || index >= aggregate.num_fences { return nil }
		return aggregate.fences[index]
	}
}
