// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <sys/mount.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

fn C.mount(&char, &char, &char, usize, voidptr) i32
fn C.execv(&char, &&char) i32
fn C.open(&char, int, ...voidptr) int
fn C.dup2(int, int) int
fn C.close(int) int

fn main() {
	// x86 /dev/console is the framebuffer; the supervisor listens on COM1.
	fd := unsafe { C.open(c'/dev/com1', C.O_WRONLY) }
	if fd < 0 { exit(1) }
	if C.dup2(fd, 1) < 0 || C.dup2(fd, 2) < 0 { exit(1) }
	if fd > 2 { C.close(fd) }
	os.mkdir_all('/root') or { panic(err) }
	if unsafe { C.mount(c'/dev/sd0', c'/root', c'ext2', 0, nil) } != 0 {
		mount_errno := i32(C.errno)
		device_present := os.exists('/dev/sd0')
		println('PERF-ERROR x86 ext2 /root mount failed errno=${mount_errno} device_present=${device_present}')
		exit(1)
	}
	println('PERF-X86 root=/dev/sd0 filesystem=ext2 resolution=2048x1536')
	mut args := [c'/bin/sh', c'/opt/vinix-perf/perf-init.sh', unsafe { nil }]
	unsafe { C.execv(c'/bin/sh', args.data) }
	println('PERF-ERROR x86 perf-init exec failed')
	exit(1)
}
