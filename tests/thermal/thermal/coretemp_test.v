// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// kernel/thermal/coretemp_decode_amd64.v against the rules of Linux's
// coretemp.c: the status register, TjMax from its register, from the tables
// and from the guess, and the package zone's trips.
module thermal

const valid_bit = u64(1) << 31

// A status register that reads `readout` degrees below TjMax.
fn status_of(readout u64) u64 {
	return valid_bit | (readout << 16)
}

fn test_status_bits() {
	decoded := dts_decode(status_of(37) | 0x33)
	assert decoded.valid && decoded.readout == 37
	assert decoded.prochot && decoded.prochot_log
	assert decoded.critical && decoded.critical_log
	quiet := dts_decode(u64(0x7f) << 16)
	assert !quiet.valid && quiet.readout == 0x7f
	assert !quiet.prochot && !quiet.prochot_log && !quiet.critical && !quiet.critical_log
	// Only seven bits are the readout: bit 23 is not.
	assert dts_decode(u64(1) << 23).readout == 0
}

fn test_core_temperature_ignores_the_valid_bit() {
	assert coretemp_temperature(status_of(30), 100000) == 70000
	assert coretemp_temperature(u64(30) << 16, 100000) == 70000
	assert coretemp_temperature(status_of(0), 105000) == 105000
	assert coretemp_temperature(status_of(127), 100000) == -27000
}

fn zone_temperature(status u64) i64 {
	return dts_zone_temperature(status, 100000, 105000) or { i64(-1) }
}

fn test_zone_temperature_needs_the_valid_bit() {
	assert zone_temperature(status_of(25)) == 75000
	assert zone_temperature(status_of(0)) == 100000
	assert zone_temperature(u64(25) << 16) == -1
	assert zone_temperature(0) == -1
}

fn test_the_critical_status_bit_reaches_the_critical_trip() {
	// The sensor stops at TjMax; the processor's own "critical" does not.
	assert zone_temperature(status_of(0) | (u64(1) << 4)) == 105000
	assert zone_temperature(status_of(3) | (u64(1) << 4)) == 105000
	// The log bit says it has been critical, not that it is.
	assert zone_temperature(status_of(3) | (u64(1) << 5)) == 97000
	// And PROCHOT is the processor throttling itself, which is not critical.
	assert zone_temperature(status_of(0) | 1) == 100000
}

fn test_temperature_target_register() {
	target := (u64(100) << 16) | (u64(15) << 8)
	assert coretemp_target_tjmax(target) == 100000
	assert coretemp_target_ttarget(target) == 85000
	assert coretemp_target_tjmax(u64(0x69) << 16) == 105000
	assert coretemp_target_tjmax(0) == 0
	// Bits above 23 are the TCC offset and a lock, not TjMax.
	assert coretemp_target_tjmax((u64(0x8a) << 24) | (u64(90) << 16)) == 90000
}

fn test_models_with_a_tjmax_register() {
	assert coretemp_has_tjmax(0x1a)
	assert coretemp_has_tjmax(0x5e)
	assert coretemp_has_tjmax(0xf)
	for model in [u32(0xe), 0x1c, 0x26, 0x27, 0x35, 0x36, 0x9] {
		assert !coretemp_has_tjmax(model)
	}
}

fn test_tjmax_comes_from_the_register_when_it_says() {
	facts := TjmaxFacts{
		model: 0x5e
	}
	found := coretemp_tjmax(true, u64(100) << 16, 90000, facts)
	assert found.millicelsius == 100000 && found.from_register
	// A register that reads zero, or cannot be read, does not say: then what
	// was forced, and failing that the tables.
	forced := coretemp_tjmax(true, 0, 90000, facts)
	assert forced.millicelsius == 90000 && !forced.from_register
	unreadable := coretemp_tjmax(false, u64(100) << 16, 95000, facts)
	assert unreadable.millicelsius == 95000 && !unreadable.from_register
	guessed := coretemp_tjmax(false, 0, 0, facts)
	assert guessed.millicelsius == 100000 && !guessed.from_register
}

fn test_tjmax_by_host_bridge() {
	assert coretemp_adjust_tjmax(TjmaxFacts{
		model:         0x36
		stepping:      9
		bridge_vendor: 0x8086
		bridge_device: 0x0c72
	}) == 102000
	assert coretemp_adjust_tjmax(TjmaxFacts{
		model:         0x36
		bridge_vendor: 0x8086
		bridge_device: 0x0708
	}) == 110000
	// The same device number from another vendor is another device, and the
	// model's entry decides.
	assert coretemp_adjust_tjmax(TjmaxFacts{
		model:         0x36
		bridge_vendor: 0x1022
		bridge_device: 0x0c72
	}) == 100000
}

fn test_tjmax_by_name() {
	// The name comes before the model: both are model 0x1c.
	assert coretemp_adjust_tjmax(TjmaxFacts{
		model:    0x1c
		stepping: 2
		brand:    'Intel(R) Atom(TM) CPU  330   @ 1.60GHz'
	}) == 125000
	assert coretemp_adjust_tjmax(TjmaxFacts{
		model:    0x1c
		stepping: 2
		brand:    'Intel(R) Atom(TM) CPU  230   @ 1.60GHz'
	}) == 100000
}

fn test_tjmax_by_model_and_stepping() {
	assert coretemp_adjust_tjmax(TjmaxFacts{ model: 0x1c, stepping: 10 }) == 100000
	assert coretemp_adjust_tjmax(TjmaxFacts{ model: 0x1c, stepping: 2 }) == 90000
	assert coretemp_adjust_tjmax(TjmaxFacts{ model: 0x26, stepping: 1 }) == 90000
	assert coretemp_adjust_tjmax(TjmaxFacts{ model: 0x27, stepping: 1 }) == 90000
	assert coretemp_adjust_tjmax(TjmaxFacts{ model: 0x35, stepping: 1 }) == 90000
	assert coretemp_adjust_tjmax(TjmaxFacts{ model: 0x36, stepping: 1 }) == 100000
}

const mobile_bit = u64(0x10000000)
const ee_bit = u64(0x40000000)

fn test_tjmax_guess_for_core_2() {
	// A mobile Merom: bit 28 of the platform register, and MSR 0xee chooses
	// 85 C.
	assert coretemp_adjust_tjmax(TjmaxFacts{
		model:       0xf
		stepping:    6
		platform_ok: true
		platform:    mobile_bit
		ee_ok:       true
		ee:          ee_bit
	}) == 85000
	assert coretemp_adjust_tjmax(TjmaxFacts{
		model:       0xf
		stepping:    6
		platform_ok: true
		platform:    mobile_bit
		ee_ok:       true
		ee:          0
	}) == 100000
	// A desktop one is not asked about 0xee.
	assert coretemp_adjust_tjmax(TjmaxFacts{
		model:       0xf
		stepping:    6
		platform_ok: true
		platform:    0
		ee_ok:       true
		ee:          ee_bit
	}) == 100000
	// Nor is one whose platform register cannot be read.
	assert coretemp_adjust_tjmax(TjmaxFacts{
		model:    0xf
		stepping: 6
		ee_ok:    true
		ee:       ee_bit
	}) == 100000
	// The earliest steppings have no such register at all.
	assert coretemp_adjust_tjmax(TjmaxFacts{
		model:       0xf
		stepping:    3
		platform_ok: true
		platform:    mobile_bit
		ee_ok:       true
		ee:          ee_bit
	}) == 100000
}

fn test_tjmax_guess_for_penryn() {
	// Platform ID, bits 52:50 of the register: 5 and 7 are taken for mobile.
	for id in [u64(5), 7] {
		assert coretemp_adjust_tjmax(TjmaxFacts{
			model:       0x17
			stepping:    6
			platform_ok: true
			platform:    id << 50
			ee_ok:       true
			ee:          0
		}) == 105000
		assert coretemp_adjust_tjmax(TjmaxFacts{
			model:       0x17
			stepping:    6
			platform_ok: true
			platform:    id << 50
			ee_ok:       true
			ee:          ee_bit
		}) == 90000
	}
	// Any other: the usual pair. Bit 28 is not looked at from Penryn on.
	assert coretemp_adjust_tjmax(TjmaxFacts{
		model:       0x17
		stepping:    6
		platform_ok: true
		platform:    u64(2) << 50
		ee_ok:       true
		ee:          ee_bit
	}) == 85000
	assert coretemp_adjust_tjmax(TjmaxFacts{
		model:       0x17
		stepping:    6
		platform_ok: true
		platform:    u64(2) << 50
		ee_ok:       false
		ee:          ee_bit
	}) == 100000
}

fn test_tjmax_guess_for_the_first_core() {
	// Model 0xe and below: the platform register is not asked, 0xee is.
	assert coretemp_adjust_tjmax(TjmaxFacts{ model: 0xe, stepping: 8, ee_ok: true, ee: ee_bit }) == 85000
	assert coretemp_adjust_tjmax(TjmaxFacts{ model: 0xe, stepping: 8, ee_ok: true, ee: 0 }) == 100000
	assert coretemp_adjust_tjmax(TjmaxFacts{ model: 0xe, stepping: 8 }) == 100000
}

fn test_package_trips() {
	said := Tjmax{
		millicelsius:  100000
		from_register: true
	}
	// The firmware's target where it names one below TjMax.
	assert coretemp_passive_trip(said, (u64(100) << 16) | (u64(15) << 8)) == 85000
	// None named: ten degrees below TjMax.
	assert coretemp_passive_trip(said, u64(100) << 16) == 90000
	// An offset as large as TjMax itself is not a target.
	assert coretemp_passive_trip(said, (u64(100) << 16) | (u64(100) << 8)) == 90000
	guessed := Tjmax{
		millicelsius: 100000
	}
	// A TjMax that was guessed makes the register's other bits a guess too.
	assert coretemp_passive_trip(guessed, (u64(100) << 16) | (u64(15) << 8)) == 90000
	assert coretemp_critical_trip(said) == 105000
	assert coretemp_critical_trip(Tjmax{ millicelsius: 90000 }) == 95000
}
