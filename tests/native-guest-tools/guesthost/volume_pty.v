// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import os

// The old byte regex was VOLUME DONE (\w+) ino=(\d+)\r*\n. A partial
// line cannot finish the test, and the first complete match selects the phase.
pub fn volume_done(text string) ?string {
	mut offset := 0
	for offset < text.len {
		found := text[offset..].index('VOLUME DONE ') or { return none }
		start := offset + found + 'VOLUME DONE '.len
		mut end := start
		for end < text.len && (text[end].is_alnum() || text[end] == `_`) { end++ }
		offset = start
		if end == start || !text[end..].starts_with(' ino=') { continue }
		mut position := end + ' ino='.len
		digits := position
		for position < text.len && text[position].is_digit() { position++ }
		if position == digits { continue }
		for position < text.len && text[position] == `\r` { position++ }
		if position < text.len && text[position] == `\n` { return text[start..end] }
	}
	return none
}

pub fn volume_verdict(text string) int {
	phase := volume_done(text) or { return 1 }
	return if phase == 'full' && text.contains('VOLUME START')
		&& !['FAIL END', 'FATAL EXCEPTION', 'KERNEL PANIC'].any(text.contains(it)) {
		0
	} else {
		1
	}
}

// This directly owns QEMU. Killing its process group is a power cut: no QMP
// quit, monitor exit or graceful shutdown can flush data before inspection.
pub fn boot_volume(command []string, env map[string]string, state string, timeout int, inherit bool) !int {
	if timeout <= 0 { return error('Volume timeout must be positive') }
	unsafe { C.__atomic_store_n(&interrupted, i32(0), C.__ATOMIC_RELAXED) }
	previous := unsafe { C.signal(C.SIGINT, voidptr(interrupt)) }
	defer { unsafe { C.signal(C.SIGINT, previous) } }
	previous_pipe := unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	defer { unsafe { C.signal(C.SIGPIPE, previous_pipe) } }
	pid, master := spawn_guest(command, env)!
	mut reaped := false
	defer {
		if !reaped {
			C.killpg(pid, C.SIGKILL)
			C.kill(pid, C.SIGKILL)
			wait(pid, false) or {}
		}
		C.close(master)
	}
	mut transcript := []u8{}
	mut cause := ''
	deadline := now() + timeout
	for now() < deadline {
		done, _ := wait(pid, true) or {
			cause = err.msg()
			break
		}
		if done {
			reaped = true
			break
		}
		readable := ready(master, false, now() + 0.25) or {
			cause = err.msg()
			break
		}
		if !readable { continue }
		mut buffer := [65536]u8{}
		count := C.read(master, &buffer[0], buffer.len)
		if count < 0 {
			if C.errno in [C.EIO, C.EAGAIN, C.EWOULDBLOCK] { break }
			cause = posix_error().msg()
			break
		}
		if count == 0 { break }
		transcript << buffer[..count]
		if inherit {
			abi_console(buffer[..count]) or {
				cause = err.msg()
				break
			}
		}
		text := transcript.bytestr()
		if _ := volume_done(text) { break }
		if ['FAIL END', 'FATAL EXCEPTION', 'KERNEL PANIC'].any(text.contains(it)) && text.ends_with('\n') {
			break
		}
	}
	// Retire the writer before reading its disk; shutdown output is excluded.
	if !reaped {
		C.killpg(pid, C.SIGKILL)
		C.kill(pid, C.SIGKILL)
		done, _ := wait(pid, false) or { return err }
		reaped = done
	}
	os.write_file_array(state + '/serial.log', transcript)!
	if cause != '' { return error(cause) }
	result := volume_verdict(transcript.bytestr())
	if result != 0 && inherit {
		eprintln('ERROR: volume guest stopped without the full completion contract')
	}
	return result
}
