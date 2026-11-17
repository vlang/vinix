// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import memory
import proc
import sched
import usercopy

fn verify_detached_before_free(allocation voidptr, size u64) {
	for index in 0 .. wait_fixture_object_count {
		syncobj.assert_no_capture_in_region_for_checks(wait_fixture_objects[index], allocation, size)
	}
}

fn check_large(handles &u32, count u32, flags u32, timeout i64, expected int, expected_first u32) {
	usercopy.allow(u64(handles), u64(count) * sizeof(u32))
	mut request := ioctl.DrmSyncobjWait{ handles: u64(handles), count_handles: count,
		flags: flags, timeout_nsec: timeout, first_signaled: 123 }
	before_calls := memory.calls()
	before_frees := memory.frees()
	assert ioctl_syncobj_wait(voidptr(11), &request) == expected
	if expected == 0 { assert request.first_signaled == expected_first }
	else { assert request.first_signaled == 123 }
	for index in 0 .. wait_fixture_object_count { syncobj.assert_no_captures_for_checks(wait_fixture_objects[index]) }
	assert memory.outstanding() == 0 && memory.live_bytes() == 0
	if count > 64 {
		assert memory.calls() == before_calls + 1 && memory.frees() == before_frees + 1
	} else { assert memory.calls() == before_calls && memory.frees() == before_frees }
	assert usercopy.reads == 1
}

pub fn run_large_wait_checks() {
	mut geometries := 0
	for count in u64(1) .. 4097 {
		geometry := syncobj_wait_geometry(count) or { panic('small geometry') }
		assert geometry.objects_offset % 16 == 0 && geometry.captures_offset % 16 == 0
		assert geometry.objects_offset >= count * sizeof(u32)
		assert geometry.objects_offset - count * sizeof(u32) < 16
		objects_end := geometry.objects_offset + count * sizeof(voidptr)
		assert geometry.captures_offset >= objects_end && geometry.captures_offset - objects_end < 16
		assert geometry.bytes - geometry.captures_offset == count * sizeof(syncobj.FenceCapture)
		geometries++
	}
	for count in [u64(~u32(0)), u64(1) << 32, u64(1) << 50]! {
		geometry := syncobj_wait_geometry(count) or { panic('wide geometry') }
		assert geometry.bytes > count && geometry.objects_offset < geometry.captures_offset
		assert geometry.captures_offset < geometry.bytes
		geometries++
	}
	stride := sizeof(u32) + sizeof(voidptr) + sizeof(syncobj.FenceCapture)
	for count in [u64(0), ~u64(0), ~u64(0) / sizeof(u32), ~u64(0) / stride + 1]! {
		if _ := syncobj_wait_geometry(count) { assert false, 'overflow geometry accepted' }
		geometries++
	}
	memory.reset()
	memory.check_before_free(verify_detached_before_free)
	mut owner := new_syncobj_wait_buffer(65) or { panic('owned wait buffer') }
	assert memory.outstanding() == 1
	owner.free_owned(); owner.free_owned()
	assert memory.outstanding() == 0 && memory.live_bytes() == 0 && memory.frees() == 1
	memory.reset()
	mut checks := 0
	for _ in 0 .. 200 {
		proc.reset(); sched.reset(unsafe { nil })
		done := make_object(ioctl.drm_syncobj_create_signaled)
		pending := make_object(0)
		syncobj.replace_fence(pending, make_fence())
		mut handles := [4096]u32{init: done.handle}
		for count in [u32(1), 64, 65, 66, 127, 128, 129, 1023, 1024, 4096]! {
			check_large(unsafe { &handles[0] }, count, ioctl.drm_syncobj_wait_all, 0, 0, 0)
			checks++
		}
		// WAIT_ANY sees a ready index beyond both the old cap and 1,024 slots.
		for index in 0 .. 4095 { handles[index] = pending.handle }
		check_large(unsafe { &handles[0] }, 4096, 0, 0, 0, 4095); checks++
		for count in [u32(65), 129, 1024]! {
			wait_fixture_target = make_object(0)
			wait_fixture_original = make_fence(); wait_fixture_replacement = make_fence()
			for index in 0 .. 4096 { handles[index] = wait_fixture_target.handle }
			proc.reset(); sched.reset(unsafe { nil })
			check_large(unsafe { &handles[0] }, count,
				ioctl.drm_syncobj_wait_all | ioctl.drm_syncobj_wait_for_submit, 0, -62, 0); checks++
			proc.shared_signal()
			check_large(unsafe { &handles[0] }, count,
				ioctl.drm_syncobj_wait_all | ioctl.drm_syncobj_wait_for_submit, 6000, -512, 0); checks++
			proc.reset(); wait_fixture_mode = 7; sched.reset(scripted)
			check_large(unsafe { &handles[0] }, count,
				ioctl.drm_syncobj_wait_all | ioctl.drm_syncobj_wait_for_submit, 6000, 0, ~u32(0)); checks++
			assert sched.polls == 2
			syncobj.replace_fence(wait_fixture_target, wait_fixture_replacement)
		}
		proc.reset(); sched.reset(unsafe { nil })
		for index in 0 .. 4096 { handles[index] = done.handle }
		handles[64] = 999
		check_large(unsafe { &handles[0] }, 65, 0, 0, -2, 0); checks++
		handles[64] = pending.handle
		check_large(unsafe { &handles[0] }, 65, ioctl.drm_syncobj_wait_all, 0, -62, 0); checks++
		empty := make_object(0); handles[64] = empty.handle
		check_large(unsafe { &handles[0] }, 65, 0, 0, -22, 0); checks++
		mut request := ioctl.DrmSyncobjWait{ handles: unsafe { u64(&handles[0]) }, count_handles: 65 }
		usercopy.allow(request.handles, 260); usercopy.inject_fault()
		assert ioctl_syncobj_wait(voidptr(11), &request) == -14; checks++
		assert memory.outstanding() == 0 && memory.live_bytes() == 0
		memory.fail_next()
		usercopy.allow(request.handles, 260)
		assert ioctl_syncobj_wait(voidptr(11), &request) == -12; checks++
		assert usercopy.reads == 0 && memory.outstanding() == 0
		// Allocation failure cannot affect the inline path.
		memory.fail_next(); handles[0] = done.handle
		check_large(unsafe { &handles[0] }, 1, 0, 0, 0, 0); checks++
		request.count_handles = ~u32(0)
		assert ioctl_syncobj_wait(voidptr(11), &request) == -12; checks++
		assert memory.outstanding() == 0 && memory.live_bytes() == 0
		assert memory.last_request() > 1024 * 1024
		assert ioctl_syncobj_wait(voidptr(11), &request) == -12; checks++
		assert memory.outstanding() == 0 && memory.live_bytes() == 0
		clear()
	}
	println('DRM large waits: ${checks} checks across 200 cycles; 1/64 inline and 65..4096 handles, duplicate captures, ready index 4095, OOM/copy/lookup/prepare/timeout/signal cleanup; all owned bytes returned before later publication')
	println('DRM wait geometry: ${geometries} checked aligned/non-overlapping layouts and zero/overflow bounds')
}
