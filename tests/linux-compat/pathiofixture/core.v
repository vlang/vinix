// SPDX-License-Identifier: GPL-2.0-or-later
module pathiofixture

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_mode u32 }
struct IOVec { base u64 len u64 }
struct Object { path &char kind u32 }
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.fstat(i32, &C.stat) i32
fn C.fcntl(i32, i32, ...) i32
fn C.lseek(i32, i64, i32) i64
fn C.write(i32, voidptr, usize) isize
fn C.mkdir(&char, u32) i32
fn C.chmod(&char, u32) i32
fn C.mkfifo(&char, u32) i32
fn C.symlink(&char, &char) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) isize
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn refuse(fd i32, number isize, buffer voidptr, count usize) bool {
	unsafe {
		e := C.__errno_location(); *e = 0
		actual := C.syscall(number, isize(fd), buffer, count, isize(0))
		code := *e
		if actual != -1 || code != C.EBADF {
			C.printf(c'LINUX PATHIO DETAIL: fd=%d nr=%ld count=%lu actual=%ld/%d expected=-1/9\n', fd, number, count, actual, code)
			C.fflush(nil); return false
		}
		return true
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary {
			if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { return false }
			e := C.__errno_location(); *e = 0
			denied := C.open(c'/tmp/linux-pathio/secret', C.O_RDONLY)
			if denied != -1 || *e != C.EACCES { if denied >= 0 { C.close(denied) }; return false }
		}
		page := usize(C.sysconf(C._SC_PAGESIZE))
		protected := C.mmap(nil, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(protected) == u64(-1) { return false }
		defer { C.munmap(protected, page) }
		mut byte := u8(0)
		mut checks := i32(0)
		objects := [Object{&char(c'/tmp/linux-pathio/secret'), u32(C.S_IFREG)},
			Object{&char(c'/tmp/linux-pathio'), u32(C.S_IFDIR)},
			Object{&char(c'/tmp/linux-pathio/fifo'), u32(C.S_IFIFO)},
			Object{&char(c'/tmp/linux-pathio/link'), u32(C.S_IFLNK)}]!
		for object in objects {
			fd := C.open(object.path, C.O_PATH | C.O_NOFOLLOW)
			if fd < 0 { return false }
			copy := C.dup(fd)
			if copy < 0 { C.close(fd); return false }
			for handle in [fd, copy]! {
				mut metadata := C.stat{}
				if C.fstat(handle, &metadata) != 0 || metadata.st_mode & u32(C.S_IFMT) != object.kind
					|| C.fcntl(handle, C.F_GETFL) & C.O_PATH == 0 { return false }; checks += 2
				for number in [isize(C.SYS_read), isize(C.SYS_pread64)]! {
					for buffer in [voidptr(&byte), voidptr(1), protected]! {
						for count in [usize(1), 0]! {
							if !refuse(handle, number, buffer, count) { return false }; checks++
						}
					}
				}
				if !refuse(handle, isize(C.SYS_read), nil, 0) || !refuse(handle, isize(C.SYS_pread64), nil, 0)
					|| !refuse(handle, isize(C.SYS_write), &byte, 0) || !refuse(handle, isize(C.SYS_pwrite64), &byte, 0) { return false }; checks += 4
				for buffer in [voidptr(&byte), voidptr(1), protected]! {
					iov := IOVec{base: u64(buffer), len: 1}
					if !refuse(handle, isize(C.SYS_readv), &iov, 1) { return false }; checks++
				}
				for number in [isize(C.SYS_readv), isize(C.SYS_writev)]! {
					empty := IOVec{base: u64(protected)}
					if !refuse(handle, number, nil, 0) || !refuse(handle, number, &empty, 1)
						|| !refuse(handle, number, voidptr(1), 1) { return false }; checks += 3
				}
				if C.fstat(handle, &metadata) != 0 || metadata.st_mode & u32(C.S_IFMT) != object.kind { return false }; checks++
			}
			if C.close(fd) != 0 || C.close(copy) != 0 { return false }
		}
		for number in [isize(C.SYS_readv), isize(C.SYS_writev)]! {
			if !refuse(-1, number, nil, 0) || !refuse(-1, number, voidptr(1), 1) { return false }; checks += 2
		}
		fd := C.open(c'/tmp/linux-pathio/ordinary', C.O_RDWR)
		if fd < 0 { return false }
		mut data := [u8(0x41), u8(0x42)]!
		mut vector := [IOVec{base: u64(&data[0]), len: 1}, IOVec{base: u64(&data[1]), len: 1}]!
		if C.syscall(isize(C.SYS_writev), isize(fd), &vector[0], isize(2)) != 2 || C.lseek(fd, 0, C.SEEK_SET) != 0 { return false }; checks++
		data[0] = 0; data[1] = 0
		if C.syscall(isize(C.SYS_readv), isize(fd), &vector[0], isize(2)) != 2 || data[0] != 0x41 || data[1] != 0x42 { return false }; checks++
		empty := IOVec{base: u64(protected)}
		for number in [isize(C.SYS_readv), isize(C.SYS_writev)]! {
			if C.syscall(number, isize(fd), &empty, isize(1)) != 0 || C.syscall(number, isize(fd), voidptr(nil), isize(0)) != 0 { return false }; checks += 2
		}
		if C.close(fd) != 0 { return false }
		for write in [false, true]! {
			mode := if write { C.O_WRONLY } else { C.O_RDONLY }
			number := if write { C.SYS_readv } else { C.SYS_writev }
			handle := C.open(c'/tmp/linux-pathio/ordinary', mode)
			if handle < 0 || !refuse(handle, isize(number), nil, 0)
				|| !refuse(handle, isize(number), &empty, 1) || !refuse(handle, isize(number), voidptr(1), 1)
				|| C.close(handle) != 0 { return false }; checks += 3
		}
		C.printf(c'LINUX PATHIO CASE: ordinary=%d checks=%d PASS\n', i32(ordinary), checks)
		C.fflush(nil); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.mkdir(c'/tmp/linux-pathio', u32(0o777)) != 0 || C.chmod(c'/tmp/linux-pathio', u32(0o777)) != 0 { return 1 }
		fd := C.open(c'/tmp/linux-pathio/secret', C.O_CREAT | C.O_WRONLY, u32(0o600))
		mut byte := u8(0x5a)
		if fd < 0 || C.write(fd, &byte, 1) != 1 || C.close(fd) != 0
			|| C.chmod(c'/tmp/linux-pathio/secret', u32(0o600)) != 0
			|| C.mkfifo(c'/tmp/linux-pathio/fifo', u32(0o600)) != 0
			|| C.symlink(c'/tmp/linux-pathio/secret', c'/tmp/linux-pathio/link') != 0 { return 1 }
		ordinary_file := C.open(c'/tmp/linux-pathio/ordinary', C.O_CREAT | C.O_RDWR, u32(0o666))
		if ordinary_file < 0 || C.close(ordinary_file) != 0 || C.chmod(c'/tmp/linux-pathio/ordinary', u32(0o666)) != 0 { return 1 }
		for ordinary in [true, false]! {
			C.fflush(nil)
			child := C.fork()
			if child < 0 { return 1 }
			if child == 0 { C._exit(if qualify(ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1)
			if C.waitpid(child, &outcome, 0) != child || outcome != 0 {
				C.printf(c'LINUX PATHIO DETAIL: ordinary=%d outcome=%d\n', i32(ordinary), outcome)
				C.puts(c'LINUX PATHIO FAIL: O_PATH byte I/O refusal or retained metadata/dup semantics')
				C.fflush(nil); return 1
			}
		}
		C.puts(c'LINUX PATHIO PASS: root/UID1000 scalar read/pread and empty/nonempty vectors refuse O_PATH files/directories/FIFOs/symlinks and duplicates; vector EBADF precedes copy errors; metadata and valid vectored I/O remain usable and root-owned private contents stay inaccessible')
		C.puts(c'LINUX PATHIO: PASS'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
