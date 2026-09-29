// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module sched

// setitimer(ITIMER_REAL) and alarm(): SIGALRM once the time is up, and again
// every interval after that, counted down on the scheduler's clock. Each arch
// says what drives tick_itimers() through itimer_armed(): arm64's scheduler
// tick on every CPU, amd64's clock tick.

import katomic
import klock
import proc

const max_itimer_real = 32

struct ItimerRealEntry {
mut:
	thrd        &proc.Thread = unsafe { nil }
	value_us    i64
	interval_us i64
	active      bool
}

__global (
	itimer_real_entries [max_itimer_real]ItimerRealEntry
	itimer_real_lock    klock.Lock
	itimer_last_ns      u64
)

// A tick that finds the table busy leaves the time to the next one, which
// counts it: the elapsed time is measured, not assumed, and measured under the
// lock. arm64 used to read its counter and take the last reading outside it,
// on four CPUs at once: one whose reading was older than the reading another
// had just stored subtracted into a wrap-around, took that for eons, and
// fired every armed timer -- alarm(60) raised SIGALRM within milliseconds.
fn tick_itimers() {
	if !itimer_real_lock.test_and_acquire() {
		return
	}
	defer {
		itimer_real_lock.release()
	}

	now := clock_ns()
	if itimer_last_ns == 0 || now <= itimer_last_ns {
		if itimer_last_ns == 0 {
			itimer_last_ns = now
		}
		return
	}
	elapsed_us := i64((now - itimer_last_ns) / 1000)
	if elapsed_us <= 0 {
		return
	}
	itimer_last_ns += u64(elapsed_us) * 1000

	for i := 0; i < max_itimer_real; i++ {
		mut e := unsafe { &itimer_real_entries[i] }
		if !e.active || e.value_us <= 0 {
			continue
		}
		e.value_us -= elapsed_us
		if e.value_us <= 0 {
			// SIGALRM.
			katomic.bts(mut &e.thrd.pending_signals, proc.pending_bit(14))
			enqueue_thread(e.thrd, true)
			if e.interval_us > 0 {
				e.value_us = e.interval_us
			} else {
				e.active = false
			}
		}
	}
}

// set_itimer_real arms or disarms `thrd`'s ITIMER_REAL timer and returns the
// previous (value_us, interval_us).
pub fn set_itimer_real(thrd &proc.Thread, value_us i64, interval_us i64) (i64, i64) {
	arming := value_us > 0 || interval_us > 0
	if arming {
		itimer_armed()
	}

	itimer_real_lock.acquire()
	defer {
		itimer_real_lock.release()
	}

	for i := 0; i < max_itimer_real; i++ {
		mut e := unsafe { &itimer_real_entries[i] }
		if e.active && e.thrd == thrd {
			old_value := e.value_us
			old_interval := e.interval_us
			if !arming {
				e.active = false
			} else {
				e.value_us = value_us
				e.interval_us = interval_us
			}
			return old_value, old_interval
		}
	}

	if arming {
		if itimer_last_ns == 0 {
			itimer_last_ns = clock_ns()
		}
		for i := 0; i < max_itimer_real; i++ {
			mut e := unsafe { &itimer_real_entries[i] }
			if !e.active {
				e.thrd = unsafe { thrd }
				e.value_us = value_us
				e.interval_us = interval_us
				e.active = true
				break
			}
		}
	}

	return 0, 0
}

// get_itimer_real returns the current (value_us, interval_us) for a thread.
pub fn get_itimer_real(thrd &proc.Thread) (i64, i64) {
	itimer_real_lock.acquire()
	defer {
		itimer_real_lock.release()
	}

	for i := 0; i < max_itimer_real; i++ {
		e := itimer_real_entries[i]
		if e.active && e.thrd == thrd {
			return e.value_us, e.interval_us
		}
	}

	return 0, 0
}
