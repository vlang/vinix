module event

import proc
import sched
import eventstruct
import x86.cpu
import x86.cpu.local as cpulocal
import katomic

__global (
	waiting_event_count = u64(0)
)

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
	for i := u64(0); i < events.len; i++ {
		mut event := events[i]

		if event.listeners_i == eventstruct.max_listeners {
			panic('event listeners exhausted')
		}

		mut listener := &event.listeners[event.listeners_i]

		listener.thread = voidptr(thread)
		listener.which = i

		event.listeners_i++
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

	asm volatile amd64 { cli }

	lock_events(mut events)

	if i := check_for_pending(mut events) {
		unlock_events(mut events)
		return i
	}

	if block == false {
		unlock_events(mut events)
		return none
	}

	katomic.inc(waiting_event_count)

	attach_listeners(mut events, voidptr(thread))

	sched.dequeue_thread(thread)

	unlock_events(mut events)

	sched.yield(true)

	katomic.dec(waiting_event_count)

	if thread.enqueued_by_signal {
		return none
	}

	return thread.which_event
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

	if event.listeners_i == 0 {
		if drop == false {
			event.pending++
		}
		return 0
	}

	for i := u64(0); i < event.listeners_i; i++ {
		mut thread := &proc.Thread(event.listeners[i].thread)

		thread.which_event = event.listeners[i].which

		sched.enqueue_thread(thread, false)
	}

	ret := event.listeners_i

	event.listeners_i = 0

	return ret
}

pub fn pthread_exit(ret voidptr) {
	asm volatile amd64 { cli }

	mut cpu_local := cpulocal.current()

	mut current_thread := proc.current_thread()

	sched.dequeue_thread(current_thread)

	cpu.set_gs_base(voidptr(&cpu_local.cpu_number))
	cpu.set_kernel_gs_base(voidptr(&cpu_local.cpu_number))

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
