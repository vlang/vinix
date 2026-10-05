// SPDX-License-Identifier: GPL-2.0-or-later
module time

// Integer clock discipline. Frequency is Linux's signed 16.16 ppm; limiting
// both frequency and phase slews to 500 ppm keeps every clock sample moving
// forward. The state is held inline under clock_lock, with no heap allocation.
pub const max_clock_frequency = i64(500 * 65536)
const frequency_denominator = i64(65536000000)

pub struct ClockDiscipline {
pub mut:
	last_raw            TimeSpec
	monotonic           TimeSpec
	realtime            TimeSpec
	frequency           i64
	frequency_remainder i64
	slew_remaining      i64
	slew_remainder      i64
}

fn add_signed_ns(mut value TimeSpec, ns i64) {
	value.tv_sec += ns / 1000000000
	value.tv_nsec += ns % 1000000000
	if value.tv_nsec >= 1000000000 {
		value.tv_sec++
		value.tv_nsec -= 1000000000
	} else if value.tv_nsec < 0 {
		value.tv_sec--
		value.tv_nsec += 1000000000
	}
}

fn timespec_before(a TimeSpec, b TimeSpec) bool {
	return a.tv_sec < b.tv_sec || (a.tv_sec == b.tv_sec && a.tv_nsec < b.tv_nsec)
}

pub fn (mut clock ClockDiscipline) sample(raw TimeSpec) {
	if timespec_before(raw, clock.last_raw) {
		return
	}
	mut seconds := raw.tv_sec - clock.last_raw.tv_sec
	mut nanos := raw.tv_nsec - clock.last_raw.tv_nsec
	if nanos < 0 {
		seconds--
		nanos += 1000000000
	}
	if seconds == 0 && nanos == 0 {
		return
	}
	clock.last_raw = raw
	// Divide before multiplying to avoid overflowing at ordinary uptimes.
	// The remaining product fits at the maximum accepted frequency.
	delta := seconds * 1000000000 + nanos
	whole := (delta / frequency_denominator) * clock.frequency
	mut fraction := (delta % frequency_denominator) * clock.frequency + clock.frequency_remainder
	mut slew := i64(0)
	if clock.slew_remaining != 0 {
		old_remainder := clock.slew_remainder
		budget := delta + old_remainder
		slew = budget / 2000
		clock.slew_remainder = budget % 2000
		direction := if clock.slew_remaining < 0 { i64(-1) } else { i64(1) }
		slew *= direction
		if direction < 0 && slew <= clock.slew_remaining {
			slew = clock.slew_remaining
			clock.slew_remainder = 0
		} else if direction > 0 && slew >= clock.slew_remaining {
			slew = clock.slew_remaining
			clock.slew_remainder = 0
		}
		clock.slew_remaining -= slew
		// Combine sub-nanosecond phase and frequency fractions before
		// rounding. Separate rounding can make a 1 ns sample step backwards.
		fraction += direction * (clock.slew_remainder - old_remainder) * (frequency_denominator / 2000)
	}
	correction := whole + fraction / frequency_denominator
	clock.frequency_remainder = fraction % frequency_denominator
	adjusted := delta + correction + slew
	add_signed_ns(mut clock.monotonic, adjusted)
	add_signed_ns(mut clock.realtime, adjusted)
}

pub fn (mut clock ClockDiscipline) set_realtime(value TimeSpec, forbid_backwards bool) bool {
	if value.tv_sec < 0 || value.tv_nsec < 0 || value.tv_nsec >= 1000000000 {
		return false
	}
	if forbid_backwards && timespec_before(value, clock.realtime) {
		return false
	}
	clock.realtime = value
	return true
}

pub fn (mut clock ClockDiscipline) set_frequency(value i64) bool {
	if value < -max_clock_frequency || value > max_clock_frequency {
		return false
	}
	clock.frequency = value
	clock.frequency_remainder = 0
	return true
}

pub fn (mut clock ClockDiscipline) set_slew(value i64) i64 {
	previous := clock.slew_remaining
	clock.slew_remaining = value
	clock.slew_remainder = 0
	return previous
}
