// SPDX-License-Identifier: GPL-2.0-or-later
module sourcecommand

import os
import time

pub struct DuplexChild {
pub:
	pid int
pub mut:
	request  i32 = -1
	response i32 = -1
	stdout   []u8
	stderr   []u8
mut:
	output  i32 = -1
	errors  i32 = -1
	retired bool
}

pub fn (child &DuplexChild) is_retired() bool { return child.retired }

pub fn spawn_duplex(argv []string, environment map[string]string, request_name string, response_name string) !DuplexChild {
	if argv.len == 0 || argv.any(it.contains('\x00')) || request_name == '' || response_name == '' {
		return error('invalid duplex command')
	}
	mut descriptors := [i32(-1), -1, -1, -1, -1, -1, -1, -1]!
	defer { for fd in descriptors { if fd >= 0 { C.close(fd) } }
	 }
	for pair in 0 .. 4 {
		if C.pipe(&descriptors[pair * 2]) != 0 { return os.error_posix() }
		for index in pair * 2 .. pair * 2 + 2 {
			if descriptors[index] < 3 {
				moved := C.fcntl(descriptors[index], C.F_DUPFD_CLOEXEC, 3)
				if moved < 0 { return os.error_posix() }
				C.close(descriptors[index])
				descriptors[index] = moved
			} else if C.fcntl(descriptors[index], C.F_SETFD, C.FD_CLOEXEC) != 0 {
				return os.error_posix()
			}
		}
	}
	mut actions := C.posix_spawn_file_actions_t{}
	if C.posix_spawn_file_actions_init(&actions) != 0 {
		return error('cannot initialize duplex actions')
	}
	defer { C.posix_spawn_file_actions_destroy(&actions) }
	// Explicit dup2 actions preserve the protocol descriptors and clear their
	// child CLOEXEC bits without changing the parent's standard descriptors.
	for status in [
		C.posix_spawn_file_actions_adddup2(&actions, descriptors[0], descriptors[0]),
		C.posix_spawn_file_actions_adddup2(&actions, descriptors[3], descriptors[3]),
		C.posix_spawn_file_actions_adddup2(&actions, descriptors[5], 1),
		C.posix_spawn_file_actions_adddup2(&actions, descriptors[7], 2),
	] {
		if status != 0 { return error_with_code('cannot configure duplex streams', int(status)) }
	}
	for index in [1, 2, 4, 5, 6, 7] {
		if C.posix_spawn_file_actions_addclose(&actions, descriptors[index]) != 0 {
			return error('cannot close duplex child descriptor')
		}
	}
	mut attributes := C.posix_spawnattr_t{}
	if C.posix_spawnattr_init(&attributes) != 0 {
		return error('cannot initialize duplex attributes')
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
		for fd in [descriptors[0], descriptors[3]] {
			if C.posix_spawn_file_actions_addinherit_np(&actions, fd) != 0 {
				return error('cannot inherit duplex protocol descriptor')
			}
		}
		if C.fcntl(0, C.F_GETFD) >= 0 && C.posix_spawn_file_actions_addinherit_np(&actions, 0) != 0 {
			return error('cannot preserve duplex stdin')
		}
	}
	for status in [C.posix_spawnattr_setpgroup(&attributes, 0),
		C.posix_spawnattr_setsigdefault(&attributes, &signals),
		C.posix_spawnattr_setflags(&attributes, flags)] {
		if status != 0 { return error_with_code('cannot configure duplex owner', int(status)) }
	}
	mut args := []&char{}
	for item in argv { args << unsafe { &char(item.str) } }
	args << &char(unsafe { nil })
	mut env := environment.clone()
	env[request_name] = descriptors[0].str()
	env[response_name] = descriptors[3].str()
	mut entries := []string{}
	for name, value in env {
		if name.contains_any('=\x00') || value.contains('\x00') {
			return error('invalid duplex environment')
		}
		entries << name + '=' + value
	}
	mut envp := []&char{}
	for item in entries { envp << unsafe { &char(item.str) } }
	envp << &char(unsafe { nil })
	mut pid := i32(0)
	status := unsafe { C.posix_spawnp(&pid, argv[0].str, &actions, &attributes, args.data, envp.data) }
	if status != 0 { return error_with_code('cannot spawn duplex command', int(status)) }
	mut child := DuplexChild{ pid: int(pid), request: descriptors[1], response: descriptors[2], output: descriptors[4], errors: descriptors[6] }
	for index in [1, 2, 4, 6] { descriptors[index] = -1 }
	for fd in [child.request, child.response, child.output, child.errors] {
		if C.fcntl(fd, C.F_SETFL, C.O_NONBLOCK) != 0 {
			failure := os.error_posix()
			child.close() or {}
			return failure
		}
	}
	return child
}

fn drain_duplex(descriptor i32, mut data []u8) !i32 {
	if descriptor < 0 { return descriptor }
	mut bytes := [65536]u8{}
	for {
		read := C.read(descriptor, &bytes[0], usize(bytes.len))
		if read > 0 {
			if data.len + int(read) > 32 * 1024 * 1024 {
				return error('duplex diagnostics exceed 32 MiB')
			}
			data << bytes[..int(read)]
		} else if read == 0 {
			C.close(descriptor)
			return -1
		} else if C.errno == C.EINTR {
			continue
		} else if C.errno in [C.EAGAIN, C.EWOULDBLOCK] {
			return descriptor
		} else {
			return os.error_posix()
		}
	}
}

fn (mut child DuplexChild) drain() ! {
	child.output = drain_duplex(child.output, mut child.stdout)!
	child.errors = drain_duplex(child.errors, mut child.stderr)!
}

fn (mut child DuplexChild) pause(descriptor i32, event i16) ! {
	mut descriptors := [C.pollfd{ fd: descriptor, events: event },
		C.pollfd{ fd: child.output, events: i16(C.POLLIN) },
		C.pollfd{ fd: child.errors, events: i16(C.POLLIN) }]!
	if C.poll(&descriptors[0], 3, 50) < 0 && C.errno != C.EINTR { return os.error_posix() }
	child.drain()!
}

pub fn (mut child DuplexChild) read_exact(count int, cancel fn () bool) ![]u8 {
	if child.retired || count < 0 || count > 1024 * 1024 { return error('invalid duplex read') }
	mut bytes := []u8{len: count}
	mut offset := 0
	mut deadline := time.sys_mono_now() + i64(10 * time.second)
	for offset < count {
		if cancel != unsafe { nil } && cancel() { return error('duplex operation interrupted') }
		child.drain()!
		read := unsafe { C.read(child.response, &u8(bytes.data) + offset, usize(count - offset)) }
		if read > 0 {
			offset += int(read)
			deadline = time.sys_mono_now() + i64(10 * time.second)
			continue
		}
		if read == 0 { return error('UIKit desktop connection closed') }
		if C.errno == C.EINTR { continue }
		if C.errno !in [C.EAGAIN, C.EWOULDBLOCK] { return os.error_posix() }
		if time.sys_mono_now() >= deadline { return error('UIKit desktop response timed out') }
		child.pause(child.response, i16(C.POLLIN))!
	}
	return bytes
}

pub fn (mut child DuplexChild) write_all(bytes []u8, cancel fn () bool) ! {
	if child.retired { return error('duplex child is retired') }
	mut offset := 0
	mut deadline := time.sys_mono_now() + i64(10 * time.second)
	for offset < bytes.len {
		if cancel != unsafe { nil } && cancel() { return error('duplex operation interrupted') }
		child.drain()!
		written := unsafe { C.write(child.request, &u8(bytes.data) + offset, usize(bytes.len - offset)) }
		if written > 0 {
			offset += int(written)
			deadline = time.sys_mono_now() + i64(10 * time.second)
			continue
		}
		if written < 0 && C.errno == C.EINTR { continue }
		if written < 0 && C.errno !in [C.EAGAIN, C.EWOULDBLOCK] { return os.error_posix() }
		if time.sys_mono_now() >= deadline { return error('UIKit desktop request timed out') }
		child.pause(child.request, i16(C.POLLOUT))!
	}
}

pub fn (mut child DuplexChild) wait(cancel fn () bool) !int {
	deadline := time.sys_mono_now() + i64(10 * time.second)
	for {
		if cancel != unsafe { nil } && cancel() { return error('duplex operation interrupted') }
		child.drain()!
		state := child_exit(child.pid)!
		if state.exited {
			child.close()!
			return state.return_code
		}
		if time.sys_mono_now() >= deadline { return error('UIKit desktop process did not exit') }
		child.pause(-1, 0)!
	}
}

pub fn (mut child DuplexChild) close() ! {
	if child.retired { return }
	child.retired = true
	defer {
		for fd in [child.request, child.response, child.output, child.errors] {
			if fd >= 0 { C.close(fd) }
		}
		child.request = -1
		child.response = -1
		child.output = -1
		child.errors = -1
	}
	C.killpg(child.pid, C.SIGKILL)
	C.kill(child.pid, C.SIGKILL)
	mut status := i32(0)
	for {
		result := C.waitpid(child.pid, &status, 0)
		if result == child.pid || (result < 0 && C.errno == C.ECHILD) { break }
		if result < 0 && C.errno != C.EINTR { return os.error_posix() }
	}
	child.drain() or {}
}
