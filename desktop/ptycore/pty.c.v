// SPDX-License-Identifier: GPL-2.0-or-later
module ptycore

import os

#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.posix_openpt(int) int
fn C.grantpt(int) int
fn C.unlockpt(int) int
fn C.ptsname(int) &char
fn C.setsid() int
fn C.ioctl(i32, u64, ...voidptr) i32

struct WindowSize {
	rows u16
	columns u16
	width u16
	height u16
}

pub struct Session {
pub:
	pid int
	terminal int
}

pub fn resize(fd int, rows int, columns int, width int, height int) bool {
	if fd < 0 || rows <= 0 || rows > 65535 || columns <= 0 || columns > 65535
		|| width < 0 || width > 65535 || height < 0 || height > 65535 { return false }
	size := WindowSize{ rows: u16(rows), columns: u16(columns), width: u16(width), height: u16(height) }
	return C.ioctl(fd, u64(u32(C.TIOCSWINSZ)), &size) == 0
}

// Build argv/environment before fork, then use only libc/syscalls in the child.
// Every argument is literal. No shell, PATH search or inherited fd above stderr.
pub fn spawn(argv []string, environment []string, directory string, rows int, columns int, width int, height int) !Session {
	if argv.len == 0 || argv.len > 128 || !argv[0].starts_with('/')
		|| argv.any(it.len > 4096 || it.contains('\x00')) || environment.len > 128
		|| environment.any(it.len > 8192 || it.contains('\x00') || !it.contains('='))
		|| !directory.starts_with('/') || directory.contains('\x00') {
		return error('invalid terminal command, environment or directory')
	}
	mut args := []&char{cap: argv.len + 1}
	mut env := []&char{cap: environment.len + 1}
	defer { unsafe { args.free(); env.free() } }
	for argument in argv { args << &char(argument.str) }
	for entry in environment { env << &char(entry.str) }
	args << &char(unsafe { nil })
	env << &char(unsafe { nil })
	master := C.posix_openpt(C.O_RDWR | C.O_NOCTTY | C.O_CLOEXEC)
	if master < 0 { return error('cannot allocate a terminal') }
	if C.grantpt(master) != 0 || C.unlockpt(master) != 0 {
		C.close(master)
		return error('cannot prepare a terminal')
	}
	slave_name := C.ptsname(master)
	if slave_name == unsafe { nil } { C.close(master); return error('cannot locate terminal slave') }
	slave := C.open(slave_name, C.O_RDWR | C.O_NOCTTY | C.O_CLOEXEC)
	if slave < 0 { C.close(master); return error('cannot open terminal slave') }
	if !resize(slave, rows, columns, width, height) {
		C.close(slave); C.close(master)
		return error('cannot set terminal geometry')
	}
	mut inherited := []int{}
	defer { unsafe { inherited.free() } }
	$if !linux {
		// Host fixtures have no close_range. Enumerate actual descriptors rather
		// than iterating a potentially INT_MAX process limit before exec.
		names := os.ls('/dev/fd') or {
			C.close(slave); C.close(master)
			return error('cannot enumerate terminal descriptors')
		}
		defer { unsafe { for name in names { name.free() }; (&array(&names)).free() } }
		inherited = []int{cap: names.len}
		for name in names {
			mut numeric := name.len > 0
			for byte in name { if byte < `0` || byte > `9` { numeric = false; break } }
			if numeric && name.int() > 2 { inherited << name.int() }
		}
	}
	pid := C.fork()
	if pid < 0 { C.close(slave); C.close(master); return error('cannot start terminal process') }
	if pid == 0 {
		C.close(master)
		if C.setsid() < 0 || C.ioctl(slave, u64(u32(C.TIOCSCTTY)), unsafe { nil }) != 0 {
			C.write(2, c'terminal: cannot claim controlling terminal\n', 44)
			C._exit(126)
		}
		if C.dup2(slave, 0) < 0 || C.dup2(slave, 1) < 0 || C.dup2(slave, 2) < 0 {
			C.write(2, c'terminal: cannot attach standard streams\n', 41)
			C._exit(126)
		}
		$if linux {
			if C.syscall(C.SYS_close_range, u32(3), u32(-1), u32(0)) != 0 { C._exit(126) }
		} $else {
			for fd in inherited { C.close(fd) }
		}
		if C.chdir(directory.str) != 0 {
			C.write(2, c'terminal: cannot enter working directory\n', 41)
			C._exit(126)
		}
		C.execve(argv[0].str, args.data, env.data)
		C.write(2, c'terminal: command could not be executed\n', 40)
		C._exit(127)
	}
	C.close(slave)
	flags := C.fcntl(master, C.F_GETFL)
	if flags < 0 || C.fcntl(master, C.F_SETFL, flags | C.O_NONBLOCK) != 0 {
		C.close(master)
		C.kill(pid, C.SIGTERM)
		C.waitpid(pid, unsafe { nil }, 0)
		return error('cannot make terminal reads nonblocking')
	}
	return Session{ pid: pid, terminal: master }
}
