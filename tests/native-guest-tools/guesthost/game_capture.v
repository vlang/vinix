// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import os

pub struct GameCapture {
pub:
	text     string
	failure  string
	captures []string
}

pub fn game_capture_interrupted() bool {
	return unsafe { C.__atomic_load_n(&interrupted, i32(C.__ATOMIC_RELAXED)) } != 0
}

pub fn capture_game(command []string, env map[string]string, state string, socket string, seconds int, interval int, screenshot fn (string, string) bool, inherit bool) !GameCapture {
	if seconds <= 0 || interval <= 0 { return error('Guest capture intervals must be positive') }
	mut log := os.create(state + '/vinix.log')!
	defer { log.close() }
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
	mut captures := []string{}
	mut failure := ''
	mut cause := ''
	mut failed_at := f64(-1)
	start := now()
	mut next_capture := start + 30
	for now() - start < seconds {
		readable := ready(master, false, now() + 1) or {
			cause = err.msg()
			break
		}
		if readable {
			mut bytes := [65536]u8{}
			count := C.read(master, &bytes[0], bytes.len)
			if count < 0 {
				if C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { continue }
				failure = 'VM serial connection closed'
				break
			}
			if count == 0 {
				failure = 'VM exited'
				break
			}
			transcript << bytes[..count]
			session_log(mut log, bytes[..count]) or {
				cause = err.msg()
				break
			}
			if inherit {
				abi_console(bytes[..count]) or {
					cause = err.msg()
					break
				}
			}
			tail := transcript[if transcript.len > 131072 { transcript.len - 131072 } else { 0 }..].bytestr()
			if failure == '' {
				for marker in ['VINIX-DOTA2-PROBE-FAIL', 'VINIX-DOTA2-GAME-EXIT:',
					'VINIX-DOTA2-GAME-GONE', 'KERNEL PANIC', 'FATAL EXCEPTION', 'uncaught target signal',
					'LLVM ERROR:', 'lwip: assertion'] {
					if tail.contains(marker) {
						failure = marker
						failed_at = now()
						break
					}
				}
			}
		}
		if failed_at >= 0 && now() - failed_at >= 2 { break }
		if now() >= next_capture {
			elapsed := '${int(now() - start):04d}'
			target := state + '/guest-' + elapsed + '.png'
			if screenshot(socket, target) { captures << target }
			next_capture = now() + interval
		}
	}
	if cause == '' {
		final := state + '/guest-final.png'
		if screenshot(socket, final) { captures << final }
	}
	interruption() or { cause = err.msg() }
	unsafe {
		C.__atomic_store_n(&interrupted, i32(0), C.__ATOMIC_RELAXED)
		C.signal(C.SIGINT, C.SIG_IGN)
	}
	session_stop(pid, master, reaped, SessionPolicy{ cleanup_wait: 0, term_wait: 5, kill_wait: 5 })!
	reaped = true
	os.write_file_array(state + '/serial.log', transcript)!
	if cause != '' { return error(cause) }
	return GameCapture{transcript.bytestr(), failure, captures}
}
