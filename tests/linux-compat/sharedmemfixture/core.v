// SPDX-License-Identifier: GPL-2.0-or-later
module sharedmemfixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_uid u32 st_gid u32 st_mode u32 st_nlink u64 }
fn C.syscall(isize, ...) isize
fn C.fstat(i32, &C.stat) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fchmod(i32, u32) i32
fn C.ftruncate(i32, isize) i32
fn C.umask(u32) u32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.snprintf(&char, usize, &char, ...) i32
fn C.unlink(&char) i32
fn C.fork() i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C._exit(i32)
fn C.__errno_location() &i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn ordinary_user() bool {
	unsafe {
		errno_ptr := C.__errno_location()
		if C.setgid(2000) != 0 || C.setuid(1000) != 0 { return false }
		C.umask(0o077)
		fd := i32(C.syscall(isize(C.SYS_memfd_create), c'compat-shared', isize(3)))
		mut info := C.stat{}
		if fd < 0 || C.fstat(fd, &info) != 0 || info.st_uid != 1000 || info.st_gid != 2000
			|| info.st_mode & 0o777 != 0o777 || info.st_nlink != 0 {
			C.printf(c'LINUX SHAREDMEM FAIL: memfd fd=%d uid=%u gid=%u mode=%o links=%lu\n',
				fd, info.st_uid, info.st_gid, info.st_mode, u64(info.st_nlink))
			return false
		}
		mut path := [128]char{}
		if C.snprintf(&path[0], sizeof(path), c'/proc/self/fd/%d', fd) <= 0 { return false }
		if C.fchmod(fd, 0o600) != 0 || C.ftruncate(fd, 4096) != 0 || C.write(fd, c'42', 2) != 2 { return false }
		readonly := C.open(&path[0], C.O_RDONLY | C.O_CLOEXEC)
		mut bytes := [2]u8{}
		if readonly < 0 || C.read(readonly, &bytes[0], 2) != 2 || bytes[0] != `4` || bytes[1] != `2` {
			C.printf(c'LINUX SHAREDMEM FAIL: creator readonly reopen errno=%d\n', *C.__errno_location())
			return false
		}
		C.close(readonly)
		if C.fchmod(fd, 0o400) != 0 { return false }
		*errno_ptr = 0
		if C.open(&path[0], C.O_WRONLY) != -1 || *C.__errno_location() != C.EACCES { return false }
		C.close(fd)
		shm := C.open(c'/dev/shm', C.O_PATH | C.O_DIRECTORY)
		if shm < 0 || C.fstat(shm, &info) != 0 || info.st_mode & 0o7777 != 0o1777 {
			C.printf(c'LINUX SHAREDMEM FAIL: shm directory mode=%o\n', info.st_mode)
			return false
		}
		C.close(shm)
		shared := C.open(c'/dev/shm/linux-shared-user', C.O_CREAT | C.O_EXCL | C.O_RDWR, u32(0o600))
		if shared < 0 || C.write(shared, c'42', 2) != 2 || C.fstat(shared, &info) != 0
			|| info.st_uid != 1000 || info.st_gid != 2000 { return false }
		C.close(shared)
		if C.unlink(c'/dev/shm/linux-shared-user') != 0 { return false }
		*errno_ptr = 0
		if C.unlink(c'/dev/shm/linux-shared-root') != -1 || *C.__errno_location() != C.EPERM {
			C.puts(c'LINUX SHAREDMEM FAIL: sticky directory allowed foreign removal')
			return false
		}
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		root_file := C.open(c'/dev/shm/linux-shared-root', C.O_CREAT | C.O_EXCL | C.O_RDWR, u32(0o600))
		if root_file < 0 { return 1 }
		C.close(root_file)
		child := C.fork()
		if child == 0 { C._exit(if ordinary_user() { 0 } else { 1 }) }
		mut status := i32(0)
		if child < 0 || C.waitpid(child, &status, 0) != child || !C.WIFEXITED(status) || C.WEXITSTATUS(status) != 0 { return 1 }
		if C.unlink(c'/dev/shm/linux-shared-root') != 0 { return 1 }
		C.puts(c'LINUX SHAREDMEM: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
