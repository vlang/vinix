// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic init: preserve the release init and capture its console output.
@[translated]
module sessionprobe

#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>

fn C.open(&char, int, ...) int
fn C.dup2(int, int) int
fn C.close(int) int
fn C.fork() int
fn C.execv(&char, &&char) int
fn C._exit(int)

@[export: 'main']
pub fn main() int {
	serial := C.open(c'/dev/com1', 1)
	if serial >= 0 {
		C.dup2(serial, 1)
		C.dup2(serial, 2)
		if serial > 2 { C.close(serial) }
	}
	if C.fork() == 0 {
		channel := C.open(c'/dev/com2', 2)
		if channel < 0 { C._exit(1) }
		for fd in 0 .. 3 { C.dup2(channel, fd) }
		if channel > 2 { C.close(channel) }
		args := [c'/bin/sh', c'-i', unsafe { nil }]!
		C.execv(args[0], unsafe { &&char(&args[0]) })
		C._exit(127)
	}
	args := [c'/sbin/init-original', unsafe { nil }]!
	C.execv(args[0], unsafe { &&char(&args[0]) })
	return 127
}
