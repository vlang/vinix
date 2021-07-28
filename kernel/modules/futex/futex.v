module futex

import event
import event.eventstruct
import klock
import errno
import proc
import katomic

__global (
	futex_lock klock.Lock
	futexes map[u64]&eventstruct.Event
)

pub fn initialise() {
	futexes = map[u64]&eventstruct.Event{}
}

pub fn syscall_futex_wait(_ voidptr, ptr &int, expected int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: futex_wait(0x%llx, %d)\n', voidptr(ptr), expected)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	if katomic.load(unsafe { ptr[0] }) != expected {
		return -1, errno.eagain
	}

	mut e := &eventstruct.Event(0)
	phys := proc.current_thread().process.pagemap.virt2phys(u64(ptr)) or {
		return -1, errno.get()
	}

	futex_lock.acquire()

	if phys !in futexes {
		e = &eventstruct.Event{}
		futexes[phys] = e
	} else {
		e = futexes[phys]
	}

	futex_lock.release()

	mut which := u64(0)
	event.await([e], &which, true) or {
		return -1, errno.eintr
	}

	return 0, 0
}

pub fn syscall_futex_wake(_ voidptr, ptr &int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: futex_wake(0x%llx)\n', voidptr(ptr))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	// Ensure this page is not lazily mapped
	katomic.load(unsafe { ptr[0] })

	phys := proc.current_thread().process.pagemap.virt2phys(u64(ptr)) or {
		return -1, errno.get()
	}

	futex_lock.acquire()
	defer {
		futex_lock.release()
	}

	if phys !in futexes {
		return 0, 0
	}

	ret := event.trigger(futexes[phys], false)

	return ret, 0
}
