// SPDX-License-Identifier: GPL-2.0-or-later
module table

import pipe

fn syscall_linux_pipe_checked(gpr_state voidptr, pipefds &i32) (u64, u64) {
	return pipe.syscall_pipe_checked(gpr_state, pipefds, 0)
}

pub fn init_pipe_usercopy_syscalls() {
	syscall_table[21] = voidptr(pipe.syscall_pipe_checked)
	linux_syscall_table[22] = voidptr(syscall_linux_pipe_checked)
}
