// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// kernel/thermal/k10temp_decode_amd64.v against Linux's k10temp.c: where each
// family keeps its temperature, what the register reads, the table of Tctl
// offsets, the per-die sensors, Hardware Thermal Control and erratum 319.
module thermal

fn test_where_each_family_keeps_its_temperature() {
	assert k10temp_model(.amd, 0x10, 0x4).access == .northbridge
	assert k10temp_model(.amd, 0x14, 0x2).access == .northbridge
	assert k10temp_model(.amd, 0x16, 0x30).access == .northbridge
	assert k10temp_model(.amd, 0x15, 0x02).access == .northbridge
	assert k10temp_model(.amd, 0x15, 0x60).access == .indexed
	assert k10temp_model(.amd, 0x15, 0x65).access == .indexed
	assert k10temp_model(.amd, 0x15, 0x70).access == .indexed
	for family in [u32(0x17), 0x19, 0x1a] {
		found := k10temp_model(.amd, family, 0x1)
		assert found.access == .smn && found.is_zen
		assert found.adjust_mask == zen_cur_temp_range_sel
	}
	assert k10temp_model(.hygon, 0x18, 0x0).access == .smn
	// Before family 10h there is no such register, and Intel has none.
	assert k10temp_model(.amd, 0xf, 0x6b).access == .unsupported
	assert k10temp_model(.amd, 0x6, 0x6).access == .unsupported
	assert k10temp_model(.amd, 0x13, 0x0).access == .unsupported
	assert k10temp_model(.intel, 0x17, 0x1).access == .unsupported
	// Only Zen has the bit that selects the lower range.
	assert k10temp_model(.amd, 0x10, 0x4).adjust_mask == 0
	assert !k10temp_model(.amd, 0x15, 0x60).is_zen
}

struct DieCase {
	family u32
	model  u32
	offset u32
	limit  int
}

fn test_where_the_per_die_sensors_are() {
	cases := [
		DieCase{0x17, 0x01, 0x154, 4}, // Zen
		DieCase{0x17, 0x08, 0x154, 4}, // Zen+
		DieCase{0x17, 0x11, 0x154, 4}, // Zen APU
		DieCase{0x17, 0x18, 0x154, 4}, // Zen+ APU
		DieCase{0x17, 0x31, 0x154, 8}, // Zen 2 Threadripper
		DieCase{0x17, 0x60, 0x154, 8}, // Renoir
		DieCase{0x17, 0x68, 0x154, 8}, // Lucienne
		DieCase{0x17, 0x71, 0x154, 8}, // Zen 2
		DieCase{0x17, 0xa0, 0x300, 8},
		DieCase{0x17, 0xaf, 0x300, 8},
		DieCase{0x17, 0x90, 0, 0}, // not in the list: no die sensors
		DieCase{0x19, 0x00, 0x154, 8}, // Zen 3 SP3
		DieCase{0x19, 0x01, 0x154, 8},
		DieCase{0x19, 0x21, 0x154, 8}, // Zen 3 desktop
		DieCase{0x19, 0x50, 0x154, 8}, // Green Sardine
		DieCase{0x19, 0x5f, 0x154, 8},
		DieCase{0x19, 0x44, 0x300, 8}, // Yellow Carp
		DieCase{0x19, 0x61, 0x308, 8},
		DieCase{0x19, 0x7f, 0x308, 8},
		DieCase{0x19, 0x11, 0x300, 12},
		DieCase{0x19, 0xa8, 0x300, 12},
		DieCase{0x19, 0x30, 0, 0},
		DieCase{0x1a, 0x44, 0, 0},
	]
	for c in cases {
		found := k10temp_model(.amd, c.family, c.model)
		assert found.ccd_offset == c.offset, 'family ${c.family:x} model ${c.model:x}'
		assert found.ccd_limit == c.limit, 'family ${c.family:x} model ${c.model:x}'
	}
	assert k10temp_ccd_address(0x154, 0) == 0x59954
	assert k10temp_ccd_address(0x154, 3) == 0x59960
	assert k10temp_ccd_address(0x308, 1) == 0x59b0c
}

fn test_reported_temperature() {
	// Eleven bits of eighths of a degree from bit 21: 480 of them are 60 C.
	assert k10temp_raw_temperature(u32(480) << 21, 0) == 60000
	assert k10temp_raw_temperature(u32(481) << 21, 0) == 60125
	assert k10temp_raw_temperature(0xffe00000, 0) == 255875
	// Zen's range bit moves the scale down by 49 degrees...
	range := (u32(872) << 21) | zen_cur_temp_range_sel
	assert k10temp_raw_temperature(range, zen_cur_temp_range_sel) == 60000
	// ...and means nothing where the model has no such bit.
	assert k10temp_raw_temperature(range, 0) == 109000
	// Both Tj select bits do the same on every model.
	both := (u32(872) << 21) | (u32(3) << 16)
	assert k10temp_raw_temperature(both, 0) == 60000
	assert k10temp_raw_temperature((u32(872) << 21) | (u32(1) << 16), 0) == 109000
	assert k10temp_raw_temperature((u32(872) << 21) | (u32(2) << 16), 0) == 109000
}

fn offset_of(family u32, brand string) i64 {
	offset, known := k10temp_tctl_offset(family, brand)
	return if known { offset } else { i64(-1) }
}

fn test_tctl_offset_table() {
	assert offset_of(0x17, 'AMD Ryzen 5 1600X Six-Core Processor') == 20000
	assert offset_of(0x17, 'AMD Ryzen 7 1700X Eight-Core Processor') == 20000
	assert offset_of(0x17, 'AMD Ryzen 7 1800X Eight-Core Processor') == 20000
	assert offset_of(0x17, 'AMD Ryzen 7 2700X Eight-Core Processor') == 10000
	assert offset_of(0x17, 'AMD Ryzen Threadripper 1900X 8-Core Processor') == 27000
	assert offset_of(0x17, 'AMD Ryzen Threadripper 1950X 16-Core Processor') == 27000
	assert offset_of(0x17, 'AMD Ryzen Threadripper 2990WX 32-Core Processor') == 27000
	// Not in the table: Tctl is the die's temperature, and Tdie is not shown.
	assert offset_of(0x17, 'AMD Ryzen 7 1700 Eight-Core Processor') == -1
	assert offset_of(0x17, 'AMD Ryzen 5 3600 6-Core Processor') == -1
	assert offset_of(0x17, 'AMD Ryzen Threadripper 3970X 32-Core Processor') == -1
	// The table is of family 17h only.
	assert offset_of(0x19, 'AMD Ryzen 7 1700X Eight-Core Processor') == -1
}

fn test_negative_readings_are_shown_as_zero_except_on_the_3255() {
	assert k10temp_shown(60000, 0, false) == 60000
	assert k10temp_shown(60000, 20000, false) == 40000
	assert k10temp_shown(-5000, 0, false) == 0
	assert k10temp_shown(10000, 27000, false) == 0
	assert k10temp_shown(-5000, 0, true) == -5000
	assert k10temp_shows_negative(0x17, 'AMD EPYC 3255 8-Core Processor')
	assert !k10temp_shows_negative(0x19, 'AMD EPYC 3255 8-Core Processor')
	assert !k10temp_shows_negative(0x17, 'AMD EPYC 3251 8-Core Processor')
}

fn test_die_sensors() {
	// Bit 11 says the sensor is there; the eleven below it are eighths of a
	// degree above -49 C.
	register := (u32(1) << 11) | u32(872)
	assert k10temp_ccd_valid(register)
	assert k10temp_ccd_temperature(register) == 60000
	assert !k10temp_ccd_valid(u32(872))
	assert !k10temp_ccd_valid(0)
	// A register that is not there reads all ones, with the bit set.
	assert !k10temp_ccd_valid(0xffffffff)
	assert k10temp_ccd_temperature((u32(1) << 11) | 0) == -49000
}

fn test_hardware_thermal_control() {
	capability := u32(1) << 10
	// Limit field 96: 52 C plus 96 half degrees. Hysteresis field 6.
	htc := (u32(6) << 24) | (u32(96) << 16) | 1
	assert k10temp_htc_enabled(capability, htc)
	assert !k10temp_htc_enabled(0, htc)
	assert !k10temp_htc_enabled(capability, htc & ~u32(1))
	assert k10temp_htc_critical(htc) == 100000
	assert k10temp_htc_hysteresis(htc) == 3000
	assert k10temp_htc_critical(0) == 52000
}

fn test_erratum_319() {
	socket_f := u32(0x00000000)
	am2r2_am3 := u32(0x10000000)
	other := u32(0x20000000)
	ddr3 := u32(1) << 8
	// Only family 10h has it.
	assert !k10temp_erratum_319(0x11, 2, 1, socket_f, 0)
	// Socket F always.
	assert k10temp_erratum_319(0x10, 2, 1, socket_f, ddr3)
	assert !k10temp_erratum_319(0x10, 2, 1, other, 0)
	// AM3 with DDR3 memory is good whatever the core.
	assert !k10temp_erratum_319(0x10, 2, 1, am2r2_am3, ddr3)
	// With DDR2 it may be an AM2+ board: the cores that exist for those.
	assert k10temp_erratum_319(0x10, 2, 3, am2r2_am3, 0)
	assert k10temp_erratum_319(0x10, 4, 2, am2r2_am3, 0)
	assert !k10temp_erratum_319(0x10, 4, 3, am2r2_am3, 0)
	assert !k10temp_erratum_319(0x10, 5, 0, am2r2_am3, 0)
}

fn test_trips() {
	zen := k10temp_trips(true, false, 0)
	assert zen.passive == 85000 && zen.critical == 100000 && !zen.has_maximum
	older := k10temp_trips(false, false, 0)
	assert older.passive == 60000 && older.critical == 75000
	assert older.has_maximum && older.maximum == 70000
	// The firmware's limit where Hardware Thermal Control is on.
	htc := (u32(6) << 24) | (u32(96) << 16) | 1
	programmed := k10temp_trips(false, true, htc)
	assert programmed.critical == 100000 && programmed.critical_hyst == 3000
	assert programmed.passive == 60000
	// A limit at or below the passive trip moves that down with it.
	low := k10temp_trips(false, true, (u32(10) << 16) | 1)
	assert low.critical == 57000 && low.passive == 47000
}
