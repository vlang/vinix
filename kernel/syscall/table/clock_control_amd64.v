// SPDX-License-Identifier: GPL-2.0-or-later
module table

import time.sys

pub fn init_clock_control_syscalls() {
	syscall_table[159] = voidptr(sys.syscall_adjtimex)
	syscall_table[164] = voidptr(sys.syscall_settimeofday)
	syscall_table[227] = voidptr(sys.syscall_clock_settime)
	syscall_table[305] = voidptr(sys.syscall_clock_adjtime)
}
