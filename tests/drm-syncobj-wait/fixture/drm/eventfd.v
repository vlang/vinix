// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.asahi
import drm.ioctl
import drm.syncobj
import errno
import event
import file
import gpu.agx.submission
import memory
import resource
import usercopy

__global eventfd_block_fence &syncobj.DmaFence = unsafe { nil }

fn signal_eventfd_while_enrolling() { syncobj.signal(eventfd_block_fence) }

fn test_eventfd(flags int) int {
	fd, code := file.syscall_eventfd2(unsafe { nil }, 0, flags | resource.o_nonblock)
	assert code == 0
	return int(fd)
}

fn register_test_eventfd(owner u64, handle u32, fd int, point u64, flags u32) int {
	request := ioctl.DrmSyncobjEventfd{handle: handle, fd: i32(fd), point: point, flags: flags}
	return ioctl_syncobj_eventfd(voidptr(owner), unsafe { &request })
}

fn read_eventfd(fd int) ?u64 {
	mut descriptor := file.fd_from_fdnum(unsafe { nil }, fd) or { return none }
	defer { descriptor.unref() }
	mut value := u64(0)
	mut res := descriptor.handle.resource
	assert res.read(voidptr(descriptor.handle), unsafe { &value }, 0, 8)? == 8
	return value
}

fn write_eventfd(fd int, value u64) ?i64 {
	mut descriptor := file.fd_from_fdnum(unsafe { nil }, fd) or { return none }
	defer { descriptor.unref() }
	mut res := descriptor.handle.resource
	return res.write(voidptr(descriptor.handle), unsafe { &value }, 0, 8)
}

fn check_blocking_eventfd() {
	obj := make_object(0)
	eventfd_block_fence = make_fence()
	syncobj.replace_fence(obj, eventfd_block_fence)
	number, code := file.syscall_eventfd2(unsafe { nil }, 0, 0)
	assert code == 0
	fd := int(number)
	assert register_test_eventfd(11, obj.handle, fd, 0, 0) == 0
	event.complete_while_enrolling(signal_eventfd_while_enrolling)
	assert (read_eventfd(fd) or { panic('blocking eventfd read') }) == 1
	mut descriptor := file.fd_from_fdnum(unsafe { nil }, fd) or { panic('blocking descriptor') }
	assert !descriptor.handle.l.is_held()
	descriptor.unref()
	file.close(fd)
	eventfd_block_fence = unsafe { nil }
	clear()
}

fn expect_empty_eventfd(fd int) {
	if _ := read_eventfd(fd) { assert false, 'unexpected eventfd notification' }
	assert errno.get() == errno.eagain
}

fn verify_eventfd_publish_from_submit(modern bool) {
	memory.reset()
	obj := make_object(0)
	fd := test_eventfd(0)
	leaf := make_fence()
	assert register_test_eventfd(11, obj.handle, fd, if modern { u64(5) } else { u64(0) }, 0) == 0
	mut out := submission.SyncArray{}
	if modern {
		record := asahi.Sync{ handle: obj.handle, sync_type: ioctl.asahi_sync_timeline_syncobj, timeline_value: 5 }
		usercopy.allow(u64(&record), sizeof(record))
		code, _, outputs := submission.stage_packet_syncs(11, u64(&record), 0, 1)
		assert code == 0
		out = outputs
	} else {
		record := ioctl.DrmAsahiSync{handle: obj.handle}
		usercopy.allow(u64(&record), sizeof(record))
		code, outputs := submission.stage_sync_array(11, u64(&record), 1, false)
		assert code == 0
		out = outputs
	}
	assert syncobj.destroy(11, obj.handle)
	expect_empty_eventfd(fd)
	assert submission.install_output_syncs(unsafe { &out }, leaf)
	submission.release_sync_array(out)
	if modern { remember_fence(current(obj)) }
	expect_empty_eventfd(fd)
	syncobj.signal(leaf)
	assert (read_eventfd(fd) or { panic('submission notification') }) == 1
	file.close(fd)
	clear()
	assert memory.outstanding() == 0
}

fn run_syncobj_eventfd_checks() {
	memory.check_before_free(unsafe { nil })
	assert sizeof(ioctl.DrmSyncobjEventfd) == 24 && ioctl.drm_ioctl_syncobj_eventfd == 0xcf
	layout := common_ioctl_layout(ioctl.drm_ioctl_syncobj_eventfd) or { panic('eventfd layout') }
	assert layout.size == 24 && layout.direction == 3 && layout.extensible
	for _ in 0 .. 100 {
		obj := make_object(0)
		leaf := make_fence()
		available := test_eventfd(0)
		complete := test_eventfd(0)
		opaque := export_object(11, obj.handle, 0)
		assert register_test_eventfd(11, 0, -1, 0, 1) == -22
		assert register_test_eventfd(11, 0, -1, 0, 0) == -2
		assert register_test_eventfd(11, obj.handle, -1, 0, 0) == -9
		assert register_test_eventfd(11, obj.handle, opaque, 0, 0) == -22
		mut padded := ioctl.DrmSyncobjEventfd{handle: obj.handle, fd: i32(complete), pad: 1}
		assert ioctl_syncobj_eventfd(voidptr(11), unsafe { &padded }) == -22
		mut context := file.retain_eventfd(complete) or { panic('counter') }
		before := memory.outstanding()
		memory.fail_next()
		assert register_test_eventfd(11, obj.handle, complete, 7, 0) == -12
		assert file.eventfd_refs_for_checks(context) == 2 && memory.outstanding() == before
		assert register_test_eventfd(11, obj.handle, available, 7, ioctl.drm_syncobj_wait_available) == 0
		assert register_test_eventfd(11, obj.handle, complete, 7, 0) == 0
		assert register_test_eventfd(11, obj.handle, complete, 7, 0) == 0
		assert file.eventfd_refs_for_checks(context) == 4
		assert syncobj.destroy(11, obj.handle)
		alias := import_object(12, opaque)
		file.close(opaque)
		expect_empty_eventfd(available)
		expect_empty_eventfd(complete)
		root := remember_fence(syncobj.reserve_chain() or { panic('event chain') })
		assert syncobj.add_chain_point(obj, root, leaf, 7)
		assert (read_eventfd(available) or { panic('available notification') }) == 1
		expect_empty_eventfd(complete)
		syncobj.replace_fence(obj, unsafe { nil })
		assert syncobj.destroy(12, alias)
		file.close(complete)
		reused := test_eventfd(0)
		assert reused == complete
		syncobj.signal_error(leaf, -5)
		assert file.eventfd_refs_for_checks(context) == 1 && context.poll_status(0) & file.pollin != 0
		expect_empty_eventfd(available)
		expect_empty_eventfd(reused)
		context.release()
		file.close(available)
		file.close(reused)

		pending := make_object(0)
		fd := test_eventfd(0)
		mut counter := file.retain_eventfd(fd) or { panic('pending counter') }
		assert register_test_eventfd(11, pending.handle, fd, 0, 0) == 0
		assert file.eventfd_refs_for_checks(counter) == 3
		syncobj.destroy_owner(11)
		assert file.eventfd_refs_for_checks(counter) == 2
		syncobj.replace_fence(pending, leaf)
		expect_empty_eventfd(fd)
		counter.release()
		file.close(fd)
		clear()
		assert file.outstanding() == 0 && memory.outstanding() == 0
	}

	for flags in [0, 1]! {
		obj := make_object(ioctl.drm_syncobj_create_signaled)
		fd := test_eventfd(flags)
		mut counter := file.retain_eventfd(fd) or { panic('overflow counter') }
		assert (write_eventfd(fd, ~u64(0) - 1) or { panic('fill eventfd') }) == 8
		assert counter.poll_status(0) == file.pollin
		for _ in 0 .. 2 { assert register_test_eventfd(11, obj.handle, fd, 0, 0) == 0 }
		assert counter.poll_status(0) == file.pollin | file.pollerr
		if _ := write_eventfd(fd, 0) { assert false }
		assert errno.get() == errno.eagain
		assert (read_eventfd(fd) or { panic('overflow read') }) == if flags == 0 { ~u64(0) } else { u64(1) }
		assert counter.poll_status(0) == if flags == 0 { file.pollout } else { file.pollin }
		if flags == 1 {
			assert (read_eventfd(fd) or { panic('semaphore read') }) == 1
			assert counter.poll_status(0) == file.pollout | file.pollin
		}
		counter.release()
		file.close(fd)
		clear()
	}
	verify_eventfd_publish_from_submit(false)
	verify_eventfd_publish_from_submit(true)
	check_blocking_eventfd()
	println('DRM syncobj eventfd: 100 ownership cycles, availability and completion, blocking enrollment, overflow, FD reuse, close and both staged submission paths passed')
}
