// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module perfconsole

import os
import sync
import time

#flag -I @DIR
#flag linux -lutil
#include "abi.h"
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
@[typedef]
struct C.vinix_source_child_info {
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
fn C.waitid(i32, u32, &C.vinix_source_child_info, i32) i32
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

pub fn cancelled() bool {
	return unsafe { C.__atomic_load_n(&pending_signal, C.__ATOMIC_RELAXED) } != 0
}

pub fn interrupt_status() int {
	return 128 + int(unsafe { C.__atomic_load_n(&pending_signal, C.__ATOMIC_RELAXED) })
}

pub fn checkpoint() ! {
	if cancelled() {
		return error_with_code('desktop performance run interrupted', interrupt_status())
	}
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

@[heap]
struct Reader {
	fd   int
	echo bool
mut:
	lock     sync.Mutex
	data     []u8
	lines    []string
	consumed int
	closed   bool
	stop     i32
}

fn drain(mut reader Reader) {
	defer {
		reader.lock.lock()
		reader.closed = true
		reader.lock.unlock()
	}
	mut pending := ''
	mut buffer := [65536]u8{}
	mut descriptor := C.pollfd{ fd: reader.fd, events: i16(C.POLLIN) }
	for unsafe { C.__atomic_load_n(&reader.stop, C.__ATOMIC_RELAXED) } == 0 {
		result := C.poll(&descriptor, 1, 50)
		if result == 0 { continue }
		if result < 0 {
			if C.errno == C.EINTR { continue }
			break
		}
		count := C.read(reader.fd, &buffer[0], buffer.len)
		if count < 0 {
			if C.errno in [C.EINTR, C.EAGAIN] { continue }
			break
		}
		if count == 0 { break }
		chunk := unsafe { buffer[..int(count)] }
		if reader.echo {
			mut out := os.stdout()
			out.write(chunk) or {}
			out.flush()
		}
		pending += chunk.bytestr()
		parts := pending.split('\n')
		pending = parts.last()
		reader.lock.lock()
		reader.data << chunk
		for line in parts[..parts.len - 1] { reader.lines << line }
		reader.lock.unlock()
	}
}

fn observed(pid i32) !(bool, int) {
	mut info := C.vinix_source_child_info{}
	for {
		if C.waitid(C.P_PID, u32(pid), &info, C.WEXITED | C.WNOHANG | C.WNOWAIT) == 0 { break }
		if C.errno != C.EINTR { return os.error_posix() }
	}
	return info.si_pid == pid, if info.si_code == C.CLD_EXITED {
		int(info.si_status)
	} else {
		-int(info.si_status)
	}
}

// The leader's zombie reserves its identity until every descendant is retired.
fn retire(pid i32, master int, grace f64) !int {
	mut reaped := false
	defer { if !reaped {
		C.killpg(pid, C.SIGKILL)
		C.kill(pid, C.SIGKILL)
		mut status := i32(0)
		for { if C.waitpid(pid, &status, 0) >= 0 || C.errno != C.EINTR { break } }
	} }
	mut exited, mut code := observed(pid)!
	if !exited {
		C.write(master, c'\x01x', 2)
		deadline := time.sys_mono_now() + u64(grace * f64(time.second))
		for !exited && time.sys_mono_now() < deadline {
			exited, code = observed(pid)!
			if !exited { time.sleep(10 * time.millisecond) }
		}
	}
	C.killpg(pid, C.SIGKILL)
	C.kill(pid, C.SIGKILL)
	// Observe a forced termination before the one and only reap.
	if !exited {
		mut info := C.vinix_source_child_info{}
		for {
			if C.waitid(C.P_PID, u32(pid), &info, C.WEXITED | C.WNOWAIT) == 0 { break }
			if C.errno != C.EINTR { return os.error_posix() }
		}
		code = if info.si_code == C.CLD_EXITED { int(info.si_status) } else { -int(info.si_status) }
	}
	mut raw := i32(0)
	for {
		if C.waitpid(pid, &raw, 0) >= 0 { break }
		if C.errno != C.EINTR { return os.error_posix() }
	}
	reaped = true
	return code
}

pub struct Output {
pub:
	data      []u8
	status    int
	timed_out bool
	drained   bool
	failure   string
}

// The reader never waits on QMP or a bounded line queue. All callback work is
// performed on the supervising thread while the reader drains serial output.
pub fn capture(argv []string, env map[string]string, cwd string, timeout f64, grace f64,
	echo bool, line fn (string, voidptr) !bool, context voidptr) !Output {
	if argv.len == 0 || argv.any(it.contains('\x00')) || cwd.contains('\x00') {
		return error('invalid guest command')
	}
	mut args := []&char{}
	for value in argv { args << unsafe { &char(value.str) } }
	args << &char(unsafe { nil })
	mut text := []string{}
	for key, value in env {
		if key.contains('\x00') || value.contains('\x00') {
			return error('invalid guest environment')
		}
		text << key + '=' + value
	}
	mut environment := []&char{}
	for value in text { environment << unsafe { &char(value.str) } }
	environment << &char(unsafe { nil })
	mut master := i32(-1)
	pid := C.forkpty(&master, unsafe { nil }, unsafe { nil }, unsafe { nil })
	if pid < 0 { return os.error_posix() }
	if pid == 0 {
		unsafe {
			C.signal(C.SIGINT, C.SIG_DFL)
			C.signal(C.SIGTERM, C.SIG_DFL)
			C.signal(C.SIGPIPE, C.SIG_DFL)
		}
		if C.chdir(cwd.str) != 0 { C._exit(127) }
		unsafe { C.execve(argv[0].str, args.data, environment.data) }
		C._exit(127)
	}
	mut retired := false
	defer {
		if !retired { retire(pid, master, 0) or {} }
		C.close(master)
	}
	if C.fcntl(master, C.F_SETFL, C.O_NONBLOCK) != 0 || C.fcntl(master, C.F_SETFD, C.FD_CLOEXEC) != 0 {
		return os.error_posix()
	}
	mut reader := &Reader{ fd: master, echo: echo }
	task := spawn drain(mut reader)
	mut joined := false
	defer { if !joined {
		unsafe { C.__atomic_store_n(&reader.stop, 1, C.__ATOMIC_RELAXED) }
		task.wait()
	} }
	deadline := time.sys_mono_now() + u64(timeout * f64(time.second))
	mut timed_out := false
	mut failure := ''
	for {
		if cancelled() {
			failure = 'desktop performance run interrupted'
			break
		}
		if time.sys_mono_now() >= deadline {
			timed_out = true
			break
		}
		reader.lock.lock()
		mut next := ''
		mut available := false
		if reader.consumed < reader.lines.len {
			next = reader.lines[reader.consumed]
			reader.consumed++
			available = true
		}
		closed := reader.closed
		reader.lock.unlock()
		if available {
			finished := line(next, context) or {
				failure = err.msg()
				break
			}
			if finished { break }
		} else if closed {
			break
		} else {
			time.sleep(10 * time.millisecond)
		}
	}
	status := retire(pid, master, grace)!
	retired = true
	drain_deadline := time.sys_mono_now() + u64(2 * time.second)
	mut drained := false
	for time.sys_mono_now() < drain_deadline {
		reader.lock.lock()
		drained = reader.closed
		reader.lock.unlock()
		if drained { break }
		time.sleep(10 * time.millisecond)
	}
	unsafe { C.__atomic_store_n(&reader.stop, 1, C.__ATOMIC_RELAXED) }
	task.wait()
	joined = true
	return Output{reader.data.clone(), status, timed_out, drained, failure}
}
