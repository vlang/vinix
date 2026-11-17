// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module syncobj

import event.eventstruct
import klock
import memory

__global chain_callbacks = 0
__global chain_racing_leaf &DmaFence = unsafe { nil }

fn chain_completed(fence &DmaFence) {
	assert fence.lock.is_held()
	assert fence.signaled && fence.error == 0
	chain_callbacks++
}

fn chain_race_signal() { signal(chain_racing_leaf) }

fn append_chain(obj &SyncObj, leaf &DmaFence, point u64) &DmaFence {
	node := reserve_chain() or { panic('chain allocation') }
	assert add_chain_point(obj, node, leaf, point)
	return node
}

fn retire_test_chain(node &DmaFence) {
	// Fixture-only: every child is completed, all callbacks have returned and
	// no descriptor/capture survives. Production metadata remains retained.
	assert is_signaled(node) && node.chain_waiters == unsafe { nil }
	assert !node.chain_notify_queued && node.chain_notify_next == unsafe { nil }
	unsafe { node.waiters.free() }
	memory.free(voidptr(node))
}

pub fn run_chain_checks() ? {
	start := memory.outstanding()
	// Reservation failures and all unpublished cleanup have one clear owner.
	for _ in 0 .. 1000 {
		node := reserve_chain() or { panic('reserve') }
		release_chain_reservation(node)
	}
	memory.fail_at(0)
	if _ := reserve_chain() { panic('OOM reservation unexpectedly succeeded') }
	memory.fail_at(-1)
	assert memory.outstanding() == start
	invalid_reservation := reserve_chain() or { panic('reserve') }
	mut invalid_object := SyncObj{}
	assert !add_chain_point(&invalid_object, invalid_reservation, invalid_reservation, 1)
	release_chain_reservation(invalid_reservation)
	for cycle in 0 .. 64 {
		mut obj := SyncObj{}
		mut a := DmaFence{context: 100, seqno: 1}
		mut b := DmaFence{context: 100, seqno: 2}
		mut c := DmaFence{context: 200, seqno: 3}
		n1 := append_chain(&obj, &a, 10)
		n2 := append_chain(&obj, &b, 20)
		n3 := append_chain(&obj, &c, 30)
		assert n1.context == n2.context && n2.context == n3.context
		assert n2.chain_prev_seqno == 10 && n3.chain_prev_seqno == 20
		assert get_chain_fence(&obj, 0)? == n3
		assert get_chain_fence(&obj, 1)? == n1
		assert get_chain_fence(&obj, 11)? == n2
		assert get_chain_fence(&obj, 30)? == n3
		if _ := get_chain_fence(&obj, 31) { panic('unsubmitted point') }
		mut waiter := FenceWaiter{callback: chain_completed}
		add_waiter(n3, &waiter)
		mut target := eventstruct.Event{}
		mut poll := FenceEvent{}
		assert !poll_fence(n3, &poll, &target)
		before := chain_callbacks
		// A later payload alone cannot complete the cumulative root, nor may
		// a direct signal/error producer force a container ready.
		signal_error(&c, -5)
		signal(n3); signal_error(n3, -19)
		assert !is_signaled(n3) && !waiter.triggered && target.generation == 0
		assert !queue_dependency_ready(n3, 100)
		signal(&b)
		assert !is_signaled(n2) && !is_signaled(n3)
		// Completed contained leaves are skipped even while their prefix is
		// still blocked: lower queries resolve the earlier unfinished fence.
		assert get_chain_fence(&obj, 11)? == n1
		assert chain_previous(n3) == n1
		signal(&a)
		assert is_signaled(n1) && is_signaled(n2) && is_signaled(n3)
		assert get_error(n3) == 0 && snapshot(n3).kind == .chain
		assert chain_callbacks == before + 1 && target.generation == 1
		assert get_chain_fence(&obj, 11)? == unsafe { nil }
		assert get_chain_fence(&obj, 30)? == n3
		cancel_fence_event(n3, &poll)
		assert poll.fence == unsafe { nil }
		for node in [n3, n2, n1]! { retire_test_chain(node) }
		_ = cycle
	}
	// Duplicate/decreasing values start a fresh context and retain the high
	// sequence number; they still depend on every earlier pending payload.
	for value in [u64(0), 1, 10, 99, ~u64(0)]! {
		mut obj := SyncObj{}
		mut a := DmaFence{}
		mut b := DmaFence{}
		n1 := append_chain(&obj, &a, ~u64(0))
		n2 := append_chain(&obj, &b, value)
		assert n2.context != n1.context && n2.seqno == ~u64(0) && n2.chain_prev_seqno == 0
		assert get_chain_fence(&obj, 1)? == n2
		signal(&b)
		assert !is_signaled(n2)
		signal(&a)
		assert is_signaled(n2)
		retire_test_chain(n2); retire_test_chain(n1)
	}
	// Preserve binary predecessors, zero outputs, pending WAIT_FOR_SUBMIT
	// captures and captured roots across replacement of the sync object.
	mut obj := SyncObj{}
	mut capture := FenceCapture{}
	assert prepare_capture(&obj, &capture, true)
	mut first := DmaFence{}
	n0 := append_chain(&obj, &first, 0)
	assert captured_fence(&capture)? == n0
	assert get_chain_fence(&obj, 0)? == n0
	if _ := get_chain_fence(&obj, 1) { panic('zero head positive lookup') }
	mut binary := DmaFence{}
	replace_fence(&obj, &binary)
	mut last := DmaFence{}
	n1 := append_chain(&obj, &last, 3)
	assert n1.chain_prev == &binary && captured_fence(&capture)? == n0
	assert get_chain_fence(&obj, 2)? == n1
	mut canceled := FenceEvent{}
	mut canceled_target := eventstruct.Event{}
	assert !poll_fence(n1, &canceled, &canceled_target)
	cancel_fence_event(n1, &canceled)
	signal(&last); assert !is_signaled(n1)
	signal_error(&binary, -110); assert is_signaled(n1)
	assert canceled_target.generation == 0
	signal(&first); release_capture(&capture)
	retire_test_chain(n1); retire_test_chain(n0)
	// Complete exactly as registration acquires the child's lock.
	for child in 0 .. 2 {
		mut object := SyncObj{}
		mut previous := DmaFence{}
		mut payload := DmaFence{}
		replace_fence(&object, &previous)
		chain_racing_leaf = if child == 0 { &previous } else { &payload }
		klock.before_once(unsafe { &chain_racing_leaf.lock }, chain_race_signal)
		node := append_chain(&object, &payload, 7)
		assert !is_signaled(node)
		if child == 0 { signal(&payload) } else { signal(&previous) }
		assert is_signaled(node)
		retire_test_chain(node)
	}
	chain_racing_leaf = unsafe { nil }
	// Reverse completion of a long timeline exercises a bounded stack. No
	// allocations are allowed in signal, lookup, notification or snapshot.
	mut object := SyncObj{}
	mut leaves := []DmaFence{len: 10000}
	mut nodes := []&DmaFence{cap: leaves.len}
	for index in 0 .. leaves.len { nodes << append_chain(&object, unsafe { &leaves[index] }, u64(index + 1)) }
	allocations := memory.attempts()
	mut final_waiter := FenceWaiter{callback: chain_completed}
	add_waiter(nodes.last(), &final_waiter)
	for index := leaves.len - 1; index >= 0; index-- {
		signal(unsafe { &leaves[index] })
		assert is_signaled(nodes.last()) == (index == 0)
	}
	assert final_waiter.triggered && memory.attempts() == allocations
	for node in nodes { retire_test_chain(node) }
	unsafe { nodes.free(); leaves.free() }
	assert memory.outstanding() == start
	println('Timeline chains: cumulative readiness, zero/duplicate/decreasing/u64-max points, retired-prefix lookup, binary predecessors, immutable captures, poll/callback cancellation, exact-lock publication races, 10000 reverse completions and flat unpublished reservation storage pass.')
}

pub fn run_chain_trace() {
	values := [u64(0), 1, 2, 3, u64(1) << 63, ~u64(0)]!
	queries := [u64(0), 1, 2, 3, 4, (u64(1) << 63) - 1, u64(1) << 63, ~u64(0)]!
	for a in values { for b in values { for c in values {
		for predecessor in 0 .. 3 { for mask in 0 .. 8 {
			mut obj := SyncObj{}
			mut binary := DmaFence{}
			if predecessor != 0 { replace_fence(&obj, &binary) }
			if predecessor == 2 { signal(&binary) }
			mut leaves := [3]DmaFence{}
			mut nodes := unsafe { [3]&DmaFence{} }
			for index, point in [a, b, c]! { nodes[index] = append_chain(&obj, unsafe { &leaves[index] }, point) }
			for index in 0 .. 3 { if mask & (1 << index) != 0 { signal(unsafe { &leaves[index] }) } }
			for query in queries {
				mut id := -2
				mut ready := false
				if fence := get_chain_fence(&obj, query) {
					id = -1
					if fence == &binary { id = 3 }
					for index, node in nodes { if fence == node { id = index } }
					ready = is_signaled(fence)
				}
				println('${id} ${int(ready)}')
			}
			signal(&binary)
			for index in 0 .. 3 { signal(unsafe { &leaves[index] }) }
			for node in nodes { retire_test_chain(node) }
		} }
	} } }
}
