// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

const battery_unavailable = -1
const battery_permission = -2
const battery_invalid = -3
const battery_io = -4

const battery_history_capacity = 64
const battery_history_window_ms = u64(24 * 60 * 60 * 1000)
const battery_estimate_minimum_ms = u64(10 * 60 * 1000)
const battery_estimate_minimum_drop = 2
const battery_estimate_maximum_hours = 48

const battery_estimate_unavailable = -1
const battery_estimate_calculating = -2
const battery_estimate_charging = -3
const battery_estimate_full = -4
const battery_estimate_not_charging = -5

// Where the kernel lists a machine's batteries and chargers, by Linux's names.
const power_supply_directory = '/sys/class/power_supply'
// The longest text read from a supply's file is a 64-bit count and its
// newline. The buffer holds more, so a file that fills it held too much.
const power_supply_text_capacity = 24
const power_supply_path_capacity = 96
const power_supply_retries = 4

enum BatteryTrend {
	unknown
	discharging
	charging
}

// Where a sample came from, which decides how much it says.
enum BatterySource {
	// Nothing has been read.
	none_
	// /dev/battery: a percentage and nothing else.
	device
	// A power supply in /sys: the kernel's own status and estimates as well.
	supply
}

// A power supply's `status`, in the kernel's words.
enum BatteryStatus {
	unknown
	charging
	discharging
	not_charging
	full
}

// One poll of the battery. `percent` is 0..100 or one of the battery_*
// failures, and a failed sample carries nothing else: the status and times
// below describe a valid percentage read from a power supply.
struct BatteryReading {
mut:
	percent int = battery_unavailable
	source  BatterySource
	status  BatteryStatus
	// The kernel's estimates in seconds. Zero is the kernel having none.
	to_empty_s u64
	to_full_s  u64
	// A Mains supply was listed, and whether it is supplying power.
	mains        bool
	mains_online bool
}

struct BatterySample {
	at_ms     u64
	percent   int
	connected bool
}

// Percentage changes are enough to draw the step graph and avoid retaining a
// sample every five seconds. Sixty-four changes cover a complete discharge
// with useful resolution while keeping all state fixed-size and allocation-free.
struct BatteryHistory {
mut:
	samples              [battery_history_capacity]BatterySample
	start                int
	count                int
	initialized          bool
	contiguous           bool
	observed_ms          u64
	last_valid_ms        u64
	last_percent         int
	discharge_percent    int
	discharge_started_ms u64
	trend                BatteryTrend
}

fn (history &BatteryHistory) sample(index int) BatterySample {
	if index < 0 || index >= history.count {
		return BatterySample{}
	}
	return history.samples[(history.start + index) % battery_history_capacity]
}

fn (mut history BatteryHistory) append(at_ms u64, percent int, connected bool) {
	mut index := 0
	if history.count < battery_history_capacity {
		index = (history.start + history.count) % battery_history_capacity
		history.count++
	} else {
		index = history.start
		history.start = (history.start + 1) % battery_history_capacity
	}
	history.samples[index] = BatterySample{
		at_ms: at_ms
		percent: percent
		connected: connected
	}
}

fn (mut history BatteryHistory) reset() {
	history.start = 0
	history.count = 0
	history.initialized = false
	history.contiguous = false
	history.observed_ms = 0
	history.last_valid_ms = 0
	history.last_percent = 0
	history.discharge_percent = 0
	history.discharge_started_ms = 0
	history.trend = .unknown
}

// observe keeps the graph and discharge trend in lock-step with real device
// polls. Invalid reads never become zero-percent samples and never erase the
// last 24 hours of valid history.
fn (mut history BatteryHistory) observe(now_ms u64, percent int) {
	if history.initialized && now_ms < history.observed_ms {
		history.reset()
	}
	if percent < 0 || percent > 100 {
		if history.initialized {
			history.observed_ms = now_ms
			history.contiguous = false
			history.trend = .unknown
		}
		return
	}
	if !history.initialized {
		history.initialized = true
		history.contiguous = true
		history.observed_ms = now_ms
		history.last_valid_ms = now_ms
		history.last_percent = percent
		history.discharge_percent = percent
		history.discharge_started_ms = now_ms
		history.append(now_ms, percent, false)
		return
	}
	if !history.contiguous {
		history.contiguous = true
		history.observed_ms = now_ms
		history.last_valid_ms = now_ms
		history.last_percent = percent
		history.discharge_percent = percent
		history.discharge_started_ms = now_ms
		history.trend = .unknown
		history.append(now_ms, percent, false)
		return
	}
	previous_observed_ms := history.observed_ms
	previous_percent := history.last_percent
	history.observed_ms = now_ms
	history.last_valid_ms = now_ms
	if percent == previous_percent {
		return
	}
	history.append(now_ms, percent, true)
	history.last_percent = percent
	if percent > previous_percent {
		history.trend = .charging
		history.discharge_percent = percent
		history.discharge_started_ms = now_ms
		return
	}
	if history.trend != .discharging {
		history.trend = .discharging
		history.discharge_percent = previous_percent
		history.discharge_started_ms = previous_observed_ms
	}
}

// remaining_hours returns a rounded hour count, or a negative presentation
// state. The estimate is deliberately withheld for short or quantized runs.
fn (history &BatteryHistory) remaining_hours(percent int) int {
	if percent < 0 || percent > 100 || !history.initialized || !history.contiguous {
		return battery_estimate_unavailable
	}
	if history.trend == .charging {
		return battery_estimate_charging
	}
	if percent == 100 {
		return battery_estimate_full
	}
	if history.trend != .discharging || history.observed_ms < history.discharge_started_ms {
		return battery_estimate_calculating
	}
	drop := history.discharge_percent - percent
	elapsed_ms := history.observed_ms - history.discharge_started_ms
	if drop < battery_estimate_minimum_drop || elapsed_ms < battery_estimate_minimum_ms {
		return battery_estimate_calculating
	}
	remaining_ms := u64(percent) * elapsed_ms / u64(drop)
	// Round to the nearest hour. Zero is meaningful and is rendered as less
	// than one hour; implausibly slow trends remain in the calculating state.
	hours := int((remaining_ms + 30 * 60 * 1000) / (60 * 60 * 1000))
	if hours > battery_estimate_maximum_hours {
		return battery_estimate_calculating
	}
	return hours
}

fn battery_io_result(result DeviceError) int {
	return match result {
		.unavailable { battery_unavailable }
		.permission { battery_permission }
		else { battery_io }
	}
}

// One to three decimal digits and LF, then EOF. Do not turn failures into 0%.
fn parse_battery(text []u8) int {
	if text.len < 2 || text.len > 4 || text[text.len - 1] != `\n` {
		return battery_invalid
	}
	mut percent := 0
	for byte in text[..text.len - 1] {
		if byte < `0` || byte > `9` {
			return battery_invalid
		}
		percent = percent * 10 + int(byte - `0`)
	}
	return if percent <= 100 { percent } else { battery_invalid }
}

fn read_battery_with(mut io DeviceIO) int {
	mut fd := -1
	mut open_error := DeviceError.io
	for _ in 0 .. 16 {
		fd, open_error = io.open('/dev/battery', false)
		if fd >= 0 || open_error != .interrupted {
			break
		}
	}
	if fd < 0 {
		return battery_io_result(open_error)
	}
	mut text := [5]u8{} // Four valid bytes, plus one to detect excess input.
	mut buffer := unsafe { (&text[0]).vbytes(text.len) }
	mut used := 0
	mut result := battery_io
	for _ in 0 .. 32 {
		mut tail := unsafe { buffer[used..] }
		count, read_error := io.read(fd, mut tail)
		if count < 0 {
			if read_error == .interrupted {
				continue
			}
			result = battery_io_result(read_error)
			break
		}
		if count == 0 {
			result = parse_battery(buffer[..used])
			break
		}
		if count > tail.len {
			result = battery_invalid
			break
		}
		used += count
		if used >= text.len {
			result = battery_invalid
			break
		}
	}
	// Never retry close: EINTR may mean the descriptor is already released.
	if io.close(fd) != .none {
		result = battery_io
	}
	return result
}

// A supply's file, /sys/class/power_supply/<name>/<file>, built in place: the
// text borrows this storage and is good until the next set().
struct SupplyPath {
mut:
	bytes [power_supply_path_capacity]u8
	len   int
}

fn (mut p SupplyPath) set(names &DeviceNames, index int, file string) bool {
	if index < 0 || index >= names.count {
		return false
	}
	length := power_supply_directory.len + 1 + names.lens[index] + 1 + file.len
	if length >= power_supply_path_capacity {
		return false
	}
	mut at := 0
	for byte in power_supply_directory {
		p.bytes[at] = byte
		at++
	}
	p.bytes[at] = `/`
	at++
	for i in 0 .. names.lens[index] {
		p.bytes[at] = names.names[index][i]
		at++
	}
	p.bytes[at] = `/`
	at++
	for byte in file {
		p.bytes[at] = byte
		at++
	}
	// open(2) takes the path as a C string.
	p.bytes[at] = 0
	p.len = at
	return true
}

fn (p &SupplyPath) text() string {
	return unsafe { tos(&p.bytes[0], p.len) }
}

// One file of a supply: opened read-only, read once and closed. /sys makes a
// file's text afresh for every read, so a second read would continue some
// other snapshot. The buffer is larger than anything valid, and a read that
// fills it is rejected. Returns the length, or a battery_* failure.
fn read_supply_text(mut io DeviceIO, path string, mut buffer []u8) int {
	mut fd := -1
	mut open_error := DeviceError.io
	for _ in 0 .. 16 {
		fd, open_error = io.open(path, false)
		if fd >= 0 || open_error != .interrupted {
			break
		}
	}
	if fd < 0 {
		return battery_io_result(open_error)
	}
	mut length := -1
	mut read_error := DeviceError.io
	for _ in 0 .. power_supply_retries {
		length, read_error = io.read(fd, mut buffer)
		if length >= 0 || read_error != .interrupted {
			break
		}
	}
	mut result := if length < 0 {
		battery_io_result(read_error)
	} else if length == 0 || length >= buffer.len {
		battery_invalid
	} else {
		length
	}
	// Never retry close: EINTR may mean the descriptor is already released.
	if io.close(fd) != .none {
		result = battery_io
	}
	return result
}

// Decimal digits and LF, nothing else: what /sys writes for a count. More
// than a 64-bit value holds is refused rather than wrapped.
fn parse_supply_count(text []u8) ?u64 {
	if text.len < 2 || text.len > 21 || text[text.len - 1] != `\n` {
		return none
	}
	mut value := u64(0)
	for byte in text[..text.len - 1] {
		if byte < `0` || byte > `9` {
			return none
		}
		digit := u64(byte - `0`)
		if value > (~u64(0) - digit) / 10 {
			return none
		}
		value = value * 10 + digit
	}
	return value
}

// The five words the kernel writes, each with its LF. Anything else is not a
// status, including a word in another case.
fn parse_supply_status(text []u8) ?BatteryStatus {
	if bytes_equal_text(text, 'Charging\n') {
		return .charging
	}
	if bytes_equal_text(text, 'Discharging\n') {
		return .discharging
	}
	if bytes_equal_text(text, 'Full\n') {
		return .full
	}
	if bytes_equal_text(text, 'Not charging\n') {
		return .not_charging
	}
	if bytes_equal_text(text, 'Unknown\n') {
		return .unknown
	}
	return none
}

// `present` and `online`: 0 or 1 and LF.
fn parse_supply_flag(text []u8) ?bool {
	if bytes_equal_text(text, '1\n') {
		return true
	}
	if bytes_equal_text(text, '0\n') {
		return false
	}
	return none
}

// One count of the chosen battery. A file that is not there reads as
// `absent`; anything else that is not a count fails the sample.
fn read_supply_count(mut io DeviceIO, path string, mut buffer []u8, absent u64) (u64, int) {
	length := read_supply_text(mut io, path, mut buffer)
	if length == battery_unavailable {
		return absent, 0
	}
	if length < 0 {
		return 0, length
	}
	value := parse_supply_count(buffer[..length]) or { return 0, battery_invalid }
	return value, 0
}

// What the battery holds when full, in whichever unit it counts in: a battery
// reports energy or charge, not both, and only that one's file exists. The
// kernel writes a capacity of 0 for a battery whose full amount it does not
// know, so a full amount of zero means the percentage is not one. With
// neither file there is nothing to check the capacity against.
fn read_supply_full(mut io DeviceIO, mut path SupplyPath, names &DeviceNames, index int, mut buffer []u8) (bool, int) {
	for file in ['energy_full', 'charge_full']! {
		if !path.set(names, index, file) {
			return false, battery_invalid
		}
		length := read_supply_text(mut io, path.text(), mut buffer)
		if length == battery_unavailable {
			continue
		}
		if length < 0 {
			return false, length
		}
		full := parse_supply_count(buffer[..length]) or { return false, battery_invalid }
		return full != 0, 0
	}
	return true, 0
}

// read_supply_battery_with fills `reading` from the first power supply /sys
// lists that is a battery and present, and reports whether there was one. A
// battery that is there but answers badly is still the source: its failure is
// the sample, and /dev/battery is not asked instead. A charger is noted on
// the way, whichever battery is used.
fn read_supply_battery_with(mut io DeviceIO, mut reading BatteryReading) bool {
	mut names := DeviceNames{}
	if io.list(power_supply_directory, mut names) != .none {
		return false
	}
	mut path := SupplyPath{}
	mut text := [power_supply_text_capacity]u8{}
	mut buffer := unsafe { (&text[0]).vbytes(text.len) }
	mut battery := -1
	for index in 0 .. names.count {
		// A directory that is not a supply, such as the kernel's `policy`, has
		// no `type` and is passed over; so is a kind this does not know.
		if !path.set(&names, index, 'type') {
			continue
		}
		mut length := read_supply_text(mut io, path.text(), mut buffer)
		if length < 0 {
			continue
		}
		if bytes_equal_text(buffer[..length], 'Mains\n') {
			if !path.set(&names, index, 'online') {
				continue
			}
			length = read_supply_text(mut io, path.text(), mut buffer)
			if length < 0 {
				continue
			}
			online := parse_supply_flag(buffer[..length]) or { continue }
			reading.mains = true
			if online {
				reading.mains_online = true
			}
		} else if battery < 0 && bytes_equal_text(buffer[..length], 'Battery\n') {
			if !path.set(&names, index, 'present') {
				continue
			}
			length = read_supply_text(mut io, path.text(), mut buffer)
			if length < 0 {
				continue
			}
			present := parse_supply_flag(buffer[..length]) or { continue }
			if present {
				battery = index
			}
		}
	}
	if battery < 0 {
		return false
	}
	reading.source = .supply
	reading.percent = read_supply_values(mut io, mut path, &names, battery, mut buffer, mut
		reading)
	return true
}

// The chosen battery's files. Returns the percentage, or the failure that
// replaces it: nothing read before a failure is kept.
fn read_supply_values(mut io DeviceIO, mut path SupplyPath, names &DeviceNames, index int, mut buffer []u8, mut reading BatteryReading) int {
	if !path.set(names, index, 'capacity') {
		return battery_invalid
	}
	mut length := read_supply_text(mut io, path.text(), mut buffer)
	if length < 0 {
		return length
	}
	percent := parse_battery(buffer[..length])
	if percent < 0 {
		return percent
	}
	if !path.set(names, index, 'status') {
		return battery_invalid
	}
	length = read_supply_text(mut io, path.text(), mut buffer)
	if length < 0 {
		return length
	}
	status := parse_supply_status(buffer[..length]) or { return battery_invalid }
	known, full_error := read_supply_full(mut io, mut path, names, index, mut buffer)
	if full_error < 0 {
		return full_error
	}
	if !known {
		return battery_invalid
	}
	if !path.set(names, index, 'time_to_empty_now') {
		return battery_invalid
	}
	to_empty, empty_error := read_supply_count(mut io, path.text(), mut buffer, 0)
	if empty_error < 0 {
		return empty_error
	}
	if !path.set(names, index, 'time_to_full_now') {
		return battery_invalid
	}
	to_full, full_time_error := read_supply_count(mut io, path.text(), mut buffer, 0)
	if full_time_error < 0 {
		return full_time_error
	}
	reading.status = status
	reading.to_empty_s = to_empty
	reading.to_full_s = to_full
	return percent
}

// A battery in /sys when there is one, and otherwise /dev/battery exactly as
// before: Apple's SMC battery is not a power supply to the kernel yet.
fn read_battery_reading_with(mut io DeviceIO) BatteryReading {
	mut reading := BatteryReading{}
	if read_supply_battery_with(mut io, mut reading) {
		return reading
	}
	reading.source = .device
	reading.percent = read_battery_with(mut io)
	return reading
}

// How the machine is powered, as far as the kernel has said. /dev/battery
// says nothing about it, and a rise there is only an inference.
enum BatteryPower {
	unknown
	on_battery
	charging
	full
	not_charging
	// No status, but a charger that is supplying power.
	plugged_in
}

fn battery_power(reading BatteryReading) BatteryPower {
	if reading.percent < 0 || reading.percent > 100 || reading.source != .supply {
		return .unknown
	}
	return match reading.status {
		.charging {
			BatteryPower.charging
		}
		.full {
			BatteryPower.full
		}
		.discharging {
			BatteryPower.on_battery
		}
		.not_charging {
			BatteryPower.not_charging
		}
		.unknown {
			if !reading.mains {
				BatteryPower.unknown
			} else if reading.mains_online {
				BatteryPower.plugged_in
			} else {
				BatteryPower.on_battery
			}
		}
	}
}

// What the estimate line says: hours when `estimate` is not negative, counted
// to full rather than to empty when `to_full`, and otherwise one of the
// battery_estimate_* states.
struct BatteryOutlook {
	estimate int = battery_estimate_unavailable
	to_full  bool
}

// The kernel's seconds as the hours the estimate is shown in, rounded to the
// nearest. More than the longest estimate shown stays in the calculating
// state, as an implausibly slow trend does.
fn battery_seconds_to_hours(seconds u64) int {
	if seconds > u64(battery_estimate_maximum_hours) * 3600 + 1799 {
		return battery_estimate_calculating
	}
	return int((seconds + 1800) / 3600)
}

// battery_outlook is the kernel's own estimate for a power supply and the
// trend inferred from the history for /dev/battery, which has nothing else.
fn battery_outlook(reading BatteryReading, history &BatteryHistory) BatteryOutlook {
	if reading.percent < 0 || reading.percent > 100 {
		return BatteryOutlook{}
	}
	if reading.source != .supply {
		return BatteryOutlook{
			estimate: history.remaining_hours(reading.percent)
		}
	}
	match reading.status {
		.full {
			return BatteryOutlook{
				estimate: battery_estimate_full
			}
		}
		.charging {
			hours := if reading.to_full_s == 0 {
				battery_estimate_calculating
			} else {
				battery_seconds_to_hours(reading.to_full_s)
			}
			if hours < 0 {
				return BatteryOutlook{
					estimate: battery_estimate_charging
				}
			}
			return BatteryOutlook{
				estimate: hours
				to_full:  true
			}
		}
		.discharging {
			return BatteryOutlook{
				estimate: if reading.to_empty_s == 0 {
					battery_estimate_calculating
				} else {
					battery_seconds_to_hours(reading.to_empty_s)
				}
			}
		}
		.not_charging {
			return BatteryOutlook{
				estimate: battery_estimate_not_charging
			}
		}
		.unknown {
			return BatteryOutlook{}
		}
	}
}

struct BatteryCache {
mut:
	polled_ms   u64
	initialized bool
	value       int = battery_unavailable
	// The whole of the last sample; `value` is its percentage.
	reading BatteryReading
	history BatteryHistory
}

// Whether the cache still answers for now_ms. A clock that went backwards
// does not.
fn (cache &BatteryCache) fresh(now_ms u64, force bool) bool {
	return !force && cache.initialized && now_ms >= cache.polled_ms
		&& now_ms - cache.polled_ms < 5000
}

// A failed clock invalidates the cache rather than leaving stale charge visible.
fn (mut cache BatteryCache) fail_clock() {
	cache.initialized = false
	cache.value = battery_io
	cache.reading = BatteryReading{
		percent: battery_io
	}
	cache.history.reset()
}

// A failed sample replaces the last one whole: no status or estimate outlives
// the percentage it described. The charger is its own reading and is kept.
fn (mut cache BatteryCache) store(now_ms u64, next BatteryReading) {
	cache.value = if next.percent > 100 || next.percent < battery_io {
		battery_invalid
	} else {
		next.percent
	}
	cache.reading = if cache.value < 0 {
		BatteryReading{
			percent:      cache.value
			source:       next.source
			mains:        next.mains
			mains_online: next.mains_online
		}
	} else {
		next
	}
	cache.polled_ms = now_ms
	cache.initialized = true
	cache.history.observe(now_ms, cache.value)
}

// Settings and the taskbar run on one compositor thread and share this state.
fn (mut cache BatteryCache) poll(now_ms u64, force bool, reader fn () int) int {
	if now_ms == ~u64(0) {
		cache.fail_clock()
		return cache.value
	}
	if cache.fresh(now_ms, force) {
		return cache.value
	}
	cache.store(now_ms, BatteryReading{
		percent: reader()
		source:  .device
	})
	return cache.value
}

// poll for a reader that knows more than a percentage.
fn (mut cache BatteryCache) poll_reading(now_ms u64, force bool, reader fn () BatteryReading) BatteryReading {
	if now_ms == ~u64(0) {
		cache.fail_clock()
		return cache.reading
	}
	if cache.fresh(now_ms, force) {
		return cache.reading
	}
	cache.store(now_ms, reader())
	return cache.reading
}

__global desktop_battery_cache = BatteryCache{}

fn read_battery_sources() BatteryReading {
	mut io := PosixDeviceIO{}
	return read_battery_reading_with(mut io)
}

fn battery_get(force bool) int {
	return desktop_battery_cache.poll_reading(desktop_monotonic_ms(), force, read_battery_sources).percent
}

// The sample the last poll took, without taking another.
fn battery_reading_snapshot() BatteryReading {
	return desktop_battery_cache.reading
}

fn battery_history_snapshot() BatteryHistory {
	return desktop_battery_cache.history
}
