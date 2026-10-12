// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module corevm

import os
import time

#flag -I @DIR
#flag linux -lutil
#include "abi.h"
#include <fcntl.h>
@[typedef]
struct C.vinix_core_child_info {
	si_pid    i32
	si_code   i32
	si_status i32
}

struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

fn C.forkpty(&i32, &char, voidptr, voidptr) i32
fn C.waitid(i32, u32, &C.vinix_core_child_info, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.killpg(i32, i32) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.signal(i32, voidptr) voidptr
fn C.__atomic_load_n(&i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)

__global (
	pending_signal i32
)

fn interrupted(signal i32) {
	unsafe { C.__atomic_store_n(&pending_signal, signal, C.__ATOMIC_RELAXED) }
}

pub fn checkpoint() ! {
	signal := unsafe { C.__atomic_load_n(&pending_signal, C.__ATOMIC_RELAXED) }
	if signal != 0 { return error_with_code('Core guest run interrupted', 128 + int(signal)) }
}

pub struct Guard {
	interrupt voidptr
	terminate voidptr
	pipe      voidptr
}

pub fn own_commands() Guard {
	unsafe { C.__atomic_store_n(&pending_signal, 0, C.__ATOMIC_RELAXED) }
	return Guard{unsafe { C.signal(C.SIGINT, voidptr(interrupted)) }, unsafe { C.signal(C.SIGTERM, voidptr(interrupted)) }, unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }}
}

pub fn (guard Guard) close() {
	unsafe {
		C.signal(C.SIGINT, guard.interrupt)
		C.signal(C.SIGTERM, guard.terminate)
		C.signal(C.SIGPIPE, guard.pipe)
	}
}

fn now() f64 { return f64(time.sys_mono_now()) / f64(time.second) }

struct Child {
	pid    i32
	master i32
}

fn start(command []string, env map[string]string, cwd string) !Child {
	if command.len == 0 || command.any(it.contains('\x00')) || cwd.contains('\x00') {
		return error('invalid core guest command')
	}
	mut argv := []&char{}
	for value in command { argv << unsafe { &char(value.str) } }
	argv << &char(unsafe { nil })
	mut values := []string{}
	for key, value in env {
		if key.contains('\x00') || key.contains('=') || value.contains('\x00') {
			return error('invalid core guest environment')
		}
		values << key + '=' + value
	}
	mut envp := []&char{}
	for value in values { envp << unsafe { &char(value.str) } }
	envp << &char(unsafe { nil })
	mut master := i32(-1)
	pid := C.forkpty(&master, unsafe { nil }, unsafe { nil }, unsafe { nil })
	if pid < 0 { return os.error_posix() }
	if pid == 0 {
		unsafe {
			C.signal(C.SIGINT, C.SIG_DFL)
			C.signal(C.SIGTERM, C.SIG_DFL)
			C.signal(C.SIGPIPE, C.SIG_DFL)
		}
		if cwd != '' && C.chdir(cwd.str) != 0 { C._exit(127) }
		unsafe { C.execve(command[0].str, argv.data, envp.data) }
		C._exit(127)
	}
	return Child{pid, master}
}

// Observe without reaping so the leader reserves its identity through cleanup.
fn (child Child) observe() !(bool, int) {
	mut info := C.vinix_core_child_info{}
	for {
		if C.waitid(C.P_PID, u32(child.pid), &info, C.WEXITED | C.WNOHANG | C.WNOWAIT) == 0 {
			break
		}
		if C.errno != C.EINTR { return os.error_posix() }
	}
	return info.si_pid == child.pid, if info.si_code == C.CLD_EXITED {
		int(info.si_status)
	} else {
		128 + int(info.si_status)
	}
}

fn (child Child) shutdown() ! {
	if C.write(child.master, c'\x01x', 2) < 0 && C.errno != C.EIO { return os.error_posix() }
}

fn (child Child) settle(seconds f64) !bool {
	deadline := now() + seconds
	for now() < deadline {
		exited, _ := child.observe()!
		if exited { return true }
		time.sleep(50 * time.millisecond)
	}
	exited, _ := child.observe()!
	return exited
}

// Retirement never responds to pending interrupts. Every path kills the group
// before the sole reap. The read loop has stopped before entry; close its master
// after termination so Darwin slave teardown cannot block that reap.
fn (child Child) close(amd64 bool) ! {
	mut descriptor_closed := false
	defer { if !descriptor_closed { C.close(child.master) } }
	mut reaped := false
	defer {
		if !reaped {
			C.killpg(child.pid, C.SIGKILL)
			C.kill(child.pid, C.SIGKILL)
			if !descriptor_closed {
				C.close(child.master)
				descriptor_closed = true
			}
			mut status := i32(0)
			for { if C.waitpid(child.pid, &status, 0) >= 0 || C.errno != C.EINTR { break } }
		}
	}
	mut exited, _ := child.observe()!
	if !exited && !amd64 {
		child.shutdown() or {}
		exited = child.settle(5)!
	}
	if !exited {
		C.killpg(child.pid, C.SIGTERM)
		exited = child.settle(2)!
	}
	C.killpg(child.pid, C.SIGKILL)
	C.kill(child.pid, C.SIGKILL)
	close_status := C.close(child.master)
	descriptor_closed = true
	if close_status != 0 { return os.error_posix() }
	mut status := i32(0)
	for {
		if C.waitpid(child.pid, &status, 0) >= 0 { break }
		if C.errno != C.EINTR { return os.error_posix() }
	}
	reaped = true
}

pub struct Run {
pub:
	output     string
	has_status bool
	status     int
	forced     bool
	finished   bool
}

pub fn capture(command []string, env map[string]string, cwd string, timeout f64,
	verification bool, amd64 bool, echo bool) !Run {
	child := start(command, env, cwd)!
	mut closed := false
	defer { if !closed { child.close(amd64) or {} } }
	deadline := now() + timeout
	mut transcript := []u8{}
	mut buffer := [65536]u8{}
	mut descriptor := C.pollfd{ fd: child.master, events: i16(C.POLLIN) }
	mut has_status := false
	mut status := 0
	mut finished_at := f64(-1)
	for now() < deadline {
		checkpoint()!
		has_status, status = child.observe()!
		if has_status { break }
		ready := C.poll(&descriptor, 1, 250)
		if ready < 0 {
			if C.errno == C.EINTR { continue }
			return os.error_posix()
		}
		if ready > 0 {
			count := C.read(child.master, &buffer[0], buffer.len)
			if count < 0 {
				if C.errno in [C.EIO, C.EINTR] { continue }
				return os.error_posix()
			}
			if count > 0 {
				chunk := unsafe { buffer[..int(count)] }
				transcript << chunk
				if echo {
					mut stdout := os.stdout()
					stdout.write(chunk)!
					stdout.flush()
				}
			}
		}
		recent := transcript[if transcript.len > 131072 { transcript.len - 131072 } else { 0 }..].bytestr()
		expected := if verification { core_persist_marker } else { core_pass_marker }
		if finished_at < 0 && (recent.contains(expected) || core_fail_markers.any(recent.contains(it))) {
			finished_at = now()
			if !amd64 { child.shutdown()! }
		}
		if finished_at >= 0 && ((amd64 && now() - finished_at > 2) || (!amd64 && now() - finished_at >= 10)) {
			break
		}
	}
	// Mark closed before cleanup: close owns its fallback even on an error.
	closed = true
	child.close(amd64)!
	return Run{transcript.bytestr(), has_status, status, !has_status, finished_at >= 0}
}
