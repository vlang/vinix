// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
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

enum BatteryTrend {
	unknown
	discharging
	charging
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

struct BatteryCache {
mut:
	polled_ms   u64
	initialized bool
	value       int = battery_unavailable
	history     BatteryHistory
}

// Settings and the taskbar run on one compositor thread and share this state.
// A failed clock invalidates the cache rather than leaving stale charge visible.
fn (mut cache BatteryCache) poll(now_ms u64, force bool, reader fn () int) int {
	if now_ms == ~u64(0) {
		cache.initialized = false
		cache.value = battery_io
		cache.history.reset()
		return cache.value
	}
	if !force && cache.initialized && now_ms >= cache.polled_ms
		&& now_ms - cache.polled_ms < 5000 {
		return cache.value
	}
	next := reader()
	cache.value = if next > 100 || next < battery_io { battery_invalid } else { next }
	cache.polled_ms = now_ms
	cache.initialized = true
	cache.history.observe(now_ms, cache.value)
	return cache.value
}

__global desktop_battery_cache = BatteryCache{}

fn read_battery_device() int {
	mut io := PosixDeviceIO{}
	return read_battery_with(mut io)
}

fn battery_get(force bool) int {
	return desktop_battery_cache.poll(desktop_monotonic_ms(), force, read_battery_device)
}

fn battery_history_snapshot() BatteryHistory {
	return desktop_battery_cache.history
}
