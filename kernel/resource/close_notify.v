// SPDX-License-Identifier: GPL-2.0-or-later
module resource

// A resource told every time a process closes one of its descriptors, as
// Linux's file_operations.flush is: by close(2), dup2(2) over it, close-on-exec
// and exit. A POSIX message queue drops the notification the closing process
// registered. `pid` is the closing process's global pid.
pub interface CloseNotifyResource {
mut:
	descriptor_closed(pid int)
}

struct CloseNotifyScratch {
mut:
	backend CloseNotifyResource
}

pub fn descriptor_closed(mut res Resource, pid int) {
	if mut res is CloseNotifyResource {
		mut scratch := unsafe { &CloseNotifyScratch(C.__builtin_alloca(sizeof(CloseNotifyScratch))) }
		unsafe { scratch.backend = CloseNotifyResource(res) }
		scratch.backend.descriptor_closed(pid)
	}
}
