// SPDX-License-Identifier: GPL-2.0-or-later
module xtcontroller

import cachecli
import gamehost
import os
import qmpclient
import sourcecommand
import time

fn drain(child &sourcecommand.PtyChild, mut transcript []u8, milliseconds int) ! {
	mut buffer := [65536]u8{}
	mut delay := milliseconds
	for {
		count := child.read(mut buffer[..], delay)!
		delay = 0
		if count <= 0 { return }
		if transcript.len + count > 64 * 1024 * 1024 {
			return error('ext2 serial log exceeds 64 MiB')
		}
		transcript << buffer[..count]
		print(gamehost.decode_utf8(buffer[..count]))
		flush_stdout()
	}
}

fn quit_monitor(state string) ! {
	mut monitor := qmpclient.connect_bounded(state + '/qmp.sock', u64(time.sys_mono_now() + time.second), unsafe { nil })!
	defer { monitor.close() }
	monitor.set_deadline(u64(time.sys_mono_now() + time.second))
	monitor.command('quit', {})!
}

fn stop(child &sourcecommand.PtyChild, state string, mut transcript []u8) ! {
	// The original monitor exchange is best effort. Cleanup must remain usable
	// after cancellation; its own one-second socket deadline bounds the attempt.
	quit_monitor(state) or {}
	child.write([u8(1), `x`]) or {}
	for phase in 0 .. 3 {
		if phase > 0 {
			signal := if phase == 1 { C.SIGTERM } else { C.SIGKILL }
			if C.killpg(child.pid, signal) != 0 {
				if C.errno == C.EPERM {
					if C.kill(child.pid, signal) != 0 && C.errno != C.ESRCH {
						return os.error_posix()
					}
				} else if C.errno != C.ESRCH {
					return os.error_posix()
				}
			}
		}
		deadline := time.sys_mono_now() + 3 * time.second
		for time.sys_mono_now() < deadline {
			drain(child, mut transcript, 0)!
			if child.poll()!.exited { return }
			time.sleep(50 * time.millisecond)
		}
	}
	return error('QEMU runner ${child.pid} did not stop')
}

pub fn boot(command []string, environment map[string]string, state string, timeout int) !int {
	mut child := sourcecommand.spawn_pty(command, environment, '')!
	defer { child.close() or {} }
	mut transcript := []u8{}
	mut status := sourcecommand.ChildExit{}
	mut timed_out := false
	mut failed := false
	mut cause := IError(none)
	deadline := time.sys_mono_now() + i64(timeout) * time.second
	mut settled := i64(-1)
	for time.sys_mono_now() < deadline {
		cachecli.checkpoint() or {
			failed = true
			cause = err
			break
		}
		drain(&child, mut transcript, 200) or {
			failed = true
			cause = err
			break
		}
		status = child.poll() or {
			failed = true
			cause = err
			break
		}
		if status.exited { break }
		text := transcript.bytestr()
		if ['FAIL:', 'KERNEL PANIC', 'FATAL EXCEPTION'].any(text.contains(it)) { break }
		if text.contains('XATTR: PASS') {
			if settled < 0 {
				settled = time.sys_mono_now()
			} else if time.sys_mono_now() - settled >= 2 * time.second {
				break
			}
		}
	}
	if time.sys_mono_now() >= deadline { timed_out = true }
	if !status.exited {
		stop(&child, state, mut transcript) or {
			failed = true
			cause = err
		}
	}
	drain(&child, mut transcript, 0) or {
		failed = true
		cause = err
	}
	child.close() or {
		failed = true
		cause = err
	}
	os.write_file_array(state + '/serial.log', transcript)!
	if failed { return cause }
	text := transcript.bytestr()
	if !text.contains('XATTR: PASS') || ['FAIL:', 'KERNEL PANIC', 'FATAL EXCEPTION'].any(text.contains(it)) || (status.exited && status.return_code != 0) || timed_out {
		println('Missing or failed guest verdicts; see ' + state + '/serial.log')
		return 1
	}
	println('All requested guest verdicts passed.')
	return 0
}
