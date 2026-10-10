// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// kernel/thermal/energy.v: a 32-bit energy register added up in 64 bits, and
// the power between two samples of the sum.
module thermal

// 2^-14 J: the unit of most Intel processors, in nanojoules.
const unit_14 = u64(61035)

const mask_32 = u64(0xffffffff)

fn test_first_reading_is_the_register_itself() {
	counter := EnergyCounter{}.advanced(1000, mask_32, unit_14)
	assert counter.primed
	assert counter.last_raw == 1000
	assert counter.microjoules == 61035
	assert counter.remainder == 0
}

fn test_differences_add_up_with_the_remainder_carried() {
	mut counter := EnergyCounter{}.advanced(0, mask_32, unit_14)
	assert counter.microjoules == 0
	// 3 counts are 183 105 nJ: 183 uJ and 105 nJ over.
	counter = counter.advanced(3, mask_32, unit_14)
	assert counter.microjoules == 183 && counter.remainder == 105
	// 10 more are 610 350 nJ, and with the 105: 610 uJ and 455 nJ over.
	counter = counter.advanced(13, mask_32, unit_14)
	assert counter.microjoules == 793 && counter.remainder == 455
	// A register that has not moved adds nothing.
	counter = counter.advanced(13, mask_32, unit_14)
	assert counter.microjoules == 793 && counter.remainder == 455
}

fn test_one_wrap_between_two_readings_is_counted_right() {
	mut counter := EnergyCounter{}.advanced(0xfffffff0, mask_32, 1000)
	before := counter.microjoules
	assert before == 0xfffffff0
	counter = counter.advanced(0x10, mask_32, 1000)
	// 0x20 counts of a microjoule each, across the wrap.
	assert counter.microjoules - before == 0x20
	assert counter.last_raw == 0x10
	// The sum is past what the register can hold.
	assert counter.microjoules > mask_32
}

fn test_bits_above_the_register_are_ignored() {
	mut counter := EnergyCounter{}.advanced(0xdead00000005, mask_32, 1000)
	assert counter.last_raw == 5 && counter.microjoules == 5
	counter = counter.advanced(0xbeef00000009, mask_32, 1000)
	assert counter.microjoules == 9
}

fn test_many_wraps_add_up_to_the_exact_total() {
	// A register that advances by 0x60000000 between readings wraps three
	// times in every eight readings.
	mut counter := EnergyCounter{}.advanced(0, mask_32, unit_14)
	mut raw := u64(0)
	mut wraps := 0
	for _ in 0 .. 1000 {
		next := (raw + 0x60000000) & mask_32
		if next < raw {
			wraps++
		}
		raw = next
		counter = counter.advanced(raw, mask_32, unit_14)
	}
	assert wraps == 375
	counts := u64(1000) * 0x60000000
	assert counter.microjoules == counts * unit_14 / 1000
	assert counter.remainder == counts * unit_14 % 1000
}

fn test_register_range() {
	assert register_range_microjoules(mask_32, unit_14) == mask_32 * unit_14 / 1000
	assert register_range_microjoules(mask_32, 1000) == mask_32
}

fn sample(microjoules u64, nanoseconds u64) EnergySample {
	return EnergySample{
		valid:       true
		microjoules: microjoules
		nanoseconds: nanoseconds
	}
}

fn milliwatts(before EnergySample, after EnergySample) i64 {
	power := average_milliwatts(before, after) or { return -1 }
	return i64(power)
}

fn test_average_power() {
	// 15 J in a second.
	assert milliwatts(sample(1000000, 5000000000), sample(16000000, 6000000000)) == 15000
	// 3.75 J in a quarter of one.
	assert milliwatts(sample(0, 0), sample(3750000, 250000000)) == 15000
	// Nothing used.
	assert milliwatts(sample(7, 1), sample(7, 1000000001)) == 0
}

fn test_average_power_needs_two_samples_and_time_between_them() {
	assert milliwatts(EnergySample{}, sample(5, 5)) == -1
	assert milliwatts(sample(5, 5), EnergySample{}) == -1
	assert milliwatts(sample(5, 5), sample(9, 5)) == -1
	assert milliwatts(sample(5, 9), sample(9, 5)) == -1
	assert milliwatts(sample(9, 5), sample(5, 9)) == -1
}
