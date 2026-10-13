// SPDX-License-Identifier: GPL-2.0-or-later
module seekextentfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat { st_mode u32 st_size i64 st_ino u64 st_dev u64 st_blocks i64 }
struct Handles { mut: fds [45]i32 sizes [5]i64 metadata [5]C.stat }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.lseek(i32, i64, i32) i64
fn C.dup(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fstat(i32, &C.stat) i32
fn C.ftruncate(i32, i64) i32
fn C.chmod(&char, u32) i32
fn C.mkdir(&char, u32) i32
fn C.pipe2(&i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.getpagesize() i32
fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn path(index i32) &char {
	return match index { 0 { &char(c'/tmp/linux-seekextent-empty') } 1 { &char(c'/tmp/linux-seekextent-small') }
		2 { &char(c'/tmp/linux-seekextent-page') } 3 { &char(c'/tmp/linux-seekextent-4g') } else { &char(c'/tmp/linux-seekextent-8g') } }
}
fn file_size(index i32) i64 {
	return match index { 0 { i64(0) } 1 { i64(4) } 2 { i64(C.getpagesize()) + 1 } 3 { i64(1) << 32 | 123 } else { i64(1) << 33 | 17 } }
}
fn prepare(bank &Handles) bool {
	unsafe {
		mut handles := &Handles(bank)
		for index in 0 .. 5 {
			handles.sizes[index] = file_size(i32(index))
			for mode in 0 .. 3 {
				slot := index * 9 + mode * 3
				handles.fds[slot] = C.open(path(i32(index)), if mode == 0 { C.O_RDONLY } else if mode == 1 { C.O_WRONLY } else { C.O_RDWR })
				if handles.fds[slot] < 0 { return false }
				handles.fds[slot + 1] = C.dup(handles.fds[slot]); if handles.fds[slot + 1] < 0 { return false }
				handles.fds[slot + 2] = C.fcntl(handles.fds[slot], C.F_DUPFD_CLOEXEC, 0); if handles.fds[slot + 2] < 0 { return false }
			}
			if C.fstat(handles.fds[index * 9], &handles.metadata[index]) != 0 || handles.metadata[index].st_size != handles.sizes[index] { return false }
		}
		return true
	}
}
fn cleanup(bank &Handles) { unsafe { for fd in bank.fds { if fd >= 0 { C.close(fd) } } } }
fn probe(original i32, fd i32, size i64, offset i64, whence i32, high u64, selector_high u64, raw bool, verbose bool) bool {
	unsafe {
		if C.lseek(original, 1, C.SEEK_SET) != 1 { return false }
		e := C.__errno_location(); *e = 0
		actual := if raw { C.syscall(isize(C.SYS_lseek), high | u64(u32(fd)), offset, selector_high | u64(u32(whence))) } else { isize(C.lseek(fd, offset, whence)) }
		code := *e
		wanted := if offset < 0 || offset >= size { isize(-1) } else if whence == 3 { isize(offset) } else { isize(size) }
		expected := if wanted < 0 { C.ENXIO } else { 0 }
		cursor := if actual >= 0 { i64(actual) } else { i64(1) }
		valid := actual == wanted && code == expected && C.lseek(original, 0, C.SEEK_CUR) == cursor && C.lseek(fd, 0, C.SEEK_CUR) == cursor
		if !valid && verbose && offset == 0 && high == 0 && selector_high == 0 {
			C.printf(c'LINUX SEEKEXTENT DETAIL: raw=%d size=%ld offset=%ld whence=%d result=%ld/%d expected=%ld/%d\n', i32(raw), size, offset, whence, actual, code, wanted, expected); C.fflush(nil)
		}
		return valid
	}
}
fn retained(bank &Handles) bool {
	unsafe {
		for index in 0 .. 5 {
			for alias in 0 .. 9 {
				fd := bank.fds[index * 9 + alias]; mut value := C.stat{}
				if C.fstat(fd, &value) != 0 || value.st_size != bank.metadata[index].st_size || value.st_blocks != bank.metadata[index].st_blocks || value.st_mode != bank.metadata[index].st_mode || value.st_ino != bank.metadata[index].st_ino || value.st_dev != bank.metadata[index].st_dev { return false }
				if C.fcntl(fd, C.F_GETFD) & C.FD_CLOEXEC != if alias % 3 == 2 { C.FD_CLOEXEC } else { 0 } { return false }
			}
			fd := bank.fds[index * 9 + 6]; size := bank.sizes[index]; mut byte := u8(0xff)
			if size == 0 { if C.pread(fd, &byte, 1, 0) != 0 || byte != 0xff { return false } }
			else {
				if C.pread(fd, &byte, 1, 0) != 1 || byte != 0x41 || C.pread(fd, &byte, 1, size - 1) != 1 || byte != 0x5a || C.pread(fd, &byte, 1, size / 2) != 1 || byte != 0 { return false }
				byte = 0xff; if C.pread(fd, &byte, 1, size) != 0 || byte != 0xff { return false }
			}
		}
		return true
	}
}
fn errors() bool {
	unsafe {
		pathname := C.open(path(1), C.O_PATH); if pathname < 0 { return false }; defer { C.close(pathname) }
		mut pipe := [i32(-1), i32(-1)]!; if C.pipe2(&pipe[0], C.O_NONBLOCK) != 0 { return false }; defer { C.close(pipe[0]); C.close(pipe[1]) }
		mut pair := [i32(-1), i32(-1)]!; if C.socketpair(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_NONBLOCK, 0, &pair[0]) != 0 { return false }; defer { C.close(pair[0]); C.close(pair[1]) }
		for fd in [i32(-1), pathname, pipe[0], pipe[1], pair[0]]! {
			for offset in [i64(0), -1, i64(1) << 33 | 17]! { for whence in [i32(3), 4]! {
				e := C.__errno_location(); *e = 0
				actual := C.syscall(isize(C.SYS_lseek), u64(0x1234567800000000) | u64(u32(fd)), offset, u64(0xffffffff00000000) | u64(u32(whence)))
				if actual != -1 || *e != if fd == -1 || fd == pathname { C.EBADF } else { C.ESPIPE } { return false }
			} }
		}
		return true
	}
}
fn storage_cycle(bank &Handles) bool {
	unsafe {
		for index in 0 .. 5 { for mode in 0 .. 3 { for alias in 0 .. 3 {
			original := bank.fds[index * 9 + mode * 3]; fd := bank.fds[index * 9 + mode * 3 + alias]; size := bank.sizes[index]
			for offset in [i64(-1), 0, size - 1, size, i64(0x7fffffffffffffff)]! { for whence in [i32(3), 4]! {
				if !probe(original, fd, size, offset, whence, 0x1234567800000000, 0xffffffff00000000, true, false)
					|| !probe(original, fd, size, offset, whence, 0, 0, false, false) { return false }
			} }
		} } }
		for mode in 0 .. 3 {
			original := bank.fds[9 + mode * 3]; copy := C.dup(original); if copy < 0 { return false }
			valid := probe(original, copy, 4, 1, 4, 0, 0, true, false)
			if C.close(copy) != 0 || !valid { return false }
		}
		return retained(bank)
	}
}

fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination); mut data := [4096]char{}
		length := C.pread(fd, &data[0], usize(data.len - 1), 0)
		if length <= 0 || length >= data.len { return false }; data[int(length)] = 0
		mut position := 0; mut large := false
		for position < int(length) {
			mut size := u64(0); mut duplicate_size := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate_size, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate_size { return false }
				counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }
			for position < int(length) && data[position] != char(10) { position++ }; position++
		}
		return counts.rows > 0 && large
	}
}
fn storage(bank &Handles, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !storage_cycle(bank) { return false } }; C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}; if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle(bank) { return false } }; C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}; if !snapshot(observer, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for index in 0 .. int(before.rows) {
			if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { valid = false }
			C.printf(c'LINUX SEEKEXTENT SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX SEEKEXTENT STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
// A bounded backup-style DATA/HOLE walker must copy the complete contents,
// including zero regions, when the filesystem reports one generic extent.
fn copy_walk(bank &Handles, ordinary bool) bool {
	unsafe {
		for index in 0 .. 3 {
			target := C.open(if ordinary { c'/tmp/linux-seekextent-copy/user' } else { c'/tmp/linux-seekextent-copy/root' }, C.O_CREAT | C.O_TRUNC | C.O_RDWR, u32(0o600))
			if target < 0 { return false }
			valid := copy_file(bank.fds[index * 9 + 6], target, bank.sizes[index])
			if C.close(target) != 0 || !valid { return false }
		}
		return true
	}
}
fn copy_file(source i32, target i32, size i64) bool {
	unsafe {
		mut buffer := [1024]u8{}; mut comparison := [1024]u8{}; mut position := i64(0)
		for position < size {
			data := C.lseek(source, position, 3); hole := C.lseek(source, data, 4)
			if data != position || hole != size || C.lseek(source, data, C.SEEK_SET) != data { return false }
			for position < hole {
				wanted := usize(if hole - position < 1024 { hole - position } else { i64(1024) })
				if C.read(source, &buffer[0], wanted) != isize(wanted) || C.pwrite(target, &buffer[0], wanted, position) != isize(wanted) { return false }
				position += i64(wanted)
			}
		}
		e := C.__errno_location(); *e = 0
		if C.lseek(source, size, 3) != -1 || *e != C.ENXIO { return false }
		mut metadata := C.stat{}; if C.fstat(target, &metadata) != 0 || metadata.st_size != size { return false }
		position = 0
		for position < size {
			wanted := usize(if size - position < 1024 { size - position } else { i64(1024) })
			if C.pread(source, &buffer[0], wanted, position) != isize(wanted) || C.pread(target, &comparison[0], wanted, position) != isize(wanted) { return false }
			for byte in 0 .. int(wanted) { if buffer[byte] != comparison[byte] { return false } }
			position += i64(wanted)
		}
		return true
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(300); mut bad := i32(0); mut cases := i32(0)
		mut bank := &Handles(C.alloca(usize(sizeof(Handles)))); *bank = Handles{}
		for index in 0 .. 45 { bank.fds[index] = -1 }; defer { cleanup(bank) }
		if !prepare(bank) || !retained(bank) || !errors() { return false }
		for index in 0 .. 5 { for mode in 0 .. 3 { for alias in 0 .. 3 {
			original := bank.fds[index * 9 + mode * 3]; fd := bank.fds[index * 9 + mode * 3 + alias]; size := bank.sizes[index]
			for offset in [-i64(0x7fffffffffffffff) - 1, i64(-1), 0, 1, size - 1, size, size + 1, i64(1) << 32 | 17, i64(1) << 33 | 17, i64(0x7fffffffffffffff)]! {
				for whence in [i32(3), 4]! {
					for high in [u64(0), 0x1234567800000000, 0xffffffff00000000]! { for selector_high in [u64(0), 0x8000000000000000, 0xffffffff00000000]! {
						cases++; if !probe(original, fd, size, offset, whence, high, selector_high, true, true) { bad++ }
					} }
					cases++; if !probe(original, fd, size, offset, whence, 0, 0, false, true) { bad++ }
				}
			}
		} } }
		if !retained(bank) || !errors() { return false }
		C.printf(c'LINUX SEEKEXTENT OUTCOMES: ordinary=%d cases=%d failures=%d\n', i32(ordinary), cases, bad)
		C.printf(c'LINUX SEEKEXTENT CONTROLS: ordinary=%d metadata/blocks/flags/bytes/aliases/descriptor-errors PASS\n', i32(ordinary)); C.fflush(nil)
		if bad != 0 || !storage(bank, ordinary) || !copy_walk(bank, ordinary) { return false }
		C.printf(c'LINUX SEEKEXTENT COPY: ordinary=%d empty/small/page-crossing byte comparison PASS\n', i32(ordinary)); C.fflush(nil)
		C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.mkdir(c'/tmp/linux-seekextent-copy', u32(0o777)) != 0 || C.chmod(c'/tmp/linux-seekextent-copy', u32(0o777)) != 0 { return 1 }
		for index in 0 .. 5 {
			fd := C.open(path(i32(index)), C.O_CREAT | C.O_TRUNC | C.O_RDWR, u32(0o666)); if fd < 0 { return 1 }
			size := file_size(i32(index)); mut first := u8(0x41); mut last := u8(0x5a)
			valid := C.ftruncate(fd, size) == 0 && (size == 0 || (C.pwrite(fd, &first, 1, 0) == 1 && C.pwrite(fd, &last, 1, size - 1) == 1))
			if C.close(fd) != 0 || !valid || C.chmod(path(i32(index)), u32(0o666)) != 0 { return 1 }
		}
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1); if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX SEEKEXTENT FAIL: generic DATA/HOLE behavior or storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX SEEKEXTENT PASS: root/UID1000 raw/musl DATA reports the in-file position and HOLE reports EOF; empty/out-of-file/negative positions return ENXIO; sparse signed64 offsets, shared alias cursors, descriptor errors, retained bytes/metadata/blocks and bounded backup-style copies pass with flat 200-cycle storage')
		C.puts(c'LINUX SEEKEXTENT: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
