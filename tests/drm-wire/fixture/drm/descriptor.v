// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl

__global descriptor_point = u64(0)

fn handle_descriptor(cmd u32, data voidptr) int {
	mut request := unsafe { &ioctl.DrmSyncobjHandle(data) }
	descriptor_point = request.point
	if cmd == ioctl.drm_ioctl_syncobj_handle_to_fd { request.fd = 17 }
	else { request.handle = 21 }
	return 0
}

fn check_descriptor_transport() {
	driver := DrmDriver{}
	device := DrmDevice{driver: &driver}
	mut node := DrmNode{dev: &device}
	assert sizeof(ioctl.DrmSyncobjHandle) == 24
	for cmd in [ioctl.drm_ioctl_syncobj_handle_to_fd, ioctl.drm_ioctl_syncobj_fd_to_handle] {
		mut request := ioctl.DrmSyncobjHandle{handle: 4, fd: -1, point: ~u64(0)}
		legacy_word := u64(0xc0106400) | cmd
		current_word := u64(0xc0186400) | cmd
		for word in [legacy_word, current_word] {
			assert (node.ioctl(unsafe { nil }, word, unsafe { &request }) or { panic('descriptor request layout') }) == 0
			assert descriptor_point == if word == legacy_word { u64(0) } else { ~u64(0) }
			assert request.point == ~u64(0)
			assert request.handle == if cmd == 0xc1 { u32(4) } else { u32(21) }
			assert request.fd == if cmd == 0xc1 { i32(17) } else { i32(-1) }
		}
	}
	println('DRM sync-file descriptor wire: 16- and 24-byte export and import, missing point zero extension and bounded results passed')
}
