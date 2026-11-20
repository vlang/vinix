// SPDX-License-Identifier: GPL-2.0-or-later
module table

import mqueue
import proc
import sysvmsg
import sysvsem

fn destroy_ipc_namespace(ns u64) {
	sysvmsg.destroy_namespace(ns)
	sysvsem.destroy_namespace(ns)
	mqueue.destroy_namespace(ns)
}

fn init_sysv_message_syscalls() {
	proc.register_ipc_namespace_release_hook(voidptr(destroy_ipc_namespace))
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
	init_posix_mqueue_syscalls()
}

fn init_posix_mqueue_syscalls() {
	$if amd64 {
		syscall_table[240] = voidptr(mqueue.syscall_mq_open)
		syscall_table[241] = voidptr(mqueue.syscall_mq_unlink)
		syscall_table[242] = voidptr(mqueue.syscall_mq_timedsend)
		syscall_table[243] = voidptr(mqueue.syscall_mq_timedreceive)
		syscall_table[244] = voidptr(mqueue.syscall_mq_notify)
		syscall_table[245] = voidptr(mqueue.syscall_mq_getsetattr)
	} $else {
		syscall_table[180] = voidptr(mqueue.syscall_mq_open)
		syscall_table[181] = voidptr(mqueue.syscall_mq_unlink)
		syscall_table[182] = voidptr(mqueue.syscall_mq_timedsend)
		syscall_table[183] = voidptr(mqueue.syscall_mq_timedreceive)
		syscall_table[184] = voidptr(mqueue.syscall_mq_notify)
		syscall_table[185] = voidptr(mqueue.syscall_mq_getsetattr)
	}
}
