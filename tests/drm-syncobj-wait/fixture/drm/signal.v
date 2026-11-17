// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import klock
import memory
import proc
import sched
import time
import usercopy

__global signal_fixture_target &syncobj.SyncObj = unsafe { nil }
__global signal_fixture_old &syncobj.DmaFence = unsafe { nil }
__global signal_fixture_other &syncobj.SyncObj = unsafe { nil }
__global signal_fixture_fresh &syncobj.SyncObj = unsafe { nil }
__global signal_fixture_handles &u32 = unsafe { nil }
__global signal_fixture_mode = 0

fn signal_one(obj &syncobj.SyncObj) int {
	mut handles := [obj.handle]!
	usercopy.allow(unsafe { u64(&handles[0]) }, sizeof(handles))
	mut request := ioctl.DrmSyncobjArray{ handles: unsafe { u64(&handles[0]) }, count_handles: 1 }
	return ioctl_syncobj_signal(voidptr(11), &request)
}

fn signal_during_wait(step u32) {
	if step == 1 {
		assert signal_one(signal_fixture_target) == 0
		if signal_fixture_mode == 1 { assert reset_one(signal_fixture_target) == 0 }
	}
	if step == 2 { syncobj.signal_error(signal_fixture_old, -5) }
}

fn advance_before_first_replacement() { time.advance() }

fn reuse_before_signal_effect() {
	// First replacement starts only after the entire handle/object snapshot.
	handle := signal_fixture_other.handle
	assert syncobj.destroy(11, handle)
	signal_fixture_fresh = make_object(ioctl.drm_syncobj_create_signaled)
	assert signal_fixture_fresh.handle == handle
	unsafe { signal_fixture_handles[1] = 999 }
}

fn current(obj &syncobj.SyncObj) &syncobj.DmaFence {
	return syncobj.get_fence(obj) or { panic('expected current fence') }
}

fn check_stub(fence &syncobj.DmaFence, timestamp u64) {
	assert syncobj.is_signaled(fence) && syncobj.get_error(fence) == 0
	assert fence.context == 0 && fence.seqno == 0 && fence.timestamp_ns == timestamp
	syncobj.assert_private_stub_for_checks(fence)
}

fn finish_signal_cycle() {
	signal_fixture_target = unsafe { nil }; signal_fixture_old = unsafe { nil }
	signal_fixture_other = unsafe { nil }; signal_fixture_fresh = unsafe { nil }
	signal_fixture_handles = unsafe { nil }
	clear()
	memory.release_retained_fences(sizeof(syncobj.DmaFence))
}

pub fn run_signal_checks() {
	layout := common_ioctl_layout(ioctl.drm_ioctl_syncobj_signal) or { panic('signal registration') }
	assert layout.size == 16 && layout.direction == ioctl_write | ioctl_read
	assert ioctl.drm_ioctl_syncobj_signal == 0xc5
	assert (u32(3) << 30 | u32(16) << 16 | u32(`d`) << 8 | ioctl.drm_ioctl_syncobj_signal) == 0xc01064c5
	mut checks := 0
	for _ in 0 .. 200 {
		memory.reset(); proc.reset(); sched.reset(unsafe { nil })
		a := make_object(0); b := make_object(0); c := make_object(0)
		old := make_fence(); syncobj.replace_fence(a, old)
		mut handles := [a.handle, b.handle, c.handle]!
		mut request := ioctl.DrmSyncobjArray{ handles: unsafe { u64(&handles[0]) }, count_handles: 3 }
		for failed_index in 0 .. 3 {
			for obj in [a, b, c]! { syncobj.replace_fence(obj, old) }
			time.reset(); usercopy.allow(request.handles, sizeof(handles))
			memory.fail_in(failed_index)
			before := memory.fence_count()
			assert ioctl_syncobj_signal(voidptr(11), &request) == -12; checks++
			assert usercopy.reads == 1 && memory.fence_count() == before + failed_index
			for index, obj in [a, b, c]! {
				if index < failed_index { check_stub(current(obj), 1000) }
				else { assert voidptr(current(obj)) == voidptr(old) }
			}
			assert !syncobj.is_signaled(old)
		}
		// A bad final identity rejects the whole array before any stub allocation.
		for obj in [a, b, c]! { syncobj.replace_fence(obj, old) }
		handles[2] = 999; usercopy.allow(request.handles, sizeof(handles))
		calls := memory.calls()
		assert ioctl_syncobj_signal(voidptr(11), &request) == -2; checks++
		assert memory.calls() == calls && voidptr(current(a)) == voidptr(old)
		handles[2] = c.handle; usercopy.inject_fault()
		assert ioctl_syncobj_signal(voidptr(11), &request) == -14; checks++
		assert memory.calls() == calls
		usercopy.allow(request.handles, sizeof(handles))
		assert ioctl_syncobj_signal(voidptr(12), &request) == -2; checks++
		request.pad = 1
		assert ioctl_syncobj_signal(voidptr(11), &request) == -22; checks++
		request.pad = 0; request.count_handles = 0
		assert ioctl_syncobj_signal(voidptr(11), &request) == -22; checks++
		request.count_handles = 1; request.handles = 0
		assert ioctl_syncobj_signal(voidptr(11), &request) == -14; checks++
		assert ioctl_syncobj_signal(unsafe { nil }, &request) == -14; checks++
		assert ioctl_syncobj_signal(voidptr(11), unsafe { nil }) == -14; checks++
		// Duplicates get different timestamped stubs. First-publication captures
		// preserve the first success after a second success replaces the head.
		syncobj.replace_fence(a, unsafe { nil })
		mut capture := syncobj.FenceCapture{}
		syncobj.arm_capture_for_checks(a, &capture)
		handles = [a.handle, a.handle, a.handle]!
		request.handles = unsafe { u64(&handles[0]) }; request.count_handles = 2
		usercopy.allow(request.handles, sizeof(handles)); time.reset()
		klock.before_once(unsafe { &a.lock }, advance_before_first_replacement)
		assert ioctl_syncobj_signal(voidptr(11), &request) == 0; checks++
		first := syncobj.captured_fence(&capture) or { panic('signal did not publish to empty waiter') }
		assert voidptr(first) != voidptr(current(a))
		check_stub(first, 1000); check_stub(current(a), 2000)
		syncobj.signal_error(first, -110)
		check_stub(first, 1000) // later attempts cannot overwrite private success/time
		syncobj.release_capture(&capture)
		// SIGNAL discards the previous timeline root, retaining a captured point.
		assert syncobj.add_timeline_point(b, 42, old)
		point := syncobj.get_timeline_fence(b, 42) or { panic('timeline snapshot') }
		assert signal_one(b) == 0; checks++
		if _ := syncobj.get_timeline_fence(b, 42) { assert false }
		assert !syncobj.is_signaled(point)
		for mode in 0 .. 2 {
			signal_fixture_mode = mode
			signal_fixture_target = make_object(0); signal_fixture_old = make_fence()
			if mode == 0 { syncobj.replace_fence(signal_fixture_target, signal_fixture_old) }
			handles[0] = signal_fixture_target.handle
			usercopy.allow(unsafe { u64(&handles[0]) }, 4)
			mut wait := ioctl.DrmSyncobjWait{ handles: unsafe { u64(&handles[0]) }, count_handles: 1,
				flags: if mode == 1 { ioctl.drm_syncobj_wait_for_submit } else { u32(0) }, timeout_nsec: 6000 }
			sched.reset(signal_during_wait)
			assert ioctl_syncobj_wait(voidptr(11), &wait) == 0; checks++
			assert sched.polls == if mode == 1 { u32(1) } else { u32(2) }
		}
		// Both exact identities are captured before an effect destroys/reuses b
		// and mutates user handles. The second target must keep its old identity.
		signal_fixture_other = b; signal_fixture_handles = unsafe { &handles[0] }
		handles = [a.handle, b.handle, c.handle]!
		request.handles = unsafe { u64(&handles[0]) }; request.count_handles = 2
		usercopy.allow(request.handles, sizeof(handles))
		klock.before_once(unsafe { &a.lock }, reuse_before_signal_effect)
		assert ioctl_syncobj_signal(voidptr(11), &request) == 0; checks++
		assert usercopy.reads == 1
		assert voidptr(current(b)) != voidptr(current(signal_fixture_fresh))
		check_stub(current(b), syncobj.now_ns())
		// Ordinary completion timestamps are first-writer state too.
		mut normal := make_fence()
		time.reset(); syncobj.signal_error(normal, -5)
		assert normal.timestamp_ns == 1000
		time.advance(); syncobj.signal(normal); syncobj.signal_error(normal, -110)
		assert normal.timestamp_ns == 1000 && syncobj.get_error(normal) == -5
		checks++
		finish_signal_cycle()
	}
	// Large duplicate arrays require one temporary owner plus one retained
	// completion per entry. Validation and prefix OOM must free only the owner.
	for count in [u32(1), 64, 65, 129, 1024, 4096]! {
		memory.reset(); proc.reset(); sched.reset(unsafe { nil }); time.reset()
		a := make_object(0); old := make_fence(); syncobj.replace_fence(a, old)
		mut handles := [4096]u32{init: a.handle}
		mut request := ioctl.DrmSyncobjArray{ handles: unsafe { u64(&handles[0]) }, count_handles: count }
		usercopy.allow(request.handles, u64(count) * 4)
		assert ioctl_syncobj_signal(voidptr(11), &request) == 0; checks++
		assert memory.outstanding() == 0 && memory.fence_count() == int(count)
		assert memory.live_bytes() == 0 && memory.fence_bytes() == u64(count) * sizeof(syncobj.DmaFence)
		assert usercopy.reads == 1 && !syncobj.is_signaled(old)
		check_stub(current(a), 1000)
		finish_signal_cycle()
	}
	for failed_index in 0 .. 4 {
		memory.reset(); proc.reset(); sched.reset(unsafe { nil }); time.reset()
		a := make_object(0); old := make_fence(); syncobj.replace_fence(a, old)
		mut handles := [65]u32{init: a.handle}
		mut request := ioctl.DrmSyncobjArray{ handles: unsafe { u64(&handles[0]) }, count_handles: 65 }
		usercopy.allow(request.handles, sizeof(handles)); memory.fail_in(failed_index)
		assert ioctl_syncobj_signal(voidptr(11), &request) == -12; checks++
		published := if failed_index == 0 { 0 } else { failed_index - 1 }
		assert memory.outstanding() == 0 && memory.fence_count() == published
		if published == 0 { assert voidptr(current(a)) == voidptr(old) }
		else { check_stub(current(a), 1000) }
		assert usercopy.reads == if failed_index == 0 { 0 } else { 1 }
		assert memory.live_bytes() == 0 && memory.fence_bytes() == u64(published) * sizeof(syncobj.DmaFence)
		finish_signal_cycle()
	}
	for fault in 0 .. 3 {
		memory.reset(); proc.reset(); sched.reset(unsafe { nil })
		a := make_object(0); old := make_fence(); syncobj.replace_fence(a, old)
		mut handles := [65]u32{init: a.handle}
		mut request := ioctl.DrmSyncobjArray{ handles: unsafe { u64(&handles[0]) }, count_handles: 65 }
		usercopy.allow(request.handles, sizeof(handles))
		if fault == 0 { usercopy.inject_fault() }
		if fault == 1 { handles[64] = 999 }
		if fault == 2 { request.count_handles = ~u32(0) }
		assert ioctl_syncobj_signal(voidptr(11), &request) == if fault == 0 { -14 } else if fault == 1 { -2 } else { -12 }
		checks++
		assert memory.outstanding() == 0 && memory.live_bytes() == 0
		assert memory.calls() == 1 && memory.frees() == if fault == 2 { 0 } else { 1 }
		assert voidptr(current(a)) == voidptr(old) && !syncobj.is_signaled(old)
		finish_signal_cycle()
	}
	memory.reset()
	println('DRM SIGNAL: ${checks} cases over 200 identity/capture/failure cycles plus 1..4096 handles; private timestamped completions, first status/time, validation before effects, prefix OOM, duplicate captures, old GPU/timeline snapshots and handle reuse passed; retained fence bytes accounted separately from freed request owners')
}
