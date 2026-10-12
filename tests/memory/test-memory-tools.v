// SPDX-License-Identifier: GPL-2.0-or-later
module main

import cachecli
import guesthost
import memorytools
import os
import sourcecommand
import time

#include <signal.h>
fn C.kill(i32, i32) i32

struct SignalCase { work string signal int }

fn signal_child(pid int, pointer voidptr) ! {
	data := unsafe { &SignalCase(pointer) }
	deadline := time.sys_mono_now() + u64(30 * time.second)
	for !os.exists(data.work + '/ready') {
		if time.sys_mono_now() > deadline { return error('compiler fixture never became ready') }
		time.sleep(20 * time.millisecond)
	}
	if C.kill(pid, data.signal) != 0 { return os.error_posix() }
}

fn blocked() ! {
	work := os.getenv('VINIX_MEMORY_TEST_BLOCKED')
	mut child := os.new_process('/bin/sleep')
	child.set_args(['600'])
	child.run()
	os.write_file(work + '/pids', os.getpid().str() + '\n' + child.pid.str() + '\n')!
	os.write_file(work + '/ready', 'ready')!
	for { time.sleep(50 * time.millisecond) }
}

fn retired(work string) ! {
	ids := os.read_file(work + '/pids')!.split_into_lines().map(it.int())
	deadline := time.sys_mono_now() + u64(5 * time.second)
	for ids.any(C.kill(it, 0) == 0) && time.sys_mono_now() < deadline { time.sleep(20 * time.millisecond) }
	assert ids.all(C.kill(it, 0) != 0), 'compiler descendants survived'
}

fn invoke(argv []string) !sourcecommand.Output {
	return sourcecommand.capture([os.executable(), '--tool', ...argv], os.environ(), 30, 4 * 1024 * 1024, unsafe { nil })!
}

fn guest_owner(work string) !int {
	guard := cachecli.own_commands()
	defer { guard.close() }
	guesthost.boot_from_cancelled([os.executable(), '--blocked-guest', work], os.environ(), work, ['never printed'], [], 300, false, '', cachecli.cancelled) or {
		return if cachecli.cancelled() { cachecli.interrupt_status() } else if err.msg() == 'Guest run interrupted' { 130 } else { 1 }
	}
	return 0
}

fn cases(work string) ! {
	os.mkdir(work)!
	protected := work + '/protected'
	os.mkdir(protected)!
	os.write_file(protected + '/keep', 'unchanged')!
	for argv in [['runtime', '--bad'], ['runtime', '--arch', 'no'], ['runtime', '--host-arch', 'no'], ['runtime', '--build-only'], ['runtime', '--arch', 'aarch64'], ['bigio'], ['bigio', '--state-dir', protected]] {
		result := invoke(argv)!
		assert result.status == 2, argv.str() + result.str()
	}
	for state in [protected, ''] {
		result := invoke(['runtime', '--state-dir', state])!
		assert result.status == 1, result.str()
		assert os.read_file(protected + '/keep')! == 'unchanged'
	}
	println('CLI / existing state / empty path: PASS')
	for signal in [2, 15] {
		directory := work + '/guest-' + signal.str()
		os.mkdir(directory)!
		data := SignalCase{directory, signal}
		result := sourcecommand.capture_owned([os.executable(), '--guest-owner', directory], os.environ(), 30, 4 * 1024 * 1024, unsafe { nil }, unsafe { nil }, signal_child, unsafe { &data }, 0)!
		assert result.status == 128 + signal, result.str()
		retired(directory)!
		println('GUEST / signal / descendant retirement: PASS ' + signal.str())
	}
	bin := work + '/bin'
	os.mkdir(bin)!
	os.symlink(os.executable(), bin + '/blocked-cc')!
	previous := os.getenv_opt('CC')
	defer { if value := previous { os.setenv('CC', value, true) } else { os.unsetenv('CC') }; os.unsetenv('VINIX_MEMORY_TEST_BLOCKED') }
	os.setenv('CC', bin + '/blocked-cc', true)
	for tool in ['runtime', 'bigio'] {
		for signal in [2, 15] {
			directory := work + '/' + tool + '-' + signal.str()
			os.mkdir(directory)!
			os.setenv('VINIX_MEMORY_TEST_BLOCKED', directory, true)
			data := SignalCase{directory, signal}
			mut argv := [os.executable(), '--tool', tool, '--state-dir', directory + '/build']
			if tool == 'bigio' { argv << ['--original-reference', os.getenv('VINIX_MEMORY_TEST_C_BIGIO')] }
			result := sourcecommand.capture_owned(argv, os.environ(), 45, 4 * 1024 * 1024, unsafe { nil }, unsafe { nil }, signal_child, unsafe { &data }, 0)!
			assert result.status == 128 + signal, result.str()
			retired(directory)!
			assert !os.exists(directory + '/build/'+ if tool == 'runtime' { 'v' } else { 'original' } + '/inputs.json')
			println('COMPILER / signal / descendant retirement: PASS ' + tool + ' ' + signal.str())
		}
	}
}

fn main() {
	if os.base(os.args[0]) == 'blocked-cc' { blocked() or { panic(err) }; return }
	args := os.args[1..]
	if args.len == 2 && args[0] == '--blocked-guest' { os.setenv('VINIX_MEMORY_TEST_BLOCKED', args[1], true); blocked() or { panic(err) }; return }
	if args.len == 2 && args[0] == '--guest-owner' { exit(guest_owner(args[1]) or { eprintln(err); 1 }) }
	if args.len >= 2 && args[0] == '--tool' { exit(memorytools.cli(args[2..], args[1] == 'runtime')) }
	if args.len != 1 { eprintln('usage: test-memory-tools NEW_STATE'); exit(2) }
	cases(args[0]) or { eprintln(err); exit(1) }
}
