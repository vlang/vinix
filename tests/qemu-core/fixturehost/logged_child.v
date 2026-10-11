// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

import os
import time

// A controller owns this child, its private process group and the write end
// of its stdin pipe until close(). stdout/stderr go directly to its disk log.
pub struct LoggedChild {
pub:
	pid i32
mut:
	input  i32 = -1
	reaped bool
	closed bool
	status int
}

pub fn spawn_logged(argv []string, env map[string]string, host_arch string, directory string, log string) !LoggedChild {
	mut file := os.create(log)!
	defer { file.close() }
	fd := C.fcntl(file.fd, C.F_DUPFD_CLOEXEC, 3)
	if fd < 0 { return file_error(log, C.errno) }
	defer { C.close(fd) }
	mut pipes := [i32(-1), -1]!
	if C.pipe(&pipes[0]) != 0 { return file_error('', C.errno) }
	for i in 0 .. 2 {
		if pipes[i] < 3 {
			moved := C.fcntl(pipes[i], C.F_DUPFD_CLOEXEC, 3)
			if moved < 0 {
				C.close(pipes[0])
				C.close(pipes[1])
				return file_error('', C.errno)
			}
			C.close(pipes[i])
			pipes[i] = moved
		} else if C.fcntl(pipes[i], C.F_SETFD, C.FD_CLOEXEC) != 0 {
			C.close(pipes[0])
			C.close(pipes[1])
			return file_error('', C.errno)
		}
	}
	input, output := pipes[0], pipes[1]
	mut input_open := true
	defer {
		if input_open { C.close(input) }
		C.close(output)
	}
	mut actions := C.posix_spawn_file_actions_t{}
	status := C.posix_spawn_file_actions_init(&actions)
	if status != 0 { return file_error(log, status) }
	defer { C.posix_spawn_file_actions_destroy(&actions) }
	if directory != '' {
		if directory.contains('\x00') { return error('embedded null byte') }
		changed := C.posix_spawn_file_actions_addchdir_np(&actions, directory.str)
		if changed != 0 { return file_error(directory, changed) }
	}
	for configured in [C.posix_spawn_file_actions_adddup2(&actions, input, 0),
		C.posix_spawn_file_actions_adddup2(&actions, fd, 1),
		C.posix_spawn_file_actions_adddup2(&actions, fd, 2),
		C.posix_spawn_file_actions_addclose(&actions, fd),
		C.posix_spawn_file_actions_addclose(&actions, input),
		C.posix_spawn_file_actions_addclose(&actions, output)] {
		if configured != 0 { return file_error(log, configured) }
	}
	pid := spawn_command_preferred(argv, env, &actions, [fd, input, output], host_arch, true)!
	// The parent keeps the write side only. Release the read side before
	// returning, and retain a single owner for the surviving descriptor.
	input_open = false
	C.close(input)
	kept := C.fcntl(output, C.F_DUPFD_CLOEXEC, 3)
	if kept < 0 {
		C.killpg(pid, C.SIGKILL)
		C.kill(pid, C.SIGKILL)
		wait(pid) or {}
		return file_error('', C.errno)
	}
	return LoggedChild{ pid: pid, input: kept }
}

pub fn (mut child LoggedChild) poll() !bool {
	if child.reaped { return true }
	mut raw := i32(0)
	result := C.waitpid(child.pid, &raw, C.WNOHANG)
	if result < 0 && C.errno != C.EINTR { return file_error('', C.errno) }
	if result != child.pid { return false }
	child.reaped = true
	child.status = if C.WIFEXITED(raw) != 0 {
		int(C.WEXITSTATUS(raw))
	} else {
		-int(C.WTERMSIG(raw))
	}
	return true
}

pub fn (mut child LoggedChild) wait_for(seconds f64, should_cancel fn () bool) !int {
	deadline := f64(time.sys_mono_now()) / 1e9 + seconds
	for {
		if child.poll()! { return child.status }
		if should_cancel() { return error_with_code('Host test interrupted', 130) }
		if f64(time.sys_mono_now()) / 1e9 >= deadline { return error('Desktop VM did not exit') }
		time.sleep(10 * time.millisecond)
	}
	return 0
}

pub fn (mut child LoggedChild) close() {
	child.close_after(10)
}

// Guest observers with a shorter original shutdown grace keep that deadline.
pub fn (mut child LoggedChild) close_after(seconds f64) {
	if child.closed { return }
	child.closed = true
	if child.input >= 0 {
		C.close(child.input)
		child.input = -1
	}
	if !child.reaped {
		C.killpg(child.pid, C.SIGTERM)
		deadline := time.sys_mono_now() + u64(seconds * f64(time.second))
		for time.sys_mono_now() < deadline {
			if child.poll() or { false } { break }
			time.sleep(10 * time.millisecond)
		}
	}
	// Retire descendants even if the direct child ended on its own.
	C.killpg(child.pid, C.SIGKILL)
	if !child.reaped {
		C.kill(child.pid, C.SIGKILL)
		child.status = wait(child.pid) or { -9 }
		child.reaped = true
	}
}
