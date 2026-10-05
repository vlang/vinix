// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_activity_energy_preserves_signed_device_readings() {
	stats := activity_energy_parse('voltage_mv: 12480\ncurrent_ma: -875\npower_mw: -10920\n')
	assert stats.has_voltage && stats.has_current && stats.has_power
	assert stats.voltage_mv == 12480
	assert stats.current_ma == -875
	assert stats.power_mw == -10920
	zero := activity_energy_parse('power_mw: 0\n')
	assert zero.has_power
	assert zero.power_mw == 0
	assert !zero.has_voltage && !zero.has_current
}

fn test_activity_energy_missing_keys_are_unavailable_and_bad_numbers_are_rejected() {
	assert !activity_energy_parse('').has_power
	assert !activity_energy_parse('power_mw: -\n').has_power
	assert !activity_energy_parse('power_mw: 5x\n').has_power
	assert !activity_energy_parse('power_mw: 9223372036854775808\n').has_power
	assert !activity_energy_parse('power_mw: -9223372036854775809\n').has_power
	assert activity_energy_signed_field('power_mw: -9223372036854775808\n', 'power_mw') or { 0 } == i64(-9223372036854775807) - 1
	assert activity_energy_signed_field('power_mw: +875\n', 'power_mw') or { 0 } == 875
}

fn test_activity_energy_formats_milliunits_without_losing_small_negative_readings() {
	for reading, expected in {i64(0): '0.000', 1: '0.001', -1: '-0.001', 12080: '12.080', -875: '-0.875'} {
		text := activity_energy_milli_text(reading)
		assert text == expected
		unsafe { text.free() }
	}
}
