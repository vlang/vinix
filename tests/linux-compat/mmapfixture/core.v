// SPDX-License-Identifier: GPL-2.0-or-later
module mmapfixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

fn C.syscall(isize, ...) isize
fn C.sysconf(i32) isize
fn C.__errno_location() &i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.munmap(voidptr, usize) i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

@[export: 'main']
pub fn run() i32 {
	unsafe {
		page := C.sysconf(C._SC_PAGESIZE)
		if page < 4096 { return 1 }
		for descriptor in [i64(-1), 123456, 0, 0xffffffff, 0x123400000001]! {
			address := C.syscall(isize(C.SYS_mmap), isize(0), page,
				isize(C.PROT_READ | C.PROT_WRITE), isize(C.MAP_PRIVATE | C.MAP_ANONYMOUS),
				isize(descriptor), isize(0))
			if address == -1 {
				C.printf(c'LINUX MMAP FAIL: anonymous fd=%ld errno=%d\n', isize(descriptor), *C.__errno_location())
				return 1
			}
			mut memory := &u8(voidptr(address))
			memory[0] = 42
			memory[page - 1] = 19
			if memory[0] != 42 || memory[page - 1] != 19
				|| C.munmap(voidptr(address), usize(page)) != 0 { return 1 }
		}
		file := C.open(c'/tmp/linux-mmap-file', C.O_CREAT | C.O_EXCL | C.O_RDWR, u32(0o600))
		if file < 0 || C.write(file, c'data', 4) != 4 { return 1 }
		// Only the low C-int descriptor belongs to the ABI argument.
		wide_descriptor := i64(file) | (i64(0x1234) << 32)
		address := C.syscall(isize(C.SYS_mmap), isize(0), page, isize(C.PROT_READ),
			isize(C.MAP_PRIVATE), isize(wide_descriptor), isize(0))
		if address == -1 || (&u8(voidptr(address)))[0] != `d`
			|| (&u8(voidptr(address)))[3] != `a` { C.puts(c'LINUX MMAP FAIL: file descriptor width'); return 1 }
		if C.munmap(voidptr(address), usize(page)) != 0 { return 1 }
		C.close(file)
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		if C.syscall(isize(C.SYS_mmap), isize(0), page, isize(C.PROT_READ),
			isize(C.MAP_PRIVATE), isize(0xffffffff), isize(0)) != -1
			|| *C.__errno_location() != C.EBADF { return 1 }
		C.puts(c'LINUX MMAP: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
