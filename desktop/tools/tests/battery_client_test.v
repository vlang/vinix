// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

fn mock_battery(text string) MockDevice {
	return MockDevice{ path: '/dev/battery', reply: text.bytes(), stream: true }
}

fn test_battery_parser_all_percentages_and_malformed_input() {
	for percent in 0 .. 101 {
		assert parse_battery('${percent}\n'.bytes()) == percent
	}
	assert parse_battery('000\n'.bytes()) == 0
	for bad in ['', '\n', '1', '100', '101\n', '-1\n', '+1\n', ' 1\n', '1 \n', '1\r\n', '1\n2',
		'1000\n', '1\x00\n', 'abc\n'] {
		assert parse_battery(bad.bytes()) == battery_invalid
	}
}

fn test_battery_readonly_short_reads_and_eof() {
	for percent in 0 .. 101 {
		for chunk in 1 .. 6 {
			mut m := mock_battery('${percent}\n')
			m.chunk = chunk
			assert read_battery_with(mut m) == percent
			assert m.opens == 1 && m.closes == 1 && !m.live
			assert !m.write_open && m.writes == 0 && m.reads >= 2
		}
	}
	for bad in ['', '1', '100', '100\nextra'] {
		mut m := mock_battery(bad)
		assert read_battery_with(mut m) == battery_invalid && !m.live
	}
}

fn test_battery_failures_and_bounded_retries() {
	for failure in [DeviceError.unavailable, .permission, .io] {
		mut m := mock_battery('50\n')
		m.open_error = failure
		assert read_battery_with(mut m) == battery_io_result(failure) && !m.live && m.closes == 0
		m = mock_battery('50\n')
		m.read_error = failure
		assert read_battery_with(mut m) == battery_io_result(failure) && m.closes == 1 && !m.live
	}
	mut m := mock_battery('50\n')
	m.interrupted_opens = 3
	m.interrupted_reads = 3
	assert read_battery_with(mut m) == 50 && m.opens == 4 && m.closes == 1
	m = mock_battery('50\n')
	m.interrupted_opens = 100
	assert read_battery_with(mut m) == battery_io && m.opens == 16 && m.closes == 0
	m = mock_battery('50\n')
	m.interrupted_reads = 100
	assert read_battery_with(mut m) == battery_io && m.reads == 32 && m.closes == 1
	m = mock_battery('50\n')
	m.close_error = .interrupted
	assert read_battery_with(mut m) == battery_io && m.closes == 1 && !m.live
}

__global (
	cache_calls int
	cache_value int
)

fn cache_reader() int {
	cache_calls++
	return cache_value
}

fn test_battery_cache_throttle_force_expiry_and_clock_failure() {
	mut cache := BatteryCache{}
	cache_calls = 0
	cache_value = 75
	assert cache.poll(100, false, cache_reader) == 75 && cache_calls == 1
	cache_value = 70
	assert cache.poll(5099, false, cache_reader) == 75 && cache_calls == 1
	assert cache.poll(5100, false, cache_reader) == 70 && cache_calls == 2
	assert cache.poll(5101, true, cache_reader) == 70 && cache_calls == 3
	cache_value = battery_unavailable
	assert cache.poll(10200, false, cache_reader) == battery_unavailable
	cache_value = 50
	assert cache.poll(10, false, cache_reader) == 50 // backwards clock repolls
	before := cache_calls
	assert cache.poll(~u64(0), false, cache_reader) == battery_io && !cache.initialized
	assert cache_calls == before
	assert cache.poll(11, false, cache_reader) == 50 && cache_calls == before + 1
	cache_value = 101
	assert cache.poll(12, true, cache_reader) == battery_invalid
	cache_value = -5
	assert cache.poll(13, true, cache_reader) == battery_invalid
	for failure in [battery_unavailable, battery_permission, battery_invalid, battery_io] {
		cache_value = failure
		assert cache.poll(14, true, cache_reader) == failure
	}
}
