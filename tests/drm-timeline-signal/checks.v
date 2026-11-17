// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import klock
import memory
import usercopy

struct TimelineSignalInput {
mut:
	handles [129]u32
	points [129]u64
}

__global timeline_signal_target &syncobj.SyncObj = unsafe { nil }
__global timeline_signal_input &TimelineSignalInput = unsafe { nil }
__global timeline_signal_fresh &syncobj.SyncObj = unsafe { nil }

fn timeline_signal_replace_during_publish() {
	// All user records and object identities have already been captured.
	handle := timeline_signal_target.handle
	assert syncobj.destroy(11, handle)
	timeline_signal_fresh = make_object(0)
	assert timeline_signal_fresh.handle == handle
	unsafe {
		timeline_signal_input.handles[1] = ~u32(0)
		timeline_signal_input.points[1] = 999
	}
}

fn prepare_timeline_signal(input &TimelineSignalInput, count u32, flags u32) ioctl.DrmSyncobjTimelineArray {
	usercopy.allow(u64(input), sizeof(TimelineSignalInput))
	return ioctl.DrmSyncobjTimelineArray{handles: unsafe { u64(&input.handles[0]) },
		points: unsafe { u64(&input.points[0]) }, count_handles: count, flags: flags}
}

fn retire_timeline_signal(obj &syncobj.SyncObj, predecessor &syncobj.DmaFence) {
	head := syncobj.get_fence(obj) or { panic('timeline head') }
	syncobj.replace_fence(obj, unsafe { nil })
	syncobj.retire_timeline_signal_chain_for_checks(head, predecessor)
}

pub fn measure_timeline_signal_failures() {
	$if macos {
		memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
		obj := make_object(0)
		mut input := TimelineSignalInput{handles: [129]u32{init: obj.handle}}
		for count in [u32(1), 65, 129]! {
			mut request := prepare_timeline_signal(&input, count, 0)
			for batch in 0 .. 4 {
				before_blocks, before_bytes := live_record_heap()
				for _ in 0 .. 1000 {
					usercopy.allow(unsafe { u64(&input) }, sizeof(input))
					// Fail the final chain node after reserving every earlier one.
					memory.fail_in(int(count) + 1 + int(count > 64))
					assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { &request }) == -12
					assert memory.outstanding() == 0 && memory.live_bytes() == 0
				}
				after_blocks, after_bytes := live_record_heap()
				if batch != 0 {
					assert before_blocks == after_blocks && before_bytes == after_bytes
					println('timeline-signal-failure count=${count} batch=${batch} cycles=1000 retained_blocks=${i64(after_blocks) - before_blocks} retained_bytes=${i64(after_bytes) - i64(before_bytes)}')
				}
			}
		}
		clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence))
	} $else { panic('malloc-zone measurement requires macOS') }
}

pub fn run_timeline_signal_checks() {
	memory.reset(); memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
	syncobj.check_shared_timeline_stub()
	assert sizeof(ioctl.DrmSyncobjTimelineArray) == 24 && ioctl.drm_ioctl_syncobj_timeline_signal == 0xcd
	layout := common_ioctl_layout(ioctl.drm_ioctl_syncobj_timeline_signal) or { panic('timeline SIGNAL registration') }
	assert layout.size == 24 && layout.direction == ioctl_write | ioctl_read
	assert u32(3) << 30 | u32(24) << 16 | u32(`d`) << 8 | ioctl.drm_ioctl_syncobj_timeline_signal == 0xc01864cd
	mut cases := 0
	for count in [u32(1), 3, 64, 65, 129]! {
		obj := make_object(0)
		mut input := TimelineSignalInput{handles: [129]u32{init: obj.handle}}
		for index in 0 .. int(count) { input.points[index] = u64(index + 1) }
		// Every allocation failure must leave the original head unchanged,
		// release all private reservations and keep pending captures private.
		for failure in 0 .. int(count) + 2 + int(count > 64) {
			mut request := prepare_timeline_signal(&input, count, 0)
			before := memory.outstanding()
			memory.fail_in(failure)
			assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { &request }) == -12
			assert memory.outstanding() == before && memory.live_bytes() == 0
			if _ := syncobj.get_fence(obj) { panic('failure published a prefix') }
			cases++
		}
		mut request := prepare_timeline_signal(&input, count, 0)
		assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { &request }) == 0
		assert usercopy.reads == 2 && usercopy.writes == 0
		head := current(obj)
		assert syncobj.is_signaled(head) && syncobj.query_timeline_point(obj, false) == count
		syncobj.assert_timeline_signal_payload_for_checks(head)
		assert memory.outstanding() == int(count), 'only published chain nodes retained'
		retire_timeline_signal(obj, unsafe { nil })
		// Null points mean zero, including a repeated-handle output array.
		request = prepare_timeline_signal(&input, count, 0); request.points = 0
		assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { &request }) == 0, 'null points must synthesize zeroes'
		assert usercopy.reads == 1 && syncobj.query_timeline_point(obj, true) == 0
		assert syncobj.is_signaled(current(obj))
		retire_timeline_signal(obj, unsafe { nil })
		cases += 2
		clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	}
	// The generic UAPI has no fixed record bound. Exercise a full 4096-node
	// published chain without treating its retained metadata as request storage.
	large_obj := make_object(0)
	mut large_handles := [4096]u32{init: large_obj.handle}
	usercopy.allow(unsafe { u64(&large_handles[0]) }, sizeof(large_handles))
	mut large := ioctl.DrmSyncobjTimelineArray{handles: unsafe { u64(&large_handles[0]) }, count_handles: 4096}
	assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { &large }) == 0
	assert usercopy.reads == 1 && memory.outstanding() == 4096
	retire_timeline_signal(large_obj, unsafe { nil })
	clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	obj := make_object(0)
	mut input := TimelineSignalInput{handles: [129]u32{init: obj.handle}, points: [129]u64{init: 10}}
	mut request := prepare_timeline_signal(&input, 65, 1)
	before := memory.attempts()
	assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { &request }) == -22 && memory.attempts() == before
	request.flags = 0; request.count_handles = 0
	assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { &request }) == -22
	assert ioctl_syncobj_timeline_signal(unsafe { nil }, unsafe { &request }) == -14
	assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { nil }) == -14
	for count in [u32(1), 65, 129]! {
		for bad in [u32(0), count / 2, count - 1]! {
			input.handles[bad] = ~u32(0)
			request = prepare_timeline_signal(&input, count, 0)
			request.points = ~u64(0)
			assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { &request }) == -2
			assert usercopy.reads == 1 && memory.outstanding() == 0
			input.handles[bad] = obj.handle
			cases++
		}
		request = prepare_timeline_signal(&input, count, 0)
		assert ioctl_syncobj_timeline_signal(voidptr(12), unsafe { &request }) == -2
		usercopy.inject_fault()
		assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { &request }) == -14
		request = prepare_timeline_signal(&input, count, 0)
		request.points = ~u64(0)
		assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { &request }) == -14
		assert memory.outstanding() == 0
		cases += 3
	}
	// A completed SIGNAL payload cannot complete an earlier GPU predecessor.
	old := make_fence(); syncobj.replace_fence(obj, old)
	request = prepare_timeline_signal(&input, 2, 0)
	input.points[0] = 20; input.points[1] = 10
	assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { &request }) == 0
	assert !syncobj.is_signaled(current(obj)) && !syncobj.is_signaled(old)
	assert syncobj.query_timeline_point(obj, false) == 0 && syncobj.query_timeline_point(obj, true) == 20
	syncobj.signal_error(old, -5)
	assert syncobj.is_signaled(current(obj)) && syncobj.get_error(current(obj)) == 0
	retire_timeline_signal(obj, old)
	syncobj.replace_fence(obj, unsafe { nil })
	// Capture the first published root; a duplicate handle must not retarget
	// that capture to the second output or reread mutated user records/names.
	mut capture := syncobj.FenceCapture{}
	timeline_signal_target = obj; timeline_signal_input = &input
	request = prepare_timeline_signal(&input, 2, 0)
	input.points[0] = 7; input.points[1] = 9
	assert syncobj.prepare_capture(obj, &capture, true)
	klock.before_once(unsafe { &obj.lock }, timeline_signal_replace_during_publish)
	assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { &request }) == 0
	assert syncobj.query_timeline_point(obj, true) == 9
	assert syncobj.query_timeline_point(timeline_signal_fresh, true) == 0
	captured := syncobj.captured_fence(&capture) or { panic('missing first capture') }
	assert captured.seqno == 7 && captured != current(obj) && syncobj.is_signaled(captured)
	syncobj.release_capture(&capture)
	retire_timeline_signal(obj, unsafe { nil })
	timeline_signal_target = unsafe { nil }; timeline_signal_input = unsafe { nil }; timeline_signal_fresh = unsafe { nil }
	clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	println('DRM timeline SIGNAL: ${cases} counted allocation/copy/lookup cases; all-node reservation before effects, zero/null/duplicate/decreasing points, shared stable completion, pending predecessor, first capture and immutable records/objects through handle reuse pass.')
}

pub fn run_timeline_signal_trace() {
	memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
	values := [u64(0), 1, 2, 3, u64(1) << 63, ~u64(0)]!
	for a in values { for b in values { for c in values {
		for predecessor in 0 .. 3 { for null_points in [false, true]! { for separate in [false, true]! {
			objects := [make_object(0), make_object(0), make_object(0)]!
			old := make_fence()
			if predecessor != 0 { for obj in objects { syncobj.replace_fence(obj, old) } }
			if predecessor == 2 { syncobj.signal(old) }
			mut input := TimelineSignalInput{}
			for index, value in [a, b, c]! {
				input.handles[index] = objects[if separate { index } else { 0 }].handle
				input.points[index] = value
			}
			mut request := prepare_timeline_signal(&input, 3, 0)
			if null_points { request.points = 0 }
			assert ioctl_syncobj_timeline_signal(voidptr(11), unsafe { &request }) == 0
			for phase in 0 .. 2 {
				if phase == 1 { syncobj.signal(old) }
				for obj in objects {
					head := syncobj.get_fence(obj) or { unsafe { nil } }
					println('${int(syncobj.is_signaled(head))} ${syncobj.query_timeline_point(obj, false)} ${syncobj.query_timeline_point(obj, true)}')
				}
			}
			for index, obj in objects {
				if separate || index == 0 { retire_timeline_signal(obj, if predecessor == 0 { unsafe { nil } } else { old }) }
			}
			clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
		} } }
	} } }
}
