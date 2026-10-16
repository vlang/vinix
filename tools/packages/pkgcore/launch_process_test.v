// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct LaunchProcessLimit { current u64 maximum u64 }

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

struct LaunchObservation { arguments []string directory string environment string uid int gid int }

fn testsuite_begin() {
	if os.getenv('VINIX_PACKAGE_LAUNCH_CHILD') != '' { return }
	path := os.real_path(os.temp_dir()) + '/vinix-launch-child-' + os.getpid().str()
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	mut compiler := os.new_process(v)
	compiler.set_args(['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-o', path, 'tests/packages/launch-process-child.v'])
	compiler.wait(); code := compiler.code; compiler.close(); assert code == 0
	os.setenv('VINIX_PACKAGE_LAUNCH_CHILD', path, true)
	os.setenv('VINIX_PACKAGE_LAUNCH_CHILD_CLEANUP', path, true)
}

fn testsuite_end() {
	path := os.getenv('VINIX_PACKAGE_LAUNCH_CHILD_CLEANUP')
	if path != '' { os.rm(path)! }
}

fn launch_process_child() string {
	path := os.getenv('VINIX_PACKAGE_LAUNCH_CHILD')
	assert path.starts_with('/') && os.is_executable(path)
	return path
}

fn launch_process_cycles() int { return $if track_heap ? { 1000 } $else { 16 } }

fn launch_process_work() string { return os.real_path(os.temp_dir()) + '/vinix-child-' + os.getpid().str() + '-' + time.now().unix_micro().str() }

fn launch_process_refusal(launch Launch, stage string) {
	if _ := run_launch_process(launch) { assert false }
	else { message := err.msg(); assert message.contains(stage), message; unsafe { message.free(); err.free() } }
}

fn launch_process_unused_fd() int {
	fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC); assert fd >= 0
	C.close(fd); return fd
}

fn launch_process_no_children() {
	mut status := i32(0)
	assert C.vinix_package_waitpid(-1, unsafe { &status }, C.WNOHANG) == -1 && C.errno == C.ECHILD
}

fn test_launch_process_literal_argv_environment_working_directory_and_identity() {
	work := launch_process_work(); os.mkdir_all(work + '/cwd with spaces')!
	defer { os.rmdir_all(work) or {} }
	child := launch_process_child(); defer { unsafe { child.free() } }
	program := work + '/literal child'; os.symlink(child, program)!
	path := work + '/observation.json'
	literal := ['', 'a space', 'é🚀', '$HOME', '$(literal)', '--uid', '0', 'quote"', 'new\nline', '@APP@']
	os.setenv('VINIX_LAUNCH_PROCESS_LITERAL', 'space é🚀; $HOME=literal\nnext', true)
	launch := Launch{ program: program, directory: work + '/cwd with spaces', arguments: ['observe', path, ...literal] }
	assert run_launch_process(launch)! == 37
	observed := json2.decode[LaunchObservation](os.read_file(path)!)!
	assert observed.arguments == literal && observed.directory == launch.directory
	assert observed.environment == 'space é🚀; $HOME=literal\nnext'
	assert observed.uid == os.geteuid() && observed.gid == int(C.getegid())
	assert launch.arguments[3] == 'a space' && launch.directory.ends_with('cwd with spaces')
	println('LAUNCH PROCESS literal empty/Unicode/shell-looking arguments, inherited environment, exact working directory and identity PASS')
}

fn test_launch_process_waits_retire_all_parent_scratch() {
	child := launch_process_child(); defer { unsafe { child.free() } }
	for mode in ['37', '126', '127', 'signal']! {
		args := if mode != 'signal' { ['exit', mode] } else { ['signal'] }
		launch := Launch{ program: child, directory: '/tmp', arguments: args }
		expected := if mode != 'signal' { mode.int() } else { 143 }
		assert run_launch_process(launch)! == expected
		unused := launch_process_unused_fd()
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. launch_process_cycles() { assert run_launch_process(launch)! == expected }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, mode + ' retained ' + kept.str() }
		assert launch_process_unused_fd() == unused
		launch_process_no_children()
	}
	$if track_heap ? { println('LAUNCH PROCESS tracked exits: four modes, 1000 attempts each retained 0 bytes') }
	println('LAUNCH PROCESS normal and signal exits preserve 37/126/127/143 status, reap children and retire parent storage/descriptors PASS')
}

fn test_launch_process_failures_refuse_before_execution_and_retire_storage() {
	work := launch_process_work(); os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	child := launch_process_child(); defer { unsafe { child.free() } }
	os.write_file(work + '/not-executable', 'not executable')!
	os.write_file(work + '/bad-format', 'not an ELF executable')!; os.chmod(work + '/bad-format', 0o755)!
	cases := [
		Launch{ program: child, directory: work + '/missing', arguments: ['observe', work + '/must-not-run'] },
		Launch{ program: child, directory: work + '/not-executable', arguments: ['exit', '0'] },
		Launch{ program: work + '/missing', directory: work },
		Launch{ program: work + '/not-executable', directory: work },
		Launch{ program: work + '/bad-format', directory: work },
		Launch{ program: 'relative', directory: work },
		Launch{ program: child, directory: 'relative' },
		Launch{ program: child + '\x00tail', directory: work },
		Launch{ program: child, directory: work + '\x00tail' },
		Launch{ program: child, directory: work, arguments: ['nul\x00tail'] },
	]
	for i, launch in cases {
		stage := if i < 2 { 'cannot enter application working directory ' + launch.directory + ' (errno ' }
			else if i < 5 { 'cannot execute application program ' + launch.program + ' (errno ' }
			else if i < 9 { 'absolute executable and working-directory paths' } else { 'argument contains NUL' }
		launch_process_refusal(launch, stage)
		unused := launch_process_unused_fd()
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. launch_process_cycles() { launch_process_refusal(launch, stage) }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, stage + ' retained ' + kept.str() }
		assert launch_process_unused_fd() == unused
		launch_process_no_children()
	}
	assert !os.exists(work + '/must-not-run')
	$if track_heap ? { println('LAUNCH PROCESS tracked refusals: ten paths, 1000 attempts each retained 0 bytes') }
	println('LAUNCH PROCESS missing/non-directory cwd, missing/denied/invalid executable and malformed-plan diagnostics refuse before execution with retired scratch PASS')
}

fn test_launch_process_inherits_streams_and_keeps_closed_streams_closed() {
	child := launch_process_child(); defer { unsafe { child.free() } }
	work := launch_process_work(); os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/input', 'x')!
	pid := C.fork(); assert pid >= 0
	if pid == 0 {
		input := C.open((work + '/input').str, C.O_RDONLY)
		output := C.open((work + '/output').str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, 0o600)
		failure := C.open((work + '/error').str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, 0o600)
		assert input > 2 && output > 2 && failure > 2
		assert C.dup2(input, 0) == 0 && C.dup2(output, 1) == 1 && C.dup2(failure, 2) == 2
		C.close(input); C.close(output); C.close(failure)
		code := run_launch_process(Launch{ program: child, directory: work, arguments: ['streams'] })!
		C._exit(code)
	}
	assert launch_wait(pid)! == 23
	assert os.read_file(work + '/output')! == 'out' && os.read_file(work + '/error')! == 'err'
	closed := C.fork(); assert closed >= 0
	if closed == 0 {
		for fd in 0 .. 3 { C.close(fd) }
		code := run_launch_process(Launch{ program: child, directory: work, arguments: ['closed-streams'] })!
		for fd in 0 .. 3 { if C.fcntl(fd, C.F_GETFD) >= 0 { C._exit(94) } }
		C._exit(code)
	}
	assert launch_wait(closed)! == 24
	println('LAUNCH PROCESS existing stdin/stdout/stderr stay separate and closed standard descriptors remain closed PASS')
}

fn test_launch_process_keeps_parent_lease_and_retires_setup_failures() {
	child := launch_process_child(); defer { unsafe { child.free() } }
	work := launch_process_work(); os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/lease', '')!
	lease := C.open((work + '/lease').str, C.O_RDONLY | C.O_CLOEXEC); assert lease >= 0
	assert C.flock(lease, C.LOCK_SH | C.LOCK_NB) == 0
	assert run_launch_process(Launch{ program: child, directory: work, arguments: ['lease', work + '/lease', lease.str()] })! == 25
	assert C.fcntl(lease, C.F_GETFD) >= 0
	C.close(lease)
	probe := C.open((work + '/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	assert probe >= 0 && C.flock(probe, C.LOCK_EX | C.LOCK_NB) == 0; C.close(probe)
	pid := C.fork(); assert pid >= 0
	if pid == 0 {
		mut original := LaunchProcessLimit{}
		assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		limited := LaunchProcessLimit{ current: 32, maximum: original.maximum }
		assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limited }) == 0
		mut fds := []int{cap: 32}
		for { fd := C.open(c'/dev/null', C.O_RDONLY); if fd < 0 { break }; fds << fd }
		launch := Launch{ program: child, directory: work, arguments: ['exit', '0'] }
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. launch_process_cycles() { launch_process_refusal(launch, 'cannot create application launch status pipe') }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
		for fd in fds { C.close(fd) }
		assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
		assert run_launch_process(launch)! == 0
		C._exit(0)
	}
	assert launch_wait(pid)! == 0
	$if track_heap ? { println('LAUNCH PROCESS tracked descriptor exhaustion: 1000 refusals retained 0 bytes') }
	println('LAUNCH PROCESS parent retains its generation lease, final close releases it, descriptor exhaustion retires scratch and restoration permits retry PASS')
}
