// SPDX-License-Identifier: GPL-2.0-or-later
module table
import aarch64.cpu.local as cpulocal

fn user_stack_pointer(context voidptr) u64 {
	return unsafe { &cpulocal.GPRState(context) }.sp
}
