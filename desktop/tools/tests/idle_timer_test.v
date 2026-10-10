// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

const idle_minute = u64(60_000)
const idle_lost_clock = ~u64(0)

// The compositor looks at the clock at least this often while a timeout is
// set, which is what wait_ms allows it.
const idle_test_pass = idle_gap_ms / 2

// run_idle looks at the clock once a pass from `from` to `until` and returns
// the steps that were asked for on the way, each with the time it came at.
fn run_idle(mut timer IdleTimer, from u64, until u64, display_off int, sleep int) ([]IdleStep, []u64) {
	mut steps := []IdleStep{}
	mut times := []u64{}
	mut now := from
	for now <= until {
		step := timer.tick(now, display_off, sleep)
		if step != .none_ {
			steps << step
			times << now
		}
		now += idle_test_pass
	}
	return steps, times
}

fn test_idle_timer_turns_the_display_off_and_then_sleeps() {
	mut timer := IdleTimer{}
	assert timer.phase == .active && !timer.started
	// The first look starts the count; nothing is due at once.
	assert timer.tick(1000, 10, 30) == .none_
	assert timer.started && timer.last_input_ms == 1000
	steps, times := run_idle(mut timer, 1000, 1000 + 40 * idle_minute, 10, 30)
	assert steps == [IdleStep.display_off, .sleep]
	assert times == [1000 + 10 * idle_minute, 1000 + 30 * idle_minute]
	assert timer.phase == .asleep && timer.before_sleep == .display_off
	// Asleep, it asks for nothing more until told how the sleep ended.
	assert timer.tick(1000 + 41 * idle_minute, 10, 30) == .none_

	// The machine wakes with its display on and a whole timeout ahead of it.
	woke_at := 1000 + 50 * idle_minute
	timer.woke(woke_at)
	assert timer.phase == .active && timer.last_input_ms == woke_at
	again, again_at := run_idle(mut timer, woke_at, woke_at + 40 * idle_minute, 10, 30)
	assert again == [IdleStep.display_off, .sleep]
	assert again_at == [woke_at + 10 * idle_minute, woke_at + 30 * idle_minute]
}

fn test_idle_timer_each_timeout_may_be_never() {
	// Never for both: a day goes by and nothing is asked.
	mut timer := IdleTimer{}
	mut steps, _ := run_idle(mut timer, 0, 24 * 60 * idle_minute, 0, 0)
	assert steps.len == 0 && timer.phase == .active

	// The display only.
	timer = IdleTimer{}
	steps, _ = run_idle(mut timer, 0, 24 * 60 * idle_minute, 1, 0)
	assert steps == [IdleStep.display_off] && timer.phase == .display_off

	// Sleep only: straight from active, with the display never turned off.
	timer = IdleTimer{}
	mut times := []u64{}
	steps, times = run_idle(mut timer, 0, 20 * idle_minute, 0, 15)
	assert steps == [IdleStep.sleep] && times == [15 * idle_minute]
	assert timer.phase == .asleep && timer.before_sleep == .active

	// Both due on the same look: the display first, the sleep on the next.
	timer = IdleTimer{}
	steps, times = run_idle(mut timer, 0, 10 * idle_minute, 5, 5)
	assert steps == [IdleStep.display_off, .sleep]
	assert times == [5 * idle_minute, 5 * idle_minute + idle_test_pass]

	// Every pair Settings can produce turns the display off no later than
	// the machine sleeps.
	for display_off in idle_timeout_choices {
		for sleep in idle_timeout_choices {
			if !idle_timeouts_valid(display_off, sleep) {
				continue
			}
			timer = IdleTimer{}
			steps, times = run_idle(mut timer, 0, 61 * idle_minute, display_off, sleep)
			mut want := []IdleStep{}
			if display_off != 0 {
				want << IdleStep.display_off
			}
			if sleep != 0 {
				want << IdleStep.sleep
			}
			assert steps == want, '${display_off} ${sleep}'
			if display_off != 0 {
				assert times[0] == u64(display_off) * idle_minute
			}
			if sleep != 0 {
				assert times.last() >= u64(sleep) * idle_minute
				assert times.last() <= u64(sleep) * idle_minute + idle_test_pass
			}
		}
	}
	// A timeout that is not a time is never.
	timer = IdleTimer{}
	steps, _ = run_idle(mut timer, 0, 60 * idle_minute, -5, -1)
	assert steps.len == 0
}

fn test_idle_timer_input_restarts_the_count_and_wakes_the_display() {
	mut timer := IdleTimer{}
	timer.tick(0, 2, 5)
	// Input while the display is on is the application's: not swallowed.
	assert !timer.input(90_000)
	assert timer.last_input_ms == 90_000 && timer.phase == .active
	// The two minutes count from that input, not from the start.
	mut steps, mut times := run_idle(mut timer, 90_000, 4 * idle_minute, 2, 5)
	assert steps == [IdleStep.display_off] && times == [90_000 + 2 * idle_minute]

	// The input that finds the display off turns it on and is swallowed.
	assert timer.input(4 * idle_minute + 1)
	assert timer.phase == .active && timer.last_input_ms == 4 * idle_minute + 1
	// The next one is delivered as usual.
	assert !timer.input(4 * idle_minute + 2)
	// And the sleep that was two minutes away is five minutes away again.
	steps, times = run_idle(mut timer, 4 * idle_minute + 2, 12 * idle_minute, 2, 5)
	assert steps == [IdleStep.display_off, .sleep]
	assert times[0] == 4 * idle_minute + 2 + 2 * idle_minute
	assert times[1] == 4 * idle_minute + 2 + 5 * idle_minute

	// Steady input never lets either timeout arrive.
	timer = IdleTimer{}
	mut now := u64(0)
	for now < 30 * idle_minute {
		assert timer.tick(now, 1, 2) == .none_
		assert !timer.input(now)
		now += 30_000
	}
	assert timer.phase == .active
}

fn test_idle_timer_follows_timeouts_changed_while_idle() {
	// Shortened under a display that has been idle longer: off on the next
	// look.
	mut timer := IdleTimer{}
	mut steps, mut times := run_idle(mut timer, 0, 3 * idle_minute, 10, 0)
	assert steps.len == 0
	assert timer.tick(3 * idle_minute + 1000, 2, 0) == .display_off
	// Lengthened past the time idle: the display comes back on, and goes off
	// again when the longer timeout arrives. Nothing is swallowed for it.
	assert timer.tick(3 * idle_minute + 2000, 5, 0) == .display_on
	assert timer.phase == .active && timer.last_input_ms == 0
	steps, times = run_idle(mut timer, 3 * idle_minute + 2000, 6 * idle_minute, 5, 0)
	assert steps == [IdleStep.display_off]
	assert times[0] >= 5 * idle_minute && times[0] < 5 * idle_minute + idle_test_pass
	// Turned off altogether while the display is off.
	assert timer.tick(6 * idle_minute + 1000, 0, 0) == .display_on
	assert timer.tick(6 * idle_minute + 2000, 0, 0) == .none_
	assert !timer.input(6 * idle_minute + 3000)

	// A sleep timeout set while the display is off and already overdue.
	timer = IdleTimer{}
	steps, _ = run_idle(mut timer, 0, idle_minute, 1, 0)
	assert steps == [IdleStep.display_off]
	assert timer.tick(idle_minute + 5000, 1, 0) == .none_
	assert timer.tick(idle_minute + 10_000, 1, 1) == .sleep
	assert timer.before_sleep == .display_off
	// One made never while idle no longer arrives.
	timer = IdleTimer{}
	steps, _ = run_idle(mut timer, 0, 4 * idle_minute + 55_000, 0, 5)
	assert steps.len == 0
	steps, _ = run_idle(mut timer, 5 * idle_minute, 60 * idle_minute, 0, 0)
	assert steps.len == 0 && timer.phase == .active
}

fn test_idle_timer_a_backwards_or_lost_clock_decides_nothing() {
	// Backwards: the count starts again from the look that noticed.
	mut timer := IdleTimer{}
	timer.tick(100 * idle_minute, 10, 30)
	assert timer.tick(100 * idle_minute + 5000, 10, 30) == .none_
	assert timer.tick(50 * idle_minute, 10, 30) == .none_
	assert timer.last_input_ms == 50 * idle_minute && timer.phase == .active
	mut steps, mut times := run_idle(mut timer, 50 * idle_minute, 70 * idle_minute, 10, 30)
	assert steps == [IdleStep.display_off] && times == [60 * idle_minute]
	// Backwards under a display that is off: with nothing idle any more, it
	// comes back on.
	assert timer.tick(10 * idle_minute, 10, 30) == .display_on
	assert timer.phase == .active && timer.last_input_ms == 10 * idle_minute

	// An input stamped later than the next look: the same.
	timer = IdleTimer{}
	timer.tick(0, 10, 0)
	timer.input(9 * idle_minute)
	assert timer.tick(8 * idle_minute, 10, 0) == .none_
	assert timer.last_input_ms == 8 * idle_minute

	// A clock that cannot be read turns nothing off and puts nothing to
	// sleep, however long that goes on.
	timer = IdleTimer{}
	timer.tick(0, 1, 2)
	for _ in 0 .. 1000 {
		assert timer.tick(idle_lost_clock, 1, 2) == .none_
	}
	assert timer.phase == .active && !timer.started
	// When it reads again the count starts there.
	assert timer.tick(500 * idle_minute, 1, 2) == .none_
	assert timer.started && timer.last_input_ms == 500 * idle_minute
	steps, times = run_idle(mut timer, 500 * idle_minute, 501 * idle_minute, 1, 2)
	assert steps == [IdleStep.display_off] && times == [501 * idle_minute]
	// Lost while the display is off: it stays off, and input still wakes it.
	assert timer.tick(idle_lost_clock, 1, 2) == .none_
	assert timer.phase == .display_off
	assert timer.input(idle_lost_clock)
	assert timer.phase == .active && !timer.started
	assert timer.tick(600 * idle_minute, 1, 2) == .none_
	assert timer.last_input_ms == 600 * idle_minute
}

fn test_idle_timer_a_silence_nobody_was_there_for_is_not_idleness() {
	// The kernel put the machine to sleep by itself for an hour, or a
	// virtual machine was paused: on the look after, nothing is overdue.
	mut timer := IdleTimer{}
	timer.tick(0, 10, 30)
	assert timer.tick(5000, 10, 30) == .none_
	assert timer.tick(5000 + 60 * idle_minute, 10, 30) == .none_
	assert timer.phase == .active && timer.last_input_ms == 5000 + 60 * idle_minute
	// With the display off beforehand, it comes on: somebody opened the lid.
	mut steps, _ := run_idle(mut timer, 5000 + 60 * idle_minute, 5000 + 71 * idle_minute,
		10, 30)
	assert steps == [IdleStep.display_off]
	assert timer.tick(5000 + 200 * idle_minute, 10, 30) == .display_on
	// Looks no further apart than the gap are ordinary passes.
	timer = IdleTimer{}
	timer.tick(0, 1, 0)
	mut now := u64(0)
	for now < idle_minute {
		assert timer.tick(now, 1, 0) == .none_
		now += idle_gap_ms
	}
	assert timer.tick(now, 1, 0) == .display_off
}

fn test_idle_timer_a_refused_sleep_is_not_asked_for_again() {
	// From a display that was off: it stays off, and the sleep is not asked
	// for on every look for the rest of the night.
	mut timer := IdleTimer{}
	timer.tick(0, 1, 2)
	mut steps, _ := run_idle(mut timer, 0, 2 * idle_minute, 1, 2)
	assert steps == [IdleStep.display_off, .sleep]
	timer.sleep_refused()
	assert timer.phase == .display_off && timer.refused
	steps, _ = run_idle(mut timer, 2 * idle_minute, 600 * idle_minute, 1, 2)
	assert steps.len == 0 && timer.phase == .display_off
	// Input clears it: the waking input is swallowed, and the machine is
	// asked again after another whole timeout.
	assert timer.input(600 * idle_minute)
	assert !timer.refused
	mut times := []u64{}
	steps, times = run_idle(mut timer, 600 * idle_minute, 603 * idle_minute, 1, 2)
	assert steps == [IdleStep.display_off, .sleep]
	assert times == [601 * idle_minute, 602 * idle_minute]

	// From the display on, as when Sleep is chosen from the menu.
	timer = IdleTimer{}
	timer.tick(0, 10, 0)
	timer.begin_sleep()
	assert timer.phase == .asleep && timer.before_sleep == .active
	// Asked for twice, it still goes back to where it was.
	timer.begin_sleep()
	timer.sleep_refused()
	assert timer.phase == .active && timer.refused
	// The display's own timeout is untouched by the refusal.
	steps, _ = run_idle(mut timer, 0, 11 * idle_minute, 10, 0)
	assert steps == [IdleStep.display_off]
	// A sleep from the menu that works.
	timer = IdleTimer{}
	timer.tick(0, 10, 30)
	timer.begin_sleep()
	timer.woke(90 * idle_minute)
	assert timer.phase == .active && !timer.refused && timer.last_input_ms == 90 * idle_minute
	assert timer.tick(90 * idle_minute + 1000, 10, 30) == .none_
	// Refused with nothing asleep changes no phase.
	timer = IdleTimer{}
	timer.sleep_refused()
	assert timer.phase == .active && timer.refused
}

fn test_idle_timer_wait_reaches_each_timeout_on_time() {
	hour := u64(60) * idle_minute
	mut timer := IdleTimer{}
	// Nothing to time out: the caller's own limit.
	assert timer.wait_ms(0, 0, 0, hour) == hour
	// Before the first look there is nothing to count from; soon.
	assert timer.wait_ms(0, 10, 0, hour) == idle_gap_ms / 2
	timer.tick(0, 10, 30)
	// Never longer than half the gap, or the wait itself would restart the
	// count; never longer than the caller allows.
	assert timer.wait_ms(0, 10, 30, hour) == idle_gap_ms / 2
	assert timer.wait_ms(0, 10, 30, 250) == 250
	// Exactly up to the display's timeout, then to the sleep's.
	assert timer.wait_ms(10 * idle_minute - 1200, 10, 30, hour) == 1200
	assert timer.wait_ms(10 * idle_minute, 10, 30, hour) == 0
	mut steps, _ := run_idle(mut timer, 0, 10 * idle_minute - idle_test_pass, 10, 30)
	assert steps.len == 0
	assert timer.tick(10 * idle_minute, 10, 30) == .display_off
	assert timer.wait_ms(10 * idle_minute, 10, 30, hour) == idle_gap_ms / 2
	assert timer.wait_ms(30 * idle_minute - 7, 10, 30, hour) == 7
	assert timer.wait_ms(30 * idle_minute + 7, 10, 30, hour) == 0
	// A display that is off with no sleep to come still looks often enough
	// to tell a pause from idleness.
	assert timer.wait_ms(11 * idle_minute, 10, 0, hour) == idle_gap_ms / 2
	// Equal timeouts: the sleep is still waited for once the display is off.
	timer = IdleTimer{}
	steps, _ = run_idle(mut timer, 0, 5 * idle_minute, 5, 5)
	assert steps == [IdleStep.display_off] && timer.phase == .display_off
	assert timer.wait_ms(5 * idle_minute, 5, 5, hour) == 0
	// Asleep, or refused with nothing else to wait for, it is the limit.
	timer.begin_sleep()
	assert timer.wait_ms(6 * idle_minute, 5, 5, hour) == hour
	timer = IdleTimer{}
	timer.tick(0, 0, 5)
	timer.begin_sleep()
	timer.sleep_refused()
	assert timer.wait_ms(6 * idle_minute, 0, 5, hour) == hour
	// A clock that cannot be read, or that went backwards: soon.
	timer = IdleTimer{}
	timer.tick(1000, 10, 0)
	assert timer.wait_ms(idle_lost_clock, 10, 0, hour) == idle_gap_ms / 2
	assert timer.wait_ms(500, 10, 0, hour) == idle_gap_ms / 2
	// A simulated compositor that waits as long as it is allowed never
	// misses a timeout by more than a pass, and never restarts the count.
	timer = IdleTimer{}
	mut now := u64(0)
	mut at := []u64{}
	for now < 31 * idle_minute {
		step := timer.tick(now, 10, 30)
		if step != .none_ {
			at << now
		}
		if step == .sleep {
			break
		}
		wait := timer.wait_ms(now, 10, 30, hour)
		now += if wait == 0 { u64(1) } else { wait }
	}
	assert at == [10 * idle_minute, 30 * idle_minute]
}
