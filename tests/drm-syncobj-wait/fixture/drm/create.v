// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import memory
import proc
import sched
import time

__global create_fixture_nested &syncobj.SyncObj = unsafe { nil }

fn observe_private_creation() {
	// Outer allocation and completed initial stub exist, but no guessed handle
	// exposes either. A nested creator must acquire the lowest free handle.
	if _ := syncobj.lookup(11, 1) { assert false, 'creation published before initialization' }
	assert memory.object_count() == 1 && memory.fence_count() == 1
	create_fixture_nested = make_object(ioctl.drm_syncobj_create_signaled)
	assert create_fixture_nested.handle == 1
}

fn create_during_allocation_failure() {
	// No rollback may erase the nested object's handle when the outer CREATE
	// returns ENOMEM. This also rejects a prematurely published empty object.
	if _ := syncobj.lookup(11, 1) { assert false, 'failing creation exposed a handle' }
	create_fixture_nested = make_object(ioctl.drm_syncobj_create_signaled)
	assert create_fixture_nested.handle == 1
}

fn remember_created(obj &syncobj.SyncObj) {
	assert wait_fixture_object_count < wait_fixture_objects.len
	wait_fixture_objects[wait_fixture_object_count] = unsafe { obj }; wait_fixture_object_count++
	if fence := syncobj.get_fence(obj) { remember_fence(fence) }
}

pub fn run_create_checks() {
	memory.reset()
	memory.check_metadata_free(syncobj.assert_unpublished_allocation_for_checks)
	mut checks := 0
	for _ in 0 .. 200 {
		proc.reset(); sched.reset(unsafe { nil }); time.reset()
		for flags in [u32(0), ioctl.drm_syncobj_create_signaled]! {
			memory.reset()
			mut request := ioctl.DrmSyncobjCreate{ flags: flags, handle: 77 }
			memory.fail_next()
			assert ioctl_syncobj_create(voidptr(11), &request) == -12; checks++
			assert request.handle == 77 && memory.attempts() == 1
			assert memory.object_count() == 0 && memory.fence_count() == 0
			if _ := syncobj.lookup(11, 1) { assert false }
		}
		memory.reset()
		mut failed := ioctl.DrmSyncobjCreate{ flags: ioctl.drm_syncobj_create_signaled, handle: 77 }
		memory.fail_in(1)
		assert ioctl_syncobj_create(voidptr(11), &failed) == -12; checks++
		assert failed.handle == 77 && memory.attempts() == 2
		assert memory.object_count() == 0 && memory.fence_count() == 0
		for failing_stage in 0 .. 2 {
			memory.reset(); memory.fail_in(failing_stage)
			memory.when_failing(create_during_allocation_failure)
			assert ioctl_syncobj_create(voidptr(11), &failed) == -12; checks++
			assert failed.handle == 77
			assert voidptr(syncobj.lookup(11, 1) or { panic('failure erased nested handle') }) == voidptr(create_fixture_nested)
			assert memory.object_count() == 1 && memory.fence_count() == 1
			check_stub(current(create_fixture_nested), 1000)
			create_fixture_nested = unsafe { nil }; clear()
			assert memory.object_count() == 0 && memory.fence_count() == 0
		}
		memory.reset()
		syncobj.before_namespace_lock_for_checks(observe_private_creation)
		mut request := ioctl.DrmSyncobjCreate{ flags: ioctl.drm_syncobj_create_signaled }
		assert ioctl_syncobj_create(voidptr(11), &request) == 0; checks++
		assert request.handle == 2
		outer := syncobj.lookup(11, 2) or { panic('outer creation lost') }
		remember_created(outer)
		assert memory.object_count() == 2 && memory.fence_count() == 2
		assert voidptr(current(outer)) != voidptr(current(create_fixture_nested))
		check_stub(current(outer), 1000)
		check_stub(current(create_fixture_nested), 1000)
		create_fixture_nested = unsafe { nil }; clear()
		memory.reset()
		for flags in [u32(0), ioctl.drm_syncobj_create_signaled]! {
			request = ioctl.DrmSyncobjCreate{ flags: flags }
			assert ioctl_syncobj_create(voidptr(11), &request) == 0; checks++
			obj := syncobj.lookup(11, request.handle) or { panic('creation not published') }
			remember_created(obj)
			assert request.handle == if flags == 0 { u32(1) } else { u32(2) }
			if flags == 0 { assert_has_no_fence(obj) }
			else { check_stub(current(obj), 1000) }
			if _ := syncobj.lookup(12, request.handle) { assert false }
		}
		assert memory.object_count() == 2 && memory.fence_count() == 1
		for flags in [u32(2), 3, ~u32(0)]! {
			request = ioctl.DrmSyncobjCreate{ handle: 99, flags: flags }
			before := memory.attempts()
			assert ioctl_syncobj_create(voidptr(11), &request) == -22; checks++
			assert request.handle == 99 && memory.attempts() == before
		}
		assert ioctl_syncobj_create(unsafe { nil }, &request) == -14; checks++
		assert ioctl_syncobj_create(voidptr(11), unsafe { nil }) == -14; checks++
		if _ := syncobj.new_syncobj(0) { assert false }; checks++
		legacy := syncobj.new_syncobj(11) or { panic('legacy empty creation') }
		remember_created(legacy)
		assert legacy.handle == 3; assert_has_no_fence(legacy); checks++
		clear(); memory.reset()
	}
	// Fill the real global table using independent namespaces, avoiding a
	// fixture replica of insertion. Failures must free all private preparation
	// and preserve every previously published object/fence identity.
	mut objects := unsafe { [1024]&syncobj.SyncObj{} }
	mut fences := unsafe { [1024]&syncobj.DmaFence{} }
	for index in 0 .. objects.len {
		obj := syncobj.new_syncobj_with_flags(u64(100 + index), index % 2 == 0) or { panic('fill namespace table') }
		objects[index] = obj
		assert obj.handle == 1
		if fence := syncobj.get_fence(obj) { fences[index] = fence }
	}
	assert memory.object_count() == 1024 && memory.fence_count() == 512
	for flags in [u32(0), ioctl.drm_syncobj_create_signaled]! {
		mut request := ioctl.DrmSyncobjCreate{ flags: flags, handle: 99 }
		assert ioctl_syncobj_create(voidptr(11), &request) == -12; checks++
		assert request.handle == 99 && memory.object_count() == 1024 && memory.fence_count() == 512
	}
	for index, obj in objects {
		assert voidptr(syncobj.lookup(u64(100 + index), 1) or { panic('exhaustion erased handle') }) == voidptr(obj)
		assert syncobj.destroy(u64(100 + index), 1)
		if fences[index] != unsafe { nil } {
			assert voidptr(current(obj)) == voidptr(fences[index])
			memory.free(voidptr(fences[index]))
		}
		syncobj.free_object_metadata_for_checks(obj)
	}
	assert memory.object_count() == 0 && memory.fence_count() == 0
	// Exercise the separate per-namespace handle-exhaustion exit while one
	// global table slot is still free, again using actual creation/insertion.
	for index in 0 .. 1023 {
		obj := syncobj.new_syncobj_with_flags(11, index % 2 == 0) or { panic('fill per-file handle space') }
		objects[index] = obj
		assert obj.handle == u32(index + 1)
		fences[index] = syncobj.get_fence(obj) or { unsafe { nil } }
	}
	assert memory.object_count() == 1023 && memory.fence_count() == 512
	for flags in [u32(0), ioctl.drm_syncobj_create_signaled]! {
		mut request := ioctl.DrmSyncobjCreate{ flags: flags, handle: 99 }
		assert ioctl_syncobj_create(voidptr(11), &request) == -12; checks++
		assert request.handle == 99 && memory.object_count() == 1023 && memory.fence_count() == 512
	}
	for index in 0 .. 1023 {
		obj := objects[index]
		assert voidptr(syncobj.lookup(11, u32(index + 1)) or { panic('handle exhaustion erased identity') }) == voidptr(obj)
		assert syncobj.destroy(11, u32(index + 1))
		if fences[index] != unsafe { nil } { memory.free(voidptr(fences[index])) }
		syncobj.free_object_metadata_for_checks(obj)
	}
	assert memory.object_count() == 0 && memory.fence_count() == 0
	memory.check_metadata_free(unsafe { nil }); memory.reset()
	println('DRM CREATE: ${checks} cases over 200 failure/publication cycles, real 1024-object global exhaustion and 1023-handle namespace exhaustion; fallible object/stub initialization, unchanged outputs on error, private cleanup after unlock, nested guessed-handle races, initial completed fence visibility and empty legacy creation passed')
}
