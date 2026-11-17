// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

import memory
import event.eventstruct

pub fn array_count_for_checks(fence &DmaFence) u32 { return if fence.fence_array { fence.array_count } else { u32(1) } }
pub fn array_child_for_checks(fence &DmaFence, index u32) &DmaFence { return if fence.fence_array { unsafe { fence.array_fences[index] } } else { unsafe { fence } } }
pub fn is_array_for_checks(fence &DmaFence) bool { return fence.fence_array }

pub fn dispose_merged_for_checks(fence &DmaFence) {
	assert is_signaled(fence) && fence.chain_waiters == unsafe { nil } && !fence.chain_notify_queued
	assert fence.poll_events == unsafe { nil }
	if fence.fence_array {
		for index := u32(0); index < fence.array_count; index++ { assert is_signaled(unsafe { fence.array_fences[index] }) }
		memory.free(voidptr(fence.array_fences))
	}
	memory.free(voidptr(fence))
}

pub fn check_merge_array_protocol() {
	// Two queues owned by the same file must not collapse during dedup.
	for reverse in [false, true]! {
		mut obj := SyncObj{}
		qa := new_queue_context() or { panic('queue A') }
		qb := new_queue_context() or { panic('queue B') }
		a := new_queue_fence(7, 100, qa)
		b := new_queue_fence(7, 101, qb)
		assert a.context == qa && b.context == qb && a.context != b.context
		n1 := reserve_chain() or { panic('chain A') }; n2 := reserve_chain() or { panic('chain B') }
		assert add_chain_point(&obj, n1, a, 1) && add_chain_point(&obj, n2, b, 2)
		merged := unwrap_merge(n2) or { panic('cross-queue merge') }
		assert merged.fence_array && merged.array_count == 2, 'independent queues must both remain dependencies'
		unsafe { merged.merge_reserved = false }
		enable_array(merged)
		if reverse { signal(b); assert !is_signaled(merged); signal(a) }
		else { signal(a); assert !is_signaled(merged); signal(b) }
		assert is_signaled(merged)
		dispose_merged_for_checks(merged)
		memory.free(voidptr(n1)); memory.free(voidptr(n2))
		unsafe { free(a); free(b) }
	}
	// Standalone arrays scan lazily, preserving Linux's no-callback success;
	// enabling first preserves the first callback error and wakes every parent.
	for enabled in [false, true]! { for reverse in [false, true]! {
		mut a := DmaFence{context: 1, seqno: 1}
		mut b := DmaFence{context: 2, seqno: 1}
		storage := memory.malloc_packed_fallible(2 * sizeof(voidptr))
		mut children := unsafe { &&DmaFence(storage) }
		unsafe { children[0] = &a; children[1] = &b }
		array := new_merge_array(children, 2) or { panic('array') }
		unsafe { array.merge_reserved = false }
		mut node := FenceEvent{}
		mut wake := eventstruct.Event{}
		if enabled { assert !poll_fence(array, unsafe { &node }, unsafe { &wake }) }
		if reverse { signal_error(&b, -19); assert !is_signaled(array); signal_error(&a, -5) }
		else { signal_error(&a, -5); assert !is_signaled(array); signal_error(&b, -19) }
		assert is_signaled(array)
		assert get_error(array) == if enabled { if reverse { -19 } else { -5 } } else { 0 }
		if enabled { assert wake.generation == 1; cancel_fence_event(array, unsafe { &node }) }
		dispose_merged_for_checks(array)
	} }
}

pub fn check_large_merge_arrays() {
	for count in [u32(129), 4096]! {
		allocation := unsafe { C.malloc(u64(count) * sizeof(DmaFence)) }
		assert allocation != unsafe { nil }
		mut leaves := unsafe { &DmaFence(allocation) }
		storage := memory.malloc_packed_fallible(u64(count) * sizeof(voidptr))
		mut children := unsafe { &&DmaFence(storage) }
		for index := u32(0); index < count; index++ {
			unsafe { leaves[index] = DmaFence{context: u64(count - index), seqno: ~u64(index)}; children[index] = &leaves[index] }
		}
		array := new_merge_array(children, count) or { panic('large array') }
		merged := unwrap_merge(array) or { panic('large merge') }
		assert merged.fence_array && merged.array_count == count
		for index := u32(0); index < count; index++ { assert unsafe { merged.array_fences[index].context } == u64(index + 1) }
		release_merge_reservation(merged)
		unsafe { array.merge_reserved = false }
		mut node := FenceEvent{}
		mut wake := eventstruct.Event{}
		assert !poll_fence(array, unsafe { &node }, unsafe { &wake })
		for index := u32(0); index < count; index++ {
			signal_error(unsafe { &leaves[index] }, -19)
			assert is_signaled(array) == (index + 1 == count)
		}
		assert wake.generation == 1 && get_error(array) == -19
		dispose_merged_for_checks(array)
		unsafe { C.free(allocation) }
	}
}
