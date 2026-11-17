// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

import memory

pub fn timeline_wait_pending_for_checks(obj &SyncObj) int {
	mut o := unsafe { obj }
	o.lock.acquire()
	defer { o.lock.release() }
	mut cursor := unsafe { o.timeline_captures }
	mut count := 0
	for cursor != unsafe { nil } {
		assert cursor.object == obj && cursor.pending && !cursor.available
		count++
		assert count <= 4096, 'cyclic timeline capture list'
		cursor = unsafe { cursor.next }
	}
	return count
}

pub fn assert_no_timeline_capture_in_region_for_checks(obj &SyncObj, allocation voidptr, size u64) {
	mut o := unsafe { obj }
	o.lock.acquire()
	defer { o.lock.release() }
	mut cursor := unsafe { o.timeline_captures }
	for cursor != unsafe { nil } {
		address := u64(cursor)
		assert address < u64(allocation) || address - u64(allocation) >= size, 'timeline node freed before detach'
		cursor = unsafe { cursor.next }
	}
}

pub fn check_timeline_capture_protocol_for_checks() {
	mut obj := SyncObj{}
	mut binary := DmaFence{}
	mut cap := TimelineCapture{}
	assert !prepare_timeline_capture(&obj, &cap, 1, false)
	release_timeline_capture(&cap)
	assert prepare_timeline_capture(&obj, &cap, 1, true)
	assert timeline_wait_pending_for_checks(&obj) == 0, 'initial validation must not arm'
	arm_timeline_capture(&cap)
	assert timeline_wait_pending_for_checks(&obj) == 1
	replace_fence(&obj, &binary)
	if _ := captured_timeline_fence(&cap) { panic('binary head cannot supply positive point') }
	assert timeline_wait_pending_for_checks(&obj) == 1
	release_timeline_capture(&cap); release_timeline_capture(&cap)
	assert cap.object == unsafe { nil } && !cap.available && !cap.pending
	assert timeline_wait_pending_for_checks(&obj) == 0
	mut captures := [3]TimelineCapture{}
	for index in 0 .. 3 {
		assert prepare_timeline_capture(&obj, unsafe { &captures[index] }, u64(index + 1), true)
		arm_timeline_capture(unsafe { &captures[index] })
	}
	assert timeline_wait_pending_for_checks(&obj) == 3
	mut leaf := DmaFence{}
	node := reserve_chain() or { panic('chain') }
	assert add_chain_point(&obj, node, &leaf, 2)
	assert timeline_wait_pending_for_checks(&obj) == 1
	assert captured_timeline_fence(unsafe { &captures[0] }) or { panic('point1') } == node
	assert captured_timeline_fence(unsafe { &captures[1] }) or { panic('point2') } == node
	for index in 0 .. 3 { release_timeline_capture(unsafe { &captures[index] }) }
	assert timeline_wait_pending_for_checks(&obj) == 0
	signal(&binary); signal(&leaf)
	assert is_signaled(node)
	memory.free(voidptr(node))
}
