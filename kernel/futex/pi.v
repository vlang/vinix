// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module futex

import errno
import event
import event.eventstruct
import katomic
import klock
import memory
import memory.mmap
import proc
import sched
import time
import usercopy

const pi_waiters = u32(0x80000000)
const pi_owner_died = u32(0x40000000)
const pi_tid_mask = u32(0x3fffffff)
const max_pi_states = 256

struct PIWait {
mut:
	thread   &proc.Thread = unsafe { nil }
	next     &PIWait      = unsafe { nil }
	event    eventstruct.Event
	token    int
	finished bool
	error    u64
}

struct PIState {
mut:
	space     voidptr
	address   u64
	owner     &proc.Thread = unsafe { nil }
	owner_tid u32
	waiting   &PIWait = unsafe { nil }
}

struct PIEvents {
mut:
	items [2]&eventstruct.Event
}

__global (
	pi_lock   klock.Lock
	pi_states [max_pi_states]PIState
)

fn find_pi(space voidptr, address u64) int {
	for i in 0 .. max_pi_states {
		if pi_states[i].owner != unsafe { nil } && pi_states[i].space == space
			&& pi_states[i].address == address {
			return i
		}
	}
	return -1
}

fn unlink_pi_waiter(mut state PIState, node &PIWait) {
	if voidptr(state.waiting) == voidptr(node) {
		state.waiting = node.next
		return
	}
	for waiter := state.waiting; waiter != unsafe { nil }; waiter = waiter.next {
		if voidptr(waiter.next) == voidptr(node) {
			waiter.next = node.next
			return
		}
	}
}

// Used only after the last live wait frame has left the list. Finished frames
// refer only to their own stack node; they never dereference a recycled slot.
fn retire_pi(mut state PIState) {
	owner := state.owner
	state.owner = unsafe { nil }
	state.waiting = unsafe { nil }
	if owner != unsafe { nil } { proc.unpin_thread(owner) }
}

fn fail_pi_waiters(mut state PIState, error u64) {
	for state.waiting != unsafe { nil } {
		mut node := state.waiting
		state.waiting = node.next
		proc.remove_priority_donation(node.token)
		node.token = 0
		node.error = error
		node.finished = true
		event.trigger(mut node.event, false)
	}
	retire_pi(mut state)
}

// Ownership is installed in the user word before the selected frame wakes.
// PI lock -> donation lock -> event/queue lock; no faulting usercopy or task
// lookup occurs while that chain is held.
fn handoff_pi(mut state PIState, owner_dead bool, space &memory.Pagemap) ?bool {
	// Pageout can remove a PTE after prefault. Keep the queue intact and let
	// the caller resolve it outside pi_lock before retrying this transaction.
	old := usercopy.futex_pagemap_cmpxchg_inatomic(space, state.address, 0, 0) or { return none }
	if old & pi_tid_mask != state.owner_tid {
		fail_pi_waiters(mut state, errno.einval)
		return false
	}
	mut chosen := &PIWait(unsafe { nil })
	mut rank := -1
	for waiter := state.waiting; waiter != unsafe { nil }; waiter = waiter.next {
		candidate := proc.effective_sched_rank(waiter.thread)
		if candidate > rank {
			rank = candidate
			chosen = waiter
		}
	}
	died := if owner_dead { pi_owner_died } else { old & pi_owner_died }
	new_tid := if chosen == unsafe { nil } { u32(0) } else { u32(proc.own_tid(chosen.thread)) }
	value := new_tid | died | if chosen != unsafe { nil } && (voidptr(state.waiting) != voidptr(chosen) || chosen.next != unsafe { nil }) {
		pi_waiters
	} else {
		u32(0)
	}
	observed := usercopy.futex_pagemap_cmpxchg_inatomic(space, state.address, old, value) or { return none }
	if observed != old {
		fail_pi_waiters(mut state, errno.einval)
		return false
	}
	if chosen == unsafe { nil } {
		retire_pi(mut state)
		return true
	}
	unlink_pi_waiter(mut state, chosen)
	proc.remove_priority_donation(chosen.token)
	chosen.token = 0
	old_owner := state.owner
	proc.pin_thread(chosen.thread)
	state.owner = chosen.thread
	state.owner_tid = new_tid
	for waiter := state.waiting; waiter != unsafe { nil }; waiter = waiter.next {
		proc.retarget_priority_donation(waiter.token, chosen.thread)
	}
	proc.unpin_thread(old_owner)
	chosen.finished = true
	event.trigger(mut chosen.event, false)
	if state.waiting == unsafe { nil } { retire_pi(mut state) }
	return true
}

// Resolve outside pi_lock. A valid writable mapping can lose a page-in race;
// bounded syscall exhaustion is EAGAIN, while storage/protection failures keep
// their terminal errors. Retirement is uncancellable but bounded per state.
fn prefault_pi(space &memory.Pagemap, address u64, retiring bool) ?u32 {
	for attempt in 0 .. 64 {
		errno.set(0)
		value := usercopy.futex_pagemap_atomic_op_u32(space, address, 1, 0) or {
			failure := errno.get()
			if !mmap.writable_futex_address(space, address) {
				errno.set(errno.efault)
				return none
			}
			if failure == errno.eio || failure == errno.enomem {
				errno.set(failure)
				return none
			}
			if !retiring && katomic.load(&proc.current_thread().must_exit) {
				errno.set(errno.eintr)
				return none
			}
			if attempt % 8 == 7 { sched.yield(true) }
			continue
		}
		return value
	}
	errno.set(errno.eagain)
	return none
}

// Private-address-space PI includes pageable words and CLONE_VM processes.
// Shared PI needs a backing-object key and is rejected explicitly here.
pub fn lock_pi(address u64, try_only bool, timeout &time.TimeSpec, realtime bool) (u64, u64) {
	mut current := proc.current_thread()
	space := current.process.pagemap
	if address & 3 != 0 { return errno.err, errno.einval }
	if mmap.is_shared_address(space, address) { return errno.err, errno.enotsup }
	if current.sched.policy == proc.sched_deadline { return errno.err, errno.enotsup }
	mut node := unsafe { &PIWait(C.__builtin_alloca(sizeof(PIWait))) }
	unsafe { *node = PIWait{ thread: current } }
	mut timer := &time.Timer(unsafe { nil })
	if timeout != unsafe { nil } {
		if timeout.tv_sec < 0 || timeout.tv_nsec < 0 || timeout.tv_nsec >= 1000000000 {
			return errno.err, errno.einval
		}
		if realtime {
			timer = time.new_realtime_timer(*timeout)
		} else {
			mut duration := *timeout
			now := time.clock_now(time.clock_type_monotonic) or { return errno.err, errno.einval }
			if duration.sub(now) { duration = time.TimeSpec{} }
			timer = time.new_timer(duration)
		}
	}
	defer {
		if timer != unsafe { nil } {
			timer.disarm()
			unsafe { free(timer) }
		}
	}
	mut index := -1
	mut queued := false
	for _ in 0 .. 16 {
		// Resolve COW/page-in before taking pi_lock; a concurrent mapping
		// change is detected by the no-fault atomic operation below.
		value := prefault_pi(space, address, false) or { return errno.err, errno.get() }
		if value & pi_tid_mask == u32(proc.own_tid(current)) { return errno.err, errno.edeadlk }
		mut owner := &proc.Thread(unsafe { nil })
		if value & pi_tid_mask != 0 {
			owner = proc.pin_pi_owner(int(value & pi_tid_mask), space)
			if owner == unsafe { nil } { return errno.err, errno.esrch }
		}
		pi_lock.acquire()
		observed := usercopy.futex_cmpxchg_inatomic(address, value, value) or {
			pi_lock.release()
			if owner != unsafe { nil } { proc.unpin_thread(owner) }
			continue
		}
		if observed != value {
			pi_lock.release()
			if owner != unsafe { nil } { proc.unpin_thread(owner) }
			continue
		}
		if value & pi_tid_mask == 0 {
			changed := usercopy.futex_cmpxchg_inatomic(address, value, u32(proc.own_tid(current)) | (value & pi_owner_died)) or { u32(-1) }
			pi_lock.release()
			if changed == value { return 0, 0 }
			continue
		}
		if try_only {
			pi_lock.release()
			proc.unpin_thread(owner)
			return errno.err, errno.eagain
		}
		// Closing is published under this same lock before the retirement scan.
		// A lookup pin protects storage but does not admit a new edge after exit.
		if katomic.load(&owner.exit_claimed) != 0 || katomic.load(&owner.is_dead)
			|| katomic.load(&owner.pi_closed) {
			pi_lock.release()
			proc.unpin_thread(owner)
			return errno.err, errno.esrch
		}
		index = find_pi(voidptr(space), address)
		if index < 0 {
			for i in 0 .. max_pi_states {
				if pi_states[i].owner == unsafe { nil } {
					index = i
					break
				}
			}
			if index < 0 {
				pi_lock.release()
				proc.unpin_thread(owner)
				return errno.err, errno.eagain
			}
			pi_states[index] = PIState{ space: voidptr(space), address: address, owner: owner, owner_tid: value & pi_tid_mask }
		} else {
			proc.unpin_thread(owner)
		}
		mut state := unsafe { &pi_states[index] }
		token := proc.donate_priority(current, state.owner) or {
			error := errno.get()
			if state.waiting == unsafe { nil } { retire_pi(mut state) }
			pi_lock.release()
			return errno.err, error
		}
		node.token = token
		changed := usercopy.futex_cmpxchg_inatomic(address, value, value | pi_waiters) or { u32(-1) }
		if changed != value {
			proc.remove_priority_donation(token)
			node.token = 0
			if state.waiting == unsafe { nil } { retire_pi(mut state) }
			pi_lock.release()
			continue
		}
		// FIFO among equal priorities. Selection at handoff compares live ranks.
		if state.waiting == unsafe { nil } {
			state.waiting = node
		} else {
			mut tail := state.waiting
			for tail.next != unsafe { nil } { tail = tail.next }
			tail.next = node
		}
		sched.enqueue_thread(state.owner, false)
		queued = true
		pi_lock.release()
		break
	}
	if !queued { return errno.err, errno.eagain }
	mut storage := unsafe { &PIEvents(C.__builtin_alloca(sizeof(PIEvents))) }
	storage.items[0] = &node.event
	storage.items[1] = if timer == unsafe { nil } { &node.event } else { &timer.event }
	mut events := unsafe {
		event.stack_list(&storage.items[0], if timer == unsafe { nil } {
			1
		} else {
			2
		})
	}
	mut error := u64(0)
	for {
		pi_lock.acquire()
		finished := node.finished
		if finished { error = node.error }
		pi_lock.release()
		if finished { break }
		which := event.await(mut events, true) or {
			error = errno.eintr
			break
		}
		if which == 1 {
			error = errno.etimedout
			break
		}
	}
	pi_lock.acquire()
	if node.finished {
		error = node.error
	} else {
		mut state := unsafe { &pi_states[index] }
		unlink_pi_waiter(mut state, node)
		proc.remove_priority_donation(node.token)
		if state.waiting == unsafe { nil } { retire_pi(mut state) }
	}
	pi_lock.release()
	return if error == 0 { u64(0) } else { errno.err }, error
}

pub fn unlock_pi(address u64) (u64, u64) {
	current := proc.current_thread()
	if address & 3 != 0 { return errno.err, errno.einval }
	if mmap.is_shared_address(current.process.pagemap, address) { return errno.err, errno.enotsup }
	for _ in 0 .. 16 {
		prefault_pi(current.process.pagemap, address, false) or { return errno.err, errno.get() }
		pi_lock.acquire()
		index := find_pi(voidptr(current.process.pagemap), address)
		if index >= 0 {
			mut state := unsafe { &pi_states[index] }
			if voidptr(state.owner) != voidptr(current) {
				pi_lock.release()
				return errno.err, errno.eperm
			}
			ok := handoff_pi(mut state, false, current.process.pagemap) or {
				pi_lock.release()
				continue
			}
			pi_lock.release()
			return if ok { u64(0) } else { errno.err }, if ok { u64(0) } else { errno.einval }
		}
		value := usercopy.futex_cmpxchg_inatomic(address, 0, 0) or {
			pi_lock.release()
			continue
		}
		if value & pi_tid_mask != u32(proc.own_tid(current)) {
			pi_lock.release()
			return errno.err, errno.eperm
		}
		old := usercopy.futex_cmpxchg_inatomic(address, value, 0) or {
			pi_lock.release()
			continue
		}
		pi_lock.release()
		if old == value { return 0, 0 }
	}
	return errno.err, errno.eagain
}

// Called while the dying task's old space still exists, before robust-list/TID
// cleanup. Existing state pins Thread storage, not Process or the address space.
pub fn release_pi_owner(t &proc.Thread, space &memory.Pagemap) {
	pi_lock.acquire()
	katomic.store(mut unsafe { &t.pi_closed }, true)
	pi_lock.release()
	for i in 0 .. max_pi_states {
		mut attempts := 0
		for {
			attempts++
			pi_lock.acquire()
			address := if voidptr(pi_states[i].owner) == voidptr(t) && pi_states[i].space == voidptr(space) {
				pi_states[i].address
			} else {
				u64(0)
			}
			pi_lock.release()
			if address == 0 { break }
			// Page-in/COW may sleep. Revalidate both owner and old space after it.
			mut failure := u64(0)
			if attempts > 64 {
				failure = errno.eagain
			} else {
				prefault_pi(space, address, true) or {
					failure = errno.get()
					if failure == errno.eagain { continue }
					u32(0)
				}
			}
			pi_lock.acquire()
			mut state := unsafe { &pi_states[i] }
			if voidptr(state.owner) != voidptr(t) || state.space != voidptr(space) || state.address != address {
				pi_lock.release()
				break
			}
			if failure != 0 {
				fail_pi_waiters(mut state, failure)
				pi_lock.release()
				break
			}
			handoff_pi(mut state, true, space) or {
				pi_lock.release()
				continue
			}
			pi_lock.release()
			break
		}
	}
}
