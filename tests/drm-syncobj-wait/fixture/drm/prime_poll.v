// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.gem
import drm.ioctl
import drm.syncobj
import event
import file
import memory
import proc

__global poll_prime_writer &syncobj.DmaFence = unsafe { nil }
__global poll_prime_reader &syncobj.DmaFence = unsafe { nil }
__global poll_prime_fd = -1

fn complete_prime_poll_step(step int) {
	assert !prime_exported.lock.is_held()
	if step == 1 { syncobj.signal_error(poll_prime_writer, -5) }
	else {
		assert step == 2
		syncobj.assert_fence_events_for_checks(poll_prime_reader, 1)
		syncobj.signal(poll_prime_reader)
	}
}

fn complete_poll_before_enrollment() { syncobj.signal(poll_prime_writer) }

fn close_while_polling_prime() {
	file.close(poll_prime_fd)
	syncobj.signal(poll_prime_writer)
}

fn check_prime_poll(features u32) {
	memory.reset()
	proc.reset()
	mut object := gem.create(7)
	object.file_scoped = features == 0
	prime_exported = unsafe { object }
	driver := DrmDriver{features: features, gem_export: prime_export}
	device := DrmDevice{driver: unsafe { &driver }}
	mut request := ioctl.DrmPrimeHandle{handle: 7, fd: -1}
	assert ioctl_prime_handle_to_fd(&device, voidptr(11), &request) == 0
	first := request.fd
	request.flags = ioctl.drm_rdwr
	assert ioctl_prime_handle_to_fd(&device, voidptr(12), &request) == 0
	second := request.fd
	mut exporter := file.fd_from_fdnum(unsafe { nil }, first) or { panic('PRIME exporter') }
	both := file.pollin | file.pollout
	assert file.poll_for_checks(first, both, false, false) == both
	assert file.poll_for_checks(second, both, false, true) == both

	mut in_edge := file.watch_for_checks(file.epollet | u32(file.pollin))
	mut combined_edge := file.watch_for_checks(file.epollet | u32(both))
	assert in_edge.sample(first) == u32(file.pollin)
	assert combined_edge.sample(first) == u32(both)
	reader := make_fence()
	prime_add_export_leaf(mut exporter, reader, 1)
	assert file.poll_for_checks(first, file.pollpri | file.pollwrnorm, false, false) == 0
	assert file.poll_for_checks(first, file.pollin, false, false) == file.pollin
	syncobj.assert_fence_events_for_checks(reader, 0)
	assert file.poll_for_checks(first, both, false, false) == file.pollin
	syncobj.assert_fence_events_for_checks(reader, 1)
	syncobj.signal(reader)
	assert in_edge.sample(first) == 0
	assert combined_edge.sample(first) == u32(both)
	assert combined_edge.sample(first) == 0

	poll_prime_reader = make_fence()
	poll_prime_writer = make_fence()
	prime_add_export_leaf(mut exporter, poll_prime_reader, 1)
	prime_add_export_leaf(mut exporter, poll_prime_writer, 2)
	event.script_poll_wait(complete_prime_poll_step)
	assert file.poll_for_checks(second, file.pollout, true, false) == file.pollout
	assert event.poll_wait_count == 2
	assert file.poll_for_checks(first, both, false, true) == both

	poll_prime_writer = make_fence()
	prime_add_export_leaf(mut exporter, poll_prime_writer, 2)
	syncobj.before_fence_lock_for_checks(poll_prime_writer, complete_poll_before_enrollment)
	assert file.poll_for_checks(second, file.pollin, false, false) == file.pollin
	syncobj.assert_fence_events_for_checks(poll_prime_writer, 0)

	last := make_fence()
	prime_add_export_leaf(mut exporter, last, 2)
	dup := file.duplicate(first)
	assert file.poll_for_checks(first, both, false, false) == 0
	assert file.poll_for_checks(dup, both, false, false) == 0
	assert file.poll_for_checks(second, file.pollin, false, false) == 0
	syncobj.assert_fence_events_for_checks(last, 3)
	exporter.unref()
	file.close(first)
	syncobj.assert_fence_events_for_checks(last, 3)
	file.close(dup)
	syncobj.assert_fence_events_for_checks(last, 1)
	syncobj.signal(last)
	assert file.poll_for_checks(second, file.pollin, false, false) == file.pollin

	mut next := file.fd_from_fdnum(unsafe { nil }, second) or { panic('remaining PRIME descriptor') }
	poll_prime_writer = make_fence()
	prime_add_export_leaf(mut next, poll_prime_writer, 2)
	next.unref()
	gem.unref(object)
	poll_prime_fd = second
	syncobj.before_fence_lock_for_checks(poll_prime_writer, close_while_polling_prime)
	assert file.poll_for_checks(second, file.pollin, false, false) == file.pollin
	assert file.outstanding() == 0 && gem.live() == 0 && memory.outstanding() == 0

	prime_exported = unsafe { nil }; poll_prime_fd = -1
	poll_prime_writer = unsafe { nil }; poll_prime_reader = unsafe { nil }
	event.script_poll_wait(unsafe { nil })
	clear()
	memory.reset()
	proc.reset()
	println('DRM PRIME poll: direction masks, ppoll wake and rearm, independent epoll edges, dup ownership and final close passed')
}
