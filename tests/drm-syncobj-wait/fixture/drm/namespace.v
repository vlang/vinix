// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import memory
import proc
import sched

fn retire_namespace_object(obj &syncobj.SyncObj) {
	if fence := syncobj.get_fence(obj) { memory.free(voidptr(fence)) }
	syncobj.free_object_metadata_for_checks(obj)
}

pub fn run_namespace_checks() {
	memory.reset(); proc.reset(); sched.reset(unsafe { nil })
	memory.check_metadata_free(syncobj.assert_unpublished_allocation_for_checks)
	syncobj.check_namespace_boundaries_for_checks()
	syncobj.assert_namespace_for_checks(0)
	mut checks := 0
	// Both old limits must be crossed through the actual CREATE ioctl.
	for single_owner in [false, true]! {
		mut objects := unsafe { [4096]&syncobj.SyncObj{} }
		for index in 0 .. objects.len {
			owner := if single_owner { u64(11) } else { u64(100 + index % 4) }
			mut request := ioctl.DrmSyncobjCreate{ flags: if index % 2 == 0 { ioctl.drm_syncobj_create_signaled } else { u32(0) } }
			assert ioctl_syncobj_create(voidptr(owner), &request) == 0; checks++
			assert request.handle == u32(if single_owner { index + 1 } else { index / 4 + 1 })
			objects[index] = syncobj.lookup(owner, request.handle) or { panic('large namespace lookup') }
			if index % 2 == 0 { check_stub(current(objects[index]), syncobj.now_ns()) }
		}
		syncobj.assert_namespace_for_checks(4096)
		assert memory.object_count() == 4096 && memory.fence_count() == 2048
		if single_owner {
			// Deleting/reusing a high handle must preserve an already captured
			// object/fence, while the new identity takes the lowest free number.
			old := objects[3071]
			mut capture := syncobj.FenceCapture{}
			assert syncobj.prepare_capture(old, &capture, true)
			assert syncobj.destroy(11, 3072); checks++
			mut request := ioctl.DrmSyncobjCreate{ flags: ioctl.drm_syncobj_create_signaled }
			assert ioctl_syncobj_create(voidptr(11), &request) == 0; checks++
			assert request.handle == 3072
			fresh := syncobj.lookup(11, 3072) or { panic('high handle reuse') }
			assert voidptr(fresh) != voidptr(old)
			if _ := syncobj.captured_fence(&capture) { assert false }
			later := make_fence(); syncobj.replace_fence(old, later)
			assert voidptr(syncobj.captured_fence(&capture) or { panic('old identity capture lost') }) == voidptr(later)
			assert voidptr(current(fresh)) != voidptr(later)
			mut fresh_capture := syncobj.FenceCapture{}
			assert syncobj.prepare_capture(fresh, &fresh_capture, false)
			fresh_fence := current(fresh)
			syncobj.destroy_owner(11)
			assert voidptr(syncobj.captured_fence(&capture) or { panic('detached old capture lost on close') }) == voidptr(later)
			assert voidptr(syncobj.captured_fence(&fresh_capture) or { panic('current capture lost on close') }) == voidptr(fresh_fence)
			syncobj.release_capture(&capture); syncobj.release_capture(&fresh_capture)
			retire_namespace_object(fresh)
		} else {
			// Remove complete owner blocks in non-sorted order; neighboring
			// namespaces keep their original object identities and handles.
			for step, owner in [u64(102), 100, 103, 101]! {
				syncobj.destroy_owner(owner); checks++
				syncobj.assert_namespace_for_checks(4096 - (step + 1) * 1024)
				for index, obj in objects {
					if u64(100 + index % 4) == owner { if _ := syncobj.lookup(owner, obj.handle) { assert false } }
				}
			}
		}
		syncobj.assert_namespace_for_checks(0)
		for obj in objects {
			if single_owner && obj.handle == 3072 { syncobj.free_object_metadata_for_checks(obj) }
			else { retire_namespace_object(obj) }
		}
		// The normal fixture list owns the one manually created old fence.
		clear()
		assert memory.object_count() == 0 && memory.fence_count() == 0
		memory.reset()
	}
	// Explicitly reuse first/middle/last handles with owners inserted out of
	// order. Each splice must preserve every other owner's original identity.
	owners := [~u64(0), u64(1), u64(1) << 63, u64(11)]!
	mut edges := unsafe { [4][3]&syncobj.SyncObj{} }
	for handle in 0 .. 3 {
		for which, owner in owners {
			obj := syncobj.new_syncobj(owner) or { panic('edge creation') }
			assert obj.handle == u32(handle + 1)
			edges[which][handle] = obj; checks++
		}
	}
	for which, owner in owners {
		for handle in 0 .. 3 {
			old := edges[which][handle]
			assert syncobj.destroy(owner, u32(handle + 1)); checks++
			fresh := syncobj.new_syncobj(owner) or { panic('edge reuse') }; checks++
			assert fresh.handle == old.handle && voidptr(fresh) != voidptr(old)
			edges[which][handle] = fresh
			syncobj.free_object_metadata_for_checks(old)
			syncobj.assert_namespace_for_checks(12)
			for other, key in owners {
				for slot in 0 .. 3 {
					assert voidptr(syncobj.lookup(key, u32(slot + 1)) or { panic('neighbor changed') }) == voidptr(edges[other][slot])
				}
			}
		}
	}
	for owner in owners { syncobj.destroy_owner(owner); checks++ }
	syncobj.assert_namespace_for_checks(0)
	for which in 0 .. 4 { for handle in 0 .. 3 { syncobj.free_object_metadata_for_checks(edges[which][handle]) } }
	memory.reset()
	// A bitmap model is independent of the linked representation. It checks
	// reuse and isolation after every randomized create/remove/owner-close.
	mut random := u32(0x6d3e19a7)
	for _ in 0 .. 10 {
		mut model := unsafe { [5][512]&syncobj.SyncObj{} }
		mut created := unsafe { [512]&syncobj.SyncObj{} }
		mut made := 0
		mut live := 0
		for _ in 0 .. 500 {
			random = random * u32(1664525) + u32(1013904223)
			which := int((random >> 16) % 5)
			owner := [u64(1), 11, 100, u64(1) << 63, ~u64(0)]![which]
			operation := random % 4
			if operation < 2 {
				mut expected := 1
				for expected < 512 && model[which][expected] != unsafe { nil } { expected++ }
				assert expected < 512 && made < 512
				obj := syncobj.new_syncobj_with_flags(owner, made % 2 == 0) or { panic('model creation') }
				assert obj.handle == u32(expected)
				model[which][expected] = obj; created[made] = obj; made++; live++
			} else if operation == 2 {
				handle := u32((random >> 8) % 96)
				expected := model[which][handle] != unsafe { nil }
				assert syncobj.destroy(owner, handle) == expected
				if expected { model[which][handle] = unsafe { nil }; live-- }
			} else {
				syncobj.destroy_owner(owner)
				for index in 1 .. 512 {
					if model[which][index] != unsafe { nil } { live--; model[which][index] = unsafe { nil } }
				}
			}
			checks++
			syncobj.assert_namespace_for_checks(live)
			for index in 0 .. 5 {
				key := [u64(1), 11, 100, u64(1) << 63, ~u64(0)]![index]
				for handle in 0 .. 96 {
					found := syncobj.lookup(key, u32(handle)) or { unsafe { nil } }
					assert voidptr(found) == voidptr(model[index][handle])
				}
			}
		}
		for owner in [u64(1), 11, 100, u64(1) << 63, ~u64(0)]! { syncobj.destroy_owner(owner) }
		syncobj.assert_namespace_for_checks(0)
		for index in 0 .. made { retire_namespace_object(created[index]) }
		memory.reset()
	}
	memory.check_metadata_free(unsafe { nil })
	println('DRM namespaces: ${checks} cases; 4096 objects across files and in one file, high-handle identity/reuse, owner-block removal, 5000 bitmap-model operations, unsigned owner ordering and checked UINT32_MAX successor passed; all fixture metadata retired after consumers')
}
