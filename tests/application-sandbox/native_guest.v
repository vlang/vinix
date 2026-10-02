// SPDX-License-Identifier: GPL-2.0-or-later
// Compile beside desktop/app_sandbox.c.v to exercise the production native
// profile without framebuffer or UI dependencies.
module main

import os

#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.fcntl(fd int, cmd int, arg ...voidptr) int

fn C.pause() int

struct AppProcessOptions {
	name        string
	request_fd  int
	response_fd int
}

fn profile_child(mode int) {
	if mode == 3 {
		mut unshare_nr := i32(97)
		$if amd64 {
			unshare_nr = 272
		}
		assert unsafe { C.syscall(unshare_nr, voidptr(0x04000000)) } == 0
	}
	options := AppProcessOptions{
		name:        'vinix-calculator'
		request_fd:  5
		response_fd: 9
	}
	native_app_apply_sandbox(options) or {
		eprintln('APPLICATION NATIVE SANDBOX FAIL: ${err.msg()}')
		C._exit(1)
	}
	mut prctl_nr := i32(167)
	mut capget_nr := i32(90)
	mut socket_nr := i32(198)
	$if amd64 {
		prctl_nr = 157
		capget_nr = 125
		socket_nr = 41
	}
	if mode == 1 {
		unsafe { C.syscall(socket_nr, voidptr(2), voidptr(1), voidptr(0)) }
		C._exit(2)
	}
	if mode == 2 {
		C.open(c'/tmp/native-secret', C.O_RDONLY)
		C._exit(2)
	}
	assert C.getuid() == 65534 && C.geteuid() == 65534
	assert unsafe { C.syscall(prctl_nr, voidptr(39), voidptr(0), voidptr(0), voidptr(0), voidptr(0)) } == 1
	header := AppSandboxCapHeader{}
	mut caps := [2]AppSandboxCapData{}
	assert unsafe { C.syscall(capget_nr, &header, &caps[0]) } == 0
	for cap in caps {
		assert cap.effective == 0 && cap.permitted == 0 && cap.inheritable == 0
	}
	assert C.fcntl(17, C.F_GETFD) == -1
	assert C.write(9, c'A', 1) == 1
	mut byte := u8(0)
	assert C.read(5, &byte, 1) == 1 && byte == `A`
	mut memory := []u8{len: 4096}
	memory[4095] = 42
	assert memory[4095] == 42
	unsafe { memory.free() }
	C._exit(0)
}

fn main() {
	assert native_app_has_sandbox('vinix-calculator')
	assert !native_app_has_sandbox('vinix-terminal')
	// Read/write pipe endpoints are deliberately nonadjacent. The profile
	// must preserve both while closing an extra inherited descriptor.
	mut pipe := [2]i32{}
	assert C.pipe(&pipe[0]) == 0
	assert C.dup2(pipe[0], 5) == 5
	assert C.dup2(pipe[1], 9) == 9
	C.close(pipe[0])
	C.close(pipe[1])
	assert C.dup2(9, 17) == 17
	os.write_file('/tmp/native-secret', 'hidden') or { panic(err) }
	for mode in 0 .. 4 {
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			profile_child(mode)
			C._exit(2)
		}
		mut status := i32(0)
		assert C.waitpid(pid, &status, 0) == pid
		if mode == 0 || mode == 3 {
			assert status == 0
		} else {
			assert status & 0x7f == 6
		}
	}
	// Let the serial logger drain the two expected violation messages before
	// emitting one complete verdict write.
	C.usleep(200000)
	message := 'APPLICATION NATIVE SANDBOX GUEST PASS\n'
	assert C.write(1, message.str, usize(message.len)) == message.len
	for {
		C.pause()
	}
}
