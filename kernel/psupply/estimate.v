// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// How long a battery will last, and the other figures worked out from what
// it reports rather than read from it.
//
// A battery says how much it holds and, usually, how fast that is changing.
// Dividing one by the other gives a number that jumps with every burst of
// work the machine does: a compile halves it, a pause doubles it. The
// estimate here follows a smoothed rate instead, weighted by how much time
// each sample covers, so that it settles within a couple of minutes of a
// change in how the machine is used and holds still in between. A battery
// that reports no rate at all has one derived from how its charge moves.
//
// Everything in this file is arithmetic on plain values, with no kernel in
// it, so that it can be tested on its own.
module psupply

pub enum Status {
	unknown
	charging
	discharging
	not_charging
	full
}

// Over how long the rate is averaged. A sample covering this long or more
// replaces the average outright.
pub const smoothing_ns = u64(120) * 1000000000

// A rate is only derived from the movement of the charge across at least this
// long: over less, one step of the gauge is most of the measurement.
pub const derive_min_ns = u64(30) * 1000000000

// No estimate longer than this is given. A rate close to zero would otherwise
// promise weeks.
pub const longest_estimate_s = u64(96) * 3600

pub struct Estimator {
pub mut:
	// The smoothed rate, in the battery's units per hour; zero for unknown.
	rate u64
	// Which way the charge was moving when the rate was taken.
	status Status
	// The last sample, for deriving a rate and for weighting the next.
	last_amount u64
	last_ns     u64
	seen        bool
	// Where the derivation last started from.
	mark_amount u64
	mark_ns     u64
}

// Take one sample: the battery holds `amount`, is in `status`, and reports
// `reported_rate` units per hour (zero if it reports none), at time `now_ns`.
// Returns the smoothed rate.
pub fn (mut e Estimator) sample(status Status, amount u64, reported_rate u64, now_ns u64) u64 {
	moving := status == .charging || status == .discharging
	if !moving {
		// Nothing is flowing: there is no rate, and what was known about the
		// last flow says nothing about the next.
		e.rate = 0
		e.status = status
		e.seen = false
		return 0
	}
	if !e.seen || e.status != status {
		// The first sample, or the charger was just plugged in or pulled.
		e.status = status
		e.rate = reported_rate
		e.last_amount = amount
		e.last_ns = now_ns
		e.mark_amount = amount
		e.mark_ns = now_ns
		e.seen = true
		return e.rate
	}
	elapsed := if now_ns > e.last_ns { now_ns - e.last_ns } else { u64(0) }
	mut instant := reported_rate
	if instant == 0 {
		// Derive it from how far the charge has moved since the mark.
		span := if now_ns > e.mark_ns { now_ns - e.mark_ns } else { u64(0) }
		moved := if amount > e.mark_amount { amount - e.mark_amount } else { e.mark_amount - amount }
		if span < derive_min_ns || moved == 0 {
			e.last_amount = amount
			e.last_ns = now_ns
			return e.rate
		}
		instant = scale(moved, 3600 * u64(1000000000), span)
		e.mark_amount = amount
		e.mark_ns = now_ns
	}
	if e.rate == 0 || elapsed >= smoothing_ns {
		e.rate = instant
	} else {
		// new = old + (instant - old) * elapsed / smoothing
		if instant >= e.rate {
			e.rate += scale(instant - e.rate, elapsed, smoothing_ns)
		} else {
			e.rate -= scale(e.rate - instant, elapsed, smoothing_ns)
		}
	}
	e.last_amount = amount
	e.last_ns = now_ns
	return e.rate
}

// a * b / c without overflowing on the way, for the sizes that occur here.
fn scale(a u64, b u64, c u64) u64 {
	if c == 0 {
		return 0
	}
	if a == 0 || b <= ~u64(0) / a {
		return a * b / c
	}
	// Too big to multiply first: divide the larger factor first and lose
	// what the division drops.
	if a > b {
		return a / c * b
	}
	return b / c * a
}

// Seconds until the battery is empty, at the smoothed rate. Zero for unknown.
pub fn (e &Estimator) seconds_to_empty(amount u64) u64 {
	if e.status != .discharging || e.rate == 0 {
		return 0
	}
	return limited(scale(amount, 3600, e.rate))
}

// Seconds until it is full. Zero for unknown.
pub fn (e &Estimator) seconds_to_full(amount u64, full u64) u64 {
	if e.status != .charging || e.rate == 0 || full <= amount {
		return 0
	}
	return limited(scale(full - amount, 3600, e.rate))
}

fn limited(seconds u64) u64 {
	return if seconds > longest_estimate_s { longest_estimate_s } else { seconds }
}

// The charge as a share of what the battery holds when full, 0 to 100, rounded
// to the nearest. -1 when the battery does not say what full is.
pub fn percent_of(amount u64, full u64) int {
	if full == 0 {
		return -1
	}
	if amount >= full {
		return 100
	}
	return int((amount * 100 + full / 2) / full)
}

pub enum Level {
	unknown
	critical
	low
	normal
	high
	full
}

// What Linux calls capacity_level, from the percentage and the two
// thresholds that are policy.
pub fn level_of(percent int, status Status, low int, critical int) Level {
	if percent < 0 {
		return .unknown
	}
	if status == .full || percent >= 100 {
		return .full
	}
	if percent <= critical {
		return .critical
	}
	if percent <= low {
		return .low
	}
	if percent >= 80 {
		return .high
	}
	return .normal
}

// What the machine should do about a battery, given what it reports.
pub enum Alarm {
	none
	// Running on the battery and at or under the low threshold: tell the user.
	low
	// At or under the critical threshold, or the battery itself says it is
	// about to give out: save and stop while there is power to do it with.
	critical
}

pub fn alarm_of(percent int, status Status, firmware_critical bool, low int, critical int) Alarm {
	if status != .discharging {
		// On the charger nothing is urgent, however little is in it.
		return .none
	}
	if firmware_critical || (percent >= 0 && percent <= critical) {
		return .critical
	}
	if percent >= 0 && percent <= low {
		return .low
	}
	return .none
}
