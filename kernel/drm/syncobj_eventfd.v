// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import errno
import file

fn finish_syncobj_eventfd(context voidptr, signal bool) {
	mut counter := unsafe { &file.EventFD(context) }
	if signal { counter.notify() }
	counter.release()
}

fn ioctl_syncobj_eventfd(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } { return -14 }
	request := unsafe { &ioctl.DrmSyncobjEventfd(data) }
	if request.flags & ~ioctl.drm_syncobj_wait_available != 0 || request.pad != 0 { return -22 }
	object := syncobj.lookup_referenced(u64(handle), request.handle) or { return -2 }
	defer { syncobj.release_syncobj(object) }
	mut counter := file.retain_eventfd(request.fd) or { return -int(errno.get()) }
	if !syncobj.register_eventfd(object, request.point, request.flags != 0, voidptr(counter), finish_syncobj_eventfd) {
		counter.release()
		return -12
	}
	return 0
}
