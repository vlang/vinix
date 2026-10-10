// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// The idle timer: how long it has been since anybody touched the keyboard or
// the pointer, and what follows from that. The display turns off after one
// timeout and the machine sleeps after another; either may be never.
//
// Nothing here reads a clock, a device or a setting. The compositor passes in
// the time of each input and asks once a pass what to do, so the tests drive
// this with a clock of their own. idle_wm.v is the side that acts.
module main

// A longer silence than this between two looks at the clock is not the user
// being away. The machine slept, a virtual machine was paused or the
// compositor was held up, and nobody could have touched anything while that
// lasted, so the count starts again from the look that noticed.
const idle_gap_ms = u64(10_000)

enum IdlePhase {
	active
	display_off
	asleep
}

// What one look at the clock asks of the compositor.
enum IdleStep {
	none_
	display_off
	display_on
	// Put the machine to sleep, then say how that went with woke() or
	// sleep_refused().
	sleep
}

struct IdleTimer {
mut:
	phase IdlePhase
	// Where a sleep that is refused goes back to.
	before_sleep IdlePhase
	// Monotonic milliseconds of the last input and of the last look. Neither
	// means anything until `started`.
	last_input_ms u64
	last_tick_ms  u64
	started       bool
	// The machine was asked to sleep and would not. It is not asked again
	// until somebody has used it, rather than once a pass for the rest of
	// the night.
	refused bool
}

fn idle_timeout_ms(minutes int) u64 {
	return if minutes > 0 { u64(minutes) * 60_000 } else { u64(0) }
}

// The count starts from now_ms. A clock that could not be read starts
// nothing; the next look that can read it does.
fn (mut t IdleTimer) restart(now_ms u64) {
	t.started = now_ms != ~u64(0)
	t.last_input_ms = now_ms
	t.last_tick_ms = now_ms
}

// input notes a key or a pointer event and reports whether it is to be
// swallowed. One that finds the display off turns it on and does nothing
// else: it is not also a click on whatever was under the pointer.
fn (mut t IdleTimer) input(now_ms u64) bool {
	swallow := t.phase == .display_off
	t.phase = .active
	t.refused = false
	t.restart(now_ms)
	return swallow
}

// tick is one look at the clock. A step it returns has already been taken
// here: the caller only has to carry it out.
fn (mut t IdleTimer) tick(now_ms u64, display_off_minutes int, sleep_minutes int) IdleStep {
	// A clock that cannot be read decides nothing. The display is not turned
	// off, nor the machine put to sleep, on the strength of a time nobody
	// knows.
	if now_ms == ~u64(0) {
		t.started = false
		return .none_
	}
	if !t.started || now_ms < t.last_tick_ms || now_ms < t.last_input_ms
		|| now_ms - t.last_tick_ms > idle_gap_ms {
		// The first look, a clock that went backwards, or a silence nobody
		// was there for.
		t.refused = false
		t.restart(now_ms)
	}
	t.last_tick_ms = now_ms
	idle := now_ms - t.last_input_ms
	display_due := display_off_minutes > 0 && idle >= idle_timeout_ms(display_off_minutes)
	sleep_due := sleep_minutes > 0 && idle >= idle_timeout_ms(sleep_minutes) && !t.refused
	match t.phase {
		.active {
			// The display goes first even when both are due on one look; the
			// next look asks for the sleep.
			if display_due {
				t.phase = .display_off
				return .display_off
			}
			if sleep_due {
				t.begin_sleep()
				return .sleep
			}
		}
		.display_off {
			// A timeout made longer, or turned off, while the display was
			// off no longer holds it off.
			if !display_due {
				t.phase = .active
				return .display_on
			}
			if sleep_due {
				t.begin_sleep()
				return .sleep
			}
		}
		.asleep {
			// The compositor has not yet said how the sleep ended.
		}
	}
	return .none_
}

// begin_sleep is the machine being put to sleep, by a timeout or because it
// was asked for outright.
fn (mut t IdleTimer) begin_sleep() {
	if t.phase != .asleep {
		t.before_sleep = t.phase
	}
	t.phase = .asleep
}

// woke is the machine back from a sleep. Somebody woke it, or an alarm did,
// and either way it stays up for a whole timeout: the count starts again with
// the display on.
fn (mut t IdleTimer) woke(now_ms u64) {
	t.phase = .active
	t.refused = false
	t.restart(now_ms)
}

// sleep_refused is the machine having stayed awake. Everything is as it was
// before it was asked, display included, and it is not asked again until
// there has been input.
fn (mut t IdleTimer) sleep_refused() {
	if t.phase == .asleep {
		t.phase = t.before_sleep
	}
	t.refused = true
}

// wait_ms is how long the compositor may wait at now_ms before it looks
// again: until the next timeout, and never so long that its own wait would be
// taken for a silence nobody was there for. With nothing to time out it is
// `limit`.
fn (t &IdleTimer) wait_ms(now_ms u64, display_off_minutes int, sleep_minutes int, limit u64) u64 {
	display_ms := idle_timeout_ms(display_off_minutes)
	sleep_ms := if t.refused { u64(0) } else { idle_timeout_ms(sleep_minutes) }
	if t.phase == .asleep || (t.phase == .active && display_ms == 0 && sleep_ms == 0) {
		return limit
	}
	mut wait := idle_gap_ms / 2
	if limit < wait {
		wait = limit
	}
	if !t.started || now_ms == ~u64(0) || now_ms < t.last_input_ms {
		return wait
	}
	idle := now_ms - t.last_input_ms
	// A display that is already off has only the sleep left to wait for.
	if display_ms != 0 && t.phase == .active {
		left := if idle >= display_ms { u64(0) } else { display_ms - idle }
		if left < wait {
			wait = left
		}
	}
	if sleep_ms != 0 {
		left := if idle >= sleep_ms { u64(0) } else { sleep_ms - idle }
		if left < wait {
			wait = left
		}
	}
	return wait
}
