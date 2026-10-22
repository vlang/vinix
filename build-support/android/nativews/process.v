// SPDX-License-Identifier: GPL-2.0-or-later
// Android thread priorities use the kernel's nice values and permission checks.
@[translated]
module atlframework

#include <sys/resource.h>

fn C.getpriority(i32, u32) i32
fn C.setpriority(i32, u32, i32) i32

fn ws_priority_error(e voidptr, code i32) {
	match code {
		3 { throw(e, c'java/lang/IllegalArgumentException', c'Given thread does not exist') }
		22 { throw(e, c'java/lang/IllegalArgumentException', c'Invalid thread priority argument') }
		1, 13 { throw(e, c'java/lang/SecurityException', c'No permission to set thread priority') }
		else { throw(e, c'java/lang/RuntimeException', c'Cannot access thread priority') }
	}
}

fn ws_thread_priority(e voidptr, tid i32) i32 {
	unsafe {
		*C.__errno_location() = 0
		priority := C.getpriority(C.PRIO_PROCESS, u32(tid))
		code := *C.__errno_location()
		// A nice value of -1 is successful when errno remains zero.
		if code != 0 { ws_priority_error(e, code) }
		return priority
	}
}

fn ws_set_thread_priority(e voidptr, tid i32, priority i32) {
	if C.setpriority(C.PRIO_PROCESS, u32(tid), priority) != 0 {
		ws_priority_error(e, unsafe { *C.__errno_location() })
	}
}
