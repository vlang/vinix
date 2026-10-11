// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import os
import time

// These three older regression runners stop at DONE and decide solely from
// the final transcript. Preserve their fractional deadlines and TERM/KILL
// retirement rather than imposing a child-exit or generic FAIL policy.
pub fn boot_check(command []string, env map[string]string, state string, done_marker string, timeout f64) ![]u8 {
	return boot_check_log(command, env, state, done_marker, timeout, state + '/serial.log')!
}

fn checkpoint(fd i32, transcript []u8, start int) !int {
	mut written := start
	for written < transcript.len {
		count := unsafe { C.write(fd, &transcript[written], transcript.len - written) }
		if count < 0 {
			if C.errno == C.EINTR { continue }
			return posix_error()
		}
		if count == 0 { return error('Regression log write made no progress') }
		written += int(count)
	}
	return written
}

pub fn boot_check_log(command []string, env map[string]string, state string, done_marker string, timeout f64, log string) ![]u8 {
	mut log_file := os.open_file(log, 'w')!
	defer { log_file.close() }
	if C.fcntl(log_file.fd, C.F_SETFD, C.FD_CLOEXEC) < 0 { return posix_error() }
	unsafe { C.__atomic_store_n(&interrupted, i32(0), C.__ATOMIC_RELAXED) }
	previous := unsafe { C.signal(C.SIGINT, voidptr(interrupt)) }
	defer { unsafe { C.signal(C.SIGINT, previous) } }
	previous_pipe := unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	defer { unsafe { C.signal(C.SIGPIPE, previous_pipe) } }
	pid, master := spawn_guest(command, env)!
	mut transcript := []u8{}
	mut written := 0
	mut reaped := false
	defer {
		if !reaped {
			C.killpg(pid, C.SIGKILL)
			C.kill(pid, C.SIGKILL)
			wait(pid, false) or {}
		}
		C.close(master)
		checkpoint(log_file.fd, transcript, written) or { eprintln(err.msg()) }
		os.write_file_array(state + '/serial.log', transcript) or { eprintln(err.msg()) }
	}
	deadline := now() + timeout
	for now() < deadline {
		interruption()!
		drain(master, mut transcript, false)!
		written = checkpoint(log_file.fd, transcript, written)!
		if [done_marker, 'KERNEL PANIC', 'FATAL EXCEPTION'].any(transcript.bytestr().contains(it)) { break }
		done, _ := wait(pid, true)!
		if done { reaped = true; break }
		ready(master, false, now() + 0.2)!
	}
	if !reaped {
		// Check before signalling: never retire an already reaped PID.
		done, _ := wait(pid, true)!
		reaped = done
		if !reaped {
			if C.killpg(pid, C.SIGTERM) < 0 && C.errno == C.EPERM { C.kill(pid, C.SIGTERM) }
			end := now() + 10
			for now() < end {
				drain(master, mut transcript, false)!
				written = checkpoint(log_file.fd, transcript, written)!
				reaped_now, _ := wait(pid, true)!
				if reaped_now { reaped = true; break }
				time.sleep(20 * time.millisecond)
			}
			if !reaped {
				C.killpg(pid, C.SIGKILL)
				C.kill(pid, C.SIGKILL)
				reaped, _ = wait(pid, false)!
			}
		}
	}
	drain(master, mut transcript, false)!
	written = checkpoint(log_file.fd, transcript, written)!
	return transcript
}
