@[has_globals]
module event

import proc
import sched
import event.eventstruct
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

fn attach_listeners(mut events []&eventstruct.Event, mut t proc.Thread) {
	t.attached_events_i = 0

	for i := u64(0); i < events.len; i++ {
		mut e := events[i]

		if e.listeners_i == eventstruct.max_listeners {
			panic('event listeners exhausted')
		}

		mut listener := &e.listeners[e.listeners_i]

		listener.thrd = voidptr(t)
		listener.which = i

		e.listeners_i++

		if t.attached_events_i == proc.max_events {
			panic('listening on too many events')
		}

		t.attached_events[t.attached_events_i] = e
		t.attached_events_i++
	}
}

fn detach_listeners(mut t proc.Thread) {
	for i := u64(0); i < t.attached_events_i; i++ {
		mut e := t.attached_events[i]

		for j := u64(0); j < e.listeners_i; j++ {
			mut listener := &e.listeners[j]

			if listener.thrd != voidptr(t) {
				continue
			}

			e.listeners[j] = e.listeners[e.listeners_i - 1]
			e.listeners_i--

			break
		}
	}

	t.attached_events_i = 0
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
	mut t := proc.current_thread()

	asm volatile amd64 {
		cli
	}
	defer {
		asm volatile amd64 {
			sti
		}
	}

	lock_events(mut events)

	if i := check_for_pending(mut events) {
		unlock_events(mut events)
		return i
	}

	if block == false {
		unlock_events(mut events)
		return none
	}

	katomic.inc(mut &waiting_event_count)

	attach_listeners(mut events, mut t)
	defer {
		asm volatile amd64 {
			cli
		}
		lock_events(mut events)
		detach_listeners(mut t)
		unlock_events(mut events)
		asm volatile amd64 {
			sti
		}
	}

	sched.dequeue_thread(t)

	unlock_events(mut events)

	sched.yield(true)

	katomic.dec(mut &waiting_event_count)

	if t.enqueued_by_signal {
		return none
	}

	return t.which_event
}

pub fn trigger(mut e eventstruct.Event, drop bool) u64 {
	ints := cpu.interrupt_state()

	asm volatile amd64 {
		cli
	}
	defer {
		if ints == true {
			asm volatile amd64 {
				sti
			}
		}
	}

	e.@lock.acquire()
	defer {
		e.@lock.release()
	}

	if e.listeners_i == 0 {
		if drop == false {
			e.pending++
		}
		return 0
	}

	for i := u64(0); i < e.listeners_i; i++ {
		mut t := unsafe { &proc.Thread(e.listeners[i].thrd) }

		t.which_event = e.listeners[i].which

		sched.enqueue_thread(t, false)
	}

	ret := e.listeners_i

	e.listeners_i = 0

	return ret
}

pub fn pthread_exit(ret voidptr) {
	asm volatile amd64 {
		cli
	}

	mut cpu_local := cpulocal.current()

	mut current_thread := proc.current_thread()

	sched.dequeue_thread(current_thread)

	cpu.set_gs_base(u64(&cpu_local.cpu_number))
	cpu.set_kernel_gs_base(u64(current_thread))

	current_thread.exit_value = ret
	trigger(mut current_thread.exited, false)

	sched.yield(false)
}

pub fn pthread_wait(t &proc.Thread) voidptr {
	mut events := [&t.exited]
	await(mut events, true) or {}
	exit_value := t.exit_value
	unsafe {
		free(t)
		events.free()
	}
	return exit_value
}
