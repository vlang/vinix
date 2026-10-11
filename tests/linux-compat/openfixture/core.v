// SPDX-License-Identifier: GPL-2.0-or-later
module openfixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

struct How { mut: flags u64 mode u64 resolve u64 extra u64 }
struct C.stat { st_mode u32 }
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.close(i32) i32
fn C.open(&char, i32, ...) i32
fn C.mkdir(&char, u32) i32
fn C.symlink(&char, &char) i32
fn C.fstat(i32, &C.stat) i32
fn C.read(i32, voidptr, usize) isize
fn C.pipe(&i32) i32
fn C.getpid() i32
fn C.access(&char, i32) i32
fn C.snprintf(&char, usize, &char, ...) i32
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

fn link_descriptor(path &char, via_openat2 bool, resolve u64) bool {
	unsafe {
		how := How{flags: u64(C.O_PATH | C.O_NOFOLLOW), resolve: resolve}
		fd := if via_openat2 {
			i32(C.syscall(isize(C.SYS_openat2), isize(C.AT_FDCWD), path, &how, isize(24)))
		} else { C.open(path, C.O_PATH | C.O_NOFOLLOW) }
		if fd < 0 { C.puts(c'LINUX OPEN FAIL: link descriptor'); return false }
		mut info := C.stat{}
		mut byte := u8(0)
		ok := C.fstat(fd, &info) == 0 && info.st_mode & u32(C.S_IFMT) == u32(C.S_IFLNK)
			&& C.read(fd, &byte, 1) == -1 && *C.__errno_location() == C.EBADF
		C.close(fd)
		if !ok { C.puts(c'LINUX OPEN FAIL: link inode or descriptor access') }
		return ok
	}
}

fn link_constraints(pipe_fd i32) bool {
	unsafe {
		mut how := How{resolve: 2}
		if !open_result(c'/tmp/linux-open-dir/link/linux-open-target', &how, 24, 0)
			|| !open_result(c'/proc/self/status', &how, 24, 0) { return false }
		for constraint in [u64(2), 4, 6]! {
			how = How{resolve: constraint}
			if !open_result(c'/tmp/linux-open-target', &how, 24, 0)
				|| !open_result(c'/proc/self/exe', &how, 24, C.ELOOP)
				|| !open_result(c'/proc/self/cwd/linux-open-target', &how, 24, C.ELOOP)
				|| !open_result(c'/proc/self/ns/mnt', &how, 24, C.ELOOP) { return false }
			mut magic_path := [64]u8{}
			C.snprintf(&char(&magic_path[0]), usize(magic_path.len), c'/proc/%d/exe', C.getpid())
			if !link_descriptor(&char(&magic_path[0]), true, constraint) { return false }
			C.snprintf(&char(&magic_path[0]), usize(magic_path.len), c'/proc/%d/fd/%d', C.getpid(), pipe_fd)
			if !open_result(&char(&magic_path[0]), &how, 24, C.ELOOP)
				|| !link_descriptor(&char(&magic_path[0]), true, constraint) { return false }
			if constraint & 4 != 0 {
				if !open_result(c'/tmp/linux-open-dir/link/linux-open-target', &how, 24, C.ELOOP)
					|| !open_result(c'/tmp/linux-open-dangling', &how, 24, C.ELOOP)
					|| !link_descriptor(c'/tmp/linux-open-dangling', true, constraint) { return false }
			}
		}
		if C.symlink(c'/proc/self/exe', c'/tmp/linux-open-magic') != 0 { return false }
		how = How{resolve: 2}
		if !open_result(c'/tmp/linux-open-magic', &how, 24, C.ELOOP) { return false }
		how = How{flags: u64(C.O_CREAT | C.O_RDWR), mode: 0o600, resolve: 4}
		if !open_result(c'/tmp/linux-open-dir/new', &how, 24, 0)
			|| !open_result(c'/tmp/linux-open-dir/link/linux-open-escape', &how, 24, C.ELOOP)
			|| C.access(c'/tmp/linux-open-escape', C.F_OK) != -1
			|| *C.__errno_location() != C.ENOENT { return false }
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		fd := C.open(c'/tmp/linux-open-target', C.O_CREAT | C.O_RDWR, u32(0o600))
		if fd < 0 { C.puts(c'LINUX OPEN FAIL: create'); return 1 }
		C.close(fd)
		if C.mkdir(c'/tmp/linux-open-dir', u32(0o700)) != 0
			|| C.symlink(c'/tmp', c'/tmp/linux-open-dir/link') != 0
			|| C.symlink(c'/tmp/linux-open-missing', c'/tmp/linux-open-dangling') != 0 { return 1 }
		for via_openat2 in [false, true]! {
			if !link_descriptor(c'/tmp/linux-open-dir/link', via_openat2, 0)
				|| !link_descriptor(c'/tmp/linux-open-dangling', via_openat2, 0)
				|| !link_descriptor(c'/proc/self/exe', via_openat2, 0) { return 1 }
		}
		mut pipes := [2]i32{}
		if C.pipe(&pipes[0]) != 0 { return 1 }
		mut pipe_path := [64]u8{}
		C.snprintf(&char(&pipe_path[0]), usize(pipe_path.len), c'/proc/self/fd/%d', pipes[0])
		if !link_descriptor(&char(&pipe_path[0]), false, 0)
			|| !link_descriptor(&char(&pipe_path[0]), true, 0)
			|| !link_constraints(pipes[0]) { return 1 }
		C.close(pipes[0]); C.close(pipes[1])
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
		for constraint in [u64(1), 8, 16, 32, 5, 10, 20, 38]! {
			how.resolve = constraint
			if !open_result(c'/tmp/linux-open-dir/link/linux-open-target', &how, 24, C.EOPNOTSUPP) { return 1 }
		}
		C.puts(c'LINUX OPEN: PASS'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
