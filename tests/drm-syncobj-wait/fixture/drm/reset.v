// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import klock
import memory
import proc
import sched
import usercopy

__global reset_fixture_target &syncobj.SyncObj = unsafe { nil }
__global reset_fixture_old &syncobj.DmaFence = unsafe { nil }
__global reset_fixture_new &syncobj.DmaFence = unsafe { nil }
__global reset_fixture_mode = 0
__global reset_fixture_fresh &syncobj.SyncObj = unsafe { nil }

fn reset_one(obj &syncobj.SyncObj) int {
	mut handles := [obj.handle]!
	usercopy.allow(unsafe { u64(&handles[0]) }, sizeof(handles))
	mut request := ioctl.DrmSyncobjArray{ handles: unsafe { u64(&handles[0]) }, count_handles: 1 }
	return ioctl_syncobj_reset(voidptr(11), &request)
}

fn reset_during_wait(step u32) {
	if step == 1 {
		assert reset_one(reset_fixture_target) == 0
		if reset_fixture_mode == 1 {
			syncobj.assert_pending_captures_for_checks(reset_fixture_target, 1)
			syncobj.replace_fence(reset_fixture_target, reset_fixture_old)
			assert reset_one(reset_fixture_target) == 0
		}
		syncobj.signal(reset_fixture_new)
		syncobj.replace_fence(reset_fixture_target, reset_fixture_new)
	}
	if step == 2 { syncobj.signal_error(reset_fixture_old, -5) }
}

fn reuse_before_reset_effect() {
	handle := reset_fixture_target.handle
	assert syncobj.destroy(11, handle)
	reset_fixture_fresh = make_object(ioctl.drm_syncobj_create_signaled)
	assert reset_fixture_fresh.handle == handle
}

fn assert_has_no_fence(obj &syncobj.SyncObj) {
	if _ := syncobj.get_fence(obj) { assert false, 'reset left a current fence' }
}

pub fn run_reset_checks() {
	assert sizeof(ioctl.DrmSyncobjArray) == 16
	mut layout_probe := ioctl.DrmSyncobjArray{}
	assert unsafe { u64(&layout_probe.count_handles) - u64(&layout_probe) } == 8
	assert unsafe { u64(&layout_probe.pad) - u64(&layout_probe) } == 12
	layout := common_ioctl_layout(ioctl.drm_ioctl_syncobj_reset) or { panic('reset registration') }
	assert layout.size == 16 && layout.direction == ioctl_write | ioctl_read
	assert ioctl.drm_ioctl_syncobj_reset == 0xc4
	assert (u32(3) << 30 | u32(16) << 16 | u32(`d`) << 8 | ioctl.drm_ioctl_syncobj_reset) == 0xc01064c4
	mut checks := 0
	memory.reset()
	for _ in 0 .. 200 {
		proc.reset(); sched.reset(unsafe { nil })
		a := make_object(0); b := make_object(ioctl.drm_syncobj_create_signaled)
		original := make_fence()
		mut handles := [4096]u32{init: a.handle}
		mut request := ioctl.DrmSyncobjArray{ handles: unsafe { u64(&handles[0]) }, count_handles: 1 }
		for count in [u32(1), 64, 65, 129, 1024, 4096]! {
			syncobj.replace_fence(a, original)
			request.count_handles = count
			usercopy.allow(request.handles, u64(count) * 4)
			before_calls := memory.calls(); before_frees := memory.frees()
			assert ioctl_syncobj_reset(voidptr(11), &request) == 0; checks++
			assert usercopy.reads == 1
			assert_has_no_fence(a)
			assert !syncobj.is_signaled(original), 'reset signaled in-flight GPU work'
			if count > 64 {
				assert memory.calls() == before_calls + 1 && memory.frees() == before_frees + 1
				geometry := syncobj_wait_geometry(u64(count)) or { panic('reset geometry') }
				assert memory.last_request() == geometry.captures_offset
			} else { assert memory.calls() == before_calls && memory.frees() == before_frees }
			assert memory.outstanding() == 0 && memory.live_bytes() == 0
		}
		// Copy/lookup errors leave every earlier valid object unchanged.
		syncobj.replace_fence(a, original)
		handles[0] = a.handle; handles[1] = 999; request.count_handles = 2
		usercopy.allow(request.handles, 8)
		assert ioctl_syncobj_reset(voidptr(11), &request) == -2; checks++
		assert voidptr(syncobj.get_fence(a) or { panic('validation mutated object') }) == voidptr(original)
		handles[1] = b.handle; usercopy.inject_fault()
		assert ioctl_syncobj_reset(voidptr(11), &request) == -14; checks++
		assert voidptr(syncobj.get_fence(a) or { panic('copy fault mutated object') }) == voidptr(original)
		usercopy.allow(request.handles, 8)
		assert ioctl_syncobj_reset(voidptr(13), &request) == -2; checks++
		// Repeat failures through the allocated path, including a final invalid
		// handle after two distinct valid identities. Neither object may change.
		request.count_handles = 65; handles[64] = 999
		usercopy.allow(request.handles, 65 * 4)
		before_owned_frees := memory.frees()
		assert ioctl_syncobj_reset(voidptr(11), &request) == -2; checks++
		assert usercopy.reads == 1 && memory.frees() == before_owned_frees + 1
		assert voidptr(syncobj.get_fence(a) or { panic('owned validation mutated object') }) == voidptr(original)
		assert syncobj.is_signaled(syncobj.get_fence(b) or { panic('owned validation reset earlier object') })
		assert memory.outstanding() == 0 && memory.live_bytes() == 0
		handles[64] = a.handle; usercopy.inject_fault()
		assert ioctl_syncobj_reset(voidptr(11), &request) == -14; checks++
		assert memory.frees() == before_owned_frees + 2
		assert memory.outstanding() == 0 && memory.live_bytes() == 0
		usercopy.allow(request.handles, 65 * 4)
		assert ioctl_syncobj_reset(voidptr(11), &request) == 0; checks++
		assert usercopy.reads == 1 && memory.frees() == before_owned_frees + 3
		assert_has_no_fence(a); assert_has_no_fence(b)
		syncobj.replace_fence(a, original)
		request.pad = 1
		assert ioctl_syncobj_reset(voidptr(11), &request) == -22; checks++
		request.pad = 0; request.count_handles = 0
		assert ioctl_syncobj_reset(voidptr(11), &request) == -22; checks++
		request.count_handles = 65; memory.fail_next()
		assert ioctl_syncobj_reset(voidptr(11), &request) == -12; checks++
		assert memory.outstanding() == 0
		request.count_handles = ~u32(0)
		assert ioctl_syncobj_reset(voidptr(11), &request) == -12; checks++
		request.count_handles = 1; request.handles = 0
		assert ioctl_syncobj_reset(voidptr(11), &request) == -14; checks++
		assert ioctl_syncobj_reset(unsafe { nil }, &request) == -14; checks++
		assert ioctl_syncobj_reset(voidptr(11), unsafe { nil }) == -14; checks++
		// Reset also removes old timeline lookup membership without changing
		// a fence already captured from that old timeline.
		timeline_fence := make_fence()
		assert syncobj.add_timeline_point(a, 42, timeline_fence)
		captured := syncobj.get_timeline_fence(a, 42) or { panic('timeline snapshot') }
		assert reset_one(a) == 0; checks++
		if _ := syncobj.get_timeline_fence(a, 42) { assert false }
		assert !syncobj.is_signaled(captured)
		assert syncobj.add_timeline_point(a, 42, timeline_fence)
		syncobj.replace_fence(a, original)
		if _ := syncobj.get_timeline_fence(a, 42) { assert false, 'binary import retained old timeline' }
		syncobj.signal_error(timeline_fence, -110)
		assert syncobj.get_error(captured) == -110
		for mode in 0 .. 2 {
			reset_fixture_mode = mode
			reset_fixture_target = make_object(0)
			reset_fixture_old = make_fence(); reset_fixture_new = make_fence()
			if mode == 0 { syncobj.replace_fence(reset_fixture_target, reset_fixture_old) }
			handles[0] = reset_fixture_target.handle
			usercopy.allow(unsafe { u64(&handles[0]) }, 4)
			mut wait := ioctl.DrmSyncobjWait{ handles: unsafe { u64(&handles[0]) }, count_handles: 1,
				flags: if mode == 1 { ioctl.drm_syncobj_wait_for_submit } else { u32(0) }, timeout_nsec: 6000 }
			sched.reset(reset_during_wait)
			assert ioctl_syncobj_wait(voidptr(11), &wait) == 0; checks++
			assert sched.polls == 2 && syncobj.get_error(reset_fixture_old) == -5
			syncobj.assert_no_captures_for_checks(reset_fixture_target)
		}
		// A destroy/reuse after all lookups must not redirect a reset to a new object.
		reset_fixture_target = a
		klock.before_once(unsafe { &a.lock }, reuse_before_reset_effect)
		assert reset_one(a) == 0; checks++
		assert_has_no_fence(a)
		assert syncobj.is_signaled(syncobj.get_fence(reset_fixture_fresh) or { panic('fresh object reset') })
		assert memory.outstanding() == 0 && memory.live_bytes() == 0
		reset_fixture_target = unsafe { nil }; reset_fixture_old = unsafe { nil }
		reset_fixture_new = unsafe { nil }; reset_fixture_fresh = unsafe { nil }
		clear()
	}
	println('DRM reset: ${checks} checks over 200 cycles; exact 16-byte IOCTL registration, 1..4096 handles, validation-before-effects, inline/owned OOM/namespace/copy errors, old fence/timeline snapshots, pending publication captures and handle reuse passed')
}
