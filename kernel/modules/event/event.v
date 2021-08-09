module event

import proc
import sched
import eventstruct
import x86.cpu
import x86.cpu.local as cpulocal

fn check_for_pending(mut events []&eventstruct.Event) ?u64 {
	for i := u64(0); i < events.len; i++ {
		if events[i].pending > 0 {
			events[i].pending--
			return i
		}
	}

	return none
}

fn attach_listeners(mut events []&eventstruct.Event, thread voidptr) {
	for mut e in events {
		if e.listeners_i == eventstruct.max_listeners {
			panic('event listeners exhausted')
		}

		e.listeners[e.listeners_i] = voidptr(thread)

		e.listeners_i++
	}
}

fn lock_events(mut events []&eventstruct.Event) {
	for mut e in events {
		e.@lock.acquire()
	}
}

fn unlock_events(mut events []&eventstruct.Event) {
	for mut e in events {
		e.@lock.release()
	}
}

pub fn await(mut events []&eventstruct.Event, block bool) ?u64 {
	mut thread := proc.current_thread()
	mut sig := false

	for {
		asm volatile amd64 { cli }

		lock_events(mut events)

		if i := check_for_pending(mut events) {
			unlock_events(mut events)
			return i
		}

		if block == false || sig == true {
			return none
		}

		attach_listeners(mut events, voidptr(thread))

		sched.dequeue_thread(cpulocal.current().current_thread)

		unlock_events(mut events)

		sched.yield(true)

		if thread.enqueued_by_signal {
			sig = true
		}
	}

	return none
}

pub fn trigger(mut event &eventstruct.Event, drop bool) u64 {
	ints := cpu.interrupt_state()

	asm volatile amd64 { cli }
	defer {
		if ints == true {
			asm volatile amd64 { sti }
		}
	}

	event.@lock.acquire()
	defer {
		event.@lock.release()
	}

	if event.listeners_i == 0 && drop == true {
		return 0
	}

	for i := u64(0); i < event.listeners_i; i++ {
		mut thread := &proc.Thread(event.listeners[i])

		sched.enqueue_thread(thread, false)
	}

	ret := event.listeners_i

	event.pending++
	event.listeners_i = 0

	return ret
}

pub fn pthread_exit(ret voidptr) {
	asm volatile amd64 { cli }

	mut current_thread := &proc.Thread(cpulocal.current().current_thread)

	sched.dequeue_thread(current_thread)

	cpulocal.current().current_thread = voidptr(0)

	current_thread.exit_value = ret
	trigger(mut current_thread.exited, false)

	sched.yield(false)
}

pub fn pthread_wait(thread &proc.Thread) voidptr {
	mut events := [&thread.exited]
	await(mut events, true) or {}
	exit_value := thread.exit_value
	unsafe { free(thread) }
	return exit_value
}
