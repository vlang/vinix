// SPDX-License-Identifier: GPL-2.0-or-later
module table

import fs

// Install after the native and Linux tables so all ordinary read/write entry
// points cross the user/kernel boundary through fs.userio.
pub fn init_userio_syscalls() {
	syscall_table[3] = voidptr(fs.syscall_read_checked)
	syscall_table[4] = voidptr(fs.syscall_write_checked)
	linux_syscall_table[0] = voidptr(fs.syscall_read_checked)
	linux_syscall_table[1] = voidptr(fs.syscall_write_checked)
}
