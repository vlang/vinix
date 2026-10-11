// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import os
import time

pub struct SessionPolicy {
pub:
	pass              string
	failures          []string
	lookback          int
	settle            f64
	monitor_at_marker bool
	cleanup_wait      f64 = 5
	term_wait         f64 = 2
	kill_wait         f64 = 2
	log               string
}

pub struct SessionResult {
pub:
	text     string
	finished bool
	passed   bool
	forced   bool
	status   int
}

fn session_log(mut file os.File, bytes []u8) ! {
	mut offset := 0
	for offset < bytes.len {
		n := file.write(bytes[offset..])!
		if n == 0 { return error('Serial log write stopped') }
		offset += n
	}
	file.flush()
}

fn session_stop(pid i32, master i32, already_reaped bool, policy SessionPolicy) ! {
	mut reaped := already_reaped
	C.write(master, c'\x01x', 2)
	for stage, seconds in [policy.cleanup_wait, policy.term_wait, policy.kill_wait] {
		if stage > 0 { C.killpg(pid, if stage == 1 { C.SIGTERM } else { C.SIGKILL }) }
		deadline := now() + seconds
		for now() < deadline {
			if !reaped {
				done, _ := wait(pid, true)!
				reaped = done
			}
			if C.killpg(pid, 0) < 0 && C.errno == C.ESRCH { return }
			if ready(master, false, now() + 0.05)! {
				mut bytes := [65536]u8{}
				if C.read(master, &bytes[0], bytes.len) <= 0 { time.sleep(10 * time.millisecond) }
			}
		}
	}
	return error('Serial guest process group did not retire')
}

// Capture policy is independent of the final verdict. In particular Docker
// retains its first observed pass/failure, while NUMA requires a natural exit.
// Cleanup bytes never supply a missing feature or turn a timeout into a pass.
pub fn boot_session(argv []string, env map[string]string, state string, policy SessionPolicy,
	seconds int, inherit bool) !SessionResult {
	if seconds <= 0 { return error('Serial timeout must be positive') }
	mut log := os.File{}
	if policy.log != '' { log = os.create(policy.log)! }
	defer { if policy.log != '' { log.close() } }
	unsafe { C.__atomic_store_n(&interrupted, i32(0), C.__ATOMIC_RELAXED) }
	previous := unsafe { C.signal(C.SIGINT, voidptr(interrupt)) }
	defer { unsafe { C.signal(C.SIGINT, previous) } }
	previous_pipe := unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	defer { unsafe { C.signal(C.SIGPIPE, previous_pipe) } }
	pid, master := spawn_guest(argv, env)!
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
	mut status := 0
	mut finish := f64(-1)
	mut passed := false
	mut cause := ''
	deadline := now() + seconds
	for now() < deadline {
		done, code := wait(pid, true) or {
			cause = err.msg()
			break
		}
		if done {
			reaped = true
			status = if code < 0 { 128 - code } else { code }
			break
		}
		readable := ready(master, false, now() + 0.25) or {
			cause = err.msg()
			break
		}
		if readable {
			mut bytes := [65536]u8{}
			count := C.read(master, &bytes[0], bytes.len)
			if count < 0 {
				if C.errno in [C.EIO, C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { continue }
				cause = posix_error().msg()
				break
			}
			if count > 0 {
				transcript << bytes[..count]
				if policy.log != '' {
					session_log(mut log, bytes[..count]) or {
						cause = err.msg()
						break
					}
				}
				if inherit {
					abi_console(bytes[..count]) or {
						cause = err.msg()
						break
					}
				}
			}
		}
		text := transcript.bytestr()
		recent := if policy.lookback > 0 && text.len > policy.lookback {
			text[text.len - policy.lookback..]
		} else {
			text
		}
		if finish < 0 && (recent.contains(policy.pass) || policy.failures.any(recent.contains(it))) {
			finish = now()
			passed = recent.contains(policy.pass)
			if policy.monitor_at_marker { C.write(master, c'\x01x', 2) }
		}
		if finish >= 0 && now() - finish >= policy.settle { break }
	}
	forced := !reaped
	unsafe {
		C.__atomic_store_n(&interrupted, i32(0), C.__ATOMIC_RELAXED)
		C.signal(C.SIGINT, C.SIG_IGN)
	}
	session_stop(pid, master, reaped, policy)!
	reaped = true
	os.write_file_array(state + '/serial.log', transcript)!
	if cause != '' { return error(cause) }
	return SessionResult{transcript.bytestr(), finish >= 0, passed, forced, status}
}
