// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import os
import time

fn C.truncate(&char, i64) i32

fn abi_console(bytes []u8) ! {
	mut written := 0
	for written < bytes.len {
		count := unsafe { C.write(1, &bytes[0] + written, uint(bytes.len - written)) }
		if count < 0 {
			if C.errno == C.EINTR { continue }
			return posix_error()
		}
		if count == 0 { return error('Serial output closed') }
		written += int(count)
	}
}

pub fn abi_verdict(text string, arch string, expected []string, failures []string,
	finished bool, forced bool, status int) int {
	for marker in expected { if text.count(marker) != 1 { return 1 } }
	for marker in failures { if text.contains(marker) { return 1 } }
	if arch == 'aarch64' { return if forced || status != 0 { 1 } else { 0 } }
	return if finished { 0 } else { 1 }
}

fn abi_stop(pid i32, master i32, state string, arm bool) !bool {
	done, _ := wait(pid, true)!
	if done { return true }
	if !arm { quit_monitor(state + '/qmp.sock') or {} }
	C.write(master, c'\x01x', 2)
	for phase in 0 .. 3 {
		if phase > 0 {
			signal := if phase == 1 { C.SIGTERM } else { C.SIGKILL }
			if C.killpg(pid, signal) < 0 && C.errno == C.EPERM { C.kill(pid, signal) }
		}
		deadline := now() + if phase == 0 {
			5
		} else if arm {
			2
		} else {
			3
		}
		for now() < deadline {
			reaped_now, _ := wait(pid, true)!
			if reaped_now { return true }
			time.sleep(50 * time.millisecond)
		}
	}
	return error('ABI guest did not stop')
}

// Preserve the imported controllers' verdicts and timing. ARM requests a
// monitor exit immediately and allows ten seconds for it; x86 captures two
// further seconds after a pass/failure. Both require every marker exactly once.
pub fn boot_abi(command []string, env map[string]string, state string, arch string,
	expected []string, pass string, failures []string, timeout int, inherit bool) !int {
	return boot_abi_from(command, env, state, arch, expected, pass, failures, timeout, inherit, '')!
}

pub fn boot_abi_from(command []string, env map[string]string, state string, arch string,
	expected []string, pass string, failures []string, timeout int, inherit bool, directory string) !int {
	return boot_abi_logged(command, env, state, arch, expected, pass, failures, timeout, inherit, directory, '')!
}

// Emulator commands retain the byte stream while also displaying it. The
// caller owns the log path; compiler output never enters the serial capture.
pub fn boot_abi_logged(command []string, env map[string]string, state string, arch string,
	expected []string, pass string, failures []string, timeout int, inherit bool, directory string, log_path string) !int {
	mut log := os.File{}
	if log_path != '' { log = os.open_append(log_path)! }
	defer { if log_path != '' { log.close() } }
	if timeout <= 0 || expected.len == 0 || expected.any(it == '') || pass == '' {
		return error('ABI timeout and markers must be positive/nonempty')
	}
	unsafe { C.__atomic_store_n(&interrupted, i32(0), C.__ATOMIC_RELAXED) }
	previous := unsafe { C.signal(C.SIGINT, voidptr(interrupt)) }
	defer { unsafe { C.signal(C.SIGINT, previous) } }
	previous_pipe := unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	defer { unsafe { C.signal(C.SIGPIPE, previous_pipe) } }
	pid, master := spawn_guest_at(command, env, directory)!
	mut transcript := []u8{}
	mut reaped := false
	defer {
		if !reaped {
			C.killpg(pid, C.SIGKILL)
			C.kill(pid, C.SIGKILL)
			wait(pid, false) or {}
		}
		C.close(master)
	}
	deadline := now() + timeout
	mut finished_at := f64(-1)
	mut status := 0
	mut cause := ''
	for now() < deadline {
		done, code := wait(pid, true) or {
			cause = err.msg()
			break
		}
		if done {
			reaped = true
			status = code
			break
		}
		readable := ready(master, false, now() + 0.25) or {
			cause = err.msg()
			break
		}
		if readable {
			// One bounded read per iteration, as in the original controllers.
			mut buffer := [65536]u8{}
			count := C.read(master, &buffer[0], buffer.len)
			if count < 0 {
				if C.errno in [C.EIO, C.EAGAIN, C.EWOULDBLOCK, C.EINTR] { continue }
				cause = posix_error().msg()
				break
			}
			if count > 0 {
				transcript << buffer[..count]
				if log_path != '' {
					log.write(buffer[..count]) or { cause = err.msg(); break }
					log.flush()
				}
				if inherit {
					abi_console(buffer[..count]) or {
						cause = err.msg()
						break
					}
				}
			}
		}
		text := transcript.bytestr()
		recent := if arch == 'aarch64' || text.len <= 131072 {
			text
		} else {
			text[text.len - 131072..]
		}
		if finished_at < 0 && (recent.contains(pass) || failures.any(recent.contains(it))) {
			finished_at = now()
			if arch == 'aarch64' { C.write(master, c'\x01x', 2) }
		}
		if finished_at >= 0 && now() - finished_at > if arch == 'aarch64' { 10 } else { 2 } {
			break
		}
	}
	forced := !reaped
	unsafe {
		C.__atomic_store_n(&interrupted, i32(0), C.__ATOMIC_RELAXED)
		C.signal(C.SIGINT, C.SIG_IGN)
	}
	if !reaped {
		reaped = abi_stop(pid, master, state, arch == 'aarch64') or {
			cause = err.msg()
			false
		}
	}
	// Save exactly what the capture loop consumed; cleanup output cannot turn
	// a timeout or an early process exit into a successful test.
	os.write_file_array(state + '/serial.log', transcript)!
	if cause != '' { return error(cause) }
	result := abi_verdict(transcript.bytestr(), arch, expected, failures, finished_at >= 0, forced, status)
	if inherit {
		for marker in expected {
			if transcript.bytestr().count(marker) != 1 {
				eprintln('ERROR: expected result must appear exactly once: ' + marker)
			}
		}
		for marker in failures {
			if transcript.bytestr().contains(marker) {
				eprintln('ERROR: observed failure: ' + marker)
			}
		}
		if arch == 'aarch64' && forced { eprintln('ERROR: VM did not exit after the test') }
		if arch == 'aarch64' && status != 0 { eprintln('ERROR: VM exited ' + status.str()) }
		if arch != 'aarch64' && finished_at < 0 {
			eprintln('ERROR: test did not finish before the timeout')
		}
		if result == 0 { println('ABI guest verdicts passed.') }
	}
	return result
}
