// SPDX-License-Identifier: GPL-2.0-or-later
// Independent pathname logging and failed child-status copy oracle.
@[has_globals]
module guestfixture

#include <diagnostics-native-abi.h>

struct C.stat {
	st_mode u32
}
@[typedef]
struct C.FILE {}
@[c_extern]
__global C.stdout &C.FILE
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.unlinkat(i32, &char, i32) i32
fn C.mkdirat(i32, &char, u32) i32
fn C.readlinkat(i32, &char, &char, usize) isize
fn C.openat(i32, &char, i32, ...) i32
fn C.syscall(isize, ...) isize
fn C.fstatat(i32, &char, &C.stat, i32) i32
fn C.linkat(i32, &char, i32, &char, i32) i32
fn C.chdir(&char) i32
fn C.stat(&char, &C.stat) i32
fn C.S_ISDIR(u32) bool
fn C.getcwd(&char, usize) &char
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.puts(&char) i32
fn C.fflush(&C.FILE) i32
fn C.pause() i32

fn clear_errno() {
	unsafe {
		location := C.__errno_location()
		*location = 0
	}
}

fn check(ok bool, line i32) bool {
	if !ok {
		unsafe { C.printf(c'SYSCALL DIAGNOSTICS FAIL: line=%d errno=%d\n', line, *C.__errno_location()) }
	}
	return ok
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		bad := &char(usize(1))
		mut buffer := [4096]char{}
		mut st := C.stat{}
		mut statx_buffer := [32]u64{}
		clear_errno()
		if !check(C.unlinkat(C.AT_FDCWD, bad, 0) == -1 && *C.__errno_location() == C.EFAULT, 22) { return 1 }
		clear_errno()
		if !check(C.mkdirat(C.AT_FDCWD, bad, 0o700) == -1 && *C.__errno_location() == C.EFAULT, 23) { return 1 }
		clear_errno()
		if !check(C.readlinkat(C.AT_FDCWD, bad, &buffer[0], sizeof(buffer)) == -1 && *C.__errno_location() == C.EFAULT, 24) { return 1 }
		clear_errno()
		if !check(C.openat(C.AT_FDCWD, bad, C.O_RDONLY) == -1 && *C.__errno_location() == C.EFAULT, 25) { return 1 }
		clear_errno()
		if !check(C.syscall(C.SYS_faccessat, i32(C.AT_FDCWD), bad, i32(C.F_OK)) == -1 && *C.__errno_location() == C.EFAULT, 26) { return 1 }
		clear_errno()
		if !check(C.fstatat(C.AT_FDCWD, bad, &st, 0) == -1 && *C.__errno_location() == C.EFAULT, 27) { return 1 }
		clear_errno()
		if !check(C.linkat(C.AT_FDCWD, bad, C.AT_FDCWD, c'/tmp/no-link', 0) == -1 && *C.__errno_location() == C.EFAULT, 28) { return 1 }
		clear_errno()
		if !check(C.linkat(C.AT_FDCWD, c'/dev/null', C.AT_FDCWD, bad, 0) == -1 && *C.__errno_location() == C.EFAULT, 29) { return 1 }
		clear_errno()
		if !check(C.chdir(bad) == -1 && *C.__errno_location() == C.EFAULT, 30) { return 1 }
		if !check(C.stat(c'/', &st) == 0 && C.S_ISDIR(st.st_mode), 31) { return 1 }
		if !check(C.syscall(C.SYS_statx, i32(C.AT_FDCWD), c'/', i32(0), i32(0x7ff), &statx_buffer[0]) == 0, 32) { return 1 }
		if !check(C.getcwd(&buffer[0], sizeof(buffer)) != nil, 33) { return 1 }
		child := C.fork()
		if !check(child >= 0, 37) { return 1 }
		if child == 0 { C._exit(37) }
		clear_errno()
		if !check(C.syscall(C.SYS_wait4, child, voidptr(usize(1)), i32(0), voidptr(nil)) == -1 && *C.__errno_location() == C.EFAULT, 39) { return 1 }
		mut status := i32(0)
		if !check(C.waitpid(child, &status, 0) == child, 41) { return 1 }
		if !check(C.WIFEXITED(status) && C.WEXITSTATUS(status) == 37, 42) { return 1 }
		C.puts(c'SYSCALL DIAGNOSTICS PASS')
		C.fflush(C.stdout)
		for { C.pause() }
	}
	return 0
}
