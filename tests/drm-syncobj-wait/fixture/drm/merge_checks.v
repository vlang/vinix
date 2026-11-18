// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import errno
import file
import gpu.agx.submission
import memory
import proc
import resource
import time
import usercopy

const merge_command = u64(0xc0303e03)

fn assert_merge_reserved(address u64, size u64) {
	assert size == sizeof(ioctl.SyncMergeData)
	request := unsafe { &ioctl.SyncMergeData(address) }
	file.assert_reservations(1)
	if _ := file.fd_from_fdnum(unsafe { nil }, request.fence) { assert false }
}

fn run_merge_request(first int, request &ioctl.SyncMergeData, expected u64) {
	address := u64(request)
	usercopy.allow(address, sizeof(ioctl.SyncMergeData))
	usercopy.allow_output(address, sizeof(ioctl.SyncMergeData))
	if expected == 0 { usercopy.after_next_output(assert_merge_reserved) }
	invoke_info(first, address, merge_command, expected)
	assert usercopy.reads == 1
	assert usercopy.writes == if expected == 0 { 1 } else { 0 }
	file.assert_reservations(0)
}

fn merge_fd(first int, second int, name string) int {
	mut request := ioctl.SyncMergeData{fd2: i32(second), fence: -123}
	for index in 0 .. name.len {
		if index == request.name.len { break }
		request.name[index] = name[index]
	}
	run_merge_request(first, unsafe { &request }, 0)
	assert request.name[31] == 0 && request.fd2 == second
	return int(request.fence)
}

fn query_merge_info(number int, expected_name string, count u32, status int) {
	mut details := [2]ioctl.SyncFenceInfo{}
	mut header := ioctl.SyncFileInfo{}
	prepare_info(unsafe { &header }, unsafe { &details[0] }, 0)
	invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), 0)
	assert header.num_fences == count
	assert header.status == status
	check_info_name(unsafe { &header.name[0] }, expected_name, 0xa5)
}

fn check_sync_file_merge() {
	assert sizeof(ioctl.SyncMergeData) == 48 && __offsetof(ioctl.SyncMergeData, fence) == 36
	memory.reset()
	proc.reset()
	context := syncobj.new_queue_context() or { panic('merge source queue') }
	a := remember_fence(syncobj.new_queue_fence(7, 1, context))
	b := remember_fence(syncobj.new_queue_fence(7, 2, context))
	first := create_sync_file_fd(a) or { panic('first sync-file') }
	second := create_sync_file_fd(b) or { panic('second sync-file') }
	baseline := memory.outstanding()
	file.fail_at(2)
	usercopy.allow(0, 0)
	invoke_info(first, 0, merge_command, errno.emfile)
	assert usercopy.reads == 0 && usercopy.writes == 0
	file.clear_failure()
	invoke_info(first, 0, merge_command, errno.efault)
	mut request := ioctl.SyncMergeData{fd2: -1, fence: -123, flags: 1}
	run_merge_request(first, unsafe { &request }, errno.einval)
	request.flags = 0
	request.pad = 1
	run_merge_request(first, unsafe { &request }, errno.einval)
	request.pad = 0
	run_merge_request(first, unsafe { &request }, 2)
	request.fd2 = i32(second)
	for position in 0 .. 4 {
		memory.fail_in(position)
		run_merge_request(first, unsafe { &request }, errno.enomem)
		assert request.fence == -123 && memory.outstanding() == baseline && file.outstanding() == 2
	}
	file.fail_at(1)
	run_merge_request(first, unsafe { &request }, errno.enomem)
	address := unsafe { u64(&request) }
	usercopy.allow(address, sizeof(request))
	usercopy.allow_output(address, sizeof(request))
	usercopy.fail_output_at(address + 39)
	invoke_info(first, address, merge_command, errno.efault)
	file.assert_reservations(0)
	assert memory.outstanding() == baseline && file.outstanding() == 2

	same := merge_fd(first, first, '')
	assert (fixture_sync_file_fence(same) or { panic('dedup leaf') }) == a
	file.close(same)
	combined := merge_fd(first, second, '12345678901234567890123456789012345')
	query_merge_info(combined, '12345678901234567890123456789012345', 2, 0)
	final_fd := merge_fd(combined, first, 'render and compute')
	query_merge_info(final_fd, 'render and compute', 2, 0)
	mut merged_fd := file.fd_from_fdnum(unsafe { nil }, final_fd) or { panic('merged fd') }
	assert merged_fd.flags & resource.o_cloexec != 0
	root := sync_file_fence(merged_fd) or { panic('merged aggregate') }
	merged_fd.unref()
	file.close(combined)
	file.close(first)
	file.close(second)
	assert poll_descriptor(final_fd) == 0

	// Resolve a merged descriptor through the real native G13 input staging.
	// The scheduler's input keeps the fence after both namespaces disappear.
	target := make_object(0)
	mut sync_request := ioctl.DrmSyncobjHandle{handle: target.handle, fd: i32(final_fd), flags: 1}
	assert ioctl_syncobj_fd_to_handle(voidptr(11), &sync_request) == 0
	input := ioctl.DrmAsahiSync{handle: target.handle, sync_type: ioctl.asahi_sync_syncobj}
	usercopy.allow(unsafe { u64(&input) }, sizeof(input))
	code, staged := submission.stage_g13_sync_array(11, unsafe { u64(&input) }, 1, true)
	assert code == 0
	copy_code, pending := submission.copy_job_dependencies(unsafe { &staged })
	assert copy_code == 0 && pending.count == 1 && pending.item(0).fence == root
	dependency := pending.item(0).fence
	file.close(final_fd)
	assert syncobj.destroy(11, target.handle)
	syncobj.signal_error(b, -5)
	assert !syncobj.queue_dependency_ready(dependency, context)
	time.advance()
	syncobj.signal(a)
	assert syncobj.queue_dependency_ready(dependency, context) && syncobj.get_error(dependency) == -5
	submission.release_sync_array(pending)
	syncobj.dispose_merged_for_checks(root)

	left := create_sync_file_fd(a) or { panic('completed first') }
	right := create_sync_file_fd(b) or { panic('completed second') }
	completed_baseline := memory.outstanding()
	memory.fail_next()
	request = ioctl.SyncMergeData{fd2: i32(right), fence: -123}
	run_merge_request(left, unsafe { &request }, errno.enomem)
	assert memory.outstanding() == completed_baseline
	done := merge_fd(left, right, 'done')
	query_merge_info(done, 'done', 1, 1)
	assert poll_descriptor(done) == file.pollin
	file.close(done)
	assert memory.outstanding() == completed_baseline
	next_done := merge_fd(left, right, 'complete')
	mut done_descriptor := file.fd_from_fdnum(unsafe { nil }, next_done) or { panic('completed fd') }
	stub := sync_file_fence(done_descriptor) or { panic('completed stub') }
	assert syncobj.identity(stub).timestamp_ns == syncobj.identity(a).timestamp_ns
	done_descriptor.unref()
	completed_target := make_object(0)
	sync_request = ioctl.DrmSyncobjHandle{handle: completed_target.handle, fd: i32(next_done), flags: 1}
	assert ioctl_syncobj_fd_to_handle(voidptr(11), &sync_request) == 0
	file.close(next_done)
	assert (syncobj.get_fence(completed_target) or { panic('retained stub') }) == stub
	assert syncobj.is_signaled(stub)
	syncobj.replace_fence(completed_target, unsafe { nil })
	syncobj.dispose_merged_for_checks(stub)
	assert memory.outstanding() == completed_baseline
	file.close(left)
	file.close(right)
	assert file.outstanding() == 0 && memory.outstanding() == 0
	clear()
	memory.reset()
	proc.reset()
	println('DRM sync-file merge: ABI, name, staged fd publication, rollback, nested dedup, G13 input lifetime and completed stub reclamation passed')
}
