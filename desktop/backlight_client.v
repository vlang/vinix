// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Userspace client for /dev/apple-panel-bl. No hardware access, C structs,
// C helper implementations, text splitting allocations or optimistic state.
module main

const backlight_path = '/dev/apple-panel-bl'
const backlight_capacity = 256
const backlight_retries = 4
const backlight_keys = ['requested_nits', 'actual_nits', 'min_nits', 'max_nits', 'pending', 'online']!

enum BacklightResult {
	ok
	unavailable
	permission
	offline
	invalid
	io
}

struct BacklightState {
mut:
	requested_nits int = -1
	actual_nits    int = -1
	min_nits       int
	max_nits       int
	pending        bool
	online         bool
	writable       bool
}

fn bytes_equal_text(bytes []u8, text string) bool {
	if bytes.len != text.len {
		return false
	}
	for i, byte in bytes {
		if byte != text[i] {
			return false
		}
	}
	return true
}

fn backlight_decimal(bytes []u8) ?int {
	if bytes.len == 0 {
		return none
	}
	mut value := 0
	for byte in bytes {
		if byte < `0` || byte > `9` {
			return none
		}
		digit := int(byte - `0`)
		if value > (0x7fffffff - digit) / 10 {
			return none
		}
		value = value * 10 + digit
	}
	return value
}

// Exactly one whole read snapshot, never a concatenation of snapshots.
// Reject missing/duplicate/unknown keys, overflow and incomplete lines.
fn parse_backlight(text []u8) ?BacklightState {
	if text.len == 0 || text.len >= backlight_capacity {
		return none
	}
	mut values := [6]int{}
	mut seen := u32(0)
	mut pos := 0
	for pos < text.len {
		start := pos
		for pos < text.len && text[pos] != `\n` {
			pos++
		}
		if pos == text.len {
			return none
		}
		end := pos
		pos++
		mut eq := start
		for eq < end && text[eq] != `=` {
			eq++
		}
		if eq == end {
			return none
		}
		mut field := -1
		for i, key in backlight_keys {
			if bytes_equal_text(text[start..eq], key) {
				field = i
				break
			}
		}
		if field < 0 || seen & (u32(1) << field) != 0 {
			return none
		}
		seen |= u32(1) << field
		value := text[eq + 1..end]
		values[field] = if field < 2 && bytes_equal_text(value, 'unknown') {
			-1
		} else {
			backlight_decimal(value) or { return none }
		}
	}
	if seen != 63 || values[2] < 1 || values[3] < values[2] || values[4] > 1 || values[5] > 1
		|| (values[0] != -1 && (values[0] < values[2] || values[0] > values[3])) {
		return none
	}
	return BacklightState{
		requested_nits: values[0]
		actual_nits: values[1]
		min_nits: values[2]
		max_nits: values[3]
		pending: values[4] != 0
		online: values[5] != 0
	}
}

fn backlight_percent_to_nits(state &BacklightState, percent int) ?int {
	if percent < 0 || percent > 100 || state.min_nits < 1 || state.max_nits < state.min_nits {
		return none
	}
	// 0% is the advertised minimum, not panel power off.
	return state.min_nits + int(((i64(state.max_nits) - state.min_nits) * percent + 50) / 100)
}

fn backlight_percent(state &BacklightState) int {
	nits := if state.requested_nits >= 0 { state.requested_nits } else { state.actual_nits }
	if nits < 0 || state.min_nits < 1 || state.max_nits < state.min_nits {
		return -1
	}
	if nits <= state.min_nits || state.max_nits == state.min_nits {
		return 0
	}
	if nits >= state.max_nits {
		return 100
	}
	range := i64(state.max_nits) - state.min_nits
	return int(((i64(nits) - state.min_nits) * 100 + range / 2) / range)
}

fn backlight_io_result(result DeviceError) BacklightResult {
	return match result {
		.unavailable { .unavailable }
		.permission { .permission }
		else { .io }
	}
}

// Returns ownership of fd only on success. All failures close exactly once.
fn open_backlight_state(mut io DeviceIO) (BacklightState, int, BacklightResult) {
	mut writable := true
	mut fd, mut open_error := io.open(backlight_path, true)
	if fd < 0 && open_error == .permission {
		writable = false
		fd, open_error = io.open(backlight_path, false)
	}
	if fd < 0 {
		return BacklightState{}, -1, backlight_io_result(open_error)
	}
	mut keep_fd := false
	defer { if !keep_fd { io.close(fd) } }
	character, stat_error := io.is_character(fd)
	if stat_error != .none {
		return BacklightState{}, -1, BacklightResult.io
	}
	if !character {
		return BacklightState{}, -1, BacklightResult.invalid
	}
	mut text := [backlight_capacity]u8{}
	mut buffer := unsafe { (&text[0]).vbytes(text.len) }
	mut length := -1
	mut read_error := DeviceError.io
	for _ in 0 .. backlight_retries {
		length, read_error = io.read(fd, mut buffer)
		if length >= 0 || read_error != .interrupted {
			break
		}
	}
	if length < 0 {
		return BacklightState{}, -1, backlight_io_result(read_error)
	}
	if length > buffer.len {
		return BacklightState{}, -1, BacklightResult.invalid
	}
	mut next := parse_backlight(buffer[..length]) or { return BacklightState{}, -1, BacklightResult.invalid }
	next.writable = writable
	keep_fd = true
	return next, fd, BacklightResult.ok
}

fn read_backlight_with(mut io DeviceIO, mut out BacklightState) BacklightResult {
	next, fd, result := open_backlight_state(mut io)
	if result != .ok {
		return result
	}
	if io.close(fd) != .none {
		return .io
	}
	out = next
	return .ok
}

// Revalidate bounds and status on the same descriptor before every command.
// Retry EINTR only; a positive short write is never followed by its suffix,
// which the kernel would interpret as a different brightness command.
fn set_backlight_percent_with(mut io DeviceIO, percent int) BacklightResult {
	if percent < 0 || percent > 100 {
		return .invalid
	}
	state, fd, result := open_backlight_state(mut io)
	if result != .ok {
		return result
	}
	defer { io.close(fd) }
	if !state.online {
		return .offline
	}
	if !state.writable {
		return .permission
	}
	nits := backlight_percent_to_nits(&state, percent) or { return .invalid }
	text := '${nits}\n'
	defer { unsafe { text.free() }
	 }
	bytes := unsafe { text.str.vbytes(text.len) }
	for _ in 0 .. backlight_retries {
		written, write_error := io.write(fd, bytes)
		if written >= 0 {
			return if written == bytes.len { .ok } else { .io }
		}
		if write_error != .interrupted {
			return backlight_io_result(write_error)
		}
	}
	return .io
}

fn read_backlight(mut out BacklightState) BacklightResult {
	mut io := PosixDeviceIO{}
	return read_backlight_with(mut io, mut out)
}

fn set_backlight_percent(percent int) BacklightResult {
	mut io := PosixDeviceIO{}
	return set_backlight_percent_with(mut io, percent)
}
