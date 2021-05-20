module kevent

import x86.cpu
import x86.cpu.local as cpulocal
import klock
import proc
import sched
import katomic

type PEventListener = &EventListener

struct Event {
pub mut:
	pending   u64
	listeners []EventListener
}

struct EventListener {
pub mut:
	l      klock.Lock
	ready  klock.Lock
	thread &proc.Thread
	index  u64
	which  &u64
}

fn (mut this Event) get_listener() &EventListener {
	for listener in this.listeners {
		if listener.l.test_and_acquire() == true {
			return unsafe { &listener }
		}
	}
	return 0
}

pub fn events_await(events []&Event, which &u64, block bool) bool {
	if events.len > 16 {
		print('events: Too many events!\n')
		return false
	}

	mut thread := &proc.Thread(cpulocal.current().current_thread)

	thread.event_block_dequeue.release()
	thread.event_occurred.release()

	mut listeners := [16]PEventListener{}
	mut listeners_armed := u64(0)

	for i := u64(0); i < events.len; i++ {
		mut event := events[i]

		if katomic.load(event.pending) > 0
		&& thread.event_occurred.test_and_acquire() == true {
			katomic.dec(event.pending)
			unsafe { which[0] = i }
			unsafe { goto unarm_listeners }
		}

		if thread.event_occurred.test_and_acquire() == false {
			unsafe { goto unarm_listeners }
		}
		thread.event_occurred.release()

		mut listener := event.get_listener()
		if listener == 0 {
			return false
		}

		listener.thread = thread
		listener.which  = unsafe { which }
		listener.index  = i
		listener.ready.acquire()

		listeners[i] = listener
		listeners_armed = i + 1
	}

	if block == false && thread.event_occurred.test_and_acquire() == true {
		unsafe { which[0] = -1 }
		unsafe { goto unarm_listeners }
	}

	if thread.event_block_dequeue.test_and_acquire() == true {
		sched.dequeue_and_yield()
	}

unarm_listeners:
	for i := u64(0); i < listeners_armed; i++ {
		listener := &EventListener(listeners[i])
		listener.ready.release()
		listener.l.release()
	}

	return true
}
