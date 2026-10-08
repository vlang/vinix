// SPDX-License-Identifier: GPL-2.0-or-later
module qemubuild

import os

#include "@DIR/spawn_abi.h"
#include <errno.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.vinix_dota_spawn_actions {}

@[typedef]
struct C.vinix_dota_spawn_attributes {}

@[typedef]
struct C.vinix_dota_signal_set {}

fn C.posix_spawn_file_actions_init(voidptr) i32
fn C.posix_spawn_file_actions_destroy(voidptr) i32
fn C.posix_spawn_file_actions_adddup2(voidptr, i32, i32) i32
fn C.posix_spawn_file_actions_addclose(voidptr, i32) i32
fn C.posix_spawn_file_actions_addinherit_np(voidptr, i32) i32

@[typedef]
struct C.posix_spawn_file_actions_t {}

fn C.posix_spawn_file_actions_addchdir_np(&C.posix_spawn_file_actions_t, &char) i32
fn C.posix_spawnattr_init(voidptr) i32
fn C.posix_spawnattr_destroy(voidptr) i32
fn C.posix_spawnattr_setflags(voidptr, i16) i32
fn C.posix_spawnattr_setsigdefault(voidptr, voidptr) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.vinix_dota_sigemptyset(voidptr) i32
fn C.vinix_dota_sigaddset(voidptr, i32) i32
fn C.posix_spawnattr_setbinpref_np(voidptr, usize, &i32, &usize) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C.WIFSIGNALED(i32) bool
fn C.WTERMSIG(i32) i32

pub struct ChildFailure {
pub:
	status int
	argv   []string
}

pub fn (e ChildFailure) code() int { return e.status }

pub fn (e ChildFailure) msg() string { return 'Build command failed' }

fn spawn_error(number int, path string) IError { return FileError{number, path} }

// SDK-owned spawn actions and attributes are destroyed after the synchronous
// spawn call. The child receives copied argv/env, and no borrowed C buffer is
// retained after the call. A negative result preserves Python signal statuses.
pub fn command(argv []string, directory string, environment map[string]string, log string, discard bool) !int {
	return command_preferred(argv, directory, environment, log, discard, '')
}

pub fn command_preferred(argv []string, directory string, environment map[string]string, log string, discard bool, host_arch string) !int {
	if log.contains('\x00') { return error('embedded null byte') }
	mut output := -1
	defer { if output >= 0 { C.close(i32(output)) } }
	if log != '' || discard {
		path := if discard { '/dev/null' } else { log }
		flags := if discard {
			C.O_WRONLY | C.O_CLOEXEC
		} else {
			C.O_WRONLY | C.O_CLOEXEC | C.O_CREAT | C.O_TRUNC
		}
		opened := C.open(path.str, flags, 0o666)
		if opened < 0 { return io_error(path) }
		// Keep the borrowed redirect descriptor above stdio, including callers
		// that arrived with a closed stdin/stdout/stderr descriptor.
		output = int(C.fcntl(opened, C.F_DUPFD_CLOEXEC, 3))
		errno := int(C.errno)
		C.close(opened)
		if output < 0 { return spawn_error(errno, path) }
	}
	if argv.len == 0 { return BuildError{'IndexError', 'list index out of range'} }
	for arg in argv { if arg.contains('\x00') { return error('embedded null byte') } }
	for name, value in environment {
		if name.contains('\x00') || value.contains('\x00') { return error('embedded null byte') }
		if name.contains('=') { return error('illegal environment variable name') }
	}
	if directory.contains('\x00') || log.contains('\x00') { return error('embedded null byte') }
	mut actions := C.vinix_dota_spawn_actions{}
	mut attributes := C.vinix_dota_spawn_attributes{}
	mut number := C.posix_spawn_file_actions_init(&actions)
	if number != 0 { return spawn_error(int(number), '') }
	defer { C.posix_spawn_file_actions_destroy(&actions) }
	$if darwin {
		// CLOEXEC_DEFAULT also closes standard descriptors unless an action
		// explicitly preserves them. Keep the caller's open stdio streams.
		for fd in 0 .. 3 {
			if C.fcntl(i32(fd), C.F_GETFD) >= 0 {
				number = C.posix_spawn_file_actions_addinherit_np(&actions, i32(fd))
				if number != 0 { return spawn_error(int(number), '') }
			}
		}
	}
	number = C.posix_spawnattr_init(&attributes)
	if number != 0 { return spawn_error(int(number), '') }
	defer { C.posix_spawnattr_destroy(&attributes) }
	mut defaults := C.vinix_dota_signal_set{}
	C.vinix_dota_sigemptyset(&defaults)
	for signal in [int(C.SIGPIPE), int(C.VINIX_DOTA_SIGXFZ), int(C.VINIX_DOTA_SIGXFSZ)] {
		if signal != 0 { C.vinix_dota_sigaddset(&defaults, i32(signal)) }
	}
	number = C.posix_spawnattr_setsigdefault(&attributes, &defaults)
	if number != 0 { return spawn_error(int(number), '') }
	number = C.posix_spawnattr_setflags(&attributes, i16(C.POSIX_SPAWN_SETSIGDEF | C.VINIX_DOTA_CLOEXEC_DEFAULT))
	if number != 0 { return spawn_error(int(number), '') }
	$if darwin {
		cpu := match host_arch.to_lower() {
			'arm64', 'aarch64' { i32(C.CPU_TYPE_ARM64) }
			'x86_64', 'amd64' { i32(C.CPU_TYPE_X86_64) }
			else { i32(0) }
		}
		if cpu != 0 {
			preferences := [cpu, i32(C.CPU_TYPE_ANY)]!
			mut copied := usize(0)
			number = C.posix_spawnattr_setbinpref_np(&attributes, 2, &preferences[0], &copied)
			if number != 0 { return spawn_error(int(number), '') }
			if copied != 2 { return error('Incomplete SDK binary preference') }
		}
	}
	if directory != '' {
		number = C.posix_spawn_file_actions_addchdir_np(unsafe { &C.posix_spawn_file_actions_t(&actions) }, directory.str)
		if number != 0 { return spawn_error(int(number), directory) }
	}
	if output >= 0 {
		for fd in [1, 2] {
			number = C.posix_spawn_file_actions_adddup2(&actions, i32(output), i32(fd))
			if number != 0 { return spawn_error(int(number), '') }
		}
	}
	// Python subprocess closes inherited non-stdio descriptors. Darwin's
	// default-close flag covers concurrent opens; the other supported hosts
	// enumerate the calling single-threaded controller's open descriptors.
	if int(C.VINIX_DOTA_CLOEXEC_DEFAULT) == 0 {
		for value in os.ls('/dev/fd') or { os.ls('/proc/self/fd') or { return err } } {
			if value.len == 0 || !value.bytes().all(it.is_digit()) { continue }
			fd := value.int()
			if fd >= 3 && fd != output && C.fcntl(i32(fd), C.F_GETFD) >= 0 {
				number = C.posix_spawn_file_actions_addclose(&actions, i32(fd))
				if number != 0 { return spawn_error(int(number), '') }
			}
		}
	}
	if output >= 0 {
		number = C.posix_spawn_file_actions_addclose(&actions, i32(output))
		if number != 0 { return spawn_error(int(number), '') }
	}
	mut values := []string{}
	for key, value in environment { values << key + '=' + value }
	mut args := []&char{cap: argv.len + 1}
	for arg in argv { args << arg.str }
	args << unsafe { &char(nil) }
	mut env := []&char{cap: values.len + 1}
	for value in values { env << value.str }
	env << unsafe { &char(nil) }
	mut pid := i32(0)
	mut executables := [argv[0]]
	if !argv[0].contains('/') {
		executables = (environment['PATH'] or { '/bin:/usr/bin' }).split(':').map(join(it, argv[0]))
	}
	mut first_error := i32(0)
	for executable in executables {
		number = C.posix_spawn(&pid, executable.str, &actions, &attributes, args.data, env.data)
		if number == 0 { break }
		if first_error == 0 && number != C.ENOENT && number != C.ENOTDIR { first_error = number }
	}
	if number != 0 {
		if directory != '' {
			os.stat(directory) or { return spawn_error(err.code(), directory) }
			if !os.is_dir(directory) { return spawn_error(int(C.ENOTDIR), directory) }
		}
		return spawn_error(int(if first_error != 0 { first_error } else { number }), argv[0])
	}
	mut reaped := false
	defer {
		if !reaped {
			C.kill(pid, C.SIGKILL)
			mut retired_status := i32(0)
			for C.waitpid(pid, &retired_status, 0) < 0 {
				if C.errno != C.EINTR { break }
			}
		}
	}
	mut status := i32(0)
	for {
		result := C.waitpid(pid, &status, 0)
		if result == pid {
			reaped = true
			break
		}
		if result < 0 && C.errno == C.EINTR { continue }
		if result < 0 && C.errno == C.ECHILD {
			reaped = true
			status = 0
			break
		}
		return io_error('')
	}
	if output >= 0 {
		retiring := output
		output = -1
		if C.close(i32(retiring)) != 0 { return io_error('') }
	}
	if C.WIFEXITED(status) != 0 { return int(C.WEXITSTATUS(status)) }
	if C.WIFSIGNALED(status) { return -int(C.WTERMSIG(status)) }
	return error('Unexpected build command status')
}

pub fn checked(argv []string, directory string, environment map[string]string) ! {
	status := command(argv, directory, environment, '', false)!
	if status != 0 { return ChildFailure{status, argv.clone()} }
}
