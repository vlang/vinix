// SPDX-License-Identifier: GPL-2.0-or-later
// readahead(2): readable regular files at any offset and count up to the
// signed range, descriptor words, and EBADF before EINVAL for unreadable,
// O_PATH, directory, pipe, socket and character-device descriptors.
// The same ELF runs as Vinix's init and, given --reference, under Linux.
module readaheadfixture

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.mkdir(&char, u32) i32
fn C.mknod(&char, u32, u64) i32
fn C.pipe(&i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.alloca(usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strcmp(&char, &char) i32

struct State {
mut:
	checks   int
	failures int
}

struct Result {
	value isize
	err   int
}

fn readahead(fd i64, offset i64, count u64) Result {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		value := C.syscall(isize(C.SYS_readahead), fd, offset, count)
		return Result{value, if value < 0 { *errno_ptr } else { 0 }}
	}
}

fn check(mut s State, label &char, ok bool, got Result) {
	s.checks++
	if !ok {
		s.failures++
		C.printf(c'LINUX READAHEAD FAIL: %s value=%ld errno=%d\n', label, got.value, got.err)
	}
}

fn works(mut s State, label &char, got Result) {
	check(mut s, label, got.value == 0 && got.err == 0, got)
}

fn fails(mut s State, label &char, got Result, err int) {
	check(mut s, label, got.value == -1 && got.err == err, got)
}

fn cases(mut s State) {
	unsafe {
		C.mkdir(c'/tmp', 0o1777)
		path := &char(c'/tmp/readahead')
		f := C.open(path, C.O_CREAT | C.O_RDWR, 0o644)
		C.write(f, c'0123456789', 10)
		works(mut s, c'range', readahead(f, 0, 10))
		works(mut s, c'zero count', readahead(f, 0, 0))
		works(mut s, c'negative offset', readahead(f, -1, 10))
		works(mut s, c'past end', readahead(f, i64(1) << 40, 10))
		works(mut s, c'largest count', readahead(f, 0, u64(0x7fffffffffffffff)))
		fails(mut s, c'count sign', readahead(f, 0, u64(-1)), C.EINVAL)
		fails(mut s, c'count sign bit', readahead(f, 0, u64(1) << 63), C.EINVAL)
		buffer := C.alloca(16)
		check(mut s, c'data intact', C.pread(f, buffer, 16, 0) == 10
			&& C.memcmp(buffer, c'0123456789', 10) == 0, Result{0, 0})
		ro := C.open(path, C.O_RDONLY)
		works(mut s, c'read only', readahead(ro, 0, 10))
		works(mut s, c'descriptor word', readahead((i64(1) << 32) | i64(ro), 0, 10))
		fails(mut s, c'closed', readahead(999, 0, 10), C.EBADF)
		fails(mut s, c'negative descriptor', readahead(-1, 0, 10), C.EBADF)
		wo := C.open(path, C.O_WRONLY)
		fails(mut s, c'write only', readahead(wo, 0, 10), C.EBADF)
		// Readability is checked before the kind of file.
		fails(mut s, c'write only bad count', readahead(wo, 0, u64(-1)), C.EBADF)
		opath := C.open(path, C.O_PATH)
		fails(mut s, c'o_path', readahead(opath, 0, 10), C.EBADF)
		dir := C.open(c'/tmp', C.O_RDONLY | C.O_DIRECTORY)
		fails(mut s, c'directory', readahead(dir, 0, 10), C.EINVAL)
		// The kind of file is checked before the count.
		fails(mut s, c'directory bad count', readahead(dir, 0, u64(-1)), C.EINVAL)
		mut ends := [2]i32{}
		C.pipe(&ends[0])
		fails(mut s, c'pipe', readahead(ends[0], 0, 10), C.EINVAL)
		fails(mut s, c'pipe write end', readahead(ends[1], 0, 10), C.EBADF)
		mut pair := [2]i32{}
		C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0])
		fails(mut s, c'socket', readahead(pair[0], 0, 10), C.EINVAL)
		C.mknod(c'/tmp/readahead-null', C.S_IFCHR | 0o666, (1 << 8) | 3)
		device := C.open(c'/tmp/readahead-null', C.O_RDONLY)
		fails(mut s, c'character device', readahead(device, 0, 10), C.EINVAL)
		check(mut s, c'device opened', device >= 0, Result{isize(device), 0})
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		mut s := State{}
		cases(mut s)
		C.printf(c'LINUX READAHEAD SUMMARY: checks=%d failures=%d\n', s.checks, s.failures)
		if s.failures == 0 {
			C.puts(if reference { c'LINUX READAHEAD REFERENCE: PASS' } else { c'LINUX READAHEAD: PASS' })
		}
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
