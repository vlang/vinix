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
	key FutexKey
	users int
	next &Futex = unsafe { nil }
}

struct FutexKey {
	// Only virtual keys have an address-space owner. Shared keys use an
	// inode and file byte offset, or a physical word for other backings.
	owner voidptr
	inode u64
	offset u64
	private bool
}

fn (key FutexKey) bucket() u64 {
	return key.offset ^ (key.inode * u64(0x9e3779b97f4a7c15))
}

// A syscall frame owns the event, which can be shared by several wait nodes.
// Requeue changes only a node's futex owner.
struct Wait {
mut:
	next &Wait = unsafe { nil }
	futex &Futex = unsafe { nil }
	event &eventstruct.Event = unsafe { nil }
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

// A private key only needs an aligned address in the user range. A shared
// key needs a readable mapping so an unmapped word cannot match a waiter.
pub fn address_error(address u64, private bool) u64 {
	if address & 3 != 0 { return errno.einval }
	if address > memory.user_address_limit() - 4 { return errno.efault }
	if !private { usercopy.read_u32(address) or { return errno.efault } }
	return 0
}

// Name the futex a user address refers to.
//
// A shared tmpfs word keeps its key when truncate discards its frame. Other
// MAP_SHARED backings use their physical word. Private mappings go by their
// virtual address because a copy-on-write fault can replace the frame.
// FUTEX_PRIVATE_FLAG always selects the address-space/virtual key. It is also
// part of queue identity on private mappings: Linux's shared anonymous key
// and explicit private key must not match one another.
fn key_for(virt u64, private bool) ?FutexKey {
	pagemap := proc.current_thread().process.pagemap
	virtual_key := FutexKey{owner: voidptr(pagemap), offset: virt, private: private}
	if private { return virtual_key }
	mapping := mmap.futex_mapping(pagemap, virt) or {
		// A shared page may still need a demand fault or have been evicted.
		usercopy.read_u32(virt) or { return none }
		mmap.futex_mapping(pagemap, virt)?
	}
	if !mapping.shared { return virtual_key }
	return FutexKey{inode: mapping.inode, offset: mapping.offset}
}

// Take a reference to the futex for `virt`. Only a waiter creates one: a
// waker that finds none has nobody to wake.
fn get(virt u64, create bool, private bool) ?&Futex {
	key := key_for(virt, private)?
	bucket := key.bucket()

	futex_lock.acquire()
	defer {
		futex_lock.release()
	}

	mut head := unsafe { &Futex(nil) }
	if bucket in futexes {
		head = unsafe { futexes[bucket] }
	}
	for f := head; f != unsafe { nil }; f = f.next {
		if f.key == key {
			mut found := unsafe { f }
			found.users++
			return found
		}
	}
	if !create {
		return none
	}

	f := &Futex{
		key:   key
		users: 1
		next:  head
	}
	futexes[bucket] = f
	return f
}

fn put(mut f Futex) {
	futex_lock.acquire()
	f.users--
	if f.users > 0 {
		futex_lock.release()
		return
	}
	bucket := f.key.bucket()
	mut head := unsafe { futexes[bucket] }
	if head == f {
		if f.next == unsafe { nil } {
			futexes.delete(bucket)
		} else {
			futexes[bucket] = f.next
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
	mut wake_event := unsafe { &eventstruct.Event(C.__builtin_alloca(sizeof(eventstruct.Event))) }
	mut node := unsafe { &Wait(C.__builtin_alloca(sizeof(Wait))) }
	unsafe {
		*wake_event = eventstruct.Event{}
		*node = Wait{bitset: bitset, event: wake_event}
	}
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
	return finish_wait(mut node, await_wake(mut wake_event, timer))
}

fn await_wake(mut wake_event eventstruct.Event, timer &time.Timer) u64 {
	if timer == unsafe { nil } {
		event.await_one(mut wake_event, true) or { return errno.eintr }
		return 0
	}
	mut storage := unsafe { &WaitEvents(C.__builtin_alloca(sizeof(WaitEvents))) }
	storage.items[0] = &wake_event
	storage.items[1] = &timer.event
	mut events := unsafe { event.stack_list(&storage.items[0], 2) }
	which := event.await(mut events, true) or { return errno.eintr }
	return if which == 1 { errno.etimedout } else { 0 }
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
	// The original Linux futex ABI wakes one for a nonpositive count when
	// waiters exist. FUTEX2's strict zero-count behavior is a separate ABI.
	count := if maximum > 0 { u64(maximum) } else { u64(1) }
	return wake_count(virt, count, private, bitset)
}

fn wake_count(virt u64, count u64, private bool, bitset u32) u64 {
	mut f := get(virt, false, private) or { return 0 }
	futex_lock.acquire()
	woken := wake_locked(mut f, count, bitset)
	futex_lock.release()
	put(mut f)
	return woken
}

// None means the comparison page must be faulted in outside futex_lock.
fn requeue_attempt(source u64, target u64, wake_count int, move_count int, source_private bool, target_private bool, compare bool, expected u32) ?(u64, u64) {
	mut from := get(source, true, source_private) or { return errno.err, errno.efault }
	defer { put(mut from) }
	mut to := get(target, true, target_private) or { return errno.err, errno.efault }
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
	return requeue_keys(source, target, wake_count, move_count, private, private, compare, expected)
}

fn requeue_keys(source u64, target u64, wake_count int, move_count int, source_private bool, target_private bool, compare bool, expected u32) (u64, u64) {
	for _ in 0..16 {
		if result, error := requeue_attempt(source, target, wake_count, move_count, source_private, target_private, compare, expected) {
			return result, error
		}
		usercopy.read_u32(source) or { return errno.err, errno.efault }
	}
	return errno.err, errno.eagain
}

