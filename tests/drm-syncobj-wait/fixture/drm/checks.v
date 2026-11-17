// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import sched
import usercopy
import proc
import memory
import klock

__global wait_fixture_objects [32]&syncobj.SyncObj
__global wait_fixture_fences [32]&syncobj.DmaFence
__global wait_fixture_object_count = 0
__global wait_fixture_fence_count = 0
__global wait_fixture_waits = 0
__global wait_fixture_target &syncobj.SyncObj = unsafe { nil }
__global wait_fixture_original &syncobj.DmaFence = unsafe { nil }
__global wait_fixture_replacement &syncobj.DmaFence = unsafe { nil }
__global wait_fixture_changing_handles &u32 = unsafe { nil }
__global wait_fixture_mode = 0

fn remember_fence(fence &syncobj.DmaFence) &syncobj.DmaFence {
	assert wait_fixture_fence_count < wait_fixture_fences.len
	wait_fixture_fences[wait_fixture_fence_count] = unsafe { fence }; wait_fixture_fence_count++
	return unsafe { fence }
}

fn make_fence() &syncobj.DmaFence { return remember_fence(syncobj.new_fence(7, u64(wait_fixture_fence_count))) }

fn make_object(flags u32) &syncobj.SyncObj {
	mut request := ioctl.DrmSyncobjCreate{ flags: flags }
	assert ioctl_syncobj_create(voidptr(11), &request) == 0
	object := syncobj.lookup(11, request.handle) or { panic('created handle') }
	assert wait_fixture_object_count < wait_fixture_objects.len
	wait_fixture_objects[wait_fixture_object_count] = object; wait_fixture_object_count++
	if fence := syncobj.get_fence(object) { remember_fence(fence) }
	return object
}

fn scripted(step u32) {
	match wait_fixture_mode {
		1 { // Replacing with incomplete work must not hide the captured completion.
			if step == 1 { syncobj.replace_fence(wait_fixture_target, wait_fixture_replacement) }
			if step == 2 { syncobj.signal(wait_fixture_original) }
		}
		2 { // A completed replacement must not satisfy an older pending wait.
			if step == 1 { syncobj.signal(wait_fixture_replacement); syncobj.replace_fence(wait_fixture_target, wait_fixture_replacement) }
		}
		3 { // Capture a submission, then keep it across another replacement.
			if step == 1 { syncobj.replace_fence(wait_fixture_target, wait_fixture_original) }
			if step == 2 { syncobj.signal(wait_fixture_replacement); syncobj.replace_fence(wait_fixture_target, wait_fixture_replacement) }
			if step == 3 { syncobj.signal(wait_fixture_original) }
		}
		4 { // Object identity survives destroy/reuse while awaiting first submission.
			if step == 1 {
				handle := wait_fixture_target.handle
				assert syncobj.destroy(11, handle)
				fresh := make_object(ioctl.drm_syncobj_create_signaled)
				assert fresh.handle == handle && fresh != wait_fixture_target
			}
			if step == 2 { syncobj.replace_fence(wait_fixture_target, wait_fixture_original); syncobj.signal(wait_fixture_original) }
		}
		5 {
			if step == 1 { unsafe { *wait_fixture_changing_handles = 999 } }
			if step == 2 { syncobj.signal(wait_fixture_original) }
		}
		6 {
			if step == 1 { syncobj.signal(wait_fixture_original) }
			if step == 3 { syncobj.signal_error(wait_fixture_replacement, -5) }
		}
		7 {
			if step == 1 {
				syncobj.replace_fence(wait_fixture_target, wait_fixture_original)
				syncobj.replace_fence(wait_fixture_target, unsafe { nil })
				syncobj.signal(wait_fixture_replacement)
				syncobj.replace_fence(wait_fixture_target, wait_fixture_replacement)
			}
			if step == 2 { syncobj.signal(wait_fixture_original) }
		}
		8 { if step == 1 { proc.private_signal(false) } }
		9 { if step == 1 { proc.shared_signal() } }
		10 { if step == 1 { proc.exit_thread() } }
		11 {
			if step == 1 { proc.private_signal(true) }
			if step == 2 { syncobj.signal(wait_fixture_original) }
		}
		12 {
			if step == 1 {
				syncobj.replace_fence(wait_fixture_target, wait_fixture_replacement)
				syncobj.signal(wait_fixture_replacement)
			}
		}
		else {}
	}
}

fn check(mut handles [2]u32, count u32, flags u32, timeout i64, expected int) u32 {
	usercopy.allow(unsafe { u64(&handles[0]) }, u64(sizeof(handles)))
	mut request := ioctl.DrmSyncobjWait{ handles: unsafe { u64(&handles[0]) },
		count_handles: count, flags: flags, timeout_nsec: timeout,
		first_signaled: 123, pad: 77, deadline_nsec: ~u64(0) }
	wait_fixture_waits++
	assert ioctl_syncobj_wait(voidptr(11), &request) == expected
	for index in 0 .. wait_fixture_object_count { syncobj.assert_no_captures_for_checks(wait_fixture_objects[index]) }
	if expected != 0 { assert request.first_signaled == 123 }
	assert usercopy.reads == if count == 0 || flags & ioctl.drm_syncobj_wait_available != 0 { 0 } else { 1 }
	return request.first_signaled
}

fn clear() {
	// Fixture-only cleanup after every wait and scripted action has returned;
	// production metadata retention and object/fence lifetime are unchanged.
	syncobj.destroy_owner(11)
	syncobj.destroy_owner(12)
	for i in 0 .. wait_fixture_object_count { syncobj.free_object_metadata_for_checks(wait_fixture_objects[i]); wait_fixture_objects[i] = unsafe { nil } }
	for i in 0 .. wait_fixture_fence_count {
		fence := wait_fixture_fences[i]
		unsafe { fence.waiters.free() }
		if memory.owns(voidptr(fence)) { memory.free(voidptr(fence)) }
		else { unsafe { free(fence) } }
		wait_fixture_fences[i] = unsafe { nil }
	}
	wait_fixture_object_count = 0; wait_fixture_fence_count = 0
	wait_fixture_target = unsafe { nil }; wait_fixture_original = unsafe { nil }; wait_fixture_replacement = unsafe { nil }
	wait_fixture_changing_handles = unsafe { nil }
	sched.reset(unsafe { nil })
}

fn transient_before_arm() {
	syncobj.replace_fence(wait_fixture_target, wait_fixture_original)
	syncobj.replace_fence(wait_fixture_target, unsafe { nil })
}

fn check_submission_gap() {
	proc.reset()
	wait_fixture_target = make_object(0)
	wait_fixture_original = make_fence()
	syncobj.signal(wait_fixture_original)
	wait_fixture_replacement = make_fence()
	other := make_object(0)
	syncobj.replace_fence(other, make_fence())
	mut handles := [wait_fixture_target.handle, other.handle]!
	wait_fixture_mode = 12
	sched.reset(scripted)
	// The first object has been snapshotted when WAIT reaches the second.
	klock.before_once(unsafe { &other.lock }, transient_before_arm)
	assert check(mut handles, 2, ioctl.drm_syncobj_wait_for_submit, 6000, 0) == 0
	assert sched.polls == 1 && syncobj.is_signaled(wait_fixture_replacement),
		'binary WAIT latched a transient submission before registration'
	clear()
}

pub fn run_wait_checks() {
	memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
	check_submission_gap()
	syncobj.run_capture_checks()
	for _ in 0 .. 200 {
		proc.reset()
		sched.reset(unsafe { nil })
		empty := make_object(0)
		if _ := syncobj.get_fence(empty) { assert false, 'unsignaled creation must start empty' }
		done := make_object(ioctl.drm_syncobj_create_signaled)
		assert syncobj.is_signaled(syncobj.get_fence(done) or { panic('signaled create') })
		mut handles := [empty.handle, done.handle]!
		check(mut handles, 1, 0, 0, -22)
		check(mut handles, 1, ioctl.drm_syncobj_wait_for_submit, 0, -62)
		check(mut handles, 1, ioctl.drm_syncobj_wait_available, 0, -22)
		check(mut handles, 0, 0, 0, 0)
		check(mut handles, 0, ioctl.drm_syncobj_wait_available, 0, -22)
		handles = [done.handle, empty.handle]!
		check(mut handles, 2, 0, 0, -22) // validate every fence before WAIT_ANY
		handles[1] = 999
		check(mut handles, 2, 0, 0, -2) // validate every handle before WAIT_ANY
		handles = [done.handle, done.handle]!
		check(mut handles, 2, ioctl.drm_syncobj_wait_all | ioctl.drm_syncobj_wait_deadline, -1, 0)
		pending := make_object(0)
		syncobj.replace_fence(pending, make_fence())
		handles = [pending.handle, done.handle]!
		assert check(mut handles, 2, 0, 0, 0) == 1
		check(mut handles, 2, ioctl.drm_syncobj_wait_all, 0, -62)
		check(mut handles, 1, 0, 1, -62)
		assert sched.polls == 0
		mut bad := ioctl.DrmSyncobjWait{ count_handles: 1 }
		usercopy.allow(0, 0)
		assert ioctl_syncobj_wait(voidptr(11), &bad) == -14
		bad.count_handles = 0
		assert ioctl_syncobj_wait(voidptr(11), &bad) == 0
		bad.count_handles = 65
		assert ioctl_syncobj_wait(voidptr(11), &bad) == -14
		bad.count_handles = 1; bad.handles = unsafe { u64(&handles[0]) }
		usercopy.allow(bad.handles, 8); usercopy.inject_fault()
		assert ioctl_syncobj_wait(voidptr(11), &bad) == -14
		usercopy.allow(bad.handles, 8)
		assert ioctl_syncobj_wait(voidptr(12), &bad) == -2
		assert ioctl_syncobj_wait(unsafe { nil }, &bad) == -14
		for scenario in 1 .. 6 {
			wait_fixture_mode = scenario
			wait_fixture_target = make_object(0); wait_fixture_original = make_fence(); wait_fixture_replacement = make_fence()
			if scenario in [1, 2, 5] { syncobj.replace_fence(wait_fixture_target, wait_fixture_original) }
			handles = [wait_fixture_target.handle, done.handle]!
			wait_fixture_changing_handles = unsafe { &handles[0] }
			usercopy.allow(unsafe { u64(&handles[0]) }, 8)
			mut request := ioctl.DrmSyncobjWait{ handles: unsafe { u64(&handles[0]) },
				count_handles: 1, timeout_nsec: 6000,
				flags: if scenario in [3, 4] { ioctl.drm_syncobj_wait_for_submit } else { u32(0) },
				first_signaled: 123 }
			sched.reset(scripted)
			result := ioctl_syncobj_wait(voidptr(11), &request)
			for index in 0 .. wait_fixture_object_count { syncobj.assert_no_captures_for_checks(wait_fixture_objects[index]) }
			wait_fixture_waits++
			assert result == if scenario == 2 { -62 } else { 0 }
			assert sched.polls == match scenario { 2 { u32(5) } 3 { u32(3) } else { u32(2) } }
			assert usercopy.reads == 1
			assert request.first_signaled == if result == 0 { u32(0) } else { u32(123) }
		}
		wait_fixture_mode = 6
		wait_fixture_original = make_fence(); wait_fixture_replacement = make_fence()
		left := make_object(0); right := make_object(0)
		syncobj.replace_fence(left, wait_fixture_original); syncobj.replace_fence(right, wait_fixture_replacement)
		handles = [left.handle, right.handle]!
		sched.reset(scripted)
		assert check(mut handles, 2, ioctl.drm_syncobj_wait_all, 6000, 0) == ~u32(0)
		assert sched.polls == 3
		wait_fixture_original = make_fence()
		syncobj.replace_fence(left, wait_fixture_original)
		sched.reset(scripted)
		assert check(mut handles, 2, ioctl.drm_syncobj_wait_all, 6000, 0) == 1
		assert sched.polls == 1
		sched.reset(unsafe { nil })
		check(mut handles, 2, 0, 1, 0) // readiness wins over expired absolute timeout
		for scenario in 7 .. 12 {
			proc.reset()
			wait_fixture_mode = scenario
			wait_fixture_target = make_object(0)
			wait_fixture_original = make_fence(); wait_fixture_replacement = make_fence()
			if scenario == 11 { syncobj.replace_fence(wait_fixture_target, wait_fixture_original) }
			handles = [wait_fixture_target.handle, wait_fixture_target.handle]!
			sched.reset(scripted)
			expected := if scenario in [8, 9, 10] { -512 } else { 0 }
			check(mut handles, 2, ioctl.drm_syncobj_wait_all | ioctl.drm_syncobj_wait_for_submit, 6000, expected)
			assert sched.polls == if expected == 0 { u32(2) } else { u32(1) }
			// Publication after cleanup must not touch the returned wait's stack.
			syncobj.replace_fence(wait_fixture_target, wait_fixture_replacement)
		}
		proc.reset(); sched.reset(unsafe { nil })
		proc.private_signal(false)
		handles = [done.handle, done.handle]!
		check(mut handles, 1, 0, 6000, 0) // completion precedes pending signal
		handles[0] = empty.handle
		check(mut handles, 1, ioctl.drm_syncobj_wait_for_submit, 0, -62) // timeout precedes signal
		check(mut handles, 1, ioctl.drm_syncobj_wait_for_submit, 6000, -512)
		assert sched.polls == 0
		proc.reset(); proc.shared_signal()
		handles[0] = pending.handle
		check(mut handles, 1, 0, 6000, -512) // an existing pending fence is interruptible too
		proc.reset(); proc.private_signal(true)
		check(mut handles, 1, 0, 6000, -62) // masked signals do not abort a pending wait
		proc.reset(); proc.exit_thread()
		handles[0] = done.handle
		check(mut handles, 1, 0, 6000, 0) // completion also wins over must_exit
		proc.reset()
		clear()
	}
	println('DRM binary waits: ${wait_fixture_waits} checks; stable snapshots, snapshot-before-arm, first submission, WAIT_ANY/ALL, errors, timeouts, flags and copy faults passed')
}
