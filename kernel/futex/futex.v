@[has_globals]
module futex

import event
import event.eventstruct
import klock
import memory
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
	waiters &Wait = unsafe { nil }
	// The address space a private futex belongs to, or nil for a shared one,
	// whose address is physical.
	owner voidptr
	addr  u64
	private bool
	users int
	// Other futexes whose keys share `addr`: the same virtual address in
	// another process, most often another copy of the same program.
	next &Futex = unsafe { nil }
}

// Each syscall frame owns its event. Requeue changes only its futex owner,
// leaving event.await's listener pointers and timer stable until they detach.
struct Wait {
mut:
	next &Wait = unsafe { nil }
	futex &Futex = unsafe { nil }
	event eventstruct.Event
	bitset u32
	woken bool
}

struct WaitEvents {
mut:
	items [2]&eventstruct.Event
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
// FUTEX_PRIVATE_FLAG always selects the address-space/virtual key. It is also
// part of queue identity on private mappings: Linux's shared anonymous key
// and explicit private key must not match one another.
fn key_for(virt u64, private bool) ?(voidptr, u64) {
	mut pagemap := proc.current_thread().process.pagemap
	if private || !mmap.is_shared_address(pagemap, virt) {
		return voidptr(pagemap), virt
	}
	if phys := pagemap.virt2phys(virt) {
		return unsafe { nil }, phys + (virt & (memory.page_size - 1))
	}
	// A shared page is mapped on first touch. Reading the word brings it in.
	usercopy.read_u32(virt) or { return none }
	phys := pagemap.virt2phys(virt) or { return none }
	return unsafe { nil }, phys + (virt & (memory.page_size - 1))
}

// Take a reference to the futex for `virt`. Only a waiter creates one: a
// waker that finds none has nobody to wake.
fn get(virt u64, create bool, private bool) ?&Futex {
	owner, addr := key_for(virt, private)?

	futex_lock.acquire()
	defer {
		futex_lock.release()
	}

	mut head := unsafe { &Futex(nil) }
	if addr in futexes {
		head = unsafe { futexes[addr] }
	}
	for f := head; f != unsafe { nil }; f = f.next {
		if f.owner == owner && f.private == private {
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
		private: private
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
	return wait_key(virt, expected, false)
}

pub fn wait_key(virt u64, expected int, private bool) (u64, u64) {
	return wait_mask_key(virt, expected, private, u32(0xffffffff))
}

pub fn wait_mask_key(virt u64, expected int, private bool, bitset u32) (u64, u64) {
	return wait_common(virt, expected, private, bitset, unsafe { nil })
}

// Block until the futex is woken or a relative timeout expires. Linux libc
// uses timed futex waits to implement pthread condition variables and sleep,
// so ignoring the timeout can leave an otherwise healthy process asleep
// forever.
pub fn wait_timeout(virt u64, expected int, duration time.TimeSpec) (u64, u64) {
	return wait_timeout_key(virt, expected, duration, false)
}

pub fn wait_timeout_key(virt u64, expected int, duration time.TimeSpec, private bool) (u64, u64) {
	return wait_timeout_mask_key(virt, expected, duration, private, u32(0xffffffff))
}

pub fn wait_timeout_mask_key(virt u64, expected int, duration time.TimeSpec, private bool, bitset u32) (u64, u64) {
	return wait_common(virt, expected, private, bitset, &duration)
}

// Called with futex_lock held. A frame remains referenced by its current
// owner after wake removes it, until await has detached both event listeners.
fn unlink_wait(mut f Futex, node &Wait) {
	if voidptr(f.waiters) == voidptr(node) { f.waiters = node.next; return }
	for previous := f.waiters; previous != unsafe { nil }; previous = previous.next {
		if voidptr(previous.next) == voidptr(node) { previous.next = node.next; return }
	}
}

fn append_wait(mut f Futex, node &Wait) {
	if f.waiters == unsafe { nil } { f.waiters = node; return }
	mut tail := f.waiters
	for tail.next != unsafe { nil } { tail = tail.next }
	tail.next = node
}

fn finish_wait(mut node Wait, error u64) (u64, u64) {
	futex_lock.acquire()
	mut owner := node.futex
	if !node.woken { unlink_wait(mut owner, &node) }
	woken := node.woken
	futex_lock.release()
	// Requeue transfers this one reference; the original owner is never used
	// by this frame again. No queue reader retains node after this unlock.
	put(mut owner)
	if woken || error == 0 { return 0, 0 }
	return errno.err, error
}

fn wait_common(virt u64, expected int, private bool, bitset u32, duration &time.TimeSpec) (u64, u64) {
	// Resolve outside the queue lock, then compare again without faulting
	// while holding it. Wakers take the same lock, closing check/enqueue races.
	value := usercopy.read_u32(virt) or { return errno.err, errno.efault }
	if value != u32(expected) { return errno.err, errno.eagain }
	if duration != unsafe { nil } && duration.tv_sec == 0 && duration.tv_nsec == 0 {
		return errno.err, errno.etimedout
	}
	mut timer := &time.Timer(unsafe { nil })
	if duration != unsafe { nil } { timer = time.new_timer(*duration) }
	defer {
		if timer != unsafe { nil } { timer.disarm(); unsafe { free(timer) } }
	}
	mut node := unsafe { &Wait(C.__builtin_alloca(sizeof(Wait))) }
	unsafe { *node = Wait{bitset: bitset} }
	mut queued := false
	for _ in 0..16 {
		mut f := get(virt, true, private) or { return errno.err, errno.efault }
		futex_lock.acquire()
		current := usercopy.futex_read_u32_inatomic(virt) or {
			futex_lock.release()
			put(mut f)
			usercopy.read_u32(virt) or { return errno.err, errno.efault }
			continue
		}
		if current != u32(expected) {
			futex_lock.release()
			put(mut f)
			return errno.err, errno.eagain
		}
		node.futex = f // Transfer get's reference to the live syscall frame.
		append_wait(mut f, node)
		queued = true
		futex_lock.release()
		break
	}
	if !queued { return errno.err, errno.eagain }
	mut storage := unsafe { &WaitEvents(C.__builtin_alloca(sizeof(WaitEvents))) }
	storage.items[0] = &node.event
	storage.items[1] = if timer == unsafe { nil } { &node.event } else { &timer.event }
	mut events := unsafe { event.stack_list(&storage.items[0], if timer == unsafe { nil } { 1 } else { 2 }) }
	mut error := u64(0)
	which := event.await(mut events, true) or { error = errno.eintr; u64(-1) }
	if which == 1 { error = errno.etimedout }
	return finish_wait(mut node, error)
}

// Wake and requeue hold futex_lock until their last use of each stack node.
// Trigger retains a pending wake when the selected frame has not yet slept.
fn wake_locked(mut f Futex, maximum u64, bitset u32) u64 {
	mut woken := u64(0)
	mut node := f.waiters
	for node != unsafe { nil } && woken < maximum {
		next := node.next
		if node.bitset & bitset != 0 {
			unlink_wait(mut f, node)
			node.woken = true
			event.trigger(mut node.event, false)
			woken++
		}
		node = next
	}
	return woken
}

pub fn wake(virt u64) u64 {
	return wake_key(virt, false)
}

pub fn wake_key(virt u64, private bool) u64 {
	return wake_mask_key(virt, 0x7fffffff, private, u32(0xffffffff))
}

pub fn wake_n(virt u64, maximum int) u64 {
	return wake_n_key(virt, maximum, false)
}

pub fn wake_n_key(virt u64, maximum int, private bool) u64 {
	return wake_mask_key(virt, maximum, private, u32(0xffffffff))
}

pub fn wake_mask_key(virt u64, maximum int, private bool, bitset u32) u64 {
	mut f := get(virt, false, private) or { return 0 }
	// The original Linux futex ABI wakes one for a nonpositive count when
	// waiters exist. FUTEX2's strict zero-count behavior is a separate ABI.
	count := if maximum > 0 { u64(maximum) } else { u64(1) }
	futex_lock.acquire()
	woken := wake_locked(mut f, count, bitset)
	futex_lock.release()
	put(mut f)
	return woken
}

// None means the comparison page must be faulted in outside futex_lock.
fn requeue_attempt(source u64, target u64, wake_count int, move_count int, private bool, compare bool, expected u32) ?(u64, u64) {
	mut from := get(source, true, private) or { return errno.err, errno.efault }
	defer { put(mut from) }
	mut to := get(target, true, private) or { return errno.err, errno.efault }
	defer { put(mut to) }
	futex_lock.acquire()
	defer { futex_lock.release() }
	if compare {
		current := usercopy.futex_read_u32_inatomic(source) or { return none }
		if current != expected { return errno.err, errno.eagain }
	}
	woken := wake_locked(mut from, u64(wake_count), u32(0xffffffff))
	mut moved := u64(0)
	if voidptr(from) == voidptr(to) {
		for node := from.waiters; node != unsafe { nil } && moved < u64(move_count); node = node.next { moved++ }
	} else {
		for from.waiters != unsafe { nil } && moved < u64(move_count) {
			mut node := from.waiters
			from.waiters = node.next
			node.next = unsafe { nil }
			// Both temporary references keep the owners alive while each
			// waiter's reference moves. Its event and timer never move.
			to.users++
			from.users--
			node.futex = to
			append_wait(mut to, node)
			moved++
		}
	}
	return woken + moved, 0
}

pub fn requeue(source u64, target u64, wake_count int, move_count int, private bool, compare bool, expected u32) (u64, u64) {
	for _ in 0..16 {
		if result, error := requeue_attempt(source, target, wake_count, move_count, private, compare, expected) {
			return result, error
		}
		usercopy.read_u32(source) or { return errno.err, errno.efault }
	}
	return errno.err, errno.eagain
}

