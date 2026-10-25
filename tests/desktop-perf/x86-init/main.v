// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <sys/mount.h>
#include <unistd.h>

fn C.mount(&char, &char, &char, usize, voidptr) i32
fn C.execv(&char, &&char) i32

fn main() {
	os.mkdir_all('/root') or { panic(err) }
	if unsafe { C.mount(c'/dev/sd0', c'/root', c'ext2', 0, nil) } != 0 {
		println('PERF-ERROR x86 ext2 /root mount failed')
		exit(1)
	}
	println('PERF-X86 root=/dev/sd0 filesystem=ext2 resolution=2048x1536')
	mut args := [c'/bin/sh', c'/opt/vinix-perf/perf-init.sh', unsafe { nil }]
	unsafe { C.execv(c'/bin/sh', args.data) }
	println('PERF-ERROR x86 perf-init exec failed')
	exit(1)
}
