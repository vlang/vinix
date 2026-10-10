// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What thermal management decides, kept apart from the machine it decides
// for.
//
// A zone is one temperature and the trip points it is held against. Each
// reading of it goes through judge_reading(), which says how far the CPUs
// have to be held back for this zone, and each failed reading through
// judge_failure(). Both take what the zone looked like before and return what
// it looks like now: plain values in, plain values out, so that the tests in
// tests/thermal run every trace on the machine the kernel is built on.
//
// The policy is Linux's step-wise governor (drivers/thermal/gov_step_wise.c),
// with one cooling device: the limit on CPU performance, in steps of ten
// points of a hundred.
//
//	above passive, and rising          one step further down
//	above passive, steady or falling   hold
//	inside the hysteresis below it     hold
//	below passive - hysteresis         one step back up
//	at hot                             the lowest limit at once
//	at critical                        the same, and the critical handler, once
//
// Linux gives a step back only while the temperature is falling. A reading
// that sits still below the trip would hold the limit for good there, so here
// being below the hysteresis is enough.
//
// Nothing in this file may import the kernel.
module thermal

pub enum TripKind {
	passive
	hot
	critical
}

// A temperature at which something is done, in millidegrees Celsius, and how
// far below it the temperature has to fall before that is undone.
pub struct Trip {
pub mut:
	kind        TripKind
	temperature i64
	hysteresis  i64
}

// Trip points a zone may have.
pub const max_trips = 4

// The limit goes down by this much for each step, in points of a hundred.
pub const limit_step = u32(10)

// The least share of its performance a CPU is ever left with.
pub const lowest_limit = u32(10)

// The deepest step: cooling_device0/max_state.
pub const deepest_state = (100 - lowest_limit) / limit_step

// A sensor that has failed this many times in a row is switched off.
pub const failure_limit = u32(5)

// No temperature is below this, so a reading that is was not one.
pub const absolute_zero = i64(-273150)

// The limit step `state` stands for: cpufreq.set_thermal_limit()'s percent.
pub fn limit_of_state(state u32) u32 {
	steps := if state > deepest_state { deepest_state } else { state }
	return 100 - steps * limit_step
}

// The trips of a zone, as the policy sees them: the lowest of each kind.
pub struct Thresholds {
pub mut:
	has_passive   bool
	passive       i64
	passive_hyst  i64
	has_hot       bool
	hot           i64
	hot_hyst      i64
	has_critical  bool
	critical      i64
	critical_hyst i64
}

pub fn thresholds_of(trips &Trip, count int) Thresholds {
	mut found := Thresholds{}
	for i in 0 .. count {
		trip := unsafe { trips[i] }
		hysteresis := if trip.hysteresis < 0 { i64(0) } else { trip.hysteresis }
		match trip.kind {
			.passive {
				if !found.has_passive || trip.temperature < found.passive {
					found.has_passive = true
					found.passive = trip.temperature
					found.passive_hyst = hysteresis
				}
			}
			.hot {
				if !found.has_hot || trip.temperature < found.hot {
					found.has_hot = true
					found.hot = trip.temperature
					found.hot_hyst = hysteresis
				}
			}
			.critical {
				if !found.has_critical || trip.temperature < found.critical {
					found.has_critical = true
					found.critical = trip.temperature
					found.critical_hyst = hysteresis
				}
			}
		}
	}
	return found
}

// What is remembered of a zone from one reading to the next.
pub struct ZoneState {
pub mut:
	// How many steps this zone holds the limit down by.
	steps u32
	// The last temperature read, if one has been.
	has_last bool
	last     i64
	// Readings that failed since the last one that did not.
	failures u32
	// Too many: the zone is switched off until someone switches it on again.
	faulted bool
	// At or above the hot trip, and not yet below its hysteresis.
	hot bool
	// The same for the critical trip: the handler has been called.
	critical bool
}

// What a reading leads to: the zone as it is now, and what the caller has to
// do about it that is not a number.
pub struct Verdict {
pub mut:
	state         ZoneState
	log_hot       bool
	fire_critical bool
	// The zone has just been switched off for its failures.
	fault bool
}

// A reading of `temperature` for a zone that was in `state`.
pub fn judge_reading(state ZoneState, limits Thresholds, temperature i64) Verdict {
	mut verdict := Verdict{
		state: state
	}
	verdict.state.failures = 0
	rising := state.has_last && temperature > state.last
	mut at_hot := false

	if limits.has_critical {
		if temperature >= limits.critical {
			at_hot = true
			if !state.critical {
				verdict.fire_critical = true
				verdict.state.critical = true
			}
		} else if temperature < limits.critical - limits.critical_hyst {
			verdict.state.critical = false
		}
	}
	if limits.has_hot {
		if temperature >= limits.hot {
			at_hot = true
			if !state.hot {
				verdict.log_hot = true
				verdict.state.hot = true
			}
		} else if temperature < limits.hot - limits.hot_hyst {
			verdict.state.hot = false
		}
	}

	if at_hot {
		verdict.state.steps = deepest_state
	} else if limits.has_passive {
		if temperature >= limits.passive {
			// The first reading above the trip takes a step whatever the
			// trend, as Linux has it for an instance not yet throttling.
			if (state.steps == 0 || rising) && state.steps < deepest_state {
				verdict.state.steps = state.steps + 1
			}
		} else if temperature < limits.passive - limits.passive_hyst {
			if state.steps > 0 {
				verdict.state.steps = state.steps - 1
			}
		}
	} else if state.steps > 0 {
		// No passive trip: what the hot or critical trip took is given back
		// once the temperature is below that trip's hysteresis.
		below := if limits.has_hot {
			temperature < limits.hot - limits.hot_hyst
		} else if limits.has_critical {
			temperature < limits.critical - limits.critical_hyst
		} else {
			true
		}
		if below {
			verdict.state.steps = state.steps - 1
		}
	}

	verdict.state.has_last = true
	verdict.state.last = temperature
	return verdict
}

// A reading that failed. It is not a temperature: the limit stays where it
// was, and after failure_limit of them in a row the zone is switched off
// rather than steered by the last thing it said.
pub fn judge_failure(state ZoneState) Verdict {
	mut verdict := Verdict{
		state: state
	}
	if state.faulted {
		return verdict
	}
	verdict.state.failures = state.failures + 1
	if verdict.state.failures >= failure_limit {
		verdict.state.faulted = true
		verdict.fault = true
	}
	return verdict
}

// A zone switched on again: its failures are forgotten and its next reading
// is the first, with no trend. The limit it holds is given back by the
// readings that follow, a step at a time.
pub fn rearm(state ZoneState) ZoneState {
	mut fresh := state
	fresh.failures = 0
	fresh.faulted = false
	fresh.has_last = false
	return fresh
}

// Whether a zone in `state` wants looking at more often than once a second:
// it is holding the limit down, which it does from its first reading above
// the passive trip until the last step has been given back.
pub fn wants_fast_polling(state ZoneState) bool {
	return !state.faulted && state.steps > 0
}

// The signed decimal number in `word`, or none if it is anything else.
pub fn parse_signed(word string) ?i64 {
	// Eighteen digits and a sign: nothing that long overflows.
	if word.len == 0 || word.len > 19 {
		return none
	}
	mut index := 0
	mut negative := false
	if word[0] == `-` || word[0] == `+` {
		negative = word[0] == `-`
		index = 1
	}
	if index == word.len || word.len - index > 18 {
		return none
	}
	mut value := i64(0)
	for index < word.len {
		digit := word[index]
		if digit < `0` || digit > `9` {
			return none
		}
		value = value * 10 + i64(digit - `0`)
		index++
	}
	return if negative { -value } else { value }
}
