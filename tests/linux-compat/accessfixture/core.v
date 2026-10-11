// SPDX-License-Identifier: GPL-2.0-or-later
module accessfixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fchmod(i32, u32) i32
fn C.mkdir(&char, u32) i32
fn C.chmod(&char, u32) i32
fn C.chdir(&char) i32
fn C.unlink(&char) i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C.setreuid(u32, u32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C._exit(i32)
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn access(fd i32, path &char, mode i32, flags i32, error_code i32) bool {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		result := C.syscall(isize(C.SYS_faccessat2), isize(fd), path, isize(mode), isize(flags))
		valid := if error_code == 0 { result == 0 } else { result == -1 && *errno_ptr == error_code }
		if !valid { C.printf(c'LINUX ACCESS FAIL: fd=%d mode=%d flags=%x result=%ld errno=%d expected=%d\n', fd, mode, flags, result, *errno_ptr, error_code) }
		return valid
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		fd := C.open(c'/tmp/linux-access', C.O_CREAT | C.O_RDWR, u32(0o600))
		if fd < 0 { C.puts(c'LINUX ACCESS FAIL: create'); return 1 }
		if !access(fd, c'', C.F_OK, C.AT_EMPTY_PATH, 0)
			|| !access(fd, c'', C.X_OK, C.AT_EMPTY_PATH, C.EACCES)
			|| !access(fd, c'', C.R_OK, C.AT_EMPTY_PATH, 0)
			|| !access(fd, c'', 8, C.AT_EMPTY_PATH, C.EINVAL)
			|| !access(fd, c'', 0, 0, C.ENOENT)
			|| !access(-1, c'', 0, C.AT_EMPTY_PATH, C.EBADF)
			|| !access(fd, &char(1), 0, C.AT_EMPTY_PATH, C.EFAULT) { return 1 }
		pathfd := C.open(c'/tmp/linux-access', C.O_PATH)
		if pathfd < 0 || C.unlink(c'/tmp/linux-access') != 0
			|| !access(pathfd, c'', C.X_OK, C.AT_EMPTY_PATH, C.EACCES)
			|| C.fchmod(fd, u32(0o700)) != 0
			|| !access(pathfd, c'', C.X_OK, C.AT_EMPTY_PATH, 0) { return 1 }
		C.close(pathfd)
		C.close(fd)
		mut pipes := [2]i32{}
		if C.pipe(&pipes[0]) != 0 || !access(pipes[0], c'', C.R_OK, C.AT_EMPTY_PATH, 0) { return 1 }
		C.close(pipes[0]); C.close(pipes[1])
		// A root-owned directory is searchable by euid 0 but not real uid 1000.
		if C.mkdir(c'/tmp/linux-access-dir', u32(0o700)) != 0 || C.chdir(c'/tmp/linux-access-dir') != 0 { return 1 }
		child := C.fork()
		if child == 0 {
			ok := C.setreuid(u32(1000), u32(0)) == 0
				&& access(C.AT_FDCWD, c'', C.X_OK, C.AT_EMPTY_PATH, C.EACCES)
				&& access(C.AT_FDCWD, c'', C.X_OK, C.AT_EMPTY_PATH | C.AT_EACCESS, 0)
				&& access(C.AT_FDCWD, c'.', C.X_OK, C.AT_EACCESS | C.AT_EMPTY_PATH, 0)
			C._exit(if ok { 0 } else { 1 })
		}
		mut status := i32(0)
		if child <= 0 || C.waitpid(child, &status, 0) != child || !C.WIFEXITED(status) || C.WEXITSTATUS(status) != 0 { return 1 }
		C.puts(c'LINUX ACCESS: PASS'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
