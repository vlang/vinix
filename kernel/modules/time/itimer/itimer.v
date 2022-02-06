module itimer

import proc
import errno

pub const itimer_real = 0
pub const itimer_virtual = 1
pub const itimer_prof = 2

struct TimeVal {
	tv_sec u64
	tv_usec u64
}

struct ITimerVal {
	it_interval TimeVal
	it_value TimeVal
}

fn syscall_getitimer(_ voidptr, which int, mut curr_value ITimerVal) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: getitimer(%d, 0x%llx)\n', which, voidptr(curr_value))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	if which > 2 {
		return -1, errno.einval
	}

	mut process := proc.current_thread().process

	mut itimers := &ITimerVal(voidptr(&process.itimers[0]))

	unsafe { *curr_value = itimers[which] }

	return 0, 0
}

fn syscall_setitimer(_ voidptr, which int, mut new_value ITimerVal, mut old_value ITimerVal) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: setitimer(%d, 0x%llx, 0x%llx)\n', which, voidptr(new_value), voidptr(old_value))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	if which > 2 {
		return -1, errno.einval
	}

	mut process := proc.current_thread().process

	mut itimers := &ITimerVal(voidptr(&process.itimers[0]))

	if voidptr(old_value) != voidptr(0) {
		unsafe { *old_value = itimers[which] }
	}

	unsafe { itimers[which] = *new_value }

	return 0, 0
}
