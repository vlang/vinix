[manualfree] module event

import proc
import sched
import katomic
import eventstruct

pub fn await(events []&eventstruct.Event, which &u64, block bool) bool {
	if events.len > 16 {
		panic('kevent: Too many events!')
	}

	mut thread := proc.current_thread()

	thread.event_block_dequeue.release()
	thread.event_occurred.release()

	mut listeners := [16]&eventstruct.EventListener{}
	mut listeners_armed := u64(0)

	for i := u64(0); i < events.len; i++ {
		mut event := events[i]

		if katomic.load(event.pending) > 0
		&& thread.event_occurred.test_and_acquire() == true {
			katomic.dec(event.pending)
			unsafe {
				which[0] = i
				goto unarm_listeners
			}
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
		unsafe {
			which[0] = -1
			goto unarm_listeners
		}
	}

	if thread.event_block_dequeue.test_and_acquire() == true {
		sched.dequeue_and_yield()
	}

unarm_listeners:
	for i := u64(0); i < listeners_armed; i++ {
		mut listener := listeners[i]
		listener.ready.release()
		listener.l.release()
	}

	return true
}

pub fn trigger(event &eventstruct.Event) {
	mut this := unsafe { event }

	if katomic.load(this.pending) > 0 {
		katomic.inc(this.pending)
		return
	}

	mut pending := true

	for i := u64(0); i < this.listeners.len; i++ {
		mut listener := &this.listeners[i]

		if listener.l.test_and_acquire() == true {
			listener.l.release()
			continue
		}

		if listener.ready.test_and_acquire() == true {
			listener.ready.release()
			continue
		}

		mut thread := &proc.Thread(listener.thread)

		if thread.event_occurred.test_and_acquire() == false {
			continue
		}

		pending = false

		unsafe { listener.which[0] = listener.index }

		if thread.event_block_dequeue.test_and_acquire() == false {
			for katomic.load(thread.is_in_queue) == true {}
		}

		sched.enqueue_thread(thread)

		listener.l.release()
		listener.ready.release()
	}

	if pending == true {
		katomic.inc(this.pending)
	}
}

pub fn pthread_exit(ret voidptr) {
	asm volatile amd64 { cli }

	mut current_thread := proc.current_thread()

	sched.dequeue_thread(current_thread)

	current_thread = voidptr(0)

	current_thread.exit_value = ret
	trigger(current_thread.exited)

	sched.yield()
}

pub fn pthread_wait(thread &proc.Thread) voidptr {
	mut which := u64(0)
	await([&thread.exited], &which, true)
	exit_value := thread.exit_value
	unsafe { free(thread) }
	return exit_value
}
