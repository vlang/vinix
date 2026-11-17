// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import memory
import usercopy
import sched
import proc
import klock

struct TimelineWaitInput {
mut:
	handles [4096]u32
	points [4096]u64
}

__global tw_obj &syncobj.SyncObj = unsafe { nil }
__global tw_other &syncobj.SyncObj = unsafe { nil }
__global tw_old &syncobj.DmaFence = unsafe { nil }
__global tw_new &syncobj.DmaFence = unsafe { nil }
__global tw_input &TimelineWaitInput = unsafe { nil }
__global tw_mode = 0
__global tw_lock_passes = 0

fn tw_chain(obj &syncobj.SyncObj, leaf &syncobj.DmaFence, point u64) &syncobj.DmaFence {
	node := remember_fence(syncobj.reserve_chain() or { panic('chain') })
	assert syncobj.add_chain_point(obj, node, leaf, point)
	return node
}

fn tw_free_check(allocation voidptr, size u64) {
	for obj in [tw_obj, tw_other]! {
		if obj != unsafe { nil } { syncobj.assert_no_timeline_capture_in_region_for_checks(obj, allocation, size) }
	}
}

fn tw_script(step u32) {
	match tw_mode {
		1 {
			if step == 1 { tw_chain(tw_obj, tw_old, 5) }
			if step == 2 { syncobj.replace_fence(tw_obj, unsafe { nil }); tw_chain(tw_obj, tw_new, 10); syncobj.signal(tw_new) }
			if step == 3 { syncobj.signal_error(tw_old, -5) }
		}
		2 {
			if step == 1 {
				assert syncobj.destroy(11, tw_obj.handle)
				tw_other = make_object(0)
				unsafe { tw_input.handles[0] = ~u32(0); tw_input.points[0] = ~u64(0) }
				tw_chain(tw_obj, tw_old, 5)
			}
			if step == 2 { syncobj.signal(tw_old) }
		}
		3 { if step == 1 { proc.private_signal(false) } }
		4 { if step == 1 { proc.shared_signal() } }
		5 { if step == 1 { proc.exit_thread() } }
		6 { if step == 1 { proc.private_signal(true) }; if step == 2 { syncobj.signal(tw_old) } }
		7 { if step == 1 { tw_chain(tw_obj, tw_new, 5) }; if step == 2 { syncobj.signal(tw_new) } }
		8 { if step == 1 { syncobj.signal(tw_old) } }
		else {}
	}
}

fn tw_gap() {
	tw_lock_passes--
	if tw_lock_passes > 0 { klock.before_once(unsafe { &tw_obj.lock }, tw_gap) }
	else {
		tw_chain(tw_obj, tw_old, 5)
		syncobj.replace_fence(tw_obj, unsafe { nil })
	}
}

fn tw_request(input &TimelineWaitInput, count u32, flags u32, timeout i64) ioctl.DrmSyncobjTimelineWait {
	usercopy.allow(u64(input), sizeof(TimelineWaitInput))
	return ioctl.DrmSyncobjTimelineWait{handles: unsafe { u64(&input.handles[0]) }, points: unsafe { u64(&input.points[0]) },
		count_handles: count, flags: flags, timeout_nsec: timeout, first_signaled: 123, pad: ~u32(0), deadline_nsec: ~u64(0)}
}

fn tw_retire() {
	for index in 0 .. wait_fixture_object_count { assert syncobj.timeline_wait_pending_for_checks(wait_fixture_objects[index]) == 0 }
	for index in 0 .. wait_fixture_fence_count { syncobj.signal(wait_fixture_fences[index]) }
	memory.check_before_free(unsafe { nil })
	clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	tw_obj = unsafe { nil }; tw_other = unsafe { nil }; tw_old = unsafe { nil }; tw_new = unsafe { nil }; tw_input = unsafe { nil }
}

pub fn measure_timeline_wait_owners() {
	$if macos {
		memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
		tw_obj = make_object(0)
		mut input := TimelineWaitInput{handles: [4096]u32{init: tw_obj.handle}, points: [4096]u64{init: 5}}
		proc.reset(); sched.reset(unsafe { nil })
		for count in [u32(1), 65, 4096]! {
			for batch in 0 .. 4 {
				before_blocks, before_bytes := live_record_heap()
				for _ in 0 .. 1000 {
					mut request := tw_request(&input, count, ioctl.drm_syncobj_wait_all | ioctl.drm_syncobj_wait_for_submit, 0)
					assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request }) == -62
					assert memory.outstanding() == 0 && memory.live_bytes() == 0
					assert syncobj.timeline_wait_pending_for_checks(tw_obj) == 0
				}
				after_blocks, after_bytes := live_record_heap()
				if batch != 0 {
					assert before_blocks == after_blocks && before_bytes == after_bytes
					println('timeline-wait count=${count} batch=${batch} cycles=1000 retained_blocks=${i64(after_blocks) - before_blocks} retained_bytes=${i64(after_bytes) - i64(before_bytes)}')
				}
			}
		}
		tw_retire()
	} $else { panic('malloc-zone measurement requires macOS') }
}

pub fn run_timeline_wait_checks() {
	memory.reset(); memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
	proc.reset(); sched.reset(unsafe { nil })
	syncobj.check_timeline_capture_protocol_for_checks()
	assert sizeof(ioctl.DrmSyncobjTimelineWait) == 48
	assert __offsetof(ioctl.DrmSyncobjTimelineWait, points) == 8 && __offsetof(ioctl.DrmSyncobjTimelineWait, timeout_nsec) == 16
	assert __offsetof(ioctl.DrmSyncobjTimelineWait, count_handles) == 24 && __offsetof(ioctl.DrmSyncobjTimelineWait, deadline_nsec) == 40
	layout := common_ioctl_layout(ioctl.drm_ioctl_syncobj_timeline_wait) or { panic('timeline WAIT registration') }
	assert layout.size == 48 && layout.direction == ioctl_write | ioctl_read
	assert u32(3) << 30 | u32(48) << 16 | u32(`d`) << 8 | ioctl.drm_ioctl_syncobj_timeline_wait == 0xc03064ca
	mut cases := 0
	for _ in 0 .. 50 {
		proc.reset(); sched.reset(unsafe { nil })
		tw_obj = make_object(0)
		tw_old = make_fence(); tw_new = make_fence()
		tw_chain(tw_obj, tw_old, 5)
		mut input := TimelineWaitInput{handles: [4096]u32{init: tw_obj.handle}, points: [4096]u64{init: 5}}
		tw_input = &input
		memory.check_before_free(tw_free_check)
		for flags in [u32(0), 1, 2, 3, 4, 5, 8, 15]! {
			mut request := tw_request(&input, 1, flags, 0)
			before := memory.outstanding()
			code := ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request })
			assert code == if flags & ioctl.drm_syncobj_wait_available != 0 { 0 } else { -62 }
			assert memory.outstanding() == before && sched.polls == 0
			assert request.first_signaled == if code == 0 { u32(0) } else { 123 }
			cases++
		}
		syncobj.signal_error(tw_old, -19)
		for count in [u32(1), 64, 65, 129, 4096]! {
			mut request := tw_request(&input, count, ioctl.drm_syncobj_wait_all, -1)
			before := memory.outstanding()
			assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request }) == 0
			assert request.first_signaled == 0 && memory.outstanding() == before && usercopy.reads == 2
			for failure in 0 .. 2 + int(count > 64) {
				request = tw_request(&input, count, 0, 0)
				memory.fail_in(failure)
				assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request }) == -12
				assert memory.outstanding() == before && request.first_signaled == 123
				cases++
			}
			request = tw_request(&input, count, 0, 0); request.points = ~u64(0)
			assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request }) == -14 && memory.outstanding() == before
			request = tw_request(&input, count, 0, 0); request.points = 0
			assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request }) == 0
			cases += 3
		}
		tw_retire()
	}
	// Future-point captures survive reset/replacement and handle reuse; initial
	// availability waits succeed before completion, normal waits keep the fence.
	for mode in [1, 2, 3, 4, 5, 6, 7]! { for available in [false, true]! {
		proc.reset(); sched.reset(tw_script); tw_mode = mode
		tw_obj = make_object(0); tw_old = make_fence(); tw_new = make_fence()
		mut input := TimelineWaitInput{handles: [4096]u32{init: tw_obj.handle}, points: [4096]u64{init: 5}}
		tw_input = &input
		if mode == 6 { tw_chain(tw_obj, tw_old, 5) }
		flags := if available { ioctl.drm_syncobj_wait_available } else { ioctl.drm_syncobj_wait_for_submit }
		mut request := tw_request(&input, 1, flags, 10000)
		memory.check_before_free(tw_free_check)
		code := ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request })
		assert code == if mode in [3, 4, 5]! { -512 } else { 0 }
		if code == 0 { assert request.first_signaled == 0 }
		else { assert request.first_signaled == 123 }
		if mode == 1 && !available { assert sched.polls == 3, 'replacement must not retarget a captured point' }
		if mode in [1, 2, 7]! && available { assert sched.polls == 1 && !syncobj.is_signaled(tw_old) }
		tw_retire(); cases++
	} }
	// The initial snapshot pass must not arm future captures. A publication
	// followed by reset before arming is missed; only the later point is held.
	proc.reset(); sched.reset(tw_script); tw_mode = 7
	tw_obj = make_object(0); tw_old = make_fence(); tw_new = make_fence()
	mut input := TimelineWaitInput{handles: [4096]u32{init: tw_obj.handle}, points: [4096]u64{init: 5}}
	tw_input = &input
	tw_lock_passes = 3; klock.before_once(unsafe { &tw_obj.lock }, tw_gap)
	mut request := tw_request(&input, 1, ioctl.drm_syncobj_wait_for_submit, 10000)
	assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request }) == 0
	assert sched.polls == 2 && !syncobj.is_signaled(tw_old), 'initial pass must not capture a transient future point'
	tw_retire()
	// ALL retains the first initial-ready index, including UINT32_MAX when
	// nothing was initially ready. Exercise large future lists on every exit.
	for count in [u32(1), 65, 4096]! { for ending in 0 .. 3 {
		proc.reset(); sched.reset(tw_script)
		tw_mode = if ending == 0 { 7 } else if ending == 1 { 3 } else { 0 }
		tw_obj = make_object(0); tw_old = make_fence(); tw_new = make_fence()
		input = TimelineWaitInput{handles: [4096]u32{init: tw_obj.handle}, points: [4096]u64{init: 5}}
		tw_input = &input
		request = tw_request(&input, count, ioctl.drm_syncobj_wait_all | ioctl.drm_syncobj_wait_for_submit, if ending == 2 { i64(0) } else { i64(10000) })
		memory.check_before_free(tw_free_check)
		before := memory.outstanding()
		code := ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request })
		assert code == if ending == 0 { 0 } else if ending == 1 { -512 } else { -62 }
		assert request.first_signaled == if code == 0 { ~u32(0) } else { 123 }
		assert memory.outstanding() == before + if ending == 0 { 1 } else { 0 } // retained published chain only
		assert syncobj.timeline_wait_pending_for_checks(tw_obj) == 0
		if ending != 0 { tw_chain(tw_obj, tw_new, 5); syncobj.signal(tw_new) }
		tw_retire(); cases++
	} }
	proc.reset(); sched.reset(tw_script); tw_mode = 8
	tw_obj = make_object(0); tw_old = make_fence(); tw_new = make_fence()
	tw_chain(tw_obj, tw_old, 5)
	tw_other = make_object(0); syncobj.signal(tw_new); tw_chain(tw_other, tw_new, 5)
	input = TimelineWaitInput{handles: [4096]u32{init: tw_obj.handle}, points: [4096]u64{init: 5}}
	input.handles[1] = tw_other.handle
	request = tw_request(&input, 2, ioctl.drm_syncobj_wait_all, 10000)
	assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request }) == 0 && request.first_signaled == 1 && sched.polls == 1
	tw_retire(); cases++
	// Every initial entry is validated even when an earlier entry is ready.
	proc.reset(); sched.reset(unsafe { nil })
	tw_obj = make_object(0); tw_old = make_fence(); syncobj.signal(tw_old); tw_chain(tw_obj, tw_old, 5)
	input = TimelineWaitInput{handles: [4096]u32{init: tw_obj.handle}, points: [4096]u64{init: 5}}
	input.points[1] = 6
	request = tw_request(&input, 2, 0, 0)
	assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request }) == -22 && request.first_signaled == 123
	request = tw_request(&input, 0, 0, 0); request.handles = ~u64(0); request.points = ~u64(0)
	assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request }) == 0 && usercopy.reads == 0 && request.first_signaled == 123
	request.flags = 16
	assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request }) == -22
	assert ioctl_syncobj_timeline_wait(unsafe { nil }, unsafe { &request }) == -14
	assert ioctl_syncobj_timeline_wait(voidptr(11), unsafe { nil }) == -14
	tw_retire()
	println('DRM timeline WAIT: ${cases} counted checks; 48-byte UAPI, 1..4096 handles, point availability/completion, snapshot-before-arm, reset/reuse, errors/deadlines/signals and every request-owner OOM path pass.')
}

fn tw_trace_object(state int) &syncobj.SyncObj {
	obj := make_object(0)
	if state == 0 { return obj }
	leaf := make_fence()
	if state in [2, 4]! { syncobj.signal(leaf) }
	if state in [1, 2]! { syncobj.replace_fence(obj, leaf) }
	else {
		if state == 5 {
			prefix := make_fence(); syncobj.signal(prefix); tw_chain(obj, prefix, 1)
		}
		tw_chain(obj, leaf, if state == 6 { ~u64(0) } else { u64(3) })
	}
	return obj
}

pub fn run_timeline_wait_trace() {
	memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
	for a in 0 .. 7 { for b in 0 .. 7 { for c in 0 .. 7 { for pattern in 0 .. 4 {
		memory.reset(); proc.reset(); sched.reset(unsafe { nil })
		mut input := TimelineWaitInput{}
		for index, state in [a, b, c]! { input.handles[index] = tw_trace_object(state).handle }
		for index in 0 .. 3 {
			input.points[index] = match pattern {
				0 { u64(0) }
				1 { u64(index + 1) }
				2 { if index == 1 { ~u64(0) } else { u64(1) } }
				else { ~u64(0) }
			}
		}
		for flags := u32(0); flags < 16; flags++ {
			mut request := tw_request(&input, 3, flags, 0)
			code := ioctl_syncobj_timeline_wait(voidptr(11), unsafe { &request })
			println('${code} ${request.first_signaled}')
		}
		tw_retire()
	} } } }
}
