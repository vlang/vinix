module itimer

import proc
import errno
import time
import event
import userland
import event.eventstruct
import sched

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
	handler_stop_event eventstruct.Event
	handler_stopped_event eventstruct.Event
	timer time.Timer
	reload_value time.TimeSpec
}

fn itimer_handler(mut itimer ITimer, mut process proc.Process) {
	itimer.handler_started = true

	C.printf(c'itimer handler started\n')

	for {
		mut events := [&itimer.timer.event, &itimer.handler_stop_event]
		which := event.await(mut events, true) or {
			-1
		}

		if which == 1 {
			event.trigger(mut itimer.handler_stopped_event, false)
			break
		}

		itimer.timer.disarm()

		userland.sendsig(process.threads[0], userland.sigalrm)

		C.printf(c'itimer triggered\n')

		if itimer.reload_value.tv_sec != 0
		|| itimer.reload_value.tv_nsec != 0 {
			itimer.timer.when = itimer.reload_value
			itimer.timer.arm()
		} else {
			break
		}
	}

	itimer.handler_started = false

	sched.dequeue_and_die()
}

pub fn syscall_getitimer(_ voidptr, which int, mut curr_value ITimerVal) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: getitimer(%d, 0x%llx)\n', process.name.str, which, voidptr(curr_value))
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	if which > 2 {
		return errno.err, errno.einval
	}

	mut itimers := &ITimer(voidptr(&process.itimers[0]))

	unsafe {
		curr_value.it_interval.tv_sec = itimers[which].reload_value.tv_sec
		curr_value.it_interval.tv_usec = itimers[which].reload_value.tv_nsec / 1000

		curr_value.it_value.tv_sec = itimers[which].timer.when.tv_sec
		curr_value.it_value.tv_usec = itimers[which].timer.when.tv_nsec / 1000
	}

	return 0, 0
}

pub fn syscall_setitimer(_ voidptr, which int, mut new_value ITimerVal, mut old_value ITimerVal) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: setitimer(%d, 0x%llx, 0x%llx)\n', process.name.str, which, voidptr(new_value), voidptr(old_value))
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	if which > 2 {
		return errno.err, errno.einval
	}

	mut itimers := &ITimer(voidptr(&process.itimers[0]))

	unsafe {
		if itimers[which].handler_started == true {
			event.trigger(mut itimers[which].handler_stop_event, false)
			mut events := [&itimers[which].handler_stopped_event]
			event.await(mut events, true) or {}
		}

		itimers[which].timer.disarm()

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

		if itimers[which].timer.when.tv_sec != 0
		|| itimers[which].timer.when.tv_nsec != 0 {
			itimers[which].timer.arm()
			go itimer_handler(mut &itimers[which], mut process)
		}
	}

	return 0, 0
}
