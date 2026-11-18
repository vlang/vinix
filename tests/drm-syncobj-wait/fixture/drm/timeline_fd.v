// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import file
import memory

fn export_timeline_fd(obj &syncobj.SyncObj, point u64, code int) int {
	mut request := ioctl.DrmSyncobjHandle{handle: obj.handle, flags: 3, fd: -123, point: point}
	assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == code,
		'timeline export at point ${point}'
	assert request.handle == obj.handle && request.flags == 3 && request.point == point
	if code != 0 { assert request.fd == -123 }
	return int(request.fd)
}

fn import_timeline_fd(obj &syncobj.SyncObj, number int, point u64, code int) {
	mut request := ioctl.DrmSyncobjHandle{handle: obj.handle, flags: 3, fd: i32(number), point: point}
	assert ioctl_syncobj_fd_to_handle(voidptr(11), &request) == code,
		'timeline import at point ${point}'
	assert request.handle == obj.handle && request.flags == 3 && request.fd == number && request.point == point
}

fn run_timeline_sync_file_checks() {
	// The large-wait hook assumes every fixture object is still allocated.
	// This suite also frees its retained chains after those objects retire.
	memory.check_before_free(unsafe { nil })
	for _ in 0 .. 100 {
		source := make_object(0)
		target := make_object(0)
		first := make_fence()
		later := make_fence()
		predecessor := make_fence()
		first_chain := remember_fence(syncobj.reserve_chain() or { panic('first chain') })
		later_chain := remember_fence(syncobj.reserve_chain() or { panic('later chain') })
		assert syncobj.add_chain_point(source, first_chain, first, 5)
		assert syncobj.add_chain_point(source, later_chain, later, 10)
		syncobj.replace_fence(target, predecessor)

		number := export_timeline_fd(source, 4, 0)
		assert (fixture_sync_file_fence(number) or { panic('selected export') }) == first_chain
		assert export_timeline_fd(source, 11, -22) == -123
		file.fail_at(2)
		assert export_timeline_fd(source, 11, -24) == -123
		file.clear_failure()
		assert file.outstanding() == 1
		mut request := ioctl.DrmSyncobjHandle{handle: source.handle, flags: 1, fd: -1, point: 99}
		assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == 0
		assert (fixture_sync_file_fence(request.fd) or { panic('implicit point zero') }) == later_chain
		file.close(request.fd)
		request = ioctl.DrmSyncobjHandle{handle: source.handle, flags: 2, fd: -123, point: 5}
		assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == -22 && request.fd == -123
		request.point = 0
		assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == 0
		opaque := request.fd
		request.point = 5
		assert ioctl_syncobj_fd_to_handle(voidptr(11), &request) == -22
		request.point = 0
		assert ioctl_syncobj_fd_to_handle(voidptr(11), &request) == 0 && request.handle != source.handle
		assert syncobj.destroy(11, request.handle)

		before := memory.outstanding()
		memory.fail_next()
		import_timeline_fd(target, number, 7, -12)
		assert memory.outstanding() == before && current(target) == predecessor
		import_timeline_fd(target, opaque, 7, -22)
		file.close(opaque)
		import_timeline_fd(target, number, 7, 0)
		root := remember_fence(current(target))
		assert root.seqno == 7 && syncobj.chain_contained(root) == first_chain
		assert syncobj.chain_previous(root) == predecessor
		file.close(number)

		// Every imported head can itself be exported, then retained intact
		// as a subsequent payload. Completion must propagate through the
		// graph without following a chain recursively under the fence lock.
		for point in u64(8) .. 24 {
			snapshot := export_timeline_fd(target, 0, 0)
			previous := current(target)
			import_timeline_fd(target, snapshot, point, 0)
			file.close(snapshot)
			next := remember_fence(current(target))
			assert syncobj.chain_contained(next) == previous
			assert !syncobj.is_signaled(next)
		}
		syncobj.signal_error(first, -5)
		assert syncobj.is_signaled(first_chain) && !syncobj.is_signaled(root)
		retired := export_timeline_fd(source, 5, 0)
		assert (fixture_sync_file_fence(retired) or { panic('retired point') }) == syncobj.shared_timeline_stub()
		syncobj.signal(predecessor)
		assert syncobj.is_signaled(current(target)) && !syncobj.is_signaled(later_chain)
		import_timeline_fd(target, retired, 0, 0)
		assert current(target) == syncobj.shared_timeline_stub()
		request = ioctl.DrmSyncobjHandle{handle: target.handle, flags: 1, fd: i32(retired), point: 99}
		assert ioctl_syncobj_fd_to_handle(voidptr(11), &request) == 0
		assert current(target) == syncobj.shared_timeline_stub()
		syncobj.signal(later)
		file.close(retired)
		assert file.outstanding() == 0
		clear()
		assert memory.outstanding() == 0 && memory.live_bytes() == 0
	}
	println('DRM timeline sync-file descriptors: 100 cycles of exact-point selection, retired stubs, binary compatibility, nested completion, OOM and FD lifetime checks passed')
}
