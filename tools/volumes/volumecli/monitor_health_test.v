// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_monitor_counter_arithmetic_borrows_across_every_byte_and_keeps_all_bits() {
	mut current := [16]u8{}
	mut previous := [16]u8{}
	mut difference := [18]u8{}
	difference[16] = 0xad
	difference[17] = 0xae
	for top in 1 .. 16 {
		current = [16]u8{}
		previous = [16]u8{}
		current[top] = 1
		for i in 0 .. top {
			previous[i] = 255
		}
		assert !monitor_counter_less(&current[0], &previous[0])
		assert monitor_counter_less(&previous[0], &current[0])
		monitor_counter_subtract(&current[0], &previous[0], &difference[0])
		assert difference[0] == 1
		for i in 1 .. 16 {
			assert difference[i] == 0
		}
		assert difference[16] == 0xad && difference[17] == 0xae
	}
	for i in 0 .. 16 {
		current[i] = 255
		previous[i] = 0
	}
	monitor_counter_subtract(&current[0], &previous[0], &difference[0])
	for i in 0 .. 16 {
		assert difference[i] == 255
	}
	assert !monitor_counter_less(&current[0], &current[0])
}

fn test_monitor_health_first_sample_gap_protocol_change_and_counter_reset() {
	mut state := MonitorHealthCounters{}
	mut report := Health{
		protocol: 2
	}
	report.data[160] = 5
	first := monitor_health_delta(mut state, &report, true)
	assert first.available && first.baseline && !first.reset && !first.media_errors
	for value in first.values {
		assert value == 0
	}
	report.data[160] = 7
	failed := monitor_health_delta(mut state, &report, false)
	assert !failed.available && state.valid && state.values[128] == 5
	next := monitor_health_delta(mut state, &report, true)
	assert next.available && !next.baseline && !next.reset && next.media_errors
	assert next.values[128] == 2
	// A high-half increase is a new media error even with a zero low half.
	report.data[168] = 1
	large := monitor_health_delta(mut state, &report, true)
	assert large.media_errors && large.values[136] == 1 && large.values[128] == 0
	for counter in 0 .. 10 {
		state = MonitorHealthCounters{}
		report = Health{
			protocol: 2
		}
		report.data[32 + counter * 16] = 5
		monitor_health_delta(mut state, &report, true)
		report.data[32 + counter * 16] = 4
		reset := monitor_health_delta(mut state, &report, true)
		assert reset.available && reset.baseline && reset.reset && !reset.media_errors
		for value in reset.values {
			assert value == 0
		}
	}
	report.protocol = 1
	other := monitor_health_delta(mut state, &report, true)
	assert !other.available && !state.valid
	report.protocol = 2
	assert monitor_health_delta(mut state, &report, true).baseline
}

fn test_monitor_health_formats_all_counters_thermal_wear_and_bounds() {
	mut state := MonitorHealthCounters{}
	mut report := Health{
		protocol: 2
	}
	report.data[1] = 44
	report.data[2] = 1
	report.data[3] = 95
	report.data[4] = 10
	report.data[5] = 200
	for i in 32 .. 192 {
		report.data[i] = 255
	}
	delta := monitor_health_delta(mut state, &report, true)
	mut text := [2050]char{}
	text[2048] = char(0x5d)
	text[2049] = char(0x5e)
	length := monitor_health_format(&report, &delta, &text[0], 2048)
	assert length > 0 && length < 2048
	output := unsafe { tos(&u8(&text[0]), length) }
	assert output.contains('scope=controller health_baseline=1 health_counters_reset=0')
	assert output.contains('temperature_kelvin=300 available_spare_percent=95 spare_threshold_percent=10 percentage_used=200')
	for name in ['data_units_read', 'data_units_written', 'host_read_commands', 'host_write_commands',
		'controller_busy_minutes', 'power_cycles', 'power_on_hours', 'unsafe_shutdowns',
		'media_errors', 'error_log_entries'] {
		assert output.contains(name + '=0xffffffffffffffffffffffffffffffff')
		assert output.contains(name + '_delta=0x00000000000000000000000000000000')
	}
	assert output.ends_with('\n') && text[length] == 0
	assert text[2048] == char(0x5d) && text[2049] == char(0x5e)
	mut short := [82]char{}
	short[80] = char(0x5d)
	short[81] = char(0x5e)
	assert monitor_health_format(&report, &delta, &short[0], 80) == -1
	assert short[79] == 0 && short[80] == char(0x5d) && short[81] == char(0x5e)
	assert monitor_health_format(&report, &delta, &short[0], 0) == -1
	report.data[1] = 0
	report.data[2] = 0
	assert monitor_health_format(&report, &delta, &text[0], 2048) > 0
	assert unsafe { cstring_to_vstring(&text[0]) }.contains('temperature_kelvin=unavailable')
	unavailable := MonitorHealthDelta{}
	assert monitor_health_format(&report, &unavailable, &text[0], 2048) > 0
	assert unsafe { cstring_to_vstring(&text[0]) } == ' telemetry=unavailable\n'
}
