@[has_globals]
module futex

import event
import event.eventstruct
import klock
import memory.mmap
import errno
import proc
import time
import usercopy

// A futex exists only while somebody holds it: every waiter for the whole of
// its wait, and a waker for as long as it takes to wake them. The table so
// never outgrows the waiters currently blocked, however many processes have
// come and gone.
@[heap]
struct Futex {
mut:
	event eventstruct.Event
	// The address space a private futex belongs to, or nil for a shared one,
	// whose address is physical.
	owner voidptr
	addr  u64
	users int
	// Other futexes whose keys share `addr`: the same virtual address in
	// another process, most often another copy of the same program.
	next &Futex = unsafe { nil }
}

__global (
	futex_lock klock.Lock
	futexes    map[u64]&Futex
)

pub fn initialise() {
	futexes = map[u64]&Futex{}
}

// Name the futex a user address refers to.
//
// A word in a MAP_SHARED mapping is the same futex in every process that maps
// it, so it goes by its physical address. Anything else is private to this
// address space and goes by its virtual address, as on Linux. Keying private
// words physically too loses wakeups: fork shares pages copy-on-write, and the
// first write afterwards moves the writer onto a fresh page. A thread already
// asleep on the word stays filed under the old page while the thread that
// wakes it looks under the new one -- which is how a Go program that has run a
// subprocess ends up with a runtime thread asleep for good.
fn key_for(virt u64) ?(voidptr, u64) {
	mut pagemap := proc.current_thread().process.pagemap
	if !mmap.is_shared_address(pagemap, virt) {
		return voidptr(pagemap), virt
	}
	if phys := pagemap.virt2phys(virt) {
		return unsafe { nil }, phys
	}
	// A shared page is mapped on first touch. Reading the word brings it in.
	usercopy.read_u32(virt) or { return none }
	phys := pagemap.virt2phys(virt) or { return none }
	return unsafe { nil }, phys
}

// Take a reference to the futex for `virt`. Only a waiter creates one: a
// waker that finds none has nobody to wake.
fn get(virt u64, create bool) ?&Futex {
	owner, addr := key_for(virt)?

	futex_lock.acquire()
	defer {
		futex_lock.release()
	}

	mut head := unsafe { &Futex(nil) }
	if addr in futexes {
		head = unsafe { futexes[addr] }
	}
	for f := head; f != unsafe { nil }; f = f.next {
		if f.owner == owner {
			mut found := unsafe { f }
			found.users++
			return found
		}
	}
	if !create {
		return none
	}

	f := &Futex{
		owner: owner
		addr:  addr
		users: 1
		next:  head
	}
	futexes[addr] = f
	return f
}

fn put(mut f Futex) {
	futex_lock.acquire()
	f.users--
	if f.users > 0 {
		futex_lock.release()
		return
	}
	mut head := unsafe { futexes[f.addr] }
	if head == f {
		if f.next == unsafe { nil } {
			futexes.delete(f.addr)
		} else {
			futexes[f.addr] = f.next
		}
	} else {
		for head.next != f {
			head = head.next
		}
		head.next = f.next
	}
	futex_lock.release()
	unsafe { free(f) }
}

// Block until woken, unless the word no longer holds the expected value.
pub fn wait(virt u64, expected int) (u64, u64) {
	mut f := get(virt, true) or { return errno.err, errno.efault }
	defer {
		put(mut f)
	}
	mut e := &f.event
	generation := event.generation(mut e)

	// Read through the pagemap rather than dereferencing the user pointer: a
	// bad address must come back as EFAULT, not as a fault in kernel mode.
	current := usercopy.read_u32(virt) or { return errno.err, errno.efault }
	if current != u32(expected) {
		return errno.err, errno.eagain
	}

	mut events := [e]
	defer {
		unsafe { events.free() }
	}
	event.await_from_generation(mut events, true, 0, generation) or {
		return errno.err, errno.eintr
	}

	return 0, 0
}

// Block until the futex is woken or a relative timeout expires. Linux libc
// uses timed futex waits to implement pthread condition variables and sleep,
// so ignoring the timeout can leave an otherwise healthy process asleep
// forever.
pub fn wait_timeout(virt u64, expected int, duration time.TimeSpec) (u64, u64) {
	mut f := get(virt, true) or { return errno.err, errno.efault }
	defer {
		put(mut f)
	}
	mut e := &f.event
	generation := event.generation(mut e)

	// Match wait(): validate and compare the userspace word before deciding that
	// even a zero-length wait has timed out.
	current := usercopy.read_u32(virt) or { return errno.err, errno.efault }
	if current != u32(expected) {
		return errno.err, errno.eagain
	}
	if duration.tv_sec == 0 && duration.tv_nsec == 0 {
		return errno.err, errno.etimedout
	}

	mut timer := time.new_timer(duration)
	defer {
		timer.disarm()
		unsafe { free(timer) }
	}

	mut events := [e, &timer.event]
	defer {
		unsafe { events.free() }
	}
	which := event.await_from_generation(mut events, true, 0, generation) or {
		return errno.err, errno.eintr
	}
	if which == 1 {
		return errno.err, errno.etimedout
	}

	return 0, 0
}

// Wake everything blocked on the word, returning how many threads that was.
// An address with no futex registered against it — including one that is not
// mapped at all — simply has nothing to wake.
pub fn wake(virt u64) u64 {
	mut f := get(virt, false) or { return 0 }
	woken := event.trigger(mut f.event, true)
	put(mut f)
	return woken
}

pub fn syscall_futex_wait(_ voidptr, ptr &i32, expected int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: futex_wait(0x%llx, %d)\n', process.name.str, voidptr(ptr),
		expected)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	return wait(u64(ptr), expected)
}

pub fn syscall_futex_wake(_ voidptr, ptr &i32) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: futex_wake(0x%llx)\n', process.name.str, voidptr(ptr))
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	return wake(u64(ptr)), 0
}
