// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import os

pub struct PowercutPolicy {
pub:
	start string
	done string
	phase string
	failures []string
	lookback int
	failure_newline bool
}

// Match the original byte regex PREFIX (\w+) ino=(\d+)\r*\n. The
// entire number and newline must have arrived before a power cut is allowed.
pub fn powercut_done(text string, prefix string) ?(string, string) {
	mut offset := 0
	for offset < text.len {
		found := text[offset..].index(prefix + ' ') or { return none }
		start := offset + found + prefix.len + 1
		mut end := start
		for end < text.len && (text[end].is_alnum() || text[end] == `_`) { end++ }
		offset = start
		if end == start || !text[end..].starts_with(' ino=') { continue }
		mut position := end + ' ino='.len
		digits := position
		for position < text.len && text[position].is_digit() { position++ }
		if position == digits { continue }
		number_end := position
		for position < text.len && text[position] == `\r` { position++ }
		if position < text.len && text[position] == `\n` { return text[start..end], text[digits..number_end] }
	}
	return none
}

pub fn powercut_verdict(text string, policy PowercutPolicy) int {
	phase, _ := powercut_done(text, policy.done) or { return 1 }
	return if phase == policy.phase && text.contains(policy.start)
		&& !policy.failures.any(text.contains(it)) { 0 } else { 1 }
}

// QEMU is the directly owned child. SIGKILL retires its writer before any
// disk inspection; monitor/QMP quit and graceful shutdown are never used.
pub fn boot_powercut(command []string, env map[string]string, state string,
	policy PowercutPolicy, timeout int, stream bool, inherit bool) !int {
	if timeout <= 0 || policy.start == '' || policy.done == '' || policy.phase == '' || policy.lookback < 0 {
		return error('Power-cut timeout and marker policy must be valid')
	}
	unsafe { C.__atomic_store_n(&interrupted, i32(0), C.__ATOMIC_RELAXED) }
	previous := unsafe { C.signal(C.SIGINT, voidptr(interrupt)) }
	defer { unsafe { C.signal(C.SIGINT, previous) } }
	previous_pipe := unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	defer { unsafe { C.signal(C.SIGPIPE, previous_pipe) } }
	pid, master := spawn_guest(command, env)!
	mut reaped := false
	defer {
		if !reaped { C.killpg(pid, C.SIGKILL); C.kill(pid, C.SIGKILL); wait(pid, false) or {} }
		C.close(master)
	}
	mut transcript := []u8{}
	mut cause := ''
	deadline := now() + timeout
	for now() < deadline {
		done, _ := wait(pid, true) or { cause = err.msg(); break }
		if done { reaped = true; break }
		readable := ready(master, false, now() + 0.25) or { cause = err.msg(); break }
		if !readable { continue }
		mut buffer := [65536]u8{}
		count := C.read(master, &buffer[0], buffer.len)
		if count < 0 {
			if C.errno in [C.EIO, C.EAGAIN, C.EWOULDBLOCK] { break }
			cause = posix_error().msg(); break
		}
		if count == 0 { break }
		transcript << buffer[..count]
		if stream && inherit { abi_console(buffer[..count]) or { cause = err.msg(); break } }
		text := transcript.bytestr()
		recent := if policy.lookback > 0 && text.len > policy.lookback { text[text.len - policy.lookback..] } else { text }
		if _, _ := powercut_done(recent, policy.done) { break }
		if policy.failures.any(recent.contains(it)) && (!policy.failure_newline || recent.ends_with('\n')) { break }
	}
	if !reaped {
		C.killpg(pid, C.SIGKILL)
		C.kill(pid, C.SIGKILL)
		done, _ := wait(pid, false)!
		reaped = done
	}
	os.write_file_array(state + '/serial.log', transcript)!
	if !stream && inherit { abi_console(transcript)!; println('') }
	if cause != '' { return error(cause) }
	result := powercut_verdict(transcript.bytestr(), policy)
	if result != 0 && inherit { eprintln('ERROR: ' + policy.phase + ' stopped without its complete power-cut contract (timeout ' + timeout.str() + 's)') }
	return result
}
