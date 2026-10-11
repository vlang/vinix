// SPDX-License-Identifier: GPL-2.0-or-later
module openfixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

struct How { mut: flags u64 mode u64 resolve u64 extra u64 }
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.close(i32) i32
fn C.open(&char, i32, ...) i32
fn C.mkdir(&char, u32) i32
fn C.symlink(&char, &char) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn open_result(path &char, how voidptr, size usize, expected i32) bool {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		result := C.syscall(isize(C.SYS_openat2), isize(C.AT_FDCWD), path, how, isize(size))
		valid := if expected == 0 { result >= 0 } else { result == -1 && *errno_ptr == expected }
		if result >= 0 { C.close(i32(result)) }
		if !valid { C.printf(c'LINUX OPEN FAIL: result=%ld errno=%d expected=%d\n', result, *errno_ptr, expected) }
		return valid
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		fd := C.open(c'/tmp/linux-open-target', C.O_CREAT | C.O_RDWR, u32(0o600))
		if fd < 0 { C.puts(c'LINUX OPEN FAIL: create'); return 1 }
		C.close(fd)
		if C.mkdir(c'/tmp/linux-open-dir', u32(0o700)) != 0
			|| C.symlink(c'/tmp', c'/tmp/linux-open-dir/link') != 0 { return 1 }
		mut how := How{}
		if !open_result(c'/tmp/linux-open-target', &how, 24, 0)
			|| !open_result(c'/tmp/linux-open-target', &how, sizeof(how), 0)
			|| !open_result(c'/tmp/linux-open-target', &how, 8, C.EINVAL)
			|| !open_result(c'/tmp/linux-open-target', voidptr(1), 24, C.EFAULT) { return 1 }
		how.extra = 1
		if !open_result(c'/tmp/linux-open-target', &how, sizeof(how), C.E2BIG) { return 1 }
		how.extra = 0; how.flags = u64(1) << 63
		if !open_result(c'/tmp/linux-open-target', &how, 24, C.EINVAL) { return 1 }
		how.flags = 0; how.mode = 0o600
		if !open_result(c'/tmp/linux-open-target', &how, 24, C.EINVAL) { return 1 }
		how.mode = 0; how.flags = u64(C.O_PATH)
		if !open_result(c'/tmp/linux-open-target', &how, 24, 0) { return 1 }
		how.flags = 0; how.resolve = 0x40
		if !open_result(c'/tmp/linux-open-target', &how, 24, C.EINVAL) { return 1 }
		how.resolve = 0x18
		if !open_result(c'/tmp/linux-open-target', &how, 24, C.EINVAL) { return 1 }
		for constraint in [u64(1), 2, 4, 8, 16, 32]! {
			how.resolve = constraint
			if !open_result(c'/tmp/linux-open-dir/link/linux-open-target', &how, 24, C.EOPNOTSUPP) { return 1 }
		}
		C.puts(c'LINUX OPEN: PASS'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
