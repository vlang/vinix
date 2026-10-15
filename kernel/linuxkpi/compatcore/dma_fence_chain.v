// SPDX-License-Identifier: GPL-2.0-only
// Reference transfers follow the pinned Linux chain over original storage.
@[translated]
module compatcore

#include "linuxkpi_dma_fence_chain_v_primitives.h"

struct C.vfc_chain {
mut:
	base C.vdf_fence
	prev voidptr
	prev_seqno u64
	fence voidptr
	callback_storage [32]u8
	guard u32
}
fn C.vfc_compare_prev(&voidptr, voidptr, voidptr) voidptr
fn C.vfc_load_prev(&voidptr) voidptr
fn C.vfc_store_prev(&voidptr, voidptr)
fn C.vfc_ops_identity() voidptr
fn C.vfc_get(voidptr) voidptr
fn C.vfc_put(voidptr)
fn C.vfc_get_prev(voidptr) voidptr
fn C.vfc_is_signaled(voidptr) bool
fn C.vfc_refcount(voidptr) u32
fn C.vfc_init_work(voidptr)
fn C.vfc_child_callback(&C.dma_fence, &C.dma_fence_cb)
fn C.vdf_add_callback(voidptr, voidptr, fn (&C.dma_fence, &C.dma_fence_cb)) i32
fn C.vdf_signal(voidptr) i32
fn C.vdf_free(voidptr)
fn C.vdf_set_deadline(voidptr, i64)
fn C.vkiw_queue(voidptr, i32) bool

fn chain_cast(fence voidptr) &C.vfc_chain {
	unsafe {
		if is_null(fence) || usize((&C.vdf_fence(fence)).ops) != usize(C.vfc_ops_identity()) {
			return nil
		}
		return &C.vfc_chain(fence)
	}
}
fn chain_contained(fence voidptr) voidptr {
	chain := chain_cast(fence)
	return if is_null(chain) { fence } else { unsafe { chain.fence } }
}
@[export: 'vfc_walk']
pub fn dma_fence_chain_walk(fence voidptr) voidptr {
	unsafe {
		chain := chain_cast(fence)
		if is_null(chain) { C.vfc_put(fence); return nil }
		mut prev := C.vfc_get_prev(chain)
		for !is_null(prev) {
			prev_chain := chain_cast(prev)
			mut replacement := voidptr(nil)
			if !is_null(prev_chain) {
				if !C.vfc_is_signaled(prev_chain.fence) { break }
				replacement = C.vfc_get_prev(prev_chain)
			} else if !C.vfc_is_signaled(prev) { break }
			old := C.vfc_compare_prev(&chain.prev, prev, replacement)
			if usize(old) == usize(prev) { C.vfc_put(old) } else { C.vfc_put(replacement) }
			C.vfc_put(prev)
			prev = C.vfc_get_prev(chain)
		}
		C.vfc_put(fence)
		return prev
	}
}
@[export: 'vfc_find_seqno']
pub fn dma_fence_chain_find_seqno(storage &voidptr, seqno u64) i32 {
	unsafe {
		if seqno == 0 { return 0 }
		head := chain_cast(*storage)
		if is_null(head) || head.base.seqno < seqno { return -22 }
		mut fence := C.vfc_get(head)
		*storage = fence
		for !is_null(fence) {
			if (&C.vdf_fence(fence)).context != head.base.context || chain_cast(fence).prev_seqno < seqno { break }
			fence = dma_fence_chain_walk(fence)
			*storage = fence
		}
		C.vfc_put(head)
		return 0
	}
}
@[export: 'vfc_enable']
pub fn dma_fence_chain_enable(fence voidptr) bool {
	unsafe {
		head := chain_cast(fence)
		require(!is_null(head))
		C.vfc_get(head)
		mut current := C.vfc_get(head)
		for !is_null(current) {
			child := chain_contained(current)
			C.vfc_get(child)
			if C.vdf_add_callback(child, &head.callback_storage[0], C.vfc_child_callback) == 0 {
				C.vfc_put(current)
				return true
			}
			C.vfc_put(child)
			current = dma_fence_chain_walk(current)
		}
		C.vfc_put(head)
		return false
	}
}
@[export: 'vfc_signaled']
pub fn dma_fence_chain_signaled(fence voidptr) bool {
	mut current := C.vfc_get(fence)
	for !is_null(current) {
		if !C.vfc_is_signaled(chain_contained(current)) {
			C.vfc_put(current)
			return false
		}
		current = dma_fence_chain_walk(current)
	}
	return true
}
@[export: 'vfc_irq']
pub fn dma_fence_chain_irq(work voidptr) {
	unsafe {
		head := voidptr(&u8(work) - 88)
		if !dma_fence_chain_enable(head) { C.vdf_signal(head) }
		C.vfc_put(head)
	}
}
@[export: 'vfc_callback']
pub fn dma_fence_chain_callback(fence voidptr, cb voidptr) {
	// Publication may run and free the chain on another CPU immediately.
	C.vfc_init_work(cb)
	C.vkiw_queue(cb, -1)
	C.vfc_put(fence)
}
@[export: 'vfc_release']
pub fn dma_fence_chain_release(fence voidptr) {
	unsafe {
		chain := chain_cast(fence)
		mut prev := C.vfc_load_prev(&chain.prev)
		for !is_null(prev) {
			if C.vfc_refcount(prev) > 1 { break }
			prev_chain := chain_cast(prev)
			if is_null(prev_chain) { break }
			C.vfc_store_prev(&chain.prev, C.vfc_load_prev(&prev_chain.prev))
			C.vfc_store_prev(&prev_chain.prev, nil)
			C.vfc_put(prev)
			prev = C.vfc_load_prev(&chain.prev)
		}
		C.vfc_put(prev)
		C.vfc_put(chain.fence)
		C.vdf_free(fence)
	}
}
@[export: 'vfc_deadline']
pub fn dma_fence_chain_deadline(fence voidptr, deadline i64) {
	mut current := C.vfc_get(fence)
	for !is_null(current) {
		C.vdf_set_deadline(chain_contained(current), deadline)
		current = dma_fence_chain_walk(current)
	}
}
@[export: 'vfc_init']
pub fn dma_fence_chain_init(storage voidptr, prev voidptr, contained voidptr, sequence u64) {
	unsafe {
		require(!is_null(storage) && !is_null(contained))
		chain := &C.vfc_chain(storage)
		prev_chain := chain_cast(prev)
		C.vkp_spin_init(&chain.guard)
		C.vfc_store_prev(&chain.prev, prev)
		chain.fence = contained
		chain.prev_seqno = 0
		mut context := u64(0)
		mut seqno := sequence
		if !is_null(prev_chain) && seqno > prev_chain.base.seqno {
			context = prev_chain.base.context
			chain.prev_seqno = prev_chain.base.seqno
		} else {
			context = dma_fence_context_alloc(1)
			if !is_null(prev_chain) && prev_chain.base.seqno > seqno { seqno = prev_chain.base.seqno }
		}
		dma_fence_init(storage, C.vfc_ops_identity(), &chain.guard, context, seqno)
		if !is_null(chain_cast(contained)) { C.vkp_warn(c'dma_fence_chain nested contained chain', 0) }
	}
}
