// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import file
import memory
import resource
import time
import usercopy

__global sharing_fd = -1
__global sharing_object &syncobj.SyncObj = unsafe { nil }

fn close_during_lookup() { file.close(sharing_fd) }
fn destroy_before_import() { assert syncobj.destroy(11, sharing_object.handle) }

fn export_object(owner u64, handle u32, flags u32) int {
	mut request := ioctl.DrmSyncobjHandle{ handle: handle, flags: flags, fd: -1 }
	assert ioctl_syncobj_handle_to_fd(voidptr(owner), &request) == 0
	mut fd := file.fd_from_fdnum(unsafe { nil }, int(request.fd)) or { panic('export descriptor') }
	assert fd.flags == resource.o_cloexec
	fd.unref()
	return int(request.fd)
}

fn import_object(owner u64, number int) u32 {
	mut request := ioctl.DrmSyncobjHandle{ fd: i32(number), handle: 999 }
	assert ioctl_syncobj_fd_to_handle(voidptr(owner), &request) == 0
	return request.handle
}

fn binary_action(owner u64, handle u32, signal bool) {
	mut handles := [handle]!
	mut request := ioctl.DrmSyncobjArray{ handles: unsafe { u64(&handles[0]) }, count_handles: 1 }
	usercopy.allow(request.handles, sizeof(handles))
	if signal { assert ioctl_syncobj_signal(voidptr(owner), &request) == 0 }
	else { assert ioctl_syncobj_reset(voidptr(owner), &request) == 0 }
}

pub fn run_sharing_checks() {
	memory.reset()
	memory.check_metadata_free(syncobj.assert_unpublished_allocation_for_checks)
	mut checks := 0
	for _ in 0 .. 200 {
		time.reset()
		obj := make_object(0)
		original := obj.handle
		sharing_object = obj
		// Empty objects can be exported opaquely; sync-file export needs a fence.
		number := export_object(11, original, 0); checks++
		mut request := ioctl.DrmSyncobjHandle{ handle: original, flags: 1, fd: -1 }
		assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == -22; checks++
		left := import_object(22, number); checks++
		right := import_object(22, number); checks++
		same_file := import_object(11, number); checks++
		assert left == 1 && right == 2 && same_file == 2 && obj.handle == original
		for key in [left, right]! { assert voidptr(syncobj.lookup(22, key) or { panic('alias') }) == voidptr(obj) }
		assert voidptr(syncobj.lookup(11, same_file) or { panic('same-file alias') }) == voidptr(obj)
		syncobj.assert_namespace_for_checks(4)
		// Pending captures through aliases see the first publication, even if
		// another alias immediately resets the shared object afterward.
		mut capture := syncobj.FenceCapture{}
		assert syncobj.prepare_capture(syncobj.lookup(22, right) or { panic('alias') }, unsafe { &capture }, true)
		binary_action(22, left, true); checks++
		first := current(obj)
		assert syncobj.is_signaled(first)
		snapshot := export_object(22, right, 1); checks++
		binary_action(11, same_file, false); checks++
		assert_has_no_fence(obj)
		assert voidptr(syncobj.captured_fence(unsafe { &capture }) or { panic('first publication') }) == voidptr(first)
		assert voidptr(sync_file_fence_from_fd(snapshot) or { panic('stable sync file') }) == voidptr(first)
		binary_action(22, right, true); checks++
		assert voidptr(current(obj)) != voidptr(first) && syncobj.is_signaled(current(obj))
		assert voidptr(sync_file_fence_from_fd(snapshot) or { panic('stable sync file') }) == voidptr(first)
		syncobj.release_capture(unsafe { &capture })
		// Opaque and fence descriptors are distinct types in both directions.
		request = ioctl.DrmSyncobjHandle{ fd: i32(snapshot), handle: 777 }
		assert ioctl_syncobj_fd_to_handle(voidptr(33), &request) == -22; checks++
		assert request.handle == 777
		if _ := sync_file_fence_from_fd(number) { assert false }
		// Linux maps private sync-file creation failure to EINVAL; opaque
		// construction retains ENOMEM. Number reservation failure is EMFILE.
		for flags in [u32(0), 1]! {
			for position in 0 .. 2 {
				memory.fail_in(position)
				request = ioctl.DrmSyncobjHandle{ handle: original, flags: flags, fd: -123 }
				assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == if flags == 0 { -12 } else { -22 }; checks++
				assert request.fd == -123 && memory.outstanding() == 4 && file.outstanding() == 2,
					'flags ${flags} allocation ${position}: fd ${request.fd}, owners ${memory.outstanding()}, descriptions ${file.outstanding()}'
			}
			for stage in 1 .. 3 {
				file.fail_at(stage)
				request = ioctl.DrmSyncobjHandle{ handle: original, flags: flags, fd: -123 }
				assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == if stage == 2 { -24 } else if flags == 0 { -12 } else { -22 }; checks++
				file.clear_failure()
				assert request.fd == -123 && file.outstanding() == 2
				assert memory.outstanding() == 4, 'flags ${flags} file stage ${stage} owners ${memory.outstanding()}'
			}
		}
		memory.fail_next()
		request = ioctl.DrmSyncobjHandle{ fd: i32(number), handle: 777 }
		assert ioctl_syncobj_fd_to_handle(voidptr(33), &request) == -12; checks++
		assert request.handle == 777 && memory.alias_count() == 3
		syncobj.assert_namespace_for_checks(4)
		for flags in [u32(2), 3, ~u32(0)]! {
			request = ioctl.DrmSyncobjHandle{ handle: original, flags: flags, fd: i32(number) }
			assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == -22; checks++
			assert ioctl_syncobj_fd_to_handle(voidptr(33), &request) == -22; checks++
		}
		request = ioctl.DrmSyncobjHandle{ handle: original, fd: i32(number), pad: 1 }
		assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == -22; checks++
		assert ioctl_syncobj_fd_to_handle(voidptr(33), &request) == -22; checks++
		for bad in [-1, 31, 32]! {
			request = ioctl.DrmSyncobjHandle{ fd: i32(bad), handle: 777 }
			assert ioctl_syncobj_fd_to_handle(voidptr(33), &request) == -22; checks++
			assert request.handle == 777
		}
		// Reuse one alias without modifying another name or the shared object.
		assert syncobj.destroy(22, left); checks++
		assert memory.alias_count() == 2
		assert import_object(22, number) == left; checks++
		// Closing a source namespace cannot invalidate an exported object.
		syncobj.destroy_owner(11); checks++
		assert voidptr(syncobj.lookup(22, right) or { panic('source close invalidated alias') }) == voidptr(obj)
		new_source := make_object(0)
		assert new_source.handle == original && voidptr(new_source) != voidptr(obj)
		assert import_object(33, number) == 1; checks++
		// A duplicated transport survives closure of its original descriptor.
		duplicate := file.duplicate(number)
		file.close(number)
		assert import_object(33, duplicate) == 2; checks++
		// Close the last descriptor after the lookup takes its reference.
		sharing_fd = duplicate; file.when_lookup(close_during_lookup)
		assert import_object(33, duplicate) == 3; checks++
		file.close(snapshot)
		assert file.outstanding() == 0
		binary_action(33, 3, false); checks++
		assert_has_no_fence(obj)
		binary_action(22, right, true); checks++
		assert syncobj.is_signaled(current(obj)) && new_source.fence == unsafe { nil }
		// Export/import again after all original handles/descriptors disappeared.
		last := export_object(33, 3, 0)
		syncobj.destroy_owner(22); syncobj.destroy_owner(33)
		assert memory.alias_count() == 0
		sharing_fd = last; file.when_lookup(close_during_lookup)
		assert import_object(22, last) == 1; checks++
		syncobj.destroy_owner(22)
		assert memory.alias_count() == 0 && file.outstanding() == 0
		sharing_object = unsafe { nil }; sharing_fd = -1
		clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	}
	// More than the old fixed limit, with one object and independently owned
	// entries. Owner-close retires only links; the transport still imports it.
	obj := make_object(0)
	number := export_object(11, obj.handle, 0)
	for index in 0 .. 4096 { assert import_object(22, number) == u32(index + 1); checks++ }
	assert memory.alias_count() == 4096
	syncobj.assert_namespace_for_checks(4097)
	for index in [0, 2047, 4095]! {
		assert syncobj.destroy(22, u32(index + 1)); checks++
		assert import_object(22, number) == u32(index + 1); checks++
	}
	syncobj.destroy_owner(22)
	assert memory.alias_count() == 0
	// Destroying the original name immediately before alias publication is safe.
	sharing_object = obj
	syncobj.before_namespace_lock_for_checks(destroy_before_import)
	assert import_object(22, number) == 1; checks++
	file.close(number); syncobj.destroy_owner(22)
	sharing_object = unsafe { nil }
	clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	println('DRM syncobj sharing: ${checks} cases; opaque identity across files and repeated imports, shared SIGNAL/RESET, stable sync-file snapshots, first captures, descriptor type/failure/close races, alias reuse, 4096 imports and complete link retirement passed')
}
