// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import gamehost
import os
import sourcecommand
import time

struct SignalCase {
	path   string
	signal i32
}

fn signal_ready(pid int, pointer voidptr) ! {
	context := unsafe { &SignalCase(pointer) }
	deadline := time.sys_mono_now() + 10 * time.second
	for !os.is_file(context.path + '/client.pid') {
		if time.sys_mono_now() >= deadline { return error('mock client did not start') }
		cachecli.checkpoint()!
		time.sleep(10 * time.millisecond)
	}
	// The synchronous SDK callback runs before the owner can reap this leader.
	// Its PID stays reserved throughout signal delivery and group retirement.
	if C.kill(i32(pid), context.signal) != 0 { return os.error_posix() }
}

fn signal_cases(host string, guest string, mock string, work string) ! {
	for name in ['mock-codex', 'mock-claude', 'mock-rg', 'mock-zsh'] {
		os.cp(mock, work + '/' + name)!
		os.chmod(work + '/' + name, 0o755)!
	}
	native_guest := work + '/validation-guest'
	os.cp(guest, native_guest)!
	os.chmod(native_guest, 0o755)!
	before := os.ls('/dev/fd')!.len
	for program in [host, native_guest] {
		for claude in [false, true] {
			for signal in [i32(C.SIGINT), i32(C.SIGTERM)] {
				path := work + '/' + if program == host { 'host' } else { 'guest' } + '-' + if claude {
					'claude'
				} else {
					'codex'
				} + '-' + signal.str()
				gamehost.mkdir(path)!
				mut environment := os.environ()
				environment['VINIX_MOCK_SMOKE_WORK'] = path
				environment['VINIX_MOCK_SMOKE_MODE'] = 'timeout'
				argv := [program, if claude { 'claude-smoke' } else { 'codex-smoke' }, '--executable',
					work + '/' + if claude { 'mock-claude' } else { 'mock-codex' }, '--rg',
					work + '/mock-rg', '--zsh', work + '/mock-zsh', '--work', path, '--timeout',
					'90']
				context := SignalCase{ path: path, signal: signal }
				result := sourcecommand.capture_owned(argv, environment, 15, 1024 * 1024, cachecli.cancelled, unsafe { nil }, signal_ready, &context, 0)!
				assert result.status == 128 + int(signal), result.stdout + result.stderr
				assert !os.exists(path + '/client-home')
				pid := os.read_file(path + '/client.pid')!.int()
				assert C.kill(i32(pid), 0) != 0 && C.errno == C.ESRCH
				println('WHOLE CLI SIGNAL / expected status, joined server, client PID and home retired: PASS ' + path.all_after_last('/'))
				flush_stdout()
			}
		}
	}
	assert os.ls('/dev/fd')!.len == before
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 5 { exit(2) }
	gamehost.mkdir(os.args[4]) or { panic(err) }
	signal_cases(os.args[1], os.args[2], os.args[3], os.args[4]) or {
		eprintln(err)
		exit(1)
	}
	os.write_file(os.args[4] + '/passed', 'PASS\n') or { panic(err) }
}
