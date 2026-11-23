// SPDX-License-Identifier: GPL-2.0-or-later
module fadvisefixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/syscall.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.eventfd(u32, i32) i32
fn C.fflush(voidptr) i32
fn C.fcntl(i32, i32, ...) i32
fn C.lseek(i32, i64, i32) i64
fn C.makedev(u32, u32) u64
fn C.mkfifo(&char, u32) i32
fn C.mknod(&char, u32, u64) i32
fn C.open(&char, i32, ...) i32
fn C.pause() i32
fn C.pipe(&i32) i32
fn C.posix_fadvise(i32, i64, i64, i32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.read(i32, voidptr, u64) i64
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.strcmp(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.unlink(&char) i32
fn C.write(i32, voidptr, u64) i64

const max_offset = i64(0x7fffffffffffffff)
const min_offset = -max_offset - 1
const upper_word = u64(0xa5a5a5a5) << 32

struct Checks {
mut:
	total int
	failed int
}

fn (mut c Checks) require(ok bool, what &char) {
	c.total++
	if !ok {
		c.failed++
		C.printf(c'LINUX FADVISE FAIL: %s\n', what)
	}
}

fn (mut c Checks) expect(what &char, fd u64, offset i64, length i64, hint u64, want i32) {
	unsafe {
		result := C.syscall(i64(C.SYS_fadvise64), fd, offset, length, hint)
		got := if result == -1 { *C.__errno_location() } else { -i32(result) }
		c.total++
		if got != want {
			if c.failed < 20 {
				C.printf(c'LINUX FADVISE FAIL: %s fd=%#lx offset=%ld length=%ld advice=%#lx got=%d want=%d\n',
					what, fd, offset, length, hint, got, want)
			}
			c.failed++
		}
	}
}

fn eligible(mut c Checks, fd i32, label &char) {
	unsafe {
		for hint in u64(0) .. 6 {
			for offset in [min_offset, i64(-1), 0, 1, max_offset - 1]! {
				for length in [i64(0), 1, max_offset, -1, min_offset]! {
					c.expect(label, u64(fd), offset, length, hint, if length < 0 { C.EINVAL } else { 0 })
				}
			}
			c.expect(label, upper_word | u64(fd), 0, 1, upper_word | hint, 0)
		}
	}
	c.expect(label, u64(fd), 0, 0, 6, C.EINVAL)
	c.expect(label, u64(fd), -1, -1, u64(-1), C.EINVAL)
}

fn rejected(mut c Checks, fd u64, label &char, err i32) {
	c.expect(label, fd, 0, 0, 0, err)
	c.expect(label, fd, -1, -1, 6, err)
	c.expect(label, fd, -1, 1, u64(-1), err)
	c.expect(label, fd, -1, max_offset, 4, err)
}

fn check_descriptions(mut c Checks, regular i32, duplicate i32, writer i32, directory i32,
	device i32, socket i32, event_fd i32, path_only i32, read_pipe i32, write_pipe i32, fifo i32,
	stale i32) {
	unsafe {
		eligible(mut c, regular, c'regular')
		eligible(mut c, writer, c'write-only')
		eligible(mut c, directory, c'directory')
		eligible(mut c, device, c'character device')
		eligible(mut c, socket, c'UNIX socket')
		eligible(mut c, event_fd, c'eventfd')
		rejected(mut c, u64(path_only), c'O_PATH', C.EBADF)
		rejected(mut c, u64(stale), c'closed fd', C.EBADF)
		rejected(mut c, u64(-1), c'negative fd', C.EBADF)
		rejected(mut c, u64(read_pipe), c'read pipe', C.ESPIPE)
		rejected(mut c, u64(write_pipe), c'write pipe', C.ESPIPE)
		rejected(mut c, u64(fifo), c'named FIFO', C.ESPIPE)
		c.require(C.lseek(duplicate, 0, C.SEEK_CUR) == 0, c'dup offset unchanged by raw hints')
		c.require(C.fcntl(writer, C.F_GETFL) & C.O_ACCMODE == C.O_WRONLY, c'write access unchanged')
		err := C.__errno_location()
		for hint in i32(0) .. 6 {
			*err = C.EDOM
			result := C.posix_fadvise(duplicate, -1, 0, hint)
			c.require(result == 0 && *err == C.EDOM, c'libc success preserves errno')
		}
		*err = C.EDOM
		c.require(C.posix_fadvise(fifo, -1, -1, 6) == C.ESPIPE
			&& *err == C.EDOM, c'libc returns FIFO error without assigning errno')
		*err = C.EDOM
		c.require(C.posix_fadvise(path_only, -1, -1, 6) == C.EBADF
			&& *err == C.EDOM, c'libc returns O_PATH error without assigning errno')
		mut byte := u8(0)
		c.require(C.read(duplicate, &byte, 1) == 1 && byte == 71, c'hints preserve file bytes')
		c.require(C.lseek(regular, 0, C.SEEK_CUR) == 1, c'dup shares the original offset')
		c.require(C.lseek(regular, 0, C.SEEK_SET) == 0, c'reset offset for next credentials')
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		mut c := Checks{}
		regular := C.open(c'/tmp/fadvisefixt-file', C.O_CREAT | C.O_EXCL | C.O_RDWR, i32(0o600))
		writer := C.open(c'/tmp/fadvisefixt-file', C.O_WRONLY)
		path_only := C.open(c'/tmp/fadvisefixt-file', C.O_PATH)
		if regular < 0 || writer < 0 || path_only < 0 { return 1 }
		C.unlink(c'/tmp/fadvisefixt-file')
		byte := u8(71)
		if C.write(regular, &byte, 1) != 1 || C.lseek(regular, 0, C.SEEK_SET) != 0 { return 1 }
		duplicate := C.dup(regular)
		mut socks := [2]i32{}
		mut pipes := [2]i32{}
		if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &socks[0]) != 0 || C.pipe(&pipes[0]) != 0
			|| C.mkfifo(c'/tmp/fadvisefixt-fifo', 0o600) != 0 { return 1 }
		fifo := C.open(c'/tmp/fadvisefixt-fifo', C.O_RDWR | C.O_NONBLOCK)
		C.unlink(c'/tmp/fadvisefixt-fifo')
		directory := C.open(c'/tmp', C.O_RDONLY | C.O_DIRECTORY)
		mut device := C.open(c'/dev/null', C.O_RDWR)
		if device < 0 && reference {
			if C.mknod(c'/tmp/fadvisefixt-null', C.S_IFCHR | 0o600, C.makedev(1, 3)) != 0 { return 1 }
			device = C.open(c'/tmp/fadvisefixt-null', C.O_RDWR)
			C.unlink(c'/tmp/fadvisefixt-null')
		}
		event_fd := C.eventfd(0, 0)
		stale := C.dup(regular)
		if duplicate < 0 || fifo < 0 || directory < 0 || device < 0 || event_fd < 0 || stale < 0 { return 1 }
		C.close(stale)
		check_descriptions(mut c, regular, duplicate, writer, directory, device, socks[0], event_fd,
			path_only, pipes[0], pipes[1], fifo, stale)
		if C.setgid(1000) != 0 || C.setuid(1000) != 0 { return 1 }
		check_descriptions(mut c, regular, duplicate, writer, directory, device, socks[0], event_fd,
			path_only, pipes[0], pipes[1], fifo, stale)
		for fd in [regular, duplicate, writer, directory, device, socks[0], socks[1], event_fd,
			path_only, pipes[0], pipes[1], fifo]! {
			C.close(fd)
		}
		C.printf(c'LINUX FADVISE SUMMARY: checks=%d failures=%d\n', i32(c.total), i32(c.failed))
		if c.failed == 0 {
			C.puts(if reference { c'LINUX FADVISE REFERENCE: PASS' } else { c'LINUX FADVISE: PASS' })
		}
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
