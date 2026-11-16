// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import file
import memory

__global import_fixture_cases = 0
__global import_fixture_number = -1
__global import_fixture_target &syncobj.SyncObj = unsafe { nil }
__global import_fixture_fresh &syncobj.SyncObj = unsafe { nil }
__global import_fixture_capture &syncobj.FenceCapture = unsafe { nil }

fn close_import_transport() { file.close(import_fixture_number) }

fn reuse_import_destination() {
	assert syncobj.destroy(12, import_fixture_target.handle)
	import_fixture_fresh = syncobj.new_syncobj(12) or { panic('reused destination') }
	assert import_fixture_fresh.handle == import_fixture_target.handle
	remember_created(import_fixture_fresh)
	assert syncobj.prepare_capture(import_fixture_fresh, import_fixture_capture, true)
}

fn remove_import_destination() { assert syncobj.destroy(12, import_fixture_target.handle) }

fn expect_sync_file_import(owner u64, handle u32, number int, expected int) {
	mut request := ioctl.DrmSyncobjHandle{ handle: handle, flags: 1, fd: i32(number) }
	assert ioctl_syncobj_fd_to_handle(voidptr(owner), &request) == expected,
		'owner ${owner} handle ${handle} fd ${number} expected ${expected}'
	assert request.handle == handle && request.flags == 1 && request.fd == number && request.pad == 0
	import_fixture_cases++
}

fn assert_fence_identity(obj &syncobj.SyncObj, fence &syncobj.DmaFence) {
	assert voidptr(current(obj)) == voidptr(fence)
}

pub fn run_sync_file_import_checks() {
	memory.reset()
	for _ in 0 .. 200 {
		source := make_object(0)
		target := syncobj.new_syncobj(12) or { panic('destination') }
		remember_created(target)
		alias := syncobj.import_syncobj(12, target) or { panic('destination alias') }
		first := make_fence()
		later := make_fence()
		old_gpu := make_fence()
		syncobj.replace_fence(source, first)
		syncobj.replace_fence(target, old_gpu)
		assert syncobj.add_timeline_point(target, 7, old_gpu)
		opaque := export_object(11, source.handle, 0)
		snapshot := export_object(11, source.handle, 1)
		mut captures := [4]syncobj.FenceCapture{}
		assert syncobj.prepare_capture(target, unsafe { &captures[0] }, false)
		// Descriptor validation wins when both descriptor and destination are
		// invalid. A valid sync-file with no destination instead gives ENOENT.
		attempts := memory.attempts()
		for missing in [u32(0), 999, ~u32(0)]! {
			for invalid in [-1, 31, 32, opaque]! { expect_sync_file_import(12, missing, invalid, -22) }
			expect_sync_file_import(12, missing, snapshot, -2)
		}
		for handle in [target.handle, alias]! {
			for invalid in [-1, 31, 32, opaque]! { expect_sync_file_import(12, handle, invalid, -22) }
		}
		for flags in [u32(2), 3, ~u32(0)]! {
			mut request := ioctl.DrmSyncobjHandle{ handle: target.handle, flags: flags, fd: i32(snapshot) }
			assert ioctl_syncobj_fd_to_handle(voidptr(12), &request) == -22
			assert request.handle == target.handle && request.fd == snapshot && request.flags == flags
			import_fixture_cases++
		}
		mut padded := ioctl.DrmSyncobjHandle{ handle: target.handle, flags: 1, fd: i32(snapshot), pad: 1 }
		assert ioctl_syncobj_fd_to_handle(voidptr(12), &padded) == -22
		assert padded.handle == target.handle && padded.fd == snapshot && padded.pad == 1
		import_fixture_cases++
		assert memory.attempts() == attempts && file.outstanding() == 2
		assert_fence_identity(target, old_gpu)
		assert voidptr(syncobj.get_timeline_fence(target, 7) or { panic('failed import cleared timeline') }) == voidptr(old_gpu)
		assert !syncobj.is_signaled(old_gpu)
		// Import publishes the snapshot through every alias and clears prior
		// timeline membership without signaling old GPU work or replacing captures.
		syncobj.replace_fence(target, unsafe { nil })
		assert syncobj.add_timeline_point(target, 7, old_gpu)
		assert syncobj.prepare_capture(target, unsafe { &captures[1] }, true)
		expect_sync_file_import(12, alias, snapshot, 0)
		assert_fence_identity(target, first)
		assert voidptr(syncobj.captured_fence(unsafe { &captures[1] }) or { panic('pending publication') }) == voidptr(first)
		assert voidptr(syncobj.captured_fence(unsafe { &captures[0] }) or { panic('old GPU capture') }) == voidptr(old_gpu)
		if _ := syncobj.get_timeline_fence(target, 7) { assert false }
		assert !syncobj.is_signaled(old_gpu) && !syncobj.is_signaled(first)
		syncobj.replace_fence(source, later)
		expect_sync_file_import(12, target.handle, snapshot, 0)
		assert_fence_identity(target, first); assert_fence_identity(source, later)
		syncobj.signal_error(first, -5)
		expect_sync_file_import(12, alias, snapshot, 0)
		assert syncobj.is_signaled(current(target)) && syncobj.get_error(current(target)) == -5
		assert !syncobj.is_signaled(old_gpu) && !syncobj.is_signaled(later)
		// Last descriptor close can free its wrapper after lookup, while the
		// captured fence remains valid for the subsequent destination lookup.
		closing := export_object(11, source.handle, 1)
		import_fixture_number = closing
		file.when_lookup(close_import_transport)
		expect_sync_file_import(12, target.handle, closing, 0)
		assert file.outstanding() == 2
		assert_fence_identity(target, later)
		// Reuse during descriptor lookup must select the new destination, not
		// a pointer obtained before resolving the transport. Old aliases survive.
		syncobj.replace_fence(target, unsafe { nil })
		syncobj.release_capture(unsafe { &captures[1] })
		assert syncobj.prepare_capture(target, unsafe { &captures[1] }, true)
		import_fixture_target = target
		import_fixture_capture = unsafe { &captures[2] }
		file.when_lookup(reuse_import_destination)
		expect_sync_file_import(12, target.handle, snapshot, 0)
		assert_fence_identity(import_fixture_fresh, first)
		assert_has_no_fence(target)
		assert voidptr(syncobj.lookup(12, alias) or { panic('old alias lost') }) == voidptr(target)
		if _ := syncobj.captured_fence(unsafe { &captures[1] }) { assert false }
		assert voidptr(syncobj.captured_fence(unsafe { &captures[2] }) or { panic('new destination capture') }) == voidptr(first)
		// Removal with no replacement returns ENOENT and leaves the removed
		// object's pending capture untouched. No publication may use a stale name.
		import_fixture_target = import_fixture_fresh
		syncobj.replace_fence(import_fixture_fresh, unsafe { nil })
		assert syncobj.prepare_capture(import_fixture_fresh, unsafe { &captures[3] }, true)
		file.when_lookup(remove_import_destination)
		expect_sync_file_import(12, import_fixture_fresh.handle, snapshot, -2)
		assert_has_no_fence(import_fixture_fresh)
		if _ := syncobj.captured_fence(unsafe { &captures[3] }) { assert false }
		expect_sync_file_import(12, alias, snapshot, 0)
		assert_fence_identity(target, first)
		for index in 0 .. captures.len { syncobj.release_capture(unsafe { &captures[index] }) }
		file.close(snapshot); file.close(opaque)
		assert file.outstanding() == 0 && memory.outstanding() == 0
		import_fixture_target = unsafe { nil }; import_fixture_fresh = unsafe { nil }
		import_fixture_capture = unsafe { nil }; import_fixture_number = -1
		clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	}
	// Repeated imports allocate neither new handles nor fences nor wrappers.
	source := make_object(0)
	target := syncobj.new_syncobj(12) or { panic('repeated destination') }
	remember_created(target)
	fence := make_fence(); syncobj.replace_fence(source, fence)
	number := export_object(11, source.handle, 1)
	attempts := memory.attempts()
	for _ in 0 .. 4096 { expect_sync_file_import(12, target.handle, number, 0) }
	assert memory.attempts() == attempts && memory.object_count() == 2 && memory.alias_count() == 0
	assert_fence_identity(target, fence)
	file.close(number); clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	println('DRM sync-file import: ${import_fixture_cases} cases; invalid descriptor precedence, ENOENT destinations, unchanged failure state, shared publication/captures, stable error snapshots, last-FD close, destination reuse/removal during FD lookup and allocation-free repeated imports passed')
}
