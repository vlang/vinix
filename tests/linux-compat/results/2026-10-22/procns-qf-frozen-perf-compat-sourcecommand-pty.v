// SPDX-License-Identifier: GPL-2.0-or-later
module sourcecommand

import os
import time

#flag linux -lutil
$if macos {
	#include <util.h>
} $else {
	#include <pty.h>
}

fn C.forkpty(&i32, &char, voidptr, voidptr) i32
fn C.execve(&char, &&char, &&char) i32
fn C.getpgid(int) int

// The caller stops and joins readers before close. Observations reserve the
// leader PID, and close retires its private process group before the sole reap.
pub struct PtyChild {
pub:
	pid int
	master int
mut:
	retired bool
}

pub fn spawn_pty(argv []string, environment map[string]string, directory string) !PtyChild {
	if argv.len == 0 || argv.any(it.contains('\x00')) || directory.contains('\x00') { return error('invalid PTY command') }
	mut arguments := []&char{}
	for value in argv { arguments << unsafe { &char(value.str) } }
	arguments << &char(unsafe { nil })
	mut values := []string{}
	for name, value in environment {
		if name.contains_any('=\x00') || value.contains('\x00') { return error('invalid PTY environment') }
		values << name + '=' + value
	}
	mut envp := []&char{}
	for value in values { envp << unsafe { &char(value.str) } }
	envp << &char(unsafe { nil })
	mut handshake := [i32(-1), -1]!
	if C.pipe(&handshake[0]) != 0 { return os.error_posix() }
	defer { for descriptor in handshake { if descriptor >= 0 { C.close(descriptor) } } }
	for index in 0 .. 2 {
		if handshake[index] < 3 {
			moved := C.fcntl(handshake[index], C.F_DUPFD_CLOEXEC, 3)
			if moved < 0 { return os.error_posix() }
			C.close(handshake[index]); handshake[index] = moved
		} else if C.fcntl(handshake[index], C.F_SETFD, C.FD_CLOEXEC) != 0 { return os.error_posix() }
	}
	mut descriptor := i32(-1)
	pid := C.forkpty(&descriptor, unsafe { nil }, unsafe { nil }, unsafe { nil })
	if pid < 0 { return os.error_posix() }
	if pid == 0 {
		C.close(handshake[0])
		unsafe {
			C.signal(C.SIGINT, C.SIG_DFL)
			C.signal(C.SIGTERM, C.SIG_DFL)
			C.signal(C.SIGPIPE, C.SIG_DFL)
		}
		// forkpty returns in the parent before Darwin's child login_tty has
		// necessarily created its session. Publish readiness from the child
		// only after that SDK setup; no caller can signal an unowned group.
		if C.write(handshake[1], c'1', 1) != 1 { C._exit(127) }
		C.close(handshake[1])
		if directory != '' && C.chdir(directory.str) != 0 { C._exit(127) }
		unsafe { C.execve(argv[0].str, arguments.data, envp.data) }
		C._exit(127)
	}
	mut child := PtyChild{int(pid), int(descriptor), false}
	mut ready := false
	defer { if !ready { child.close() or {} } }
	C.close(handshake[1]); handshake[1] = -1
	mut notification := C.pollfd{fd: handshake[0], events: i16(C.POLLIN)}
	deadline := time.sys_mono_now() + 5 * time.second
	mut acknowledged := false
	for time.sys_mono_now() < deadline {
		status := C.poll(&notification, 1, 50)
		if status < 0 { if C.errno == C.EINTR { continue }; return os.error_posix() }
		if status == 0 { continue }
		mut byte := u8(0)
		if C.read(handshake[0], &byte, 1) != 1 || byte != `1` { return error('PTY session setup failed') }
		acknowledged = true
		break
	}
	if !acknowledged { return error('PTY session setup timed out') }
	// A failed exec can exit between readiness and this query. waitid keeps
	// that leader reserved. Darwin can remove its group just before publishing
	// waitid's exit record; wait within the existing setup deadline for that
	// record. An absent group is safe only after observed exit.
	for {
		group := C.getpgid(int(pid))
		group_error := C.errno
		if group == pid { break }
		if group < 0 && group_error == C.ESRCH {
			if child.poll()!.exited { break }
			if time.sys_mono_now() < deadline { time.sleep(time.millisecond); continue }
		}
		return error('PTY child did not create a private process group (${group}, errno ${group_error})')
	}
	if C.fcntl(descriptor, C.F_SETFD, C.FD_CLOEXEC) != 0 || C.fcntl(descriptor, C.F_SETFL, C.O_NONBLOCK) != 0 { return os.error_posix() }
	ready = true
	return child
}

pub fn (child &PtyChild) poll() !ChildExit {
	if child.retired { return error('PTY child is retired') }
	return child_exit(child.pid)!
}

// A zero-length read denotes slave EOF. A timeout returns -1. A read never
// waits indefinitely, so its owning thread can always acknowledge retirement.
pub fn (child &PtyChild) read(mut buffer []u8, milliseconds int) !int {
	if child.retired || milliseconds < 0 { return error('invalid retired PTY read') }
	mut descriptor := C.pollfd{fd: i32(child.master), events: i16(C.POLLIN)}
	for {
		result := C.poll(&descriptor, 1, milliseconds)
		if result < 0 { if C.errno == C.EINTR { continue }; return os.error_posix() }
		if result == 0 { return -1 }
		count := unsafe { C.read(child.master, buffer.data, usize(buffer.len)) }
		if count < 0 {
			if C.errno == C.EIO { return 0 }
			if C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { return -1 }
			return os.error_posix()
		}
		return int(count)
	}
	return -1
}

pub fn (child &PtyChild) write(bytes []u8) ! {
	if child.retired { return error('PTY child is retired') }
	mut offset := 0
	for offset < bytes.len {
		count := unsafe { C.write(child.master, &u8(bytes.data) + offset, usize(bytes.len - offset)) }
		if count < 0 {
			if C.errno == C.EINTR { continue }
			if C.errno in [C.EAGAIN, C.EWOULDBLOCK] { time.sleep(time.millisecond); continue }
			return os.error_posix()
		}
		if count == 0 { return error('PTY write stopped') }
		offset += int(count)
	}
}

pub fn (child &PtyChild) signal(signal int) ! {
	if child.retired { return error('PTY child is retired') }
	if C.killpg(child.pid, signal) != 0 && C.errno !in [C.ESRCH, C.EPERM] { return os.error_posix() }
}

pub fn (child &PtyChild) settle(seconds f64) !bool {
	deadline := time.sys_mono_now() + u64(seconds * f64(time.second))
	for time.sys_mono_now() < deadline {
		if child.poll()!.exited { return true }
		time.sleep(10 * time.millisecond)
	}
	return child.poll()!.exited
}

pub fn (mut child PtyChild) close() ! {
	if child.retired { return }
	child.retired = true
	// The leader is still reserved even when it exited naturally. Terminate
// descendants before releasing the identity, and close the master before
// Darwin's slave teardown and final blocking wait can depend on each other.
	C.killpg(child.pid, C.SIGKILL)
	C.kill(child.pid, C.SIGKILL)
	C.close(child.master)
	mut status := i32(0)
	for {
		result := C.waitpid(child.pid, &status, 0)
		if result == child.pid || (result < 0 && C.errno == C.ECHILD) { break }
		if result < 0 && C.errno == C.EINTR { continue }
		return os.error_posix()
	}
}
