module event

import proc
import sched
import eventstruct
import x86.cpu.local as cpulocal

fn check_for_pending(mut events []&eventstruct.Event) ?u64 {
	for i := u64(0); i < events.len; i++ {
		events[i].@lock.acquire()

		if events[i].pending > 0 {
			events[i].pending--
			events[i].@lock.release()
			return i
		}

		events[i].@lock.release()
	}

	return none
}

fn attach_listeners(mut events []&eventstruct.Event, thread voidptr) {
	for mut e in events {
		e.@lock.acquire()

		if e.listeners_i == eventstruct.max_listeners {
			panic('event listeners exhausted')
		}

		e.listeners[e.listeners_i] = voidptr(thread)

		e.listeners_i++

		e.@lock.release()
	}
}

fn detach_listeners(mut events []&eventstruct.Event, thread voidptr) {
	for mut e in events {
		e.@lock.acquire()

		for i := u64(0); i < e.listeners_i; i++ {
			if e.listeners[i] == thread {
				e.listeners_i--
				for j := i; j < e.listeners_i; j++ {
					e.listeners[j] = e.listeners[j + 1]
				}

				break
			}
		}

		e.@lock.release()
	}
}

pub fn await(mut events []&eventstruct.Event, block bool) ?u64 {
	mut thread := proc.current_thread()
	mut sig := false

	for {
		if i := check_for_pending(mut events) {
			return i
		}

		if sig == true {
			return none
		}

		if block == false {
			return none
		}

		thread.event_lock.acquire()

		attach_listeners(mut events, voidptr(thread))

		asm volatile amd64 { cli }

		sched.dequeue_thread(cpulocal.current().current_thread)

		thread.event_lock.release()

		sched.yield(true)

		if thread.enqueued_by_signal {
			sig = true
		}

		detach_listeners(mut events, voidptr(thread))
	}

	return none
}

pub fn trigger(mut event &eventstruct.Event, drop bool) u64 {
	event.@lock.acquire()
	defer {
		event.@lock.release()
	}

	if event.listeners_i == 0 && drop {
		return 0
	}

	for i := u64(0); i < event.listeners_i; i++ {
		mut thread := &proc.Thread(event.listeners[i])

		thread.event_lock.acquire()

		sched.enqueue_thread(thread, false)

		thread.event_lock.release()
	}

	event.pending++

	return event.listeners_i
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
