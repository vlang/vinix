// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Waiting for hardware, with an end.
//
// Every driver waits for a bit to clear or a command to complete, and each had
// its own way of giving up: a count of register reads, which is as long as the
// machine is slow; a private clock; or nothing at all, which is a hang when
// the device is gone. A device that is unplugged, or that a sleeping machine's
// firmware left switched off, answers every read with all ones for ever, so a
// wait without an end is a machine that never comes back.
//
// These are bounded by the clock instead. The clock is the one ACPI's waits
// already use: it runs before the scheduler does and on both architectures.
module devcore

import acpisync
import event
import event.eventstruct
import time

pub const microsecond = u64(1000)
pub const millisecond = u64(1000000)
pub const second = u64(1000000000)

pub fn now_ns() u64 {
	return acpisync.clock_ns()
}

pub struct Deadline {
pub:
	start u64
	limit u64
}

pub fn deadline(ns u64) Deadline {
	return Deadline{
		start: now_ns()
		limit: ns
	}
}

pub fn (d Deadline) expired() bool {
	return now_ns() - d.start >= d.limit
}

pub fn (d Deadline) elapsed() u64 {
	return now_ns() - d.start
}

// Look at `ready` until it says yes or `timeout_ns` has passed, without giving
// up the CPU: for the microseconds a register takes, and for callers that hold
// a spinlock or run before the scheduler. `ready` is looked at once more after
// the time is up, so a caller that was itself delayed past the deadline does
// not report a timeout for something that finished.
pub fn spin_until(ready fn (context voidptr) bool, context voidptr, timeout_ns u64) bool {
	limit := deadline(timeout_ns)
	for {
		if ready(context) {
			return true
		}
		if limit.expired() {
			return ready(context)
		}
		relax()
	}
	return false
}

// The same, sleeping `poll_ms` between looks: for the seconds a disk takes to
// spin up or a controller to reset. Before the scheduler runs it spins.
pub fn sleep_until(ready fn (context voidptr) bool, context voidptr, timeout_ns u64, poll_ms u64) bool {
	limit := deadline(timeout_ns)
	for {
		if ready(context) {
			return true
		}
		if limit.expired() {
			return ready(context)
		}
		acpisync.sleep(if poll_ms == 0 { u64(1) } else { poll_ms })
	}
	return false
}

// Let `ns` pass without giving up the CPU.
pub fn stall(ns u64) {
	limit := deadline(ns)
	for !limit.expired() {
		relax()
	}
}

// Let `ms` pass, sleeping when the scheduler allows it.
pub fn sleep_ms(ms u64) {
	acpisync.sleep(ms)
}

// Wait until `e` is triggered again, counting from when `generation` was
// read off it, or until `ms` have passed. True if it was triggered. For a
// thread that does something periodically and can also be told to do it now.
pub fn wait_event(mut e eventstruct.Event, generation u64, ms u64) bool {
	mut timer := time.new_timer(time.TimeSpec{i64(ms / 1000), i64(ms % 1000) * 1000000})
	mut storage := [unsafe { &e }, &timer.event]!
	mut events := unsafe { event.stack_list(&storage[0], storage.len) }
	which := event.await_from_generation(mut events, true, 0, generation) or { u64(1) }
	timer.disarm()
	unsafe { free(timer) }
	return which == 0
}
