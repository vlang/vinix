// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module main

const battery_unavailable = -1
const battery_permission = -2
const battery_invalid = -3
const battery_io = -4

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
}

// Settings and the taskbar run on one compositor thread and share this state.
// A failed clock invalidates the cache rather than leaving stale charge visible.
fn (mut cache BatteryCache) poll(now_ms u64, force bool, reader fn () int) int {
	if now_ms == ~u64(0) {
		cache.initialized = false
		cache.value = battery_io
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
