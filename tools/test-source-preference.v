// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import os
import sourcecommand
import time

#include <unistd.h>
#include <signal.h>
fn C.fork() i32
fn C.kill(i32, i32) i32
fn C.usleep(u32) i32

__global ready_path string

fn cancelled() bool { return os.is_file(ready_path) }

fn qualify(work string, universal string) ! {
	os.mkdir(work)!
	baseline := os.ls('/dev/fd')!.len
	for arch, expected in {'arm64': 'arm64', 'aarch64': 'arm64', 'amd64': 'amd64', 'x86_64': 'amd64'} {
		result := sourcecommand.capture_preferred([universal, '--arch'], os.environ(), 10, 1024, unsafe { nil }, arch)!
		assert result.status == 0 && result.stdout == expected + '\n', result.str()
	}
	for arch in ['arm64', 'amd64'] {
		result := sourcecommand.capture_preferred([universal, '--status', '7'], os.environ(), 10, 1024, unsafe { nil }, arch)!
		assert result.status == 7
		terminated := sourcecommand.capture_preferred([universal, '--signal'], os.environ(), 10, 1024, unsafe { nil }, arch)!
		assert terminated.status == -15
	}
	for arch in ['arm64', 'amd64'] {
		result := sourcecommand.capture_preferred([universal, '--forward-stderr'], os.environ(), 10, 1024, unsafe { nil }, arch)!
		assert result.status == 0 && result.stdout == 'captured child stdout\n' && result.stderr == 'inherited child stderr\n', result.str()
	}
	ready_path = work + '/ready'
	mut stopped := false
	sourcecommand.run_preferred([universal, '--tree', work], os.environ(), cancelled, 'arm64') or { stopped = true; assert err.msg() == 'command interrupted' }
	assert stopped
	leader := os.read_file(work + '/leader')!.int()
	descendant := os.read_file(work + '/descendant')!.int()
	assert C.kill(leader, 0) != 0, 'owned leader survived cancellation'
	deadline := time.sys_mono_now() + u64(3 * time.second)
	for C.kill(descendant, 0) == 0 && time.sys_mono_now() < deadline { time.sleep(10 * time.millisecond) }
	assert C.kill(descendant, 0) != 0, 'owned descendant survived cancellation'
	for _ in 0 .. 100 { result := sourcecommand.capture_preferred([universal, '--arch'], os.environ(), 10, 1024, unsafe { nil }, 'arm64')!; assert result.status == 0 }
	assert os.ls('/dev/fd')!.len == baseline, 'preferred command descriptor count grew'
	os.write_file(work + '/passed', 'PASS\n')!
	println('SDK HOST PREFERENCE / actual ARM and Rosetta executions of universal binary / architecture aliases / ordinary and signed signal exits / cancellation retires private descendants / repeated owners: PASS')
	flush_stdout()
}

fn child() bool {
	if os.args.len == 2 && os.args[1] == '--arch' {
		println($if amd64 { 'amd64' } $else { 'arm64' }); flush_stdout(); return true
	}
	if os.args.len == 3 && os.args[1] == '--status' { exit(os.args[2].int()) }
	if os.args.len == 2 && os.args[1] == '--signal' { C.kill(os.getpid(), C.SIGTERM); C._exit(99) }
	if os.args.len == 2 && os.args[1] == '--streams' { println('captured child stdout'); flush_stdout(); eprintln('inherited child stderr'); flush_stderr(); return true }
	if os.args.len == 2 && os.args[1] == '--forward-stderr' {
		result := sourcecommand.capture_stdout_preferred([os.executable(), '--streams'], os.environ(), 10, 1024, unsafe { nil }, 'arm64') or { eprintln(err); exit(1) }
		assert result.status == 0 && result.stderr == ''
		print(result.stdout); flush_stdout(); return true
	}
	if os.args.len == 3 && os.args[1] == '--tree' {
		work := os.args[2]
		os.write_file(work + '/leader', os.getpid().str()) or { exit(1) }
		pid := C.fork()
		if pid < 0 { exit(1) }
		if pid == 0 {
			os.write_file(work + '/descendant', os.getpid().str()) or { C._exit(1) }
			os.write_file(work + '/ready', 'ready') or { C._exit(1) }
			for { C.usleep(10000) }
		}
		for { C.usleep(10000) }
	}
	return false
}

fn main() {
	if child() { return }
	if os.args.len != 3 { eprintln('usage: test-source-preference NEW_STATE UNIVERSAL_CHILD'); exit(2) }
	qualify(os.args[1], os.args[2]) or { eprintln(err); exit(1) }
}
