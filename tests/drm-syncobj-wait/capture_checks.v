// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module syncobj

import klock
import memory
import event
import event.eventstruct

pub fn before_fence_lock_for_checks(fence &DmaFence, callback fn ()) {
	klock.before_once(unsafe { &fence.lock }, callback)
}

pub fn assert_fence_events_for_checks(fence &DmaFence, expected int) {
	mut f := unsafe { fence }
	f.lock.acquire()
	mut cursor := unsafe { f.poll_events }
	mut count := 0
	for cursor != unsafe { nil } {
		count++
		assert count <= expected, 'duplicate or cyclic fence event subscription'
		assert voidptr(cursor.fence) == voidptr(fence) && cursor.event != unsafe { nil }
		cursor = unsafe { cursor.next }
	}
	assert count == expected
	f.lock.release()
}

pub fn assert_no_fence_event_in_region_for_checks(fence &DmaFence, allocation voidptr, size u64) {
	mut f := unsafe { fence }
	f.lock.acquire()
	mut cursor := unsafe { f.poll_events }
	for cursor != unsafe { nil } {
		for address in [u64(cursor), u64(cursor.event)]! {
			assert address < u64(allocation) || address - u64(allocation) >= size,
				'export storage freed while a fence can still notify its event'
		}
		cursor = unsafe { cursor.next }
	}
	f.lock.release()
}

pub fn run_fence_event_primitive_checks() {
	mut fence := DmaFence{}
	mut nodes := [4096]FenceEvent{}
	mut events := [4096]eventstruct.Event{}
	assert !poll_fence(unsafe { nil }, unsafe { &nodes[0] }, unsafe { &events[0] })
	assert !poll_fence(unsafe { &fence }, unsafe { nil }, unsafe { &events[0] })
	assert !poll_fence(unsafe { &fence }, unsafe { &nodes[0] }, unsafe { nil })
	cancel_fence_event(unsafe { nil }, unsafe { nil })
	for index in 0 .. nodes.len {
		assert !poll_fence(unsafe { &fence }, unsafe { &nodes[index] }, unsafe { &events[index] })
		assert !poll_fence(unsafe { &fence }, unsafe { &nodes[index] }, unsafe { &events[index] })
	}
	assert_fence_events_for_checks(unsafe { &fence }, 4096)
	// Head, middle and tail cancellation, then re-registration.
	for index in [4095, 2048, 0]! {
		cancel_fence_event(unsafe { &fence }, unsafe { &nodes[index] })
		cancel_fence_event(unsafe { &fence }, unsafe { &nodes[index] })
		assert !poll_fence(unsafe { &fence }, unsafe { &nodes[index] }, unsafe { &events[index] })
	}
	assert_fence_events_for_checks(unsafe { &fence }, 4096)
	notifications := event.notifications()
	signal_error(unsafe { &fence }, -5)
	assert event.notifications() == notifications + 4096
	assert_fence_events_for_checks(unsafe { &fence }, 0)
	for index in 0 .. nodes.len {
		assert events[index].generation == 1
		assert nodes[index].fence == unsafe { nil } && nodes[index].next == unsafe { nil } && nodes[index].event == unsafe { nil }
		assert poll_fence(unsafe { &fence }, unsafe { &nodes[index] }, unsafe { &events[index] })
		cancel_fence_event(unsafe { &fence }, unsafe { &nodes[index] })
	}
	signal(unsafe { &fence })
	assert event.notifications() == notifications + 4096
	println('DRM fence events: 4096 borrowed nodes, duplicate registration, head/middle/tail cancellation, single error completion wake, cleared links and no repeated wake passed')
}

pub fn assert_private_stub_for_checks(fence &DmaFence) {
	assert fence.queue_context == 0 && fence.waiters.len == 0
}

pub fn before_namespace_lock_for_checks(callback fn ()) {
	klock.before_once(unsafe { &syncobj_lock }, callback)
}

pub fn assert_unpublished_allocation_for_checks(allocation voidptr, size u64) {
	assert !syncobj_lock.is_held(), 'unpublished cleanup must follow namespace unlock'
	syncobj_lock.acquire()
	mut cursor := unsafe { syncobj_head }
	mut count := 0
	for cursor != unsafe { nil } {
		count++; assert count <= memory.object_count() + memory.alias_count(), 'namespace cycle'
		for address in [u64(cursor), u64(cursor.object), u64(cursor.object.fence)]! {
			assert address < u64(allocation) || address - u64(allocation) >= size,
				'freeing metadata still reachable through a published handle'
		}
		cursor = unsafe { cursor.next }
	}
	syncobj_lock.release()
}

pub fn assert_namespace_for_checks(expected int) {
	syncobj_lock.acquire()
	mut cursor := unsafe { syncobj_head }
	mut owner := u64(0)
	mut handle := u32(0)
	mut count := 0
	for cursor != unsafe { nil } {
		assert cursor.owner > owner || (cursor.owner == owner && cursor.handle > handle), 'namespace order/uniqueness'
		assert cursor.owner != 0 && cursor.handle != 0
		owner = cursor.owner; handle = cursor.handle
		count++; assert count <= expected, 'namespace cycle/count'
		cursor = unsafe { cursor.next }
	}
	assert count == expected
	syncobj_lock.release()
}

pub fn check_namespace_boundaries_for_checks() {
	for value in [u32(1), 1023, 1024, 0xffff_fffe]! {
		assert next_namespace_handle(value) or { panic('valid namespace successor') } == value + 1
	}
	if _ := next_namespace_handle(~u32(0)) { assert false, 'handle wrapped to zero' }
}

__global capture_check_object &SyncObj = unsafe { nil }
__global capture_check_fence &DmaFence = unsafe { nil }
__global capture_check_node &FenceCapture = unsafe { nil }

fn publish_before_lock() { replace_fence(capture_check_object, capture_check_fence) }
fn release_before_lock() { release_capture(capture_check_node) }

pub fn arm_capture_for_checks(obj &SyncObj, capture &FenceCapture) {
	prepare_capture(obj, capture, true) or { panic('capture snapshot') }
	arm_capture(capture)
}

pub fn assert_no_captures_for_checks(obj &SyncObj) {
	mut o := unsafe { obj }
	o.lock.acquire()
	assert o.pending_captures == unsafe { nil }
	o.lock.release()
}

pub fn assert_pending_captures_for_checks(obj &SyncObj, expected int) {
	mut o := unsafe { obj }
	o.lock.acquire()
	mut cursor := unsafe { o.pending_captures }
	mut count := 0
	for cursor != unsafe { nil } { count++; cursor = unsafe { cursor.next } }
	assert count == expected
	o.lock.release()
}

pub fn free_object_metadata_for_checks(obj &SyncObj) {
	assert_no_captures_for_checks(obj)
	assert obj.namespace.next == unsafe { nil }, 'retired object retained a namespace link'
	// Fixture-only disposal after namespace removal and all synchronous users.
	unsafe { obj.timeline_points.free() }
	memory.free(voidptr(obj))
}

pub fn assert_no_capture_in_region_for_checks(obj &SyncObj, allocation voidptr, size u64) {
	mut o := unsafe { obj }
	o.lock.acquire()
	mut cursor := unsafe { o.pending_captures }
	for cursor != unsafe { nil } {
		address := u64(cursor)
		assert address < u64(allocation) || address - u64(allocation) >= size,
			'wait storage freed before its capture nodes were detached'
		cursor = unsafe { cursor.next }
	}
	o.lock.release()
}

pub fn run_capture_checks() {
	if _ := prepare_capture(unsafe { nil }, unsafe { nil }, true) { assert false }
	if _ := prepare_capture(unsafe { nil }, unsafe { nil }, false) { assert false }
	if _ := captured_fence(unsafe { nil }) { assert false }
	release_capture(unsafe { nil })
	for _ in 0 .. 200 {
		mut obj := SyncObj{}
		mut first := DmaFence{}
		mut later := DmaFence{}
		mut nodes := [4]FenceCapture{}
		capture_check_object = unsafe { &obj }
		capture_check_fence = unsafe { &first }
		capture_check_node = unsafe { &nodes[0] }
		if _ := prepare_capture(unsafe { &obj }, unsafe { nil }, true) { assert false }
		if _ := prepare_capture(unsafe { &obj }, unsafe { &nodes[0] }, false) { assert false }
		release_capture(unsafe { &nodes[0] })
		// Remove a middle, head, tail, and final entry from an intrusive list.
		for index in 0 .. 4 { arm_capture_for_checks(unsafe { &obj }, unsafe { &nodes[index] }) }
		if _ := prepare_capture(unsafe { &obj }, unsafe { &nodes[0] }, true) { assert false }
		arm_capture(unsafe { &nodes[0] })
		assert_pending_captures_for_checks(unsafe { &obj }, 4)
		for index in [2, 3, 0, 1]! { release_capture(unsafe { &nodes[index] }) }
		assert_no_captures_for_checks(unsafe { &obj })
		release_capture(unsafe { &nodes[1] })
		for index in 0 .. 4 { arm_capture_for_checks(unsafe { &obj }, unsafe { &nodes[index] }) }
		replace_fence(unsafe { &obj }, unsafe { nil })
		assert obj.pending_captures != unsafe { nil }
		replace_fence(unsafe { &obj }, unsafe { &first })
		assert_no_captures_for_checks(unsafe { &obj })
		replace_fence(unsafe { &obj }, unsafe { nil })
		replace_fence(unsafe { &obj }, unsafe { &later })
		for index in 0 .. 4 {
			captured := captured_fence(unsafe { &nodes[index] }) or { panic('first publication') }
			assert voidptr(captured) == voidptr(&first)
			release_capture(unsafe { &nodes[index] })
			if _ := captured_fence(unsafe { &nodes[index] }) { assert false }
		}
		// Existing and racing publication both become stable initial snapshots.
		arm_capture_for_checks(unsafe { &obj }, unsafe { &nodes[0] })
		assert voidptr(captured_fence(unsafe { &nodes[0] }) or { panic('existing fence') }) == voidptr(&later)
		release_capture(unsafe { &nodes[0] })
		replace_fence(unsafe { &obj }, unsafe { nil })
		snapshot := prepare_capture(unsafe { &obj }, unsafe { &nodes[0] }, true) or { panic('empty snapshot') }
		assert snapshot == unsafe { nil }
		assert_no_captures_for_checks(unsafe { &obj })
		klock.before_once(unsafe { &obj.lock }, publish_before_lock)
		arm_capture(unsafe { &nodes[0] })
		assert voidptr(captured_fence(unsafe { &nodes[0] }) or { panic('racing fence') }) == voidptr(&first)
		release_capture(unsafe { &nodes[0] })
		// A publisher can win immediately before cancellation takes its lock.
		replace_fence(unsafe { &obj }, unsafe { nil })
		arm_capture_for_checks(unsafe { &obj }, unsafe { &nodes[0] })
		klock.before_once(unsafe { &obj.lock }, publish_before_lock)
		release_capture(unsafe { &nodes[0] })
		assert_no_captures_for_checks(unsafe { &obj })
		// Or cancellation can win immediately before publication takes its lock.
		replace_fence(unsafe { &obj }, unsafe { nil })
		arm_capture_for_checks(unsafe { &obj }, unsafe { &nodes[0] })
		klock.before_once(unsafe { &obj.lock }, release_before_lock)
		replace_fence(unsafe { &obj }, unsafe { &first })
		assert_no_captures_for_checks(unsafe { &obj })
		assert nodes[0].object == unsafe { nil } && !nodes[0].pending
		if _ := captured_fence(unsafe { &nodes[0] }) { assert false }
		capture_check_object = unsafe { nil }; capture_check_fence = unsafe { nil }; capture_check_node = unsafe { nil }
	}
	println('DRM submission captures: 200 cycles of multi-waiter publication, middle/head/tail removal, nil publication, duplicate registration, idempotent cleanup and exact-lock publication/cancellation races passed')
}
pub fn deadline_for_checks(fence &DmaFence) ?i64 {
	chain_notify_lock.acquire()
	defer { chain_notify_lock.release() }
	if !fence.deadline_valid { return none }
	return fence.deadline_ns
}

pub fn overlap_deadline_drain_for_checks(fence &DmaFence, later i64, earlier i64) {
	chain_notify_lock.acquire()
	assert !chain_notify_draining && chain_notify_head == unsafe { nil }
	chain_notify_draining = true
	chain_notify_lock.release()
	set_deadline(fence, later)
	set_deadline(fence, earlier)
	chain_notify_lock.acquire()
	assert chain_notify_head == fence && chain_notify_tail == fence
	chain_notify_draining = false
	chain_notify_lock.release()
	drain_chain_notifications()
}
