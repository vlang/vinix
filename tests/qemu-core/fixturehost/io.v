// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

import os
import hosttest
import strings

#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <signal.h>
#flag -I @DIR
#include "spawn_abi.h"

fn C.fopen(&char, &char) &C.FILE
fn C.fread(voidptr, usize, usize, &C.FILE) usize
fn C.fwrite(voidptr, usize, usize, &C.FILE) usize
fn C.ferror(&C.FILE) i32
fn C.clearerr(&C.FILE)
fn C.fclose(&C.FILE) i32
fn C.posix_spawn(&i32, &char, voidptr, voidptr, &&char, &&char) i32
fn C.posix_spawnp(&i32, &char, voidptr, voidptr, &&char, &&char) i32
fn C.posix_spawn_file_actions_init(voidptr) i32
fn C.posix_spawn_file_actions_destroy(voidptr) i32
fn C.posix_spawn_file_actions_adddup2(voidptr, i32, i32) i32
fn C.posix_spawn_file_actions_addclose(voidptr, i32) i32
fn C.posix_spawn_file_actions_addchdir_np(&C.posix_spawn_file_actions_t, &char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C.WTERMSIG(i32) i32
fn C.posix_spawnattr_init(voidptr) i32
fn C.posix_spawnattr_destroy(voidptr) i32
fn C.posix_spawnattr_setsigdefault(voidptr, voidptr) i32
fn C.posix_spawnattr_setflags(voidptr, i16) i32

@[typedef]
struct C.sigset_t {}

@[typedef]
struct C.posix_spawnattr_t {}

@[typedef]
struct C.posix_spawn_file_actions_t {}

pub struct FileError {
pub:
	filename string
	number   int
	message  string
}

pub fn (e FileError) msg() string { return e.message }

pub fn (e FileError) code() int { return e.number }

pub struct CommandError {
pub:
	argv          []string
	status        int
	output        string
	inherited     bool
	binary_output bool
}

pub fn (e CommandError) msg() string { return 'Command failed' }

pub fn (e CommandError) code() int { return e.status }

pub struct CopyFileError {
pub:
	kind   string
	source string
	target string
}

pub fn (e CopyFileError) msg() string {
	return if e.kind == 'SameFileError' {
		'Source and destination are the same file'
	} else {
		'Input is a named pipe'
	}
}

pub fn (e CopyFileError) code() int { return 0 }

fn file_error(path string, number int) FileError {
	return FileError{path, number, os.get_error_msg(number)}
}

fn mkdir_all(path string) ! {
	if path.contains('\x00') { return error('embedded null byte') }
	if os.is_dir(path) { return }
	parent := path.trim_right('/').all_before_last('/')
	if parent != '' && parent != path { mkdir_all(parent)! }
	os.mkdir(path) or { if !os.is_dir(path) { return file_error(path, err.code()) } }
}

fn copyfile(source string, target string) ! {
	if source.contains('\x00') || target.contains('\x00') { return error('embedded null byte') }
	if src := os.stat(source) {
		mut target_fifo := false
		if dst := os.stat(target) {
			if src.dev == dst.dev && src.inode == dst.inode {
				return CopyFileError{'SameFileError', source, target}
			}
			target_fifo = dst.get_filetype() == .fifo
		}
		if src.get_filetype() == .fifo { return CopyFileError{'SpecialFileError', source, ''} }
		if target_fifo { return CopyFileError{'SpecialFileError', target, ''} }
	}
	write(target, read(source)!)!
}

pub fn install(destination string) ! {
	copyfile(os.executable(), destination)!
	os.chmod(destination, 0o700) or { return file_error(destination, err.code()) }
}

pub fn read(path string) !string {
	if path.contains('\x00') { return error('embedded null byte') }
	stream := C.fopen(path.str, c'rb')
	if isnil(stream) {
		number := C.errno
		return file_error(path, number)
	}
	defer { C.fclose(stream) }
	mut result := strings.new_builder(8192)
	mut buffer := []u8{len: 8192}
	for {
		count := int(C.fread(buffer.data, 1, usize(buffer.len), stream))
		number := C.errno
		if count > 0 { result.write(buffer[..count])! }
		if C.ferror(stream) != 0 {
			if number == C.EINTR {
				C.clearerr(stream)
				continue
			}
			return file_error(path, number)
		}
		if count < buffer.len { break }
	}
	return result.str()
}

pub fn write(path string, text string) ! {
	if path.contains('\x00') { return error('embedded null byte') }
	stream := C.fopen(path.str, c'wb')
	if isnil(stream) {
		number := C.errno
		return file_error(path, number)
	}
	mut closed := false
	defer { if !closed { C.fclose(stream) } }
	if C.fwrite(text.str, 1, usize(text.len), stream) != usize(text.len) {
		number := C.errno
		return file_error(path, number)
	}
	closed = true
	if C.fclose(stream) != 0 {
		number := C.errno
		return file_error(path, number)
	}
}

// Capture one merged pipe with inherited stdin and no deadline. POSIX spawn
// reports exec errors directly, before any compile log is materialized.
fn spawn_command(argv []string, env map[string]string, actions voidptr, excluded []i32) !i32 {
	if argv.len == 0 || argv.any(it.contains('\x00')) { return error('embedded null byte') }
	mut c_arguments := []&char{cap: argv.len + 1}
	for item in argv { c_arguments << &char(item.str) }
	c_arguments << &char(unsafe { nil })
	mut entries := []string{}
	for key, value in env { entries << key + '=' + value }
	mut environment := []&char{cap: entries.len + 1}
	for item in entries { environment << &char(item.str) }
	environment << &char(unsafe { nil })
	mut local_actions := C.posix_spawn_file_actions_t{}
	mut action_pointer := voidptr(actions)
	if isnil(action_pointer) {
		initialized_actions := C.posix_spawn_file_actions_init(&local_actions)
		if initialized_actions != 0 { return file_error('', initialized_actions) }
		action_pointer = voidptr(&local_actions)
	}
	defer { if isnil(actions) { C.posix_spawn_file_actions_destroy(&local_actions) } }
	// close_fds preserves only the inherited standard streams. The live fd
	// listing's own descriptor is closed before the actions are assembled.
	mut descriptors := os.ls('/dev/fd') or { os.ls('/proc/self/fd') or { []string{} } }
	if descriptors.len == 0 {
		limit := C.sysconf(C._SC_OPEN_MAX)
		if limit < 0 { return error('Cannot enumerate inherited descriptors') }
		for fd in 3 .. int(limit) { if C.fcntl(fd, C.F_GETFD) >= 0 { descriptors << fd.str() } }
	}
	for name in descriptors {
		if name.len == 0 || !name.bytes().all(it.is_digit()) { continue }
		fd := name.int()
		if fd < 3 || i32(fd) in excluded || C.fcntl(fd, C.F_GETFD) < 0 { continue }
		close_status := C.posix_spawn_file_actions_addclose(action_pointer, fd)
		if close_status != 0 { return file_error('', close_status) }
	}
	// Match subprocess.run's restore_signals without changing the parent.
	mut attributes := C.posix_spawnattr_t{}
	initialized := C.posix_spawnattr_init(&attributes)
	if initialized != 0 { return file_error('', initialized) }
	defer { C.posix_spawnattr_destroy(&attributes) }
	$if darwin {
		mut defaults := u32(0)
		C.sigemptyset(&defaults)
		C.sigaddset(&defaults, C.SIGPIPE)
		if C.VINIX_QEMU_SIGXFSZ != 0 { C.sigaddset(&defaults, C.VINIX_QEMU_SIGXFSZ) }
		if C.VINIX_QEMU_SIGXFZ != 0 { C.sigaddset(&defaults, C.VINIX_QEMU_SIGXFZ) }
		default_status := C.posix_spawnattr_setsigdefault(&attributes, &defaults)
		if default_status != 0 { return file_error('', default_status) }
	} $else {
		mut defaults := C.sigset_t{}
		C.sigemptyset(&defaults)
		C.sigaddset(&defaults, C.SIGPIPE)
		if C.VINIX_QEMU_SIGXFSZ != 0 { C.sigaddset(&defaults, C.VINIX_QEMU_SIGXFSZ) }
		if C.VINIX_QEMU_SIGXFZ != 0 { C.sigaddset(&defaults, C.VINIX_QEMU_SIGXFZ) }
		default_status := C.posix_spawnattr_setsigdefault(&attributes, &defaults)
		if default_status != 0 { return file_error('', default_status) }
	}
	configured := C.posix_spawnattr_setflags(&attributes, i16(C.POSIX_SPAWN_SETSIGDEF))
	if configured != 0 { return file_error('', configured) }
	mut pid := i32(0)
	result := if argv[0].contains('/') {
		C.posix_spawn(&pid, argv[0].str, action_pointer, &attributes, c_arguments.data, environment.data)
	} else {
		C.posix_spawnp(&pid, argv[0].str, action_pointer, &attributes, c_arguments.data, environment.data)
	}
	if result != 0 { return file_error(argv[0], result) }
	return pid
}

fn wait(pid i32) !int {
	mut status := i32(0)
	for C.waitpid(pid, &status, 0) < 0 {
		number := C.errno
		if number != C.EINTR { return file_error('', number) }
	}
	return if C.WIFEXITED(status) != 0 {
		int(C.WEXITSTATUS(status))
	} else {
		-int(C.WTERMSIG(status))
	}
}

pub fn inherited_command(argv []string) ! {
	inherited_command_environment(argv, os.environ())!
}

// Explicit copies preserve a caller's original subprocess environment policy.
pub fn inherited_command_environment(argv []string, env map[string]string) ! {
	pid := spawn_command(argv, env, unsafe { nil }, []i32{})!
	status := wait(pid)!
	if status != 0 {
		return CommandError{ argv: argv.clone(), status: status, output: '', inherited: true }
	}
}

pub fn command(argv []string, log string) !string {
	mut env := os.environ()
	env['ASAN_OPTIONS'] = 'detect_leaks=0'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	return capture(argv, log, env, true)
}

pub fn capture(argv []string, log string, env map[string]string, merge bool) !string {
	return capture_in(argv, log, env, merge, '', false)
}

// Oracle Git calls retain their original cwd, inherited stderr and raw bytes.
pub fn capture_in(argv []string, log string, env map[string]string, merge bool, directory string, binary_output bool) !string {
	mut pipes := [2]i32{}
	if C.pipe(&pipes[0]) != 0 {
		number := C.errno
		return file_error('', number)
	}
	mut read_open := true
	mut write_open := true
	defer {
		if read_open { C.close(pipes[0]) }
		if write_open { C.close(pipes[1]) }
	}
	for fd in pipes {
		if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) != 0 {
			number := C.errno
			return file_error('', number)
		}
	}
	// SDK-owned action storage binds only the system primitive.
	mut actions := C.posix_spawn_file_actions_t{}
	result := C.posix_spawn_file_actions_init(&actions)
	if result != 0 { return file_error('', result) }
	defer { C.posix_spawn_file_actions_destroy(&actions) }
	if directory != '' {
		if directory.contains('\x00') { return error('embedded null byte') }
		changed := C.posix_spawn_file_actions_addchdir_np(&actions, directory.str)
		if changed != 0 { return file_error(directory, changed) }
	}
	mut action_status := C.posix_spawn_file_actions_adddup2(&actions, pipes[1], 1)
	if action_status != 0 { return file_error('', action_status) }
	if merge {
		action_status = C.posix_spawn_file_actions_adddup2(&actions, pipes[1], 2)
		if action_status != 0 { return file_error('', action_status) }
	}
	for close_status in [C.posix_spawn_file_actions_addclose(&actions, pipes[0]),
		C.posix_spawn_file_actions_addclose(&actions, pipes[1])] {
		if close_status != 0 { return file_error('', close_status) }
	}
	pid := spawn_command(argv, env, &actions, [pipes[0], pipes[1]])!
	mut reaped := false
	defer {
		if !reaped {
			// subprocess.run kills/reaps its child when communication fails.
			C.kill(pid, C.SIGKILL)
			wait(pid) or {}
		}
	}
	C.close(pipes[1])
	write_open = false
	mut output := strings.new_builder(8192)
	mut buffer := [8192]u8{}
	for {
		count := C.read(pipes[0], &buffer[0], usize(buffer.len))
		number := C.errno
		if count < 0 {
			if number == C.EINTR { continue }
			return file_error('', number)
		}
		if count == 0 { break }
		output.write(buffer[..int(count)])!
	}
	C.close(pipes[0])
	read_open = false
	status := wait(pid)!
	reaped = true
	raw := output.str()
	if !binary_output { hosttest.module_decode_utf8(raw)! }
	text := if binary_output { raw } else { raw.replace('\r\n', '\n').replace('\r', '\n') }
	if log != '' { write(log, text)! }
	if status != 0 {
		return CommandError{ argv: argv.clone(), status: status, output: text, binary_output: binary_output }
	}
	return text
}
