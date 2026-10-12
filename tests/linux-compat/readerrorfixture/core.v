// SPDX-License-Identifier: GPL-2.0-or-later
module readerrorfixture

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.lseek(i32, i64, i32) i64
fn C.mkdir(&char, u32) i32
fn C.chmod(&char, u32) i32
fn C.unlink(&char) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) isize
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn read_check(fd i32, buffer voidptr, count usize, wanted isize, error_code i32) bool {
	unsafe {
		e := C.__errno_location(); *e = 0
		actual := C.syscall(isize(C.SYS_read), isize(fd), buffer, count)
		code := *e
		if actual != wanted || code != error_code {
			C.printf(c'LINUX READERROR DETAIL: fd=%d count=%lu actual=%ld/%d expected=%ld/%d\n', fd, count, actual, code, wanted, error_code)
			C.fflush(nil); return false
		}
		return true
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		page := usize(C.sysconf(C._SC_PAGESIZE))
		protected := C.mmap(nil, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(protected) == u64(-1) { return false }
		defer { C.munmap(protected, page) }
		mut data := [4096]u8{}
		mut checks := i32(0)
		for path in [&char(c'/'), &char(c'/tmp'), &char(c'/tmp/linux-readerror'), &char(c'/proc'), &char(c'/sys')]! {
			fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY)
			if fd < 0 { return false }
			for count in [usize(0), 1, 4096]! {
				for buffer in [voidptr(&data[0]), voidptr(1), protected]! {
					if !read_check(fd, buffer, count, -1, C.EISDIR) { C.close(fd); return false }
					checks++
				}
			}
			if !read_check(fd, nil, 0, -1, C.EISDIR)
				|| !read_check(fd, voidptr(u64(0xffff000000000000)), 1, -1, C.EFAULT)
				|| C.lseek(fd, 0, C.SEEK_CUR) != 0 || C.close(fd) != 0 { return false }
			checks += 2
		}
		for count in [usize(0), 1]! {
			if !read_check(-1, protected, count, -1, C.EBADF) { return false }; checks++
		}
		fd := C.open(c'/tmp/linux-readerror/file', C.O_CREAT | C.O_RDWR | C.O_TRUNC, u32(0o666))
		if fd < 0 { return false }
		defer { C.close(fd) }
		data[0] = 0x5a
		if C.write(fd, &data[0], 1) != 1 || C.lseek(fd, 0, C.SEEK_SET) != 0 { return false }
		for buffer in [voidptr(nil), voidptr(1), protected]! {
			if !read_check(fd, buffer, 0, 0, 0) || C.lseek(fd, 0, C.SEEK_CUR) != 0 { return false }; checks++
		}
		data[0] = 0
		if !read_check(fd, &data[0], 1, 1, 0) || data[0] != 0x5a || !read_check(fd, &data[0], 1, 0, 0) { return false }; checks += 2
		writer := C.open(c'/tmp/linux-readerror/file', C.O_WRONLY)
		if writer < 0 || !read_check(writer, nil, 0, -1, C.EBADF)
			|| !read_check(writer, protected, 1, -1, C.EBADF) || C.close(writer) != 0 { return false }; checks += 2
		C.printf(c'LINUX READERROR CASE: ordinary=%d checks=%d PASS\n', i32(ordinary), checks)
		C.fflush(nil)
		return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.mkdir(c'/tmp/linux-readerror', u32(0o777)) != 0 || C.chmod(c'/tmp/linux-readerror', u32(0o777)) != 0 { return 1 }
		// Separate names keep the ordinary-user file writable despite root's umask.
		if !qualify(false) || C.unlink(c'/tmp/linux-readerror/file') != 0 || !qualify(true) {
			C.puts(c'LINUX READERROR FAIL: directory byte reads or retained descriptor/file semantics')
			C.fflush(nil); return 1
		}
		C.puts(c'LINUX READERROR PASS: root/UID1000 directory EISDIR before copying at zero/one/4096 bytes; bad ranges and descriptors preserve EFAULT/EBADF; regular zero/data/EOF reads preserve offsets')
		C.puts(c'LINUX READERROR: PASS'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
