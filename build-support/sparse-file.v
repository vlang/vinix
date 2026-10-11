// SPDX-License-Identifier: GPL-2.0-or-later
// Create a new sparse filesystem input without overwriting an existing path.
import os
import strconv

#include <fcntl.h>

struct InputError {
	message string
}

fn (e InputError) msg() string { return e.message }

fn (e InputError) code() int { return 2 }

fn checked() ! {
	if os.args.len == 2 && os.args[1] in ['-h', '--help'] {
		println('Usage: sparse-file NEW-FILE BYTES')
		return
	}
	if os.args.len != 3 { return InputError{'Usage: sparse-file NEW-FILE BYTES'} }
	size := strconv.parse_uint(os.args[2], 10, 64) or { return InputError{'Invalid byte count'} }
	if size > 0x7fffffffffffffff { return InputError{'Byte count exceeds signed file offsets'} }
	fd := unsafe { C.open(os.args[1].str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o666) }
	if fd < 0 { return os.error_posix() }
	defer { C.close(fd) }
	if C.ftruncate(fd, size) != 0 {
		failure := os.error_posix()
		os.rm(os.args[1]) or {}
		return failure
	}
}

fn main() {
	checked() or {
		eprintln(err.msg())
		exit(if err is InputError { 2 } else { 1 })
	}
}
