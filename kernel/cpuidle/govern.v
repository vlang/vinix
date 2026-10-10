// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Which idle state a CPU should enter: the decisions, apart from the machine.
//
// An idle state saves more power the deeper it is, and costs more to leave:
// the exit latency is how long the CPU takes to run again, and the target
// residency is how long it has to stay for the saving to outweigh what going
// in and coming out spent. So the question on every idle is how long the CPU
// is about to be idle, and nobody knows. Two things are known. The scheduler
// has armed a timer, and the idle cannot outlast it. And the idles of the last
// moments are a fair guide to the next: a CPU taking a network interrupt every
// 200 us will take another long before a 20 ms timer.
//
// This is the reasoning of Linux's menu governor (drivers/cpuidle/governors/
// menu.c), reduced to those two: the typical recent interval is found the way
// its get_typical_interval() finds it, and the deepest state is chosen whose
// target residency fits the shorter of that and the timer. Menu's correction
// factors and its I/O-wait multiplier are left out; nothing here tracks what
// they are computed from.
//
// Everything in this file is a function of plain values, with no kernel
// imports, so tests/cpu-power runs it on the host.
module cpuidle

// As many states as the deepest table a driver has: Intel's C1 to C10.
pub const max_states = 10

// How many recent idles the prediction looks at, as menu does.
pub const history_intervals = 8

// No idle state may be entered: the CPU polls instead.
pub const no_state = -1

// No latency limit, and no typical interval.
pub const no_limit = ~u64(0)

// What a state costs, in microseconds, as Linux's sysfs reports it.
pub struct StateCost {
pub mut:
	exit_latency_us     u32
	target_residency_us u32
}

// How long this CPU's last idles really were, in microseconds.
pub struct History {
pub mut:
	intervals [history_intervals]u32
	next      u32
}

pub fn (mut h History) record(us u64) {
	h.intervals[h.next % history_intervals] = if us > 0xffffffff { u32(0xffffffff) } else { u32(us) }
	h.next++
}

// The interval the recent idles agree on, or no_limit when they agree on
// none. They agree when they vary little: by 20 us or less, or by less than a
// sixth of their average. If they do not, the longest are set aside and the
// rest asked again -- a CPU with short idles and an occasional long pause has
// a typical short idle -- until a quarter have gone, when there is no pattern.
pub fn typical_interval_us(h &History) u64 {
	mut threshold := u64(0x7fffffff)
	for {
		mut longest := u64(0)
		mut sum := u64(0)
		mut counted := u64(0)
		for i in 0 .. history_intervals {
			value := u64(h.intervals[i])
			if value <= threshold {
				sum += value
				counted++
				if value > longest {
					longest = value
				}
			}
		}
		// Nothing recorded yet, or nothing but idles too short to measure.
		if longest == 0 {
			return no_limit
		}
		average := sum / counted
		mut variance := u64(0)
		for i in 0 .. history_intervals {
			value := u64(h.intervals[i])
			if value <= threshold {
				difference := if value > average { value - average } else { average - value }
				variance += difference * difference
			}
		}
		variance /= counted
		if variance <= no_limit / 36 {
			if (average * average > variance * 36 && counted * 4 >= history_intervals * 3)
				|| variance <= 400 {
				return average
			}
		}
		if counted * 4 <= history_intervals * 3 {
			return no_limit
		}
		threshold = longest - 1
	}
	return no_limit
}

// How long the idle about to start is expected to last: no longer than the
// timer that ends it, and no longer than the recent idles have typically been.
pub fn predict_us(timer_us u64, h &History) u64 {
	typical := typical_interval_us(h)
	return if typical < timer_us { typical } else { timer_us }
}

// The state to enter: the deepest of `count` that is not switched off in
// `disabled` (bit n for state n), that can be left within `latency_limit_us`,
// and whose target residency fits `predicted_us`. States are ordered shallow
// to deep, each costing more than the one before.
//
// The latency limit is absolute: if even the shallowest allowed state takes
// too long to leave, there is none, and the caller polls. The residency is a
// preference: the shallowest state that may be used is used however short the
// idle, since halting for too short a time still beats spinning.
pub fn choose_state(costs &StateCost, count int, disabled u32, predicted_us u64, latency_limit_us u64) int {
	mut chosen := no_state
	for i in 0 .. count {
		if i >= max_states {
			break
		}
		if disabled & (u32(1) << u32(i)) != 0 {
			continue
		}
		cost := unsafe { costs[i] }
		if u64(cost.exit_latency_us) > latency_limit_us {
			break
		}
		if chosen != no_state && u64(cost.target_residency_us) > predicted_us {
			break
		}
		chosen = i
	}
	return chosen
}

// How a finished idle compares with the state chosen for it.
pub enum Verdict {
	fitting
	// Too deep: the CPU woke before the state had paid for itself, and a
	// shallower one was there to use.
	above
	// Too shallow: the CPU stayed long enough for a deeper state.
	below
}

// What Linux's cpuidle_enter_state() counts as `above` and `below`: the next
// shallower and the next deeper state that are switched on are the ones the
// idle is judged against.
pub fn judge(costs &StateCost, count int, disabled u32, entered int, measured_us u64) Verdict {
	if entered < 0 || entered >= count || entered >= max_states {
		return .fitting
	}
	if measured_us < u64(unsafe { costs[entered] }.target_residency_us) {
		for i := entered - 1; i >= 0; i-- {
			if disabled & (u32(1) << u32(i)) == 0 {
				return .above
			}
		}
		return .fitting
	}
	for i := entered + 1; i < count && i < max_states; i++ {
		if disabled & (u32(1) << u32(i)) != 0 {
			continue
		}
		if measured_us >= u64(unsafe { costs[i] }.target_residency_us) {
			return .below
		}
		break
	}
	return .fitting
}

// `ticks` of a counter running at `hz`, in microseconds. The whole seconds
// are taken out first, so hours of a gigahertz counter do not overflow.
pub fn ticks_to_us(ticks u64, hz u64) u64 {
	if hz == 0 {
		return 0
	}
	return ticks / hz * 1000000 + ticks % hz * 1000000 / hz
}

// The other way, for a deadline. Saturates rather than wrapping.
pub fn us_to_ticks(us u64, hz u64) u64 {
	if hz != 0 && us > no_limit / hz {
		return no_limit
	}
	return us * hz / 1000000
}
