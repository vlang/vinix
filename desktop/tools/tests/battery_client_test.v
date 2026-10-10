// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

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

fn test_battery_history_graph_samples_and_remaining_time() {
	mut history := BatteryHistory{}
	history.observe(0, battery_unavailable)
	assert !history.initialized && history.count == 0
	history.observe(0, 80)
	history.observe(300_000, 80)
	assert history.count == 1
	assert history.remaining_hours(80) == battery_estimate_calculating
	history.observe(600_000, 79)
	assert history.remaining_hours(79) == battery_estimate_calculating
	history.observe(3_900_000, 70)
	assert history.count == 3
	assert history.sample(0) == BatterySample{ at_ms: 0, percent: 80 }
	assert history.sample(2) == BatterySample{
		at_ms: 3_900_000
		percent: 70
		connected: true
	}
	assert history.remaining_hours(70) == 7

	// Any observed rise suppresses a discharge estimate until a new falling
	// trend has enough duration and range of its own.
	history.observe(4_000_000, 71)
	assert history.remaining_hours(71) == battery_estimate_charging
	history.observe(4_600_000, 70)
	assert history.remaining_hours(70) == battery_estimate_calculating
	history.observe(8_200_000, 60)
	assert history.remaining_hours(60) == 6
	assert history.remaining_hours(battery_io) == battery_estimate_unavailable
	history.observe(8_300_000, battery_io)
	assert history.observed_ms == 8_300_000
	assert history.last_valid_ms == 8_200_000
	assert !history.contiguous
	history.observe(8_400_000, 60)
	assert history.count == 7
	assert !history.sample(6).connected
	assert history.remaining_hours(60) == battery_estimate_calculating

	mut full := BatteryHistory{}
	full.observe(10, 100)
	assert full.remaining_hours(100) == battery_estimate_full
}

fn test_battery_history_is_bounded_and_resets_on_clock_reversal() {
	mut history := BatteryHistory{}
	for index in 0 .. battery_history_capacity + 7 {
		history.observe(u64(index * 1000), 50 + index % 2)
	}
	assert history.count == battery_history_capacity
	assert history.sample(0).at_ms == 7_000
	history.observe(1, 42)
	assert history.initialized && history.count == 1
	assert history.sample(0) == BatterySample{ at_ms: 1, percent: 42 }
}

// A PC's /sys as the kernel publishes it: an ACPI battery that counts in
// energy, its charger, and the thresholds' directory, which is not a supply.
fn mock_supplies() MockTree {
	mut tree := MockTree{
		directory: power_supply_directory
		entries:   ['AC', 'BAT0', 'policy']
	}
	tree.put('/sys/class/power_supply/AC/type', 'Mains\n')
	tree.put('/sys/class/power_supply/AC/online', '1\n')
	tree.put('/sys/class/power_supply/BAT0/type', 'Battery\n')
	tree.put('/sys/class/power_supply/BAT0/present', '1\n')
	tree.put('/sys/class/power_supply/BAT0/status', 'Charging\n')
	tree.put('/sys/class/power_supply/BAT0/capacity', '73\n')
	tree.put('/sys/class/power_supply/BAT0/energy_full', '50000000\n')
	tree.put('/sys/class/power_supply/BAT0/time_to_empty_now', '0\n')
	tree.put('/sys/class/power_supply/BAT0/time_to_full_now', '5400\n')
	tree.put('/sys/class/power_supply/policy/low_percent', '10\n')
	return tree
}

const mock_bat0 = '/sys/class/power_supply/BAT0/'

// A /dev/battery beside the supplies, which ends at the end of its text.
fn mock_device_battery(mut tree MockTree, text string) {
	tree.put('/dev/battery', text)
	tree.node('/dev/battery').stream = true
}

// Every descriptor a read opened was closed, and nothing was written.
fn assert_supply_descriptors_closed(tree &MockTree) {
	assert tree.live < 0 && tree.closes > 0
	assert tree.writes == 0 && !tree.write_open
}

fn test_supply_parsers_accept_only_what_the_kernel_writes() {
	assert parse_supply_count('0\n'.bytes())? == 0
	assert parse_supply_count('5400\n'.bytes())? == 5400
	assert parse_supply_count('18446744073709551615\n'.bytes())? == ~u64(0)
	for bad in ['', '\n', '1', '-1\n', '+1\n', ' 1\n', '1 \n', '1\r\n', '1\n2', '1\n\n', '0x10\n',
		'1.5\n', '18446744073709551616\n', '99999999999999999999\n', '123456789012345678901\n',
		'1\x00\n'] {
		if _ := parse_supply_count(bad.bytes()) {
			assert false, 'accepted the count «${bad}»'
		}
	}
	assert parse_supply_status('Charging\n'.bytes())? == .charging
	assert parse_supply_status('Discharging\n'.bytes())? == .discharging
	assert parse_supply_status('Full\n'.bytes())? == .full
	assert parse_supply_status('Not charging\n'.bytes())? == .not_charging
	assert parse_supply_status('Unknown\n'.bytes())? == .unknown
	for bad in ['', '\n', 'Charging', 'charging\n', 'CHARGING\n', 'Charging \n', ' Charging\n',
		'Charging\r\n', 'Charging\nFull\n', 'Not Charging\n', 'Notcharging\n', 'Charged\n', 'Full\x00\n'] {
		if _ := parse_supply_status(bad.bytes()) {
			assert false, 'accepted the status «${bad}»'
		}
	}
	assert parse_supply_flag('1\n'.bytes())? == true
	assert parse_supply_flag('0\n'.bytes())? == false
	for bad in ['', '1', '2\n', '01\n', 'yes\n', '1\n1\n', ' 1\n'] {
		if _ := parse_supply_flag(bad.bytes()) {
			assert false, 'accepted the flag «${bad}»'
		}
	}
}

fn test_supply_battery_reads_status_times_and_charger() {
	mut tree := mock_supplies()
	reading := read_battery_reading_with(mut tree)
	assert reading == BatteryReading{
		percent:      73
		source:       .supply
		status:       .charging
		to_full_s:    5400
		mains:        true
		mains_online: true
	}
	assert_supply_descriptors_closed(&tree)
	// The directory once, then one read per file: type and online for the
	// charger, type and present for the battery, the type the thresholds'
	// directory does not have, and the battery's five values.
	assert tree.lists == 1
	assert tree.opens == 10 && tree.closes == 9 && tree.reads == 9
	assert tree.node('/sys/class/power_supply/policy/low_percent').reads == 0

	// Each poll opens the files again and sees what they say now.
	tree.put(mock_bat0 + 'status', 'Discharging\n')
	tree.put(mock_bat0 + 'capacity', '72\n')
	tree.put(mock_bat0 + 'time_to_empty_now', '9000\n')
	tree.put(mock_bat0 + 'time_to_full_now', '0\n')
	tree.put('/sys/class/power_supply/AC/online', '0\n')
	again := read_battery_reading_with(mut tree)
	assert again == BatteryReading{
		percent:    72
		source:     .supply
		status:     .discharging
		to_empty_s: 9000
		mains:      true
	}
	assert tree.lists == 2 && tree.opens == 20
	assert_supply_descriptors_closed(&tree)
}

fn test_supply_every_status_word_and_malformed_status() {
	for word, status in {
		'Charging':     BatteryStatus.charging
		'Discharging':  BatteryStatus.discharging
		'Full':         BatteryStatus.full
		'Not charging': BatteryStatus.not_charging
		'Unknown':      BatteryStatus.unknown
	} {
		mut tree := mock_supplies()
		tree.put(mock_bat0 + 'status', word + '\n')
		reading := read_battery_reading_with(mut tree)
		assert reading.percent == 73 && reading.source == .supply && reading.status == status
		assert_supply_descriptors_closed(&tree)
	}
	// A status that is not one fails the sample: the percentage is not shown
	// beside a state nobody reported, and /dev/battery is not asked instead.
	for bad in ['charging\n', 'Charging', 'Charging \n', 'Charged\n', 'Not Charging\n', '1\n', '\n'] {
		mut tree := mock_supplies()
		mock_device_battery(mut tree, '50\n')
		tree.put(mock_bat0 + 'status', bad)
		reading := read_battery_reading_with(mut tree)
		assert reading.percent == battery_invalid && reading.source == .supply, bad
		assert reading.status == .unknown && reading.to_full_s == 0
		assert tree.node('/dev/battery').reads == 0
		assert_supply_descriptors_closed(&tree)
	}
}

fn test_supply_missing_files() {
	// No estimates: a battery that has none to give reads as the kernel
	// having none, which is zero.
	mut tree := mock_supplies()
	tree.remove(mock_bat0 + 'time_to_empty_now')
	tree.remove(mock_bat0 + 'time_to_full_now')
	mut reading := read_battery_reading_with(mut tree)
	assert reading.percent == 73 && reading.status == .charging
	assert reading.to_empty_s == 0 && reading.to_full_s == 0
	assert_supply_descriptors_closed(&tree)

	// The battery went away between the listing and the read.
	for file in ['capacity', 'status'] {
		tree = mock_supplies()
		tree.remove(mock_bat0 + file)
		reading = read_battery_reading_with(mut tree)
		assert reading.percent == battery_unavailable && reading.source == .supply, file
		assert reading.status == .unknown && reading.to_full_s == 0
		assert_supply_descriptors_closed(&tree)
	}

	// Without `present`, or without `type`, it is not a battery to use.
	for file in ['present', 'type'] {
		tree = mock_supplies()
		mock_device_battery(mut tree, '41\n')
		tree.remove(mock_bat0 + file)
		reading = read_battery_reading_with(mut tree)
		assert reading.percent == 41 && reading.source == .device, file
		assert reading.mains && reading.mains_online
		assert_supply_descriptors_closed(&tree)
	}
}

fn test_supply_malformed_and_oversized_content() {
	oversized := '1'.repeat(power_supply_text_capacity) + '\n'
	for file in ['capacity', 'status', 'energy_full', 'time_to_empty_now', 'time_to_full_now'] {
		for bad in ['', 'abc\n', '-1\n', '7', '7\n7\n', ' 7\n', '7\r\n', oversized] {
			mut tree := mock_supplies()
			tree.put(mock_bat0 + file, bad)
			reading := read_battery_reading_with(mut tree)
			assert reading.percent == battery_invalid && reading.source == .supply, '${file} «${bad}»'
			assert reading.status == .unknown && reading.to_empty_s == 0 && reading.to_full_s == 0
			assert_supply_descriptors_closed(&tree)
		}
	}
	for bad in ['101\n', '1000\n', '100'] {
		mut tree := mock_supplies()
		tree.put(mock_bat0 + 'capacity', bad)
		assert read_battery_reading_with(mut tree).percent == battery_invalid
	}
	// More seconds than a 64-bit count holds.
	mut tree := mock_supplies()
	tree.put(mock_bat0 + 'time_to_full_now', '18446744073709551616\n')
	assert read_battery_reading_with(mut tree).percent == battery_invalid
	tree.put(mock_bat0 + 'time_to_full_now', '18446744073709551615\n')
	assert read_battery_reading_with(mut tree).to_full_s == ~u64(0)

	// A supply of a kind this does not know, or whose type or flag is not
	// what the kernel writes, is passed over rather than guessed at.
	for bad in ['USB\n', 'battery\n', 'Battery', 'Battery\n\n', oversized] {
		tree = mock_supplies()
		tree.put(mock_bat0 + 'type', bad)
		assert read_battery_reading_with(mut tree).source == .device, bad
	}
	for bad in ['2\n', 'yes\n', '1', oversized] {
		tree = mock_supplies()
		tree.put(mock_bat0 + 'present', bad)
		assert read_battery_reading_with(mut tree).source == .device, bad
		tree = mock_supplies()
		tree.put('/sys/class/power_supply/AC/online', bad)
		reading := read_battery_reading_with(mut tree)
		assert reading.percent == 73 && !reading.mains && !reading.mains_online, bad
	}
}

fn test_supply_energy_and_charge_batteries() {
	// One that counts in energy has energy_full and no charge_full.
	mut tree := mock_supplies()
	assert read_battery_reading_with(mut tree).percent == 73
	assert tree.index(mock_bat0 + 'charge_full') < 0

	// One that counts in charge has only charge_full.
	tree = mock_supplies()
	tree.remove(mock_bat0 + 'energy_full')
	tree.put(mock_bat0 + 'charge_full', '4500000\n')
	mut reading := read_battery_reading_with(mut tree)
	assert reading.percent == 73 && reading.status == .charging && reading.to_full_s == 5400
	assert tree.node(mock_bat0 + 'charge_full').reads == 1

	// The kernel writes a capacity of 0 for a battery whose full amount it
	// does not know. That is not an empty battery.
	for file in ['energy_full', 'charge_full'] {
		tree = mock_supplies()
		tree.remove(mock_bat0 + 'energy_full')
		tree.put(mock_bat0 + file, '0\n')
		tree.put(mock_bat0 + 'capacity', '0\n')
		reading = read_battery_reading_with(mut tree)
		assert reading.percent == battery_invalid && reading.source == .supply, file
	}
	// A battery that really is empty, with a full amount, reads 0%.
	tree = mock_supplies()
	tree.put(mock_bat0 + 'capacity', '0\n')
	tree.put(mock_bat0 + 'status', 'Discharging\n')
	assert read_battery_reading_with(mut tree).percent == 0

	// A driver with neither file has only its capacity to go by.
	tree = mock_supplies()
	tree.remove(mock_bat0 + 'energy_full')
	assert read_battery_reading_with(mut tree).percent == 73
	// charge_full is not read once energy_full has answered.
	tree = mock_supplies()
	tree.put(mock_bat0 + 'charge_full', '0\n')
	assert read_battery_reading_with(mut tree).percent == 73
	assert tree.node(mock_bat0 + 'charge_full').reads == 0
}

fn test_supply_mains_online_offline_and_absent() {
	mut tree := mock_supplies()
	mut reading := read_battery_reading_with(mut tree)
	assert reading.mains && reading.mains_online
	tree.put('/sys/class/power_supply/AC/online', '0\n')
	reading = read_battery_reading_with(mut tree)
	assert reading.mains && !reading.mains_online

	// No charger listed is not a charger that is off.
	tree = mock_supplies()
	tree.entries = ['BAT0']
	reading = read_battery_reading_with(mut tree)
	assert reading.percent == 73 && !reading.mains && !reading.mains_online

	// Any charger supplying power counts, wherever it is listed.
	tree = mock_supplies()
	tree.entries = ['BAT0', 'AC', 'USBC']
	tree.put('/sys/class/power_supply/AC/online', '0\n')
	tree.put('/sys/class/power_supply/USBC/type', 'Mains\n')
	tree.put('/sys/class/power_supply/USBC/online', '1\n')
	reading = read_battery_reading_with(mut tree)
	assert reading.percent == 73 && reading.mains && reading.mains_online

	// A charger and no battery: /dev/battery is asked, and the charger kept.
	tree = mock_supplies()
	tree.entries = ['AC']
	reading = read_battery_reading_with(mut tree)
	assert reading.percent == battery_unavailable && reading.source == .device
	assert reading.mains && reading.mains_online
}

fn test_supply_first_present_battery_and_listing_bounds() {
	mut tree := mock_supplies()
	tree.entries = ['BAT0', 'BAT1', 'BAT2']
	tree.put(mock_bat0 + 'present', '0\n')
	for name, capacity in {
		'BAT1': '31\n'
		'BAT2': '32\n'
	} {
		tree.put('/sys/class/power_supply/${name}/type', 'Battery\n')
		tree.put('/sys/class/power_supply/${name}/present', '1\n')
		tree.put('/sys/class/power_supply/${name}/status', 'Discharging\n')
		tree.put('/sys/class/power_supply/${name}/capacity', capacity)
	}
	reading := read_battery_reading_with(mut tree)
	assert reading.percent == 31 && reading.status == .discharging
	// The later battery's values are not read once one has been chosen.
	assert tree.node('/sys/class/power_supply/BAT2/present').reads == 0
	assert tree.node('/sys/class/power_supply/BAT2/capacity').reads == 0

	// Hidden entries and names too long to keep whole are never opened, and
	// a listing holds no more than its capacity.
	mut names := DeviceNames{}
	assert !names.add('.hidden'.bytes()) && !names.add(''.bytes())
	assert !names.add('a/b'.bytes()) && !names.add('a'.repeat(device_name_capacity).bytes())
	assert names.add('a'.repeat(device_name_capacity - 1).bytes()) && names.count == 1
	for index in 1 .. device_names_capacity {
		assert names.add('BAT${index}'.bytes())
	}
	assert names.count == device_names_capacity && !names.add('BAT9'.bytes())
	mut path := SupplyPath{}
	assert path.set(&names, 1, 'capacity') && path.text() == '/sys/class/power_supply/BAT1/capacity'
	assert path.bytes[path.len] == 0
	assert !path.set(&names, -1, 'type') && !path.set(&names, device_names_capacity, 'type')
	assert !path.set(&names, 1, 'x'.repeat(power_supply_path_capacity))
	// The longest name with the longest file still fits.
	assert path.set(&names, 0, 'time_to_empty_now')

	tree = mock_supplies()
	tree.entries = ['.', '..', 'a'.repeat(device_name_capacity), 'x1', 'x2', 'x3', 'x4', 'x5',
		'x6', 'x7', 'x8', 'BAT0']
	late := read_battery_reading_with(mut tree)
	assert late.source == .device && late.percent == battery_unavailable
}

fn test_supply_falls_back_to_the_device() {
	// No /sys/class/power_supply at all, as on a kernel without the class,
	// or one that cannot be listed: /dev/battery exactly as before.
	for failure in [DeviceError.unavailable, .permission, .io, .interrupted] {
		mut tree := mock_supplies()
		tree.list_error = failure
		mock_device_battery(mut tree, '88\n')
		reading := read_battery_reading_with(mut tree)
		assert reading == BatteryReading{
			percent: 88
			source:  .device
		}
		// Nothing below /sys was opened, and the device was read to its end.
		assert tree.opens == 1 && tree.closes == 1 && tree.reads == 2 && tree.live < 0
	}
	// The directory holds nothing but the thresholds, as on an Apple M1.
	mut tree := mock_supplies()
	tree.entries = ['policy']
	mock_device_battery(mut tree, '100\n')
	mut reading := read_battery_reading_with(mut tree)
	assert reading.percent == 100 && reading.source == .device && reading.status == .unknown
	assert !reading.mains

	// A battery bay that is empty.
	tree = mock_supplies()
	tree.put(mock_bat0 + 'present', '0\n')
	mock_device_battery(mut tree, '7\n')
	reading = read_battery_reading_with(mut tree)
	assert reading.percent == 7 && reading.source == .device
	assert tree.node(mock_bat0 + 'capacity').reads == 0

	// Neither source: unavailable, never zero.
	tree = mock_supplies()
	tree.entries = []
	reading = read_battery_reading_with(mut tree)
	assert reading.percent == battery_unavailable && reading.source == .device
	// The device's own failures and strict parsing are unchanged behind it.
	for text, want in {
		'101\n': battery_invalid
		'5':     battery_invalid
		'5\n':   5
	} {
		tree = mock_supplies()
		tree.entries = []
		mock_device_battery(mut tree, text)
		assert read_battery_reading_with(mut tree).percent == want, text
	}
	tree = mock_supplies()
	tree.entries = []
	mock_device_battery(mut tree, '5\n')
	tree.node('/dev/battery').open_error = .permission
	assert read_battery_reading_with(mut tree).percent == battery_permission
}

fn test_supply_failures_and_bounded_retries() {
	for failure in [DeviceError.permission, .io] {
		for file in ['capacity', 'status', 'energy_full', 'time_to_empty_now', 'time_to_full_now'] {
			mut tree := mock_supplies()
			tree.node(mock_bat0 + file).open_error = failure
			mut reading := read_battery_reading_with(mut tree)
			assert reading.percent == battery_io_result(failure) && reading.source == .supply
			assert tree.live < 0
			tree = mock_supplies()
			tree.node(mock_bat0 + file).read_error = failure
			reading = read_battery_reading_with(mut tree)
			assert reading.percent == battery_io_result(failure) && reading.source == .supply
			assert_supply_descriptors_closed(&tree)
			assert tree.opens == tree.closes + 1 // the type `policy` does not have
		}
	}
	// Never retry close, and never trust what a failed close followed.
	mut tree := mock_supplies()
	tree.node(mock_bat0 + 'capacity').close_error = .interrupted
	assert read_battery_reading_with(mut tree).percent == battery_io
	assert tree.live < 0

	// Interrupted opens and reads are retried, and not without end.
	tree = mock_supplies()
	tree.interrupted_opens = 3
	tree.interrupted_reads = 3
	assert read_battery_reading_with(mut tree).percent == 73
	assert tree.opens == 13 && tree.reads == 12
	mut buffer := []u8{len: power_supply_text_capacity}
	tree = mock_supplies()
	tree.interrupted_opens = 100
	assert read_supply_text(mut tree, mock_bat0 + 'capacity', mut buffer) == battery_io
	assert tree.opens == 16 && tree.closes == 0 && tree.live < 0
	tree = mock_supplies()
	tree.interrupted_reads = 100
	assert read_supply_text(mut tree, mock_bat0 + 'capacity', mut buffer) == battery_io
	assert tree.reads == power_supply_retries && tree.closes == 1 && tree.live < 0
	// One read per file: /sys does not continue a snapshot on a second.
	tree = mock_supplies()
	assert read_supply_text(mut tree, mock_bat0 + 'capacity', mut buffer) == 3
	assert buffer[..3].bytestr() == '73\n' && tree.reads == 1 && tree.closes == 1
}

__global (
	cache_reading BatteryReading
)

fn cache_reading_reader() BatteryReading {
	cache_calls++
	return cache_reading
}

fn test_battery_cache_keeps_whole_readings() {
	mut cache := BatteryCache{}
	assert cache.reading.percent == battery_unavailable && cache.reading.source == .none_
	cache_calls = 0
	cache_reading = BatteryReading{
		percent:      60
		source:       .supply
		status:       .charging
		to_full_s:    3600
		mains:        true
		mains_online: true
	}
	assert cache.poll_reading(100, false, cache_reading_reader) == cache_reading
	assert cache_calls == 1 && cache.value == 60
	// Within five seconds nothing is read again, whatever the supply says.
	first := cache_reading
	cache_reading = BatteryReading{
		percent:    59
		source:     .supply
		status:     .discharging
		to_empty_s: 7200
	}
	assert cache.poll_reading(5099, false, cache_reading_reader) == first && cache_calls == 1
	assert cache.poll_reading(5100, false, cache_reading_reader) == cache_reading
	assert cache_calls == 2 && cache.history.last_percent == 59
	assert cache.poll_reading(5101, true, cache_reading_reader) == cache_reading && cache_calls == 3

	// A failed sample replaces the last one whole: no status or estimate is
	// left standing beside a percentage that is gone.
	cache_reading = BatteryReading{
		percent:      battery_invalid
		source:       .supply
		status:       .discharging
		to_empty_s:   7200
		mains:        true
		mains_online: true
	}
	failed := cache.poll_reading(10200, false, cache_reading_reader)
	assert failed == BatteryReading{
		percent:      battery_invalid
		source:       .supply
		mains:        true
		mains_online: true
	}
	assert cache.value == battery_invalid && cache.reading == failed
	assert battery_power(failed) == .unknown
	assert battery_outlook(failed, &cache.history).estimate == battery_estimate_unavailable
	// Out-of-range percentages are failures too.
	for bad in [101, -5, 1000] {
		cache_reading = BatteryReading{
			percent: bad
			source:  .supply
			status:  .full
		}
		reading := cache.poll_reading(10300, true, cache_reading_reader)
		assert reading.percent == battery_invalid && reading.status == .unknown
	}

	// A backwards clock repolls; a failed clock invalidates without reading.
	cache_reading = first
	assert cache.poll_reading(10, false, cache_reading_reader) == first
	before := cache_calls
	lost := cache.poll_reading(~u64(0), false, cache_reading_reader)
	assert lost.percent == battery_io && lost.status == .unknown && !cache.initialized
	assert cache_calls == before && cache.value == battery_io
	assert cache.poll_reading(11, false, cache_reading_reader) == first && cache_calls == before + 1

	// The percentage-only reader shares the cache and says nothing more.
	cache_value = 42
	assert cache.poll(12, true, cache_reader) == 42
	assert cache.reading == BatteryReading{
		percent: 42
		source:  .device
	}
}

fn test_battery_outlook_and_power() {
	mut history := BatteryHistory{}
	supply := BatteryReading{
		percent: 50
		source:  .supply
	}
	// The kernel's seconds, to the nearest hour.
	for seconds, hours in {
		u64(1):                0
		u64(1799):             0
		u64(1800):             1
		u64(5399):             1
		u64(5400):             2
		u64(48 * 3600 + 1799): 48
	} {
		assert battery_seconds_to_hours(seconds) == hours
		assert battery_outlook(BatteryReading{
			...supply
			status:     .discharging
			to_empty_s: seconds
		}, &history) == BatteryOutlook{
			estimate: hours
		}
		assert battery_outlook(BatteryReading{
			...supply
			status:    .charging
			to_full_s: seconds
		}, &history) == BatteryOutlook{
			estimate: hours
			to_full:  true
		}
	}
	// No estimate, or one longer than is shown.
	for seconds in [u64(0), u64(48 * 3600 + 1800), ~u64(0)] {
		assert battery_outlook(BatteryReading{
			...supply
			status:     .discharging
			to_empty_s: seconds
		}, &history).estimate == battery_estimate_calculating
		assert battery_outlook(BatteryReading{
			...supply
			status:    .charging
			to_full_s: seconds
		}, &history) == BatteryOutlook{
			estimate: battery_estimate_charging
		}
	}
	// The time to empty is not shown while charging, nor the other way round.
	assert battery_outlook(BatteryReading{
		...supply
		status:     .charging
		to_empty_s: 3600
	}, &history).estimate == battery_estimate_charging
	assert battery_outlook(BatteryReading{
		...supply
		status:    .discharging
		to_full_s: 3600
	}, &history).estimate == battery_estimate_calculating
	assert battery_outlook(BatteryReading{
		...supply
		status:    .full
		to_full_s: 3600
	}, &history).estimate == battery_estimate_full
	assert battery_outlook(BatteryReading{
		...supply
		status: .not_charging
	}, &history).estimate == battery_estimate_not_charging
	assert battery_outlook(BatteryReading{
		...supply
		status:     .unknown
		to_empty_s: 3600
	}, &history).estimate == battery_estimate_unavailable

	// /dev/battery has only its history: the inferred trend, as before. A
	// supply's status is believed over the trend the same history shows.
	history.observe(0, 80)
	history.observe(300_000, 80)
	history.observe(600_000, 79)
	history.observe(3_900_000, 70)
	device := BatteryReading{
		percent: 70
		source:  .device
	}
	assert battery_outlook(device, &history) == BatteryOutlook{
		estimate: 7
	}
	assert battery_outlook(BatteryReading{
		...supply
		percent: 70
		status:  .charging
	}, &history).estimate == battery_estimate_charging
	history.observe(4_000_000, 71)
	assert battery_outlook(BatteryReading{
		...device
		percent: 71
	}, &history).estimate == battery_estimate_charging
	assert battery_outlook(BatteryReading{
		...supply
		percent:    71
		status:     .discharging
		to_empty_s: 7200
	}, &history).estimate == 2

	assert battery_power(device) == .unknown
	for status, power in {
		BatteryStatus.charging: BatteryPower.charging
		.discharging:           .on_battery
		.full:                  .full
		.not_charging:          .not_charging
		.unknown:               .unknown
	} {
		assert battery_power(BatteryReading{
			...supply
			status: status
		}) == power
	}
	// With no status, a charger still says which side of it the machine is.
	assert battery_power(BatteryReading{
		...supply
		mains:        true
		mains_online: true
	}) == .plugged_in
	assert battery_power(BatteryReading{
		...supply
		mains: true
	}) == .on_battery
	// The status is the battery's own word and is not overruled by a charger.
	assert battery_power(BatteryReading{
		...supply
		status:       .discharging
		mains:        true
		mains_online: true
	}) == .on_battery
	for failure in [battery_unavailable, battery_permission, battery_invalid, battery_io] {
		assert battery_power(BatteryReading{
			...supply
			percent: failure
			status:  .charging
		}) == .unknown
	}
}
