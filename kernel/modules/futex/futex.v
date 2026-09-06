@[has_globals]
module futex

import event
import event.eventstruct
import klock
import errno
import proc
import usercopy

__global (
	futex_lock klock.Lock
	futexes    map[u64]&eventstruct.Event
)

pub fn initialise() {
	futexes = map[u64]&eventstruct.Event{}
}

// Futexes are keyed on the physical address of the word, so that a futex shared
// through a shared mapping is the same futex in every process that sees it.
fn event_for(virt u64, create bool) ?&eventstruct.Event {
	phys := proc.current_thread().process.pagemap.virt2phys(virt) or { return none }

	futex_lock.acquire()
	defer {
		futex_lock.release()
	}

	if phys in futexes {
		return unsafe { futexes[phys] }
	}
	if !create {
		return none
	}

	e := &eventstruct.Event{}
	futexes[phys] = e
	return e
}

// Block until woken, unless the word no longer holds the expected value.
pub fn wait(virt u64, expected int) (u64, u64) {
	// Read through the pagemap rather than dereferencing the user pointer: a
	// bad address must come back as EFAULT, not as a fault in kernel mode.
	current := usercopy.read_u32(virt) or { return errno.err, errno.efault }
	if current != u32(expected) {
		return errno.err, errno.eagain
	}

	e := event_for(virt, true) or { return errno.err, errno.efault }

	mut events := [e]
	defer {
		unsafe { events.free() }
	}
	event.await(mut events, true) or { return errno.err, errno.eintr }

	return 0, 0
}

// Wake everything blocked on the word, returning how many threads that was.
// An address with no futex registered against it — including one that is not
// mapped at all — simply has nothing to wake.
pub fn wake(virt u64) u64 {
	mut e := event_for(virt, false) or { return 0 }

	return event.trigger(mut e, true)
}

pub fn syscall_futex_wait(_ voidptr, ptr &int, expected int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: futex_wait(0x%llx, %d)\n', process.name.str, voidptr(ptr),
		expected)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	return wait(u64(ptr), expected)
}

pub fn syscall_futex_wake(_ voidptr, ptr &int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: futex_wake(0x%llx)\n', process.name.str, voidptr(ptr))
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	return wake(u64(ptr)), 0
}
