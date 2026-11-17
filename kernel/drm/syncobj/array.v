// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

import katomic
import memory

// Flat arrays own their pointer table and callback tail. They remain private
// and unarmed until installed in a chain; published metadata stays retained.
fn new_merge_array(children &&DmaFence, count u32) ?&DmaFence {
	context := new_queue_context() or { return none }
	bytes := sizeof(DmaFence) + u64(count) * sizeof(ChainWaiter)
	allocation := memory.malloc_packed_fallible(bytes)
	if allocation == unsafe { nil } { return none }
	unsafe { C.memset(allocation, 0, bytes) }
	mut fence := unsafe { &DmaFence(allocation) }
	unsafe { *fence = DmaFence{fence_array: true, merge_reserved: true, context: context, seqno: 1,
		array_count: count, array_pending: count, array_fences: children,
		array_waiters: &ChainWaiter(&u8(allocation) + sizeof(DmaFence))} }
	return fence
}

// No fence locks or callbacks: object-locked timeline lookup uses this helper.
fn array_leaf_ready(fence &DmaFence) bool {
	if fence == unsafe { nil } || katomic.load(&fence.signaled) { return true }
	return fence.fence_array && array_ready(fence)
}

fn array_ready(fence &DmaFence) bool {
	if katomic.load(&fence.array_enabled) { return katomic.load(&fence.array_pending) == 0 }
	for index := u32(0); index < fence.array_count; index++ {
		if !katomic.load(unsafe { &fence.array_fences[index].signaled }) { return false }
	}
	return true
}

fn complete_array(fence &DmaFence) {
	mut f := unsafe { fence }
	katomic.cas(mut &f.array_error, i64(1), i64(0))
	complete_fence(fence, int(katomic.load(&f.array_error)), true)
}

// Called with the completed child's lock held. Atomic error/counter state
// avoids taking the parent's lock; final completion runs in the shared drainer.
fn array_child_complete(parent &DmaFence, error_code int) {
	mut f := unsafe { parent }
	if error_code != 0 { katomic.cas(mut &f.array_error, i64(1), i64(error_code)) }
	if !katomic.dec(mut &f.array_pending) { enqueue_chain(parent) }
}

// All immutable children and callback slots exist before this one-time handoff.
// A racing scan cannot mistake partial registration for completed membership.
fn enable_array(fence &DmaFence) {
	if fence == unsafe { nil } || !fence.fence_array { return }
	mut f := unsafe { fence }
	f.lock.acquire()
	if f.signaled || f.array_enabled { f.lock.release(); return }
	katomic.store(mut &f.array_enabled, true)
	f.lock.release()
	for index := u32(0); index < f.array_count; index++ {
		mut child := unsafe { f.array_fences[index] }
		mut node := unsafe { &f.array_waiters[index] }
		child.lock.acquire()
		if child.signaled { array_child_complete(fence, child.error) }
		else {
			node.parent = unsafe { fence }
			node.next = unsafe { child.chain_waiters }
			child.chain_waiters = unsafe { node }
		}
		child.lock.release()
	}
	if array_ready(fence) { complete_array(fence) }
}

// Only merge's uninstalled result may be disposed. add_chain_point clears the
// reservation before any callback can observe its now-retained payload.
pub fn release_merge_reservation(fence &DmaFence) {
	if fence == unsafe { nil } || !fence.merge_reserved { return }
	if fence.fence_array { memory.free(voidptr(fence.array_fences)) }
	memory.free(voidptr(fence))
}
