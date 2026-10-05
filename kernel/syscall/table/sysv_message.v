// SPDX-License-Identifier: GPL-2.0-or-later
module table

import proc
import sysvmsg

fn init_sysv_message_syscalls() {
	proc.register_ipc_namespace_release_hook(voidptr(sysvmsg.destroy_namespace))
	$if amd64 {
		syscall_table[68] = voidptr(sysvmsg.syscall_msgget)
		syscall_table[69] = voidptr(sysvmsg.syscall_msgsnd)
		syscall_table[70] = voidptr(sysvmsg.syscall_msgrcv)
		syscall_table[71] = voidptr(sysvmsg.syscall_msgctl)
	} $else {
		syscall_table[186] = voidptr(sysvmsg.syscall_msgget)
		syscall_table[187] = voidptr(sysvmsg.syscall_msgctl)
		syscall_table[188] = voidptr(sysvmsg.syscall_msgrcv)
		syscall_table[189] = voidptr(sysvmsg.syscall_msgsnd)
	}
}
