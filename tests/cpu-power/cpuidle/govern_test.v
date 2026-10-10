// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The idle governor's decisions, on the host. govern.v beside this file is
// the kernel's own, linked in.
module cpuidle

// Skylake's C1, C1E, C3 and C6.
fn four_states() [4]StateCost {
	return [StateCost{2, 2}, StateCost{10, 20}, StateCost{70, 100}, StateCost{85, 200}]!
}

fn history_of(values [8]u32) History {
	mut h := History{}
	for v in values {
		h.record(v)
	}
	return h
}

fn test_deepest_state_whose_residency_fits() {
	costs := four_states()
	assert choose_state(&costs[0], 4, 0, 1000, no_limit) == 3
	assert choose_state(&costs[0], 4, 0, 200, no_limit) == 3
	assert choose_state(&costs[0], 4, 0, 199, no_limit) == 2
	assert choose_state(&costs[0], 4, 0, 50, no_limit) == 1
	assert choose_state(&costs[0], 4, 0, 5, no_limit) == 0
}

fn test_shallowest_state_is_used_however_short_the_idle() {
	costs := four_states()
	assert choose_state(&costs[0], 4, 0, 0, no_limit) == 0
	assert choose_state(&costs[0], 4, 0, 1, no_limit) == 0
}

fn test_latency_limit_is_absolute() {
	costs := four_states()
	// C3 takes 70 us to leave.
	assert choose_state(&costs[0], 4, 0, 1000, 69) == 1
	assert choose_state(&costs[0], 4, 0, 1000, 70) == 2
	assert choose_state(&costs[0], 4, 0, 1000, 2) == 0
	// Nothing can be left in a microsecond: poll.
	assert choose_state(&costs[0], 4, 0, 1000, 1) == no_state
	assert choose_state(&costs[0], 4, 0, 1000, 0) == no_state
}

fn test_disabled_states_are_passed_over() {
	costs := four_states()
	assert choose_state(&costs[0], 4, 0b1000, 1000, no_limit) == 2
	assert choose_state(&costs[0], 4, 0b0100, 1000, no_limit) == 3
	assert choose_state(&costs[0], 4, 0b1100, 1000, no_limit) == 1
	// With C1 off, C1E is the shallowest there is, and is used for any idle.
	assert choose_state(&costs[0], 4, 0b0001, 5, no_limit) == 1
	assert choose_state(&costs[0], 4, 0b1111, 1000, no_limit) == no_state
}

fn test_no_states_no_choice() {
	costs := four_states()
	assert choose_state(&costs[0], 0, 0, 1000, no_limit) == no_state
	// One state: the table every guest here has.
	assert choose_state(&costs[0], 1, 0, 1000, no_limit) == 0
	assert choose_state(&costs[0], 1, 1, 1000, no_limit) == no_state
}

fn test_no_history_no_typical_interval() {
	h := History{}
	assert typical_interval_us(&h) == no_limit
	assert predict_us(20000, &h) == 20000
}

fn test_steady_idles_are_typical() {
	h := history_of([u32(200), 200, 200, 200, 200, 200, 200, 200]!)
	assert typical_interval_us(&h) == 200
	// The timer is further off than the CPU has been staying idle.
	assert predict_us(20000, &h) == 200
	// And nearer.
	assert predict_us(150, &h) == 150
}

fn test_small_variation_is_averaged() {
	// Within 20 us of each other: variance at most 400.
	h := history_of([u32(190), 210, 195, 205, 200, 200, 185, 215]!)
	assert typical_interval_us(&h) == 200
}

fn test_long_pauses_among_short_idles_are_set_aside() {
	// menu.c: "workloads that have long pauses interspersed with sporadic
	// activity with a bunch of short pauses".
	h := history_of([u32(100), 100, 20000, 100, 100, 20000, 100, 100]!)
	assert typical_interval_us(&h) == 100
	assert predict_us(20000, &h) == 100
}

fn test_no_pattern_no_correction() {
	h := history_of([u32(10), 5000, 300, 90000, 42, 7000, 1500, 60]!)
	assert typical_interval_us(&h) == no_limit
	assert predict_us(20000, &h) == 20000
}

fn test_history_keeps_the_last_eight() {
	mut h := History{}
	for _ in 0 .. 8 {
		h.record(50000)
	}
	assert typical_interval_us(&h) == 50000
	for _ in 0 .. 8 {
		h.record(300)
	}
	assert typical_interval_us(&h) == 300
	// Longer than 32 bits of microseconds hold: kept as the most they hold.
	h.record(u64(1) << 40)
	assert h.intervals[0] == 0xffffffff
}

fn test_prediction_picks_the_state() {
	costs := four_states()
	// A 20 ms timer, and a CPU that has been woken every 150 us: C3, not C6.
	h := history_of([u32(150), 150, 150, 150, 150, 150, 150, 150]!)
	assert choose_state(&costs[0], 4, 0, predict_us(20000, &h), no_limit) == 2
	// The same timer with nothing known: C6.
	empty := History{}
	assert choose_state(&costs[0], 4, 0, predict_us(20000, &empty), no_limit) == 3
}

fn test_woken_too_soon_is_above() {
	costs := four_states()
	// In C3 (worth it from 100 us) for 50 us, with shallower states to use.
	assert judge(&costs[0], 4, 0, 2, 50) == .above
	assert judge(&costs[0], 4, 0, 2, 100) == .fitting
	// With every shallower state off there was nothing better to choose.
	assert judge(&costs[0], 4, 0b0011, 2, 50) == .fitting
	// The shallowest state cannot be too deep.
	assert judge(&costs[0], 4, 0, 0, 0) == .fitting
}

fn test_stayed_long_enough_for_a_deeper_state_is_below() {
	costs := four_states()
	assert judge(&costs[0], 4, 0, 0, 500) == .below
	assert judge(&costs[0], 4, 0, 0, 19) == .fitting
	// The next deeper state that is on is what counts: C6, from 200 us.
	assert judge(&costs[0], 4, 0b0110, 0, 150) == .fitting
	assert judge(&costs[0], 4, 0b0110, 0, 250) == .below
	// The deepest state cannot be too shallow.
	assert judge(&costs[0], 4, 0, 3, 1000000) == .fitting
	assert judge(&costs[0], 4, 0, 9, 10) == .fitting
}

fn test_counter_arithmetic() {
	// Apple's 24 MHz counter, and a 3 GHz TSC.
	assert ticks_to_us(24, 24000000) == 1
	assert ticks_to_us(24000000, 24000000) == 1000000
	assert ticks_to_us(3000, 3000000000) == 1
	assert ticks_to_us(0, 3000000000) == 0
	assert ticks_to_us(100, 0) == 0
	// Ten days of a 3 GHz counter: ticks * 1000000 would not fit in 64 bits.
	days := u64(10) * 86400
	assert ticks_to_us(days * 3000000000, 3000000000) == days * 1000000
	assert us_to_ticks(20000, 3000000000) == 60000000
	assert us_to_ticks(1, 24000000) == 24
	assert us_to_ticks(no_limit, 3000000000) == no_limit
}
