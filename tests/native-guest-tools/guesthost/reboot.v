// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import os

const reboot_start = 'VINIX REBOOT PERSISTENCE: START'
const reboot_wrote = 'VINIX REBOOT PERSISTENCE: WROTE MARKER, REBOOTING'
const reboot_sync = 'VINIX REBOOT PERSISTENCE: SYNCING'
const reboot_pass = 'VINIX REBOOT PERSISTENCE: PASS'
const reboot_failures = ['VINIX REBOOT PERSISTENCE: FAIL', 'FATAL EXCEPTION', 'KERNEL PANIC']

pub fn reboot_verdict(text string) int {
	return if reboot_failures.any(text.contains(it)) || text.count(reboot_start) < 2
		|| text.count(reboot_sync) < 2 || !text.contains(reboot_wrote) || !text.contains(reboot_pass) {
		1
	} else {
		0
	}
}

fn reboot_stop(pid i32, master i32, already_reaped bool) ! {
	mut reaped := already_reaped
	C.write(master, c'\x01x', 2)
	for stage in 0 .. 3 {
		if stage > 0 {
			C.killpg(pid, if stage == 1 { C.SIGTERM } else { C.SIGKILL })
		}
		deadline := now() + if stage == 0 { 5 } else { 2 }
		for now() < deadline {
			if !reaped {
				done, _ := wait(pid, true)!
				reaped = done
			}
			if C.killpg(pid, 0) < 0 && C.errno == C.ESRCH { return }
			if ready(master, false, now() + 0.05)! {
				mut buffer := [65536]u8{}
				C.read(master, &buffer[0], buffer.len)
			}
		}
	}
	return error('Reboot guest process group did not retire')
}

// One QEMU process remains attached to one disk through the guest reset.
// The original capture gate is PASS/failure within the last 8192 bytes; the
// final verdict requires both boot and sync brackets in the full transcript.
pub fn boot_reboot(command []string, env map[string]string, state string, seconds int, inherit bool) !int {
	if seconds <= 0 { return error('Reboot timeout must be positive') }
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
	deadline := now() + seconds
	for now() < deadline {
		done, _ := wait(pid, true) or {
			cause = err.msg()
			break
		}
		if done {
			reaped = true
			break
		}
		if !ready(master, false, now() + 0.25) or {
			cause = err.msg()
			break
		} {
			continue
		}
		mut buffer := [65536]u8{}
		count := C.read(master, &buffer[0], buffer.len)
		if count <= 0 { break }
		transcript << buffer[..count]
		if inherit {
			abi_console(buffer[..count]) or {
				cause = err.msg()
				break
			}
		}
		text := transcript.bytestr()
		recent := if text.len > 8192 { text[text.len - 8192..] } else { text }
		if recent.contains(reboot_pass) || reboot_failures.any(recent.contains(it)) { break }
	}
	unsafe {
		C.__atomic_store_n(&interrupted, i32(0), C.__ATOMIC_RELAXED)
		C.signal(C.SIGINT, C.SIG_IGN)
	}
	reboot_stop(pid, master, reaped)!
	reaped = true
	os.write_file_array(state + '/serial.log', transcript)!
	if inherit { println('') }
	if cause != '' { return error(cause) }
	result := reboot_verdict(transcript.bytestr())
	if result != 0 && inherit {
		eprintln('ERROR: the guest did not complete both reboot and sync brackets')
	}
	return result
}
