// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module pipe

import errno
import file
import proc
import usercopy
import ioctl

pub fn syscall_pipe_checked(gpr_state voidptr, pipefds &i32, flags int) (u64, u64) {
	if pipefds == unsafe { nil } {
		return errno.err, errno.efault
	}

	mut local := [2]i32{}
	ret, code := syscall_pipe(gpr_state, &local[0], flags)
	if code != 0 {
		return ret, code
	}

	if !usercopy.copy_to_user(u64(pipefds), voidptr(&local[0]), sizeof(local)) {
		mut process := proc.current_thread().process
		file.fdnum_close(process, int(local[0]), true) or {}
		file.fdnum_close(process, int(local[1]), true) or {}
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
