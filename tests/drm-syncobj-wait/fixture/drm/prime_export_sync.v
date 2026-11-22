// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.gem
import drm.ioctl
import drm.syncobj
import file
import memory
import proc
import resource
import usercopy

const export_sync_file_command = u64(0xc0086202)

fn check_export_invisible_at_copyout(address u64, size u64) {
	assert size == sizeof(ioctl.DmaBufExportSyncFile)
	request := unsafe { &ioctl.DmaBufExportSyncFile(address) }
	file.assert_reservations(1)
	if _ := file.fd_from_fdnum(unsafe { nil }, request.fd) { assert false }
	mut other := file.FdReservation{}
	alternative := file.reserve_fd(unsafe { nil }, unsafe { &other }) or { panic('another reserved descriptor') }
	assert alternative != request.fd
	file.cancel_fd_reservation(unsafe { &other })
}

fn prime_export_result(mut fd file.FD, flags u32, expect int) int {
	mut request := ioctl.DmaBufExportSyncFile{flags: flags, fd: -99}
	address := unsafe { u64(&request) }
	usercopy.allow(address, sizeof(request))
	usercopy.allow_output(address, sizeof(request))
	if expect == 0 { usercopy.after_next_output(check_export_invisible_at_copyout) }
	assert prime_fd_ioctl(mut fd, export_sync_file_command, address) == expect
	assert request.flags == flags && usercopy.reads == 1
	assert usercopy.writes == if expect == 0 || expect == -16 { 1 } else { 0 }
	if expect != 0 && expect != -16 { assert request.fd == -99 }
	file.assert_reservations(0)
	return request.fd
}

fn prime_add_export_leaf(mut prime file.FD, fence &syncobj.DmaFence, flags u32) {
	number := create_sync_file_fd(fence) or { panic('source sync file') }
	assert prime_import_result(mut prime, flags, i32(number)) == 0
	file.close(number)
}

fn check_prime_sync_file_exports(features u32) {
	memory.reset()
	proc.reset()
	mut object := gem.create(7)
	object.file_scoped = features == 0
	prime_exported = unsafe { object }
	driver := DrmDriver{features: features, gem_export: prime_export}
	device := DrmDevice{driver: unsafe { &driver }}
	mut export := ioctl.DrmPrimeHandle{handle: 7, fd: -1}
	assert ioctl_prime_handle_to_fd(&device, voidptr(11), &export) == 0
	mut prime := file.fd_from_fdnum(unsafe { nil }, export.fd) or { panic('PRIME descriptor') }
	assert prime_fd_ioctl(mut prime, export_sync_file_command, 0) == -14
	for flags in [u32(0), 4, ~u32(0)]! { prime_export_result(mut prime, flags, -22) }
	empty := prime_export_result(mut prime, 1, 0)
	assert poll_descriptor(empty) == file.pollin
	file.close(empty)

	context := syncobj.new_queue_context() or { panic('PRIME source queue') }
	writer := remember_fence(syncobj.new_queue_fence(7, 1, context))
	reader := remember_fence(syncobj.new_queue_fence(7, 2, context))
	prime_add_export_leaf(mut prime, writer, 2)
	prime_add_export_leaf(mut prime, reader, 1)
	read := prime_export_result(mut prime, 1, 0)
	mut read_fd := file.fd_from_fdnum(unsafe { nil }, read) or { panic('read snapshot') }
	assert read_fd.flags & resource.o_cloexec != 0
	assert (sync_file_fence(read_fd) or { panic('single fence') }) == writer
	read_fd.unref()

	before := memory.outstanding()
	count := file.outstanding()
	file.fail_at(2)
	attempts := memory.attempts()
	prime_export_result(mut prime, 3, -24)
	assert memory.attempts() == attempts
	file.clear_failure()
	for position in 0 .. 4 {
		memory.fail_in(position)
		prime_export_result(mut prime, 3, -12)
		assert memory.outstanding() == before && file.outstanding() == count
	}
	file.fail_at(1)
	prime_export_result(mut prime, 3, -12)
	file.fail_at(3)
	uninstalled := prime_export_result(mut prime, 3, -16)
	if _ := file.fd_from_fdnum(unsafe { nil }, uninstalled) { assert false }
	mut output := ioctl.DmaBufExportSyncFile{flags: 3, fd: -99}
	address := unsafe { u64(&output) }
	usercopy.allow(address, sizeof(output))
	usercopy.allow_output(address, sizeof(output))
	usercopy.fail_output_at(address + 6)
	assert prime_fd_ioctl(mut prime, export_sync_file_command, address) == -14
	file.assert_reservations(0)
	assert memory.outstanding() == before && file.outstanding() == count

	// A closed, polled export detaches every pending callback. Re-import into
	// PRIME borrows the aggregate only until its flat leaves are staged.
	for _ in 0 .. 128 {
		number := prime_export_result(mut prime, 2, 0)
		assert poll_descriptor(number) == 0
		assert prime_import_result(mut prime, 1, i32(number)) == 0
		file.close(number)
		assert memory.outstanding() == before && file.outstanding() == count
	}

	queued := prime_export_result(mut prime, 3, 0)
	mut queued_fd := file.fd_from_fdnum(unsafe { nil }, queued) or { panic('queued snapshot') }
	queued_root := sync_file_fence(queued_fd) or { panic('queued root') }
	queued_fd.unref()
	assert poll_descriptor(queued) == 0
	syncobj.hold_fence_notifications_for_checks(true)
	syncobj.set_deadline(queued_root, 1)
	file.close(queued)
	assert memory.owns(voidptr(queued_root)) && memory.outstanding() == before + 2
	syncobj.hold_fence_notifications_for_checks(false)
	assert memory.outstanding() == before

	write := prime_export_result(mut prime, 3, 0)
	mut write_fd := file.fd_from_fdnum(unsafe { nil }, write) or { panic('write snapshot') }
	root := sync_file_fence(write_fd) or { panic('aggregate fence') }
	assert syncobj.array_count_for_checks(root) == 2 && !syncobj.is_signaled(root)
	assert poll_descriptor(write) == 0 && descriptor_generation(write) == 0
	write_fd.unref()
	merged := merge_fd(write, read, 'PRIME dependencies')
	query_merge_info(merged, 'PRIME dependencies', 2, 0)
	file.close(merged)

	target := make_object(0)
	mut request := ioctl.DrmSyncobjHandle{handle: ~u32(0), fd: i32(write), flags: 1}
	assert ioctl_syncobj_fd_to_handle(voidptr(11), &request) == -2
	request.handle = target.handle
	request.flags = 3
	request.point = 1
	memory.fail_next()
	assert ioctl_syncobj_fd_to_handle(voidptr(11), &request) == -12
	// Another export leaves the failed import on the reclaimable path.
	request.fd = i32(prime_export_result(mut prime, 3, 0))
	memory.fail_next()
	assert ioctl_syncobj_fd_to_handle(voidptr(11), &request) == -12
	after_failed_import := memory.outstanding()
	file.close(request.fd)
	assert memory.outstanding() == after_failed_import - 4
	request.fd = i32(write)
	request.flags = 1
	request.point = 0
	assert ioctl_syncobj_fd_to_handle(voidptr(11), &request) == 0
	assert (syncobj.get_fence(target) or { panic('imported snapshot') }) == root

	newer := make_fence()
	prime_add_export_leaf(mut prime, newer, 2)
	gem.unref(object)
	prime.unref()
	file.close(export.fd)
	prime_exported = unsafe { nil }
	assert gem.live() == 0
	syncobj.signal_error(writer, -5)
	assert poll_descriptor(read) == file.pollin && descriptor_generation(write) == 0
	assert poll_descriptor(write) == 0
	syncobj.signal(reader)
	assert poll_descriptor(write) == file.pollin && descriptor_generation(write) == 1
	assert !syncobj.is_signaled(newer)
	file.close(read)
	file.close(write)
	assert syncobj.is_signaled(root) && syncobj.get_error(root) == -5
	assert file.outstanding() == 0
	syncobj.replace_fence(target, unsafe { nil })
	syncobj.dispose_merged_for_checks(root)
	clear()
	memory.reset()
	proc.reset()
	println('DRM PRIME sync-file export: snapshots, CLOEXEC, copyout ordering, failure cleanup, repeated close and pending drainer pin passed')
}
