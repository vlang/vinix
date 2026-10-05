// SPDX-License-Identifier: GPL-2.0-or-later
module table

import time.sys

pub fn init_clock_control_syscalls() {
	syscall_table[112] = voidptr(sys.syscall_clock_settime)
	syscall_table[170] = voidptr(sys.syscall_settimeofday)
	syscall_table[171] = voidptr(sys.syscall_adjtimex)
	syscall_table[266] = voidptr(sys.syscall_clock_adjtime)
}
