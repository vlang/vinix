// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Userspace client for the kernel's power files in /sys: whether the machine
// can sleep, what closing its lid does, and the CPU performance profile. Each
// file is read whole in one read and written as one word; nothing here
// allocates, and nothing is remembered between calls.
module main

const power_state_path = '/sys/power/state'
const power_suspend_success_path = '/sys/power/suspend_stats/success'
const power_lid_state_path = '/sys/power/lid/state'
const power_lid_action_path = '/sys/power/lid/action'
const power_profile_policy_path = '/sys/power/profile_policy'
const power_profile_path = '/sys/devices/system/cpu/cpufreq/profile'
// More than any of these files says, so a file that fills it said too much.
const power_text_capacity = 64
const power_retries = 4

enum PowerResult {
	ok
	unavailable
	permission
	invalid
	io
}

// What the kernel's power files say. Each part stands alone: a machine can
// sleep and have no lid, or have a lid and no way to set a CPU's frequency.
struct PowerControls {
mut:
	// /sys/power/state takes `mem`.
	sleep bool
	// There is a lid whose position the kernel knows, and what closing it
	// does.
	lid        bool
	lid_action LidAction
	// The profile files are there and say this. `automatic` is the kernel
	// following the power source.
	profile_known bool
	profile       PowerProfile
	// The kernel takes a profile. Without a frequency driver the file is
	// read-only and a write to it is refused.
	profile_settable bool
}

fn power_io_result(result DeviceError) PowerResult {
	return match result {
		.unavailable { .unavailable }
		.permission { .permission }
		else { .io }
	}
}

fn power_word_byte(byte u8) bool {
	return (byte >= `a` && byte <= `z`) || (byte >= `0` && byte <= `9`) || byte == `_`
}

// Whether a list of words has `word` in it: lower-case words, one space
// between them and LF at the end, the way /sys/power/state lists what it
// takes. Text in any other shape lists nothing.
fn power_words_contain(text []u8, word string) bool {
	if text.len < 2 || text[text.len - 1] != `\n` {
		return false
	}
	mut found := false
	mut start := 0
	for start < text.len - 1 {
		mut end := start
		for end < text.len - 1 && power_word_byte(text[end]) {
			end++
		}
		if end == start || (end < text.len - 1 && text[end] != ` `) {
			return false
		}
		if bytes_equal_text(text[start..end], word) {
			found = true
		}
		start = end + 1
		// A space with no word after it.
		if end < text.len - 1 && start == text.len - 1 {
			return false
		}
	}
	return found
}

// One of two words, the chosen one in brackets: `[first] second` or
// `first [second]` and LF. Returns which is chosen, or -1 for anything else.
fn parse_power_choice(text []u8, first string, second string) int {
	if text.len == first.len + second.len + 4 && text[0] == `[` && text[first.len + 1] == `]`
		&& text[first.len + 2] == ` ` && text[text.len - 1] == `\n`
		&& bytes_equal_text(text[1..first.len + 1], first)
		&& bytes_equal_text(text[first.len + 3..text.len - 1], second) {
		return 0
	}
	if text.len == first.len + second.len + 4 && text[first.len] == ` `
		&& text[first.len + 1] == `[` && text[text.len - 2] == `]` && text[text.len - 1] == `\n`
		&& bytes_equal_text(text[..first.len], first)
		&& bytes_equal_text(text[first.len + 2..text.len - 2], second) {
		return 1
	}
	return -1
}

// The three profiles the kernel names, each with its LF.
fn parse_power_profile(text []u8) ?PowerProfile {
	if bytes_equal_text(text, 'performance\n') {
		return .performance
	}
	if bytes_equal_text(text, 'balanced\n') {
		return .balanced
	}
	if bytes_equal_text(text, 'power_saver\n') {
		return .power_saver
	}
	return none
}

// The profile file, and whether its mode lets it be written: opened
// read-only, asked, read once and closed. Returns the length or a negative
// failure, as read_supply_text does.
fn read_power_profile_text(mut io DeviceIO, mut buffer []u8) (int, bool) {
	mut fd := -1
	mut open_error := DeviceError.io
	for _ in 0 .. 16 {
		fd, open_error = io.open(power_profile_path, false)
		if fd >= 0 || open_error != .interrupted {
			break
		}
	}
	if fd < 0 {
		return battery_io_result(open_error), false
	}
	writable, stat_error := io.is_writable(fd)
	mut length := -1
	mut read_error := DeviceError.io
	for _ in 0 .. power_retries {
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
	if io.close(fd) != .none {
		result = battery_io
	}
	return result, writable && stat_error == .none
}

// read_power_controls_with reads every file again. A file that is missing or
// does not say what the kernel writes leaves its part as not there, which is
// how a kernel without the file, a machine without a lid and a damaged
// answer are all shown: the control is not offered.
fn read_power_controls_with(mut io DeviceIO) PowerControls {
	mut controls := PowerControls{}
	mut text := [power_text_capacity]u8{}
	mut buffer := unsafe { (&text[0]).vbytes(text.len) }
	mut length := read_supply_text(mut io, power_state_path, mut buffer)
	controls.sleep = length > 0 && power_words_contain(buffer[..length], 'mem')

	// `unknown` is the kernel having found no lid.
	length = read_supply_text(mut io, power_lid_state_path, mut buffer)
	if length > 0 && (bytes_equal_text(buffer[..length], 'open\n')
		|| bytes_equal_text(buffer[..length], 'closed\n')) {
		length = read_supply_text(mut io, power_lid_action_path, mut buffer)
		if length > 0 {
			action := parse_power_choice(buffer[..length], 'suspend', 'ignore')
			if action >= 0 {
				controls.lid = true
				controls.lid_action = if action == 1 { LidAction.ignore } else { LidAction.suspend }
			}
		}
	}

	length = read_supply_text(mut io, power_profile_policy_path, mut buffer)
	if length <= 0 {
		return controls
	}
	policy := parse_power_choice(buffer[..length], 'auto', 'manual')
	if policy < 0 {
		return controls
	}
	profile_length, writable := read_power_profile_text(mut io, mut buffer)
	if profile_length <= 0 {
		return controls
	}
	profile := parse_power_profile(buffer[..profile_length]) or { return controls }
	controls.profile_known = true
	controls.profile = if policy == 0 { PowerProfile.automatic } else { profile }
	controls.profile_settable = writable
	return controls
}

// One word and LF in one write. A positive short write is an error and its
// rest is never sent: the kernel would take that as another word.
fn write_power_word_with(mut io DeviceIO, path string, word string) PowerResult {
	mut text := [power_text_capacity]u8{}
	if word.len == 0 || word.len + 1 > text.len {
		return .invalid
	}
	for i, byte in word {
		text[i] = byte
	}
	text[word.len] = `\n`
	bytes := unsafe { (&text[0]).vbytes(word.len + 1) }
	mut fd := -1
	mut open_error := DeviceError.io
	for _ in 0 .. 16 {
		fd, open_error = io.open(path, true)
		if fd >= 0 || open_error != .interrupted {
			break
		}
	}
	if fd < 0 {
		return power_io_result(open_error)
	}
	defer { io.close(fd) }
	for _ in 0 .. power_retries {
		written, write_error := io.write(fd, bytes)
		if written >= 0 {
			return if written == bytes.len { .ok } else { .io }
		}
		if write_error != .interrupted {
			return power_io_result(write_error)
		}
	}
	return .io
}

fn set_lid_action_with(mut io DeviceIO, action LidAction) PowerResult {
	return write_power_word_with(mut io, power_lid_action_path, action.code())
}

// Automatic hands the choice back to the kernel. Any other profile tells the
// kernel to leave the profile alone and then names it. A kernel that takes
// no profile is found out from the file's mode before anything is written,
// so its policy is not turned to manual for nothing; and should the profile
// be refused after all, the policy that was there is put back.
fn set_power_profile_with(mut io DeviceIO, profile PowerProfile) PowerResult {
	if profile == .automatic {
		return write_power_word_with(mut io, power_profile_policy_path, 'auto')
	}
	before := read_power_controls_with(mut io)
	if !before.profile_known {
		return .unavailable
	}
	if !before.profile_settable {
		return .permission
	}
	policy := write_power_word_with(mut io, power_profile_policy_path, 'manual')
	if policy != .ok {
		return policy
	}
	result := write_power_word_with(mut io, power_profile_path, profile.code())
	if result != .ok && before.profile == .automatic {
		write_power_word_with(mut io, power_profile_policy_path, 'auto')
	}
	return result
}

// apply_power_settings_with puts the saved lid action and profile back into
// a kernel that has just started with its own. Only what differs is written,
// and nothing the kernel does not have or would refuse.
fn apply_power_settings_with(mut io DeviceIO, settings &Settings) {
	controls := read_power_controls_with(mut io)
	if controls.lid && controls.lid_action != settings.lid_action {
		set_lid_action_with(mut io, settings.lid_action)
	}
	if controls.profile_known && controls.profile != settings.power_profile
		&& (settings.power_profile == .automatic || controls.profile_settable) {
		set_power_profile_with(mut io, settings.power_profile)
	}
}

// How many times the machine has slept and come back, or none when the
// kernel does not say. A sleep that ended in an error from the write is
// still a sleep if this went up.
fn read_suspend_successes_with(mut io DeviceIO) ?u64 {
	mut text := [power_text_capacity]u8{}
	mut buffer := unsafe { (&text[0]).vbytes(text.len) }
	length := read_supply_text(mut io, power_suspend_success_path, mut buffer)
	if length <= 0 {
		return none
	}
	return parse_supply_count(buffer[..length])
}

fn read_power_controls(mut out PowerControls) {
	mut io := PosixDeviceIO{}
	out = read_power_controls_with(mut io)
}

fn set_lid_action(action LidAction) PowerResult {
	mut io := PosixDeviceIO{}
	return set_lid_action_with(mut io, action)
}

fn set_power_profile(profile PowerProfile) PowerResult {
	mut io := PosixDeviceIO{}
	return set_power_profile_with(mut io, profile)
}

fn apply_power_settings(settings &Settings) {
	mut io := PosixDeviceIO{}
	apply_power_settings_with(mut io, settings)
}

fn read_suspend_successes() ?u64 {
	mut io := PosixDeviceIO{}
	return read_suspend_successes_with(mut io)
}
