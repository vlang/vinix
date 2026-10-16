// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os

#include <signal.h>
#include <sys/file.h>
#include <unistd.h>
fn C.raise(int) int
fn C.flock(int, int) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize

struct Observation { arguments []string directory string environment string uid int gid int }

fn check() !int {
	if os.args.len < 2 { return error('child mode required') }
	if os.args[1] == 'exit' { return os.args[2].int() }
	if os.args[1] == 'signal' { C.raise(C.SIGTERM); return 99 }
	if os.args[1] == 'observe' {
		text := json2.encode(Observation{ arguments: os.args[3..], directory: os.getwd(),
			environment: os.getenv('VINIX_LAUNCH_PROCESS_LITERAL'), uid: os.geteuid(), gid: os.getegid() })
		os.write_file(os.args[2], text)!
		return 37
	}
	if os.args[1] == 'streams' {
		mut value := [1]u8{}
		if C.read(0, unsafe { &value[0] }, 1) != 1 || value[0] != `x` { return 90 }
		if C.write(1, c'out', 3) != 3 || C.write(2, c'err', 3) != 3 { return 91 }
		return 23
	}
	if os.args[1] == 'closed-streams' {
		for fd in 0 .. 3 { if C.fcntl(fd, C.F_GETFD) >= 0 { return 92 } }
		return 24
	}
	if os.args[1] == 'lease' {
		// Check before opening anything that could reuse the parent's descriptor.
		if C.fcntl(os.args[3].int(), C.F_GETFD) >= 0 { return 95 }
		fd := C.open(os.args[2].str, C.O_RDONLY | C.O_CLOEXEC)
		if fd < 0 || C.flock(fd, C.LOCK_EX | C.LOCK_NB) == 0 { return 93 }
		C.close(fd); return 25
	}
	return error('unknown child mode')
}
fn main() { code := check() or { eprintln(err); exit(98) }; exit(code) }
