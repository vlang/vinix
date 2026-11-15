// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module syncobj

import klock

__global capture_check_object &SyncObj = unsafe { nil }
__global capture_check_fence &DmaFence = unsafe { nil }
__global capture_check_node &FenceCapture = unsafe { nil }

fn publish_before_lock() { replace_fence(capture_check_object, capture_check_fence) }
fn release_before_lock() { release_capture(capture_check_node) }

pub fn assert_no_captures_for_checks(obj &SyncObj) {
	mut o := unsafe { obj }
	o.lock.acquire()
	assert o.pending_captures == unsafe { nil }
	o.lock.release()
}

pub fn run_capture_checks() {
	assert !prepare_capture(unsafe { nil }, unsafe { nil }, true)
	assert !prepare_capture(unsafe { nil }, unsafe { nil }, false)
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
		assert !prepare_capture(unsafe { &obj }, unsafe { nil }, true)
		assert !prepare_capture(unsafe { &obj }, unsafe { &nodes[0] }, false)
		release_capture(unsafe { &nodes[0] })
		// Remove a middle, head, tail, and final entry from an intrusive list.
		for index in 0 .. 4 { assert prepare_capture(unsafe { &obj }, unsafe { &nodes[index] }, true) }
		assert !prepare_capture(unsafe { &obj }, unsafe { &nodes[0] }, true)
		for index in [2, 3, 0, 1]! { release_capture(unsafe { &nodes[index] }) }
		assert_no_captures_for_checks(unsafe { &obj })
		release_capture(unsafe { &nodes[1] })
		for index in 0 .. 4 { assert prepare_capture(unsafe { &obj }, unsafe { &nodes[index] }, true) }
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
		assert prepare_capture(unsafe { &obj }, unsafe { &nodes[0] }, true)
		assert voidptr(captured_fence(unsafe { &nodes[0] }) or { panic('existing fence') }) == voidptr(&later)
		release_capture(unsafe { &nodes[0] })
		replace_fence(unsafe { &obj }, unsafe { nil })
		klock.before_once(unsafe { &obj.lock }, publish_before_lock)
		assert prepare_capture(unsafe { &obj }, unsafe { &nodes[0] }, true)
		assert voidptr(captured_fence(unsafe { &nodes[0] }) or { panic('racing fence') }) == voidptr(&first)
		release_capture(unsafe { &nodes[0] })
		// A publisher can win immediately before cancellation takes its lock.
		replace_fence(unsafe { &obj }, unsafe { nil })
		assert prepare_capture(unsafe { &obj }, unsafe { &nodes[0] }, true)
		klock.before_once(unsafe { &obj.lock }, publish_before_lock)
		release_capture(unsafe { &nodes[0] })
		assert_no_captures_for_checks(unsafe { &obj })
		// Or cancellation can win immediately before publication takes its lock.
		replace_fence(unsafe { &obj }, unsafe { nil })
		assert prepare_capture(unsafe { &obj }, unsafe { &nodes[0] }, true)
		klock.before_once(unsafe { &obj.lock }, release_before_lock)
		replace_fence(unsafe { &obj }, unsafe { &first })
		assert_no_captures_for_checks(unsafe { &obj })
		assert nodes[0].object == unsafe { nil } && !nodes[0].pending
		if _ := captured_fence(unsafe { &nodes[0] }) { assert false }
		capture_check_object = unsafe { nil }; capture_check_fence = unsafe { nil }; capture_check_node = unsafe { nil }
	}
	println('DRM submission captures: 200 cycles of multi-waiter publication, middle/head/tail removal, nil publication, duplicate registration, idempotent cleanup and exact-lock publication/cancellation races passed')
}
