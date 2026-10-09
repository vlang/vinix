// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module proc

import errno
import katomic
import klock
import memory

const max_priority_donations = 2048
const max_priority_chain = 64

struct PriorityDonation {
mut:
	waiter &Thread = unsafe { nil }
	owner  &Thread = unsafe { nil }
}

__global (
	priority_lock           klock.Lock
	priority_donations      [max_priority_donations]PriorityDonation
	priority_donation_count u64
)

pub fn effective_sched_rank(t &Thread) int {
	base := t.sched.rank()
	inherited := katomic.load(&t.pi_rank)
	return if inherited > base { inherited } else { base }
}

pub fn priority_donations_active() bool {
	return katomic.load(&priority_donation_count) != 0
}

pub fn timer_slack() u64 {
	t := current_thread()
	if t == unsafe { nil } || t.sched.is_realtime() { return 0 }
	return katomic.load(&t.timer_slack_ns)
}

pub fn pin_pi_owner(local_tid int, pagemap &memory.Pagemap) &Thread {
	tid := kernel_id(local_tid)
	if tid <= 0 || tid >= max_pid { return unsafe { nil } }
	lock_table()
	defer { unlock_table() }
	t := threads_by_tid[tid]
	if t == unsafe { nil } || katomic.load(&t.is_dead) || katomic.load(&t.exit_claimed) != 0
		|| katomic.load(&t.pi_closed) || t.process == unsafe { nil }
		|| t.process.exiting || voidptr(t.process.pagemap) != voidptr(pagemap) {
		return unsafe { nil }
	}
	pin_thread(t)
	return t
}

// All edges pin both Thread objects. Recompute from configured ranks, rather
// than retaining a boost from a waiter that timed out or lost its owner.
fn recompute_donations() {
	for i in 0 .. max_priority_donations {
		edge := unsafe { &priority_donations[i] }
		if edge.owner != unsafe { nil } { katomic.store(mut unsafe { &edge.owner.pi_rank }, 0) }
	}
	for _ in 0 .. max_priority_chain {
		mut changed := false
		for i in 0 .. max_priority_donations {
			edge := unsafe { &priority_donations[i] }
			if edge.owner == unsafe { nil } { continue }
			rank := effective_sched_rank(edge.waiter)
			if rank > katomic.load(&edge.owner.pi_rank) {
				katomic.store(mut unsafe { &edge.owner.pi_rank }, rank)
				changed = true
			}
		}
		if !changed { break }
	}
}

// Called from an owned wait frame and a pinned owner lookup. A task can wait
// on only one PI lock at a time. Detect cycles before publishing any donation.
pub fn donate_priority(waiter &Thread, owner &Thread) ?int {
	priority_lock.acquire()
	defer { priority_lock.release() }
	mut cursor := unsafe { owner }
	mut ended := false
	for _ in 0 .. max_priority_chain {
		if voidptr(cursor) == voidptr(waiter) {
			errno.set(errno.edeadlk)
			return none
		}
		mut next := &Thread(unsafe { nil })
		for i in 0 .. max_priority_donations {
			edge := unsafe { &priority_donations[i] }
			if voidptr(edge.waiter) == voidptr(cursor) {
				next = edge.owner
				break
			}
		}
		if next == unsafe { nil } {
			ended = true
			break
		}
		cursor = next
	}
	if !ended {
		errno.set(errno.eagain)
		return none
	}
	for i in 0 .. max_priority_donations {
		mut edge := unsafe { &priority_donations[i] }
		if edge.owner != unsafe { nil } { continue }
		pin_thread(waiter)
		pin_thread(owner)
		edge.waiter = unsafe { waiter }
		edge.owner = unsafe { owner }
		katomic.store(mut &priority_donation_count, priority_donation_count + 1)
		recompute_donations()
		return i + 1
	}
	errno.set(errno.eagain)
	return none
}

pub fn remove_priority_donation(token int) {
	if token <= 0 || token > max_priority_donations { return }
	priority_lock.acquire()
	mut edge := unsafe { &priority_donations[token - 1] }
	owner := edge.owner
	waiter := edge.waiter
	if owner == unsafe { nil } {
		priority_lock.release()
		return
	}
	edge.owner = unsafe { nil }
	edge.waiter = unsafe { nil }
	katomic.store(mut unsafe { &owner.pi_rank }, 0)
	katomic.store(mut &priority_donation_count, priority_donation_count - 1)
	recompute_donations()
	priority_lock.release()
	unpin_thread(owner)
	unpin_thread(waiter)
}

pub fn retarget_priority_donation(token int, owner &Thread) {
	if token <= 0 || token > max_priority_donations { return }
	priority_lock.acquire()
	mut edge := unsafe { &priority_donations[token - 1] }
	old := edge.owner
	if old == unsafe { nil } {
		priority_lock.release()
		return
	}
	pin_thread(owner)
	edge.owner = unsafe { owner }
	katomic.store(mut unsafe { &old.pi_rank }, 0)
	recompute_donations()
	priority_lock.release()
	unpin_thread(old)
}

// Refreshed after sched_setparam/setattr: active waiters donate their current
// configured priority, and policy changes cannot erase an existing donation.
pub fn refresh_priority_donations() {
	priority_lock.acquire()
	recompute_donations()
	priority_lock.release()
}
