// SPDX-License-Identifier: GPL-2.0-or-later
// Small OS primitives shared by the session clients and background services.
module sessionipc

import os
import time as _

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

fn C.execv(&char, &&char) int
fn C.getpeereid(int, &u32, &u32) int
fn C.lstat(&char, &C.stat) int
fn C.fcntl(int, int, ...voidptr) int
fn C.poll(&C.pollfd, usize, int) int
fn C.unlink(&char) int
fn C.setsid() int

pub struct C.pollfd {
pub mut:
	fd      int
	events  i16
	revents i16
}

pub fn monotonic_millis() i64 {
	mut stamp := C.timespec{}
	if C.clock_gettime(C.CLOCK_MONOTONIC, &stamp) != 0 { return 0 }
	return stamp.tv_sec * 1000 + stamp.tv_nsec / 1_000_000
}

pub fn desktop_realtime() (i64, i64) {
	mut stamp := C.timespec{}
	if C.clock_gettime(C.CLOCK_REALTIME, &stamp) != 0 { return -1, 0 }
	return stamp.tv_sec, stamp.tv_nsec
}

pub fn desktop_close(fd int) int { return C.close(fd) }

pub fn desktop_open_rw(path string) int {
	return C.open(&char(path.str), C.O_RDWR | C.O_CLOEXEC, 0)
}

pub fn desktop_ioctl(fd int, request u64, argument voidptr) int {
	return C.ioctl(fd, request, argument)
}

pub fn desktop_set_nonblocking(fd int, enabled bool) bool {
	flags := C.fcntl(fd, C.F_GETFL)
	if flags < 0 { return false }
	return C.fcntl(fd, C.F_SETFL, if enabled { flags | C.O_NONBLOCK } else { flags & ~C.O_NONBLOCK }) == 0
}

pub fn desktop_set_cloexec(fd int, enabled bool) bool {
	flags := C.fcntl(fd, C.F_GETFD)
	if flags < 0 { return false }
	return C.fcntl(fd, C.F_SETFD, if enabled { flags | C.FD_CLOEXEC } else { flags & ~C.FD_CLOEXEC }) == 0
}

pub fn desktop_ignore_broken_pipe() {
	unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
}

// A development/test installation can keep the three helpers together. Normal
// images use /usr/bin, including when the compositor lives in /usr/libexec.
pub fn helper_path(name string) string {
	if directory := os.getenv_opt('VINIX_SESSION_BIN_DIR') {
		defer { unsafe { directory.free() } }
		return directory + '/' + name
	}
	return '/usr/bin/' + name
}

// Compatibility for scripts using the old desktop command-line service modes.
// exec changes the kernel's process identity to the dedicated executable.
pub fn exec_helper(name string, args []string) ! {
	path := helper_path(name)
	defer { unsafe { path.free() } }
	mut argv := []&char{cap: args.len + 2}
	defer { unsafe { argv.free() } }
	argv << &char(path.str)
	for arg in args { argv << &char(arg.str) }
	argv << &char(unsafe { nil })
	C.execv(&char(path.str), argv.data)
	return error('cannot execute ${path}: ${os.get_error_msg(C.errno)}')
}
