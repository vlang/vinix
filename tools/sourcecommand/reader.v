// SPDX-License-Identifier: GPL-2.0-or-later
module sourcecommand

import os
import time

// Stream a child's stdout without buffering it in memory. The descriptor and
// unreaped private process group share one owner through final retirement.
pub struct ReaderChild {
pub:
	pid        int
	descriptor i32
mut:
	retired bool
}

pub fn spawn_reader(argv []string, environment map[string]string) !ReaderChild {
	return spawn_reader_at(argv,environment,'',false)!
}

pub fn spawn_reader_at(argv []string, environment map[string]string, directory string, merged bool) !ReaderChild {
	if argv.len == 0 || argv.any(it.contains('\x00')) || directory.contains('\x00') { return error('invalid reader command') }
	mut pipes := [i32(-1), -1]!
	if C.pipe(&pipes[0]) != 0 { return os.error_posix() }
	defer { for fd in pipes { if fd >= 0 { C.close(fd) } }
	 }
	for i in 0 .. 2 {
		if pipes[i] < 3 {
			moved := C.fcntl(pipes[i], C.F_DUPFD_CLOEXEC, 3)
			if moved < 0 { return os.error_posix() }
			C.close(pipes[i])
			pipes[i] = moved
		} else if C.fcntl(pipes[i], C.F_SETFD, C.FD_CLOEXEC) != 0 {
			return os.error_posix()
		}
	}
	mut actions := C.posix_spawn_file_actions_t{}
	if C.posix_spawn_file_actions_init(&actions) != 0 {
		return error('cannot initialize reader actions')
	}
	defer { C.posix_spawn_file_actions_destroy(&actions) }
	if directory!=''&&C.posix_spawn_file_actions_addchdir_np(&actions,directory.str)!=0{return error('cannot set reader working directory')}
	if merged&&C.posix_spawn_file_actions_adddup2(&actions,pipes[1],2)!=0{return error('cannot merge reader stderr')}
	for status in [C.posix_spawn_file_actions_adddup2(&actions, pipes[1], 1),
		C.posix_spawn_file_actions_addclose(&actions, pipes[0]),
		C.posix_spawn_file_actions_addclose(&actions, pipes[1])] {
		if status != 0 { return error_with_code('cannot configure reader streams', int(status)) }
	}
	mut attributes := C.posix_spawnattr_t{}
	if C.posix_spawnattr_init(&attributes) != 0 {
		return error('cannot initialize reader attributes')
	}
	defer { C.posix_spawnattr_destroy(&attributes) }
	mut signals := C.sigset_t{}
	$if macos {
		C.sigemptyset(unsafe { &u32(&signals) })
		for signal in [C.SIGINT, C.SIGTERM, C.SIGPIPE] {
			C.sigaddset(unsafe { &u32(&signals) }, signal)
		}
	} $else {
		C.sigemptyset(&signals)
		for signal in [C.SIGINT, C.SIGTERM, C.SIGPIPE] { C.sigaddset(&signals, signal) }
	}
	mut flags := i16(C.POSIX_SPAWN_SETPGROUP | C.POSIX_SPAWN_SETSIGDEF)
	$if macos {
		flags |= i16(C.POSIX_SPAWN_CLOEXEC_DEFAULT)
		for fd in [0, 2] {
			if merged&&fd==2{continue}
			if C.fcntl(fd, C.F_GETFD) >= 0 && C.posix_spawn_file_actions_addinherit_np(&actions, fd) != 0 {
				return error('cannot preserve reader standard descriptors')
			}
		}
	}
	for status in [C.posix_spawnattr_setpgroup(&attributes, 0),
		C.posix_spawnattr_setsigdefault(&attributes, &signals),
		C.posix_spawnattr_setflags(&attributes, flags)] {
		if status != 0 { return error_with_code('cannot configure reader group', int(status)) }
	}
	mut arguments := []&char{}
	for value in argv { arguments << unsafe { &char(value.str) } }
	arguments << &char(unsafe { nil })
	mut entries := []string{}
	for name, value in environment {
		if name.contains_any('=\x00') || value.contains('\x00') {
			return error('invalid reader environment')
		}
		entries << name + '=' + value
	}
	mut envp := []&char{}
	for value in entries { envp << unsafe { &char(value.str) } }
	envp << &char(unsafe { nil })
	mut pid := i32(0)
	status := unsafe { C.posix_spawnp(&pid, argv[0].str, &actions, &attributes, arguments.data, envp.data) }
	if status != 0 { return error_with_code('cannot start reader command', int(status)) }
	C.close(pipes[1])
	pipes[1] = -1
	mut child := ReaderChild{int(pid), pipes[0], false}
	pipes[0] = -1
	if C.fcntl(child.descriptor, C.F_SETFL, C.O_NONBLOCK) != 0 {
		cause := os.error_posix()
		child.close() or {}
		return cause
	}
	return child
}

pub fn (child &ReaderChild) poll() !ChildExit {
	if child.retired { return error('reader child is retired') }
	return child_exit(child.pid)!
}

pub fn (mut child ReaderChild) close() ! {
	if child.pid <= 0 || child.descriptor < 0 { return error('reader child has no process owner') }
	if child.retired { return }
	child.retired = true
	C.close(child.descriptor)
	// The unreaped leader reserves its group identity even after natural EOF.
	C.killpg(child.pid, C.SIGKILL)
	C.kill(child.pid, C.SIGKILL)
	mut status := i32(0)
	for {
		waited := C.waitpid(child.pid, &status, 0)
		if waited == child.pid || (waited < 0 && C.errno == C.ECHILD) { break }
		if waited < 0 && C.errno == C.EINTR { continue }
		if waited < 0 { return os.error_posix() }
		time.sleep(time.millisecond)
	}
}
