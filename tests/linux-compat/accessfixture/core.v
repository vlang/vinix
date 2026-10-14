// SPDX-License-Identifier: GPL-2.0-or-later
module accessfixture

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <alloca.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.__errno_location() &i32
struct C.stat { st_uid u32 st_gid u32 st_mode u32 }
fn C.alloca(usize) voidptr
fn C.fstat(i32, &C.stat) i32
fn C.dup(i32) i32
fn C.fcntl(i32, i32, ...) i32
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
fn C.setregid(u32, u32) i32
fn C.setgroups(usize, voidptr) i32
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

// Exercise pipe inode ownership with equal IDs and a privileged effective ID.
// Only ordinary low-word arguments are used, independently of the ABI probe.
fn pipe_owner(ordinary bool) bool {
	unsafe {
		child := C.fork(); if child < 0 { return false }
		if child == 0 {
			owner := if ordinary { u32(1000) } else { u32(0) }
			if C.setgroups(0, nil) != 0 || C.setregid(1000, owner) != 0 || C.setreuid(1000, owner) != 0 { C._exit(1) }
			mut ends := [2]i32{}; if C.pipe(&ends[0]) != 0 { C._exit(1) }
			mut fds := [6]i32{}; data := &C.stat(C.alloca(usize(sizeof(C.stat)))); mut good := true
			for end in 0 .. 2 { index := end * 3; fds[index] = ends[end]; fds[index + 1] = C.dup(ends[end]); fds[index + 2] = C.fcntl(ends[end], C.F_DUPFD_CLOEXEC, 40) }
			for fd in fds {
				if fd < 0 || C.fstat(fd, data) != 0 || data.st_uid != owner || data.st_gid != owner || data.st_mode & u32(C.S_IFMT | 0o777) != u32(C.S_IFIFO | 0o600) { good = false }
				for mode in [i32(C.R_OK), C.W_OK, C.R_OK | C.W_OK]! {
					if !access(fd, c'', mode, C.AT_EMPTY_PATH, if ordinary { 0 } else { C.EACCES }) || !access(fd, c'', mode, C.AT_EMPTY_PATH | C.AT_EACCESS, 0) { good = false }
				}
			}
			for fd in fds { if fd >= 0 && C.close(fd) != 0 { good = false } }
			C.fflush(nil); C._exit(if good { 0 } else { 1 })
		}
		mut status := i32(-1); return C.waitpid(child, &status, 0) == child && status == 0
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
		if !pipe_owner(true) || !pipe_owner(false) { C.puts(c'LINUX ACCESS FAIL: pipe inode ownership'); return 1 }
		C.puts(c'LINUX ACCESS PASS: pipe inode ownership and real/effective permissions')
		C.puts(c'LINUX ACCESS: PASS'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
