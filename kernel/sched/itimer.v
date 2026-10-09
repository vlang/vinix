// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module sched

// ITIMER_REAL belongs to the process. Its active list uses fields in the
// already charged Process object, so arming timers cannot exhaust a separate
// fixed table or allocate on the scheduler/IRQ path.
import klock
import proc
import time

__global (
	itimer_real_head &proc.Process = unsafe { nil }
	itimer_real_lock klock.Lock
)

fn unlink_itimer(mut p proc.Process) {
	if !p.itimer_linked { return }
	if p.itimer_previous == unsafe { nil } {
		itimer_real_head = p.itimer_next
	} else {
		p.itimer_previous.itimer_next = p.itimer_next
	}
	if p.itimer_next != unsafe { nil } {
		p.itimer_next.itimer_previous = p.itimer_previous
	}
	p.itimer_previous = unsafe { nil }
	p.itimer_next = unsafe { nil }
	p.itimer_linked = false
}

fn remaining_itimer(p &proc.Process, now_us u64) i64 {
	return if p.itimer_deadline_us > now_us { i64(p.itimer_deadline_us - now_us) } else { i64(0) }
}

fn tick_itimers() {
	if !itimer_real_lock.test_and_acquire() { return }
	now_us := time.monotonic_ns() / 1000
	for {
		mut due := &proc.Process(unsafe { nil })
		for p := itimer_real_head; p != unsafe { nil }; p = p.itimer_next {
			if p.itimer_deadline_us <= now_us { due = unsafe { p }; break }
		}
		if due == unsafe { nil } { itimer_real_lock.release(); return }
		if due.itimer_interval_us == 0 {
			due.itimer_deadline_us = 0
			unlink_itimer(mut due)
		} else {
			// Advance from the original phase. Late ticks coalesce ordinary
			// signals, but never add their scheduling delay to every period.
			remaining := due.itimer_interval_us - (now_us - due.itimer_deadline_us) % due.itimer_interval_us
			due.itimer_deadline_us = now_us + remaining
		}
		proc.pin_process(due)
		itimer_real_lock.release()
		// Delivery selects a live, unblocked process thread, including an exec
		// transition. No process/thread/event lock is taken under our list lock.
		proc.send_real_itimer_signal(due)
		proc.unpin_process(due)
		if !itimer_real_lock.test_and_acquire() { return }
	}
}

// Fork starts with empty timer fields. Exec and the arming thread's exit keep
// these fields on the surviving Process; only process exit removes the timer.
pub fn set_itimer_real(thrd &proc.Thread, value_us i64, interval_us i64) (i64, i64) {
	if value_us > 0 {
		itimer_armed()
		time.register_tick_deadline_hook(tick_itimers, next_itimer_deadline)
	}
	mut p := thrd.process
	itimer_real_lock.acquire()
	defer { itimer_real_lock.release(); time.deadline_changed() }
	now_us := time.monotonic_ns() / 1000
	old_value := remaining_itimer(p, now_us)
	old_interval := i64(p.itimer_interval_us)
	p.itimer_interval_us = u64(interval_us)
	p.itimer_deadline_us = if value_us > 0 { now_us + u64(value_us) } else { u64(0) }
	if value_us <= 0 {
		unlink_itimer(mut p)
	} else if !p.itimer_linked {
		p.itimer_next = itimer_real_head
		if itimer_real_head != unsafe { nil } { itimer_real_head.itimer_previous = p }
		itimer_real_head = p
		p.itimer_linked = true
	}
	return old_value, old_interval
}

pub fn get_itimer_real(thrd &proc.Thread) (i64, i64) {
	itimer_real_lock.acquire()
	defer { itimer_real_lock.release() }
	return remaining_itimer(thrd.process, time.monotonic_ns() / 1000), i64(thrd.process.itimer_interval_us)
}

// Called after every sibling has unwound, before process identity is reaped.
// A tick already dispatching owns a Process pin across delivery.
pub fn remove_itimer_real(mut p proc.Process) {
	itimer_real_lock.acquire()
	defer { itimer_real_lock.release() }
	unlink_itimer(mut p)
	p.itimer_deadline_us = 0
	p.itimer_interval_us = 0
}

fn next_itimer_deadline() u64 {
	if !itimer_real_lock.test_and_acquire() { return 1000000 }
	defer { itimer_real_lock.release() }
	now := time.monotonic_ns() / 1000
	mut remaining := ~u64(0)
	for p := itimer_real_head; p != unsafe { nil }; p = p.itimer_next {
		delay := if p.itimer_deadline_us > now { (p.itimer_deadline_us - now) * 1000 } else { u64(0) }
		if delay < remaining { remaining = delay }
	}
	return remaining
}
