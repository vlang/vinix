// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module pipe

import errno
import file
import lib
import proc
import usercopy
import ioctl
import resource

pub fn syscall_pipe_checked(gpr_state voidptr, pipefds &i32, flags int) (u64, u64) {
	// Linux's int flags occupy only the low register word. Validate before
	// pointer checks or descriptor allocation so invalid flags always win.
	open_flags := int(u32(flags))
	if open_flags & ~(resource.o_nonblock | resource.o_cloexec | resource.o_direct | resource.o_excl) != 0 {
		return errno.err, errno.einval
	}
	// O_EXCL is Linux's O_NOTIFICATION_PIPE; no watch queues are compiled in.
	if open_flags & resource.o_excl != 0 { return errno.err, errno.enopkg }
	// The ring is a byte stream, so it cannot promise O_DIRECT packet semantics.
	if open_flags & resource.o_direct != 0 { return errno.err, errno.eopnotsupp }
	if pipefds == unsafe { nil } {
		return errno.err, errno.efault
	}

	// syscall_pipe fills both words before success, and neither it nor the
	// checked user copy retains this caller's scratch beyond the call.
	local := unsafe { &i32(C.vinix_stack_alloc(2 * sizeof(i32))) }
	ret, code := syscall_pipe(gpr_state, local, open_flags)
	if code != 0 {
		return ret, code
	}

	if !usercopy.copy_to_user(u64(pipefds), voidptr(local), 2 * sizeof(i32)) {
		mut process := proc.current_thread().process
		file.fdnum_close(process, unsafe { int(local[0]) }, true) or {}
		file.fdnum_close(process, unsafe { int(local[1]) }, true) or {}
		return errno.err, errno.efault
	}
	return 0, 0
}

const fionread = ioctl.fionread

// Hand FIONREAD's count back as the int Linux gives.
fn copy_fionread(argp voidptr, queued u64) ?int {
	value := i32(if queued > u64(0x7fffffff) { u64(0x7fffffff) } else { queued })
	if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(i32)) {
		errno.set(errno.efault)
		return none
	}
	return 0
}
