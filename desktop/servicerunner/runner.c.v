// SPDX-License-Identifier: GPL-2.0-or-later
module servicerunner

import desktop.sessionipc
import os

$if linux {
	#include <sys/prctl.h>
}

fn C.prctl(int, usize, usize, usize, usize) int
fn C.execv(&char, &&char) int
fn C.getpgrp() int

pub fn run(lease int, args []string) ! {
	if lease < 3 || args.len == 0 || !args[0].starts_with('/') {
		return error('invalid service runner arguments')
	}
	mut check := i32(0)
	mut length := u32(sizeof(i32))
	if C.getsockopt(lease, C.SOL_SOCKET, C.SO_TYPE, &check, &length) != 0 || check != C.SOCK_STREAM {
		return error('service lease is not a stream socket')
	}
	if !sessionipc.desktop_set_cloexec(lease, true) || !sessionipc.desktop_set_nonblocking(lease, true) {
		return error('cannot configure service lease')
	}
	sessionipc.desktop_ignore_broken_pipe()
	mut argv := []&char{cap: args.len + 1}
	defer { unsafe { argv.free() } }
	for arg in args { argv << &char(arg.str) }
	argv << &char(unsafe { nil })
	guardian := C.getpid()
	if guardian <= 1 || C.getpgrp() != guardian {
		return error('service runner must lead a private process group')
	}
	child := C.fork()
	if child == 0 {
		$if linux {
			if C.prctl(1, usize(C.SIGKILL), 0, 0, 0) != 0 || C.getppid() != guardian {
				C._exit(127)
			}
		}
		C.close(lease)
		C.execv(argv[0], argv.data)
		C._exit(127)
	}
	if child < 0 { return os.error_posix() }
	for {
		mut status := i32(0)
		if C.waitpid(child, &status, C.WNOHANG) == child {
			C.write(lease, &status, sizeof(i32))
			C.kill(-guardian, C.SIGKILL)
			C._exit(0)
		}
		mut readiness := C.pollfd{ fd: lease, events: C.POLLIN | C.POLLHUP }
		if C.poll(&readiness, 1, 100) > 0 {
			mut byte := u8(0)
			if C.read(lease, &byte, 1) == 0 {
				C.kill(-guardian, C.SIGKILL)
				C._exit(0)
			}
		}
	}
}
