@[has_globals]
module drm

import drm.ioctl
import memory
import usercopy

__global deadline_seen = u64(0)

fn handle_wait(cmd u32, data voidptr) int {
	handler_calls++
	if cmd == ioctl.drm_ioctl_syncobj_wait {
		mut wait := unsafe { &ioctl.DrmSyncobjWait(data) }
		deadline_seen = wait.deadline_nsec
		if handler_status == 0 { wait.first_signaled = 1 }
	} else {
		mut wait := unsafe { &ioctl.DrmSyncobjTimelineWait(data) }
		deadline_seen = wait.deadline_nsec
		if handler_status == 0 { wait.first_signaled = 1 }
	}
	return handler_status
}

fn wait_word(cmd u32, size u32, direction u32) u64 {
	return u64(cmd) | (u64(`d`) << 8) | (u64(size) << 16) | (u64(direction) << 30)
}

fn check_wait_transport() {
	driver := DrmDriver{}
	device := DrmDevice{ driver: &driver }
	mut node := DrmNode{ dev: &device }
	for cmd in [ioctl.drm_ioctl_syncobj_wait, ioctl.drm_ioctl_syncobj_timeline_wait] {
		old_size := if cmd == ioctl.drm_ioctl_syncobj_wait { u32(32) } else { u32(40) }
		deadline_index := old_size / 8
		rw := ioctl_read | ioctl_write
		// Word-aligned storage includes both the current deadline field and
		// a sentinel past the 160-byte request used to force heap buffering.
		mut words := [21]u64{}
		data := unsafe { &words[0] }
		words[deadline_index] = 0x1234
		handler_status = 0
		assert (node.ioctl(unsafe { nil }, wait_word(cmd, old_size, rw), data) or { panic('historical WAIT') }) == 0
		assert deadline_seen == 0
		assert u32(words[deadline_index - 1]) == 1 && words[deadline_index] == 0x1234
		assert (node.ioctl(unsafe { nil }, wait_word(cmd, old_size + 8, rw), data) or { panic('current WAIT') }) == 0
		assert deadline_seen == 0x1234
		words[deadline_index - 1] = 77
		assert (node.ioctl(unsafe { nil }, wait_word(cmd, old_size + 8, ioctl_write), data) or { panic('write-only WAIT') }) == 0
		assert deadline_seen == 0x1234 && words[deadline_index - 1] == 77

		words[19] = 0xabc
		words[20] = 0xdef
		handler_status = -22
		expect_error(mut node, wait_word(cmd, 160, rw), data, 22)
		assert deadline_seen == 0x1234 && words[deadline_index - 1] == 77
		assert words[19] == 0xabc && words[20] == 0xdef
		expect_error(mut node, wait_word(cmd, 160, ioctl_read), data, 22)
		assert deadline_seen == 0 && words[deadline_index] == 0 && words[19] == 0 && words[20] == 0xdef

		memory.fail_next(true)
		calls_before_no_copy := handler_calls
		expect_error(mut node, wait_word(cmd, 160, 0), unsafe { nil }, 22)
		assert deadline_seen == 0 && handler_calls == calls_before_no_copy + 1
		expect_error(mut node, wait_word(cmd, 160, rw), data, 12)
		memory.fail_next(false)
		calls := handler_calls
		assert calls == calls_before_no_copy + 1
		usercopy.fail_at(unsafe { u64(&words[19]) })
		expect_error(mut node, wait_word(cmd, 160, rw), data, 14)
		assert handler_calls == calls
		expect_error(mut node, wait_word(cmd, 160, ioctl_read), data, 14)
		assert handler_calls == calls + 1
		usercopy.fail_at(0)
		expect_error(mut node, wait_word(cmd, old_size, rw), unsafe { nil }, 14)
	}
	println('DRM syncobj WAIT wire: historical and current sizes, direction-specific copies, tails, faults and buffer lifetime passed')
}
