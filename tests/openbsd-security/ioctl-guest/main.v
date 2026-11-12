// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time

#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.dup2(i32, i32) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.waitpid(i32, &i32, i32) i32

const queries = [u64(0x80086601), 0x80046601, 0x82307201, 0x82307202]!

fn pledged(promises &char) bool {
	number := $if arm64 { i32(248) } $else { i32(501) }
	return unsafe { C.syscall(number, promises, nil) == 0 }
}

fn query(fd i32, request u64) i32 {
	// Exercise the register ABI, including musl's sign-extended ioctl command.
	mut buffer := [1024]u8{}
	return unsafe { C.syscall(i32(C.SYS_ioctl), voidptr(int(fd)), voidptr(request), &buffer[0]) }
}

fn child(fd i32, request u64, mode int) {
	if C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(80) }
	promises := match mode {
		0 { c'stdio rpath error' }
		1 { c'stdio error' }
		2 { c'stdio' }
		else { c'stdio rpath wpath cpath fattr tty error' }
	}
	if !pledged(promises) { C._exit(81) }
	result := query(fd, request)
	code := C.errno
	if mode == 2 { C._exit(82) } // A violation must kill this child.
	if mode == 0 {
		if request & 0xffffffff == queries[0] {
			if result != 0 { C._exit(83) }
		} else if result != -1 || code != C.ENOTTY {
			C._exit(84)
		}
	} else if result != -1 || code != C.ENOSYS {
		C._exit(85)
	}
	C._exit(0)
}

fn check(fd i32, request u64, mode int) ! {
	pid := C.fork()
	if pid < 0 { return error('fork failed') }
	if pid == 0 { child(fd, request, mode) }
	mut status := i32(0)
	for {
		waited := C.waitpid(pid, &status, 0)
		if waited == pid { break }
		if waited < 0 && C.errno == C.EINTR { continue }
		return error('waitpid failed')
	}
	wanted := if mode == 2 { i32(6) } else { i32(0) }
	if status != wanted {
		return error('ioctl 0x${request:x} mode ${mode}: status ${status}, expected ${wanted}')
	}
}

fn run() ! {
	fd := C.open(c'/tmp', C.O_RDONLY | C.O_DIRECTORY)
	if fd < 0 { return error('open test directory failed') }
	defer { C.close(fd) }
	for request in queries {
		for mode in 0 .. 3 { check(fd, request, mode)! }
		check(fd, request | u64(0xffffffff00000000), 0)!
	}
	// The read exceptions must not admit flag changes or neighboring requests.
	for request in [u64(0x40086602), 0x40046602, 0x82307203, 0x80086603]! {
		check(fd, request, 3)!
	}
	println('HWTEST PASS pledge-file-ioctl: 20 ordinary-user query and refusal controls')
}

fn main() {
	console := $if arm64 { c'/dev/console' } $else { c'/dev/com1' }
	fd := C.open(console, C.O_WRONLY)
	if fd >= 0 {
		C.dup2(fd, 1)
		C.dup2(fd, 2)
		if fd > 2 { C.close(fd) }
	}
	run() or { eprintln('HWTEST FAIL pledge-file-ioctl: ' + err.msg()) }
	for { time.sleep(time.second) }
}
