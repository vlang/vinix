module itimer

import proc
import errno
import time
import event
import userland

pub const itimer_real = 0
pub const itimer_virtual = 1
pub const itimer_prof = 2

pub struct TimeVal {
pub mut:
	tv_sec i64
	tv_usec i64
}

pub struct ITimerVal {
pub mut:
	it_interval TimeVal
	it_value TimeVal
}

pub struct ITimer {
pub mut:
	handler_started bool
	timer time.Timer
	reload_value time.TimeSpec
}

[noreturn]
fn itimer_handler(mut itimer ITimer, mut process proc.Process) {
	itimer.handler_started = true

	C.printf(c'itimer handler started\n')

	for {
		mut events := [&itimer.timer.event]
		event.await(mut events, true) or {}

		C.printf(c'itimer triggered\n')

		userland.sendsig(process.threads[0], userland.sigabrt)
	}

	for {}
}

pub fn syscall_getitimer(_ voidptr, which int, mut curr_value ITimerVal) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: getitimer(%d, 0x%llx)\n', which, voidptr(curr_value))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	if which > 2 {
		return -1, errno.einval
	}

	mut process := proc.current_thread().process

	mut itimers := &ITimer(voidptr(&process.itimers[0]))

	unsafe {
		itimers[which].timer.disarm()

		if itimers[which].handler_started == false {
			go itimer_handler(mut &itimers[which], mut process)
		}

		curr_value.it_interval.tv_sec = itimers[which].reload_value.tv_sec
		curr_value.it_interval.tv_usec = itimers[which].reload_value.tv_nsec / 1000

		curr_value.it_value.tv_sec = itimers[which].timer.when.tv_sec
		curr_value.it_value.tv_usec = itimers[which].timer.when.tv_nsec / 1000

		itimers[which].timer.arm()
	}

	return 0, 0
}

pub fn syscall_setitimer(_ voidptr, which int, mut new_value ITimerVal, mut old_value ITimerVal) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: setitimer(%d, 0x%llx, 0x%llx)\n', which, voidptr(new_value), voidptr(old_value))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	if which > 2 {
		return -1, errno.einval
	}

	mut process := proc.current_thread().process

	mut itimers := &ITimer(voidptr(&process.itimers[0]))

	unsafe {
		itimers[which].timer.disarm()

		if itimers[which].handler_started == false {
			go itimer_handler(mut &itimers[which], mut process)
		}

		if voidptr(old_value) != voidptr(0) {
			old_value.it_interval.tv_sec = itimers[which].reload_value.tv_sec
			old_value.it_interval.tv_usec = itimers[which].reload_value.tv_nsec / 1000

			old_value.it_value.tv_sec = itimers[which].timer.when.tv_sec
			old_value.it_value.tv_usec = itimers[which].timer.when.tv_nsec / 1000
		}

		if voidptr(new_value) != voidptr(0) {
			itimers[which].reload_value.tv_sec = new_value.it_interval.tv_sec
			itimers[which].reload_value.tv_nsec = new_value.it_interval.tv_usec * 1000

			itimers[which].timer.when.tv_sec = new_value.it_value.tv_sec
			itimers[which].timer.when.tv_nsec = new_value.it_value.tv_usec * 1000
		}

		itimers[which].timer.arm()
	}

	return 0, 0
}
