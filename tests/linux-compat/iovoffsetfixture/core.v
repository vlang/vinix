// SPDX-License-Identifier: GPL-2.0-or-later
module iovoffsetfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.iovec {
mut:
	iov_base voidptr
	iov_len usize
}
struct C.stat {
mut:
	st_size i64
	st_blocks i64
}
struct Slabs {
mut:
	sizes [32]u64
	live [32]u64
	rows i32
	large u64
}
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.preadv(i32, &C.iovec, i32, i64) isize
fn C.pwritev(i32, &C.iovec, i32, i64) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.lseek(i32, i64, i32) i64
fn C.fstat(i32, &C.stat) i32
fn C.pipe2(&i32, i32) i32
fn C.ioctl(i32, usize, ...) i32
fn C.chmod(&char, u32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn number(write bool, version i32) isize {
	return isize(if version == 0 { if write { C.SYS_pwritev } else { C.SYS_preadv } }
		else { if write { C.SYS_pwritev2 } else { C.SYS_preadv2 } })
}

fn positioned(fd i32, write bool, version i32, public bool, offset u64, high u64, verbose bool) bool {
	unsafe {
		data := &u8(C.alloca(8))
		data[0] = 0x4c; data[1] = 0x4f; data[2] = 0x48; data[3] = 0x49
		alias := offset & u64(0xffffffff)
		if C.pwrite(fd, &data[0], 2, i64(alias)) != 2 || C.pwrite(fd, &data[2], 2, i64(offset)) != 2
			|| C.lseek(fd, 5, C.SEEK_SET) != 5 { return false }
		mut before := C.stat{}
		if C.fstat(fd, &before) != 0 { return false }
		mut vector := &C.iovec(C.alloca(usize(2 * sizeof(C.iovec))))
		vector[0] = C.iovec{iov_base: &data[4], iov_len: 1}
		vector[1] = C.iovec{iov_base: &data[5], iov_len: 1}
		data[4] = if write { u8(0x58) } else { u8(0) }
		data[5] = if write { u8(0x59) } else { u8(0) }
		e := C.__errno_location(); *e = 0
		actual := if public {
			if write { C.pwritev(fd, vector, 2, i64(offset)) } else { C.preadv(fd, vector, 2, i64(offset)) }
		} else { C.syscall(number(write, version), isize(fd), vector, isize(2), offset, high, isize(0)) }
		code := *e
		position := C.lseek(fd, 0, C.SEEK_CUR)
		mut after := C.stat{}
		if C.fstat(fd, &after) != 0 { return false }
		if C.pread(fd, &data[0], 2, i64(alias)) != 2 || C.pread(fd, &data[2], 2, i64(offset)) != 2 { return false }
		valid := actual == 2 && code == 0 && position == 5 && before.st_size == after.st_size
			&& before.st_blocks == after.st_blocks && data[0] == 0x4c && data[1] == 0x4f
			&& data[2] == if write { u8(0x58) } else { u8(0x48) }
			&& data[3] == if write { u8(0x59) } else { u8(0x49) }
			&& data[4] == if write { u8(0x58) } else { u8(0x48) }
			&& data[5] == if write { u8(0x59) } else { u8(0x49) }
		if !valid && verbose {
			C.printf(c'LINUX IOVOFFSET DETAIL: positioned write=%d v=%d libc=%d offset=%lu high=%lu result=%ld/%d alias=%02x,%02x data=%02x,%02x buffer=%02x,%02x position=%ld size=%ld/%ld blocks=%ld/%ld\n', i32(write), version, i32(public), offset, high, actual, code, i32(data[0]), i32(data[1]), i32(data[2]), i32(data[3]), i32(data[4]), i32(data[5]), position, before.st_size, after.st_size, before.st_blocks, after.st_blocks); C.fflush(nil)
		}
		return valid
	}
}

fn negative(fd i32, write bool, version i32, offset i64, high u64, count isize, bad_fd bool, verbose bool) bool {
	unsafe {
		if C.lseek(fd, 5, C.SEEK_SET) != 5 { return false }
		e := C.__errno_location(); *e = 0
		actual := C.syscall(number(write, version), isize(if bad_fd { -1 } else { fd }), voidptr(1), count, u64(offset), high, isize(0))
		code := *e
		position := C.lseek(fd, 0, C.SEEK_CUR)
		valid := actual == -1 && code == C.EINVAL && position == 5
		if !valid && verbose {
			C.printf(c'LINUX IOVOFFSET DETAIL: negative write=%d v=%d offset=%ld high=%lu count=%ld bad_fd=%d result=%ld/%d position=%ld\n', i32(write), version, offset, high, count, i32(bad_fd), actual, code, position); C.fflush(nil)
		}
		return valid
	}
}

fn file_sentinel(fd i32, write bool, high u64, verbose bool) bool {
	unsafe {
		data := &u8(C.alloca(4)); data[0] = 0x41; data[1] = 0x42
		if C.pwrite(fd, data, 2, 5) != 2 || C.lseek(fd, 5, C.SEEK_SET) != 5 { return false }
		data[2] = if write { u8(0x58) } else { u8(0) }; data[3] = if write { u8(0x59) } else { u8(0) }
		mut vector := &C.iovec(C.alloca(usize(2 * sizeof(C.iovec))))
		vector[0] = C.iovec{iov_base: &data[2], iov_len: 1}; vector[1] = C.iovec{iov_base: &data[3], iov_len: 1}
		e := C.__errno_location(); *e = 0
		actual := C.syscall(number(write, 1), isize(fd), vector, isize(2), u64(-1), high, isize(0))
		code := *e; position := C.lseek(fd, 0, C.SEEK_CUR)
		if C.pread(fd, data, 2, 5) != 2 { return false }
		valid := actual == 2 && code == 0 && position == 7
			&& data[0] == if write { u8(0x58) } else { u8(0x41) }
			&& data[1] == if write { u8(0x59) } else { u8(0x42) }
			&& data[2] == if write { u8(0x58) } else { u8(0x41) }
			&& data[3] == if write { u8(0x59) } else { u8(0x42) }
		if !valid && verbose {
			C.printf(c'LINUX IOVOFFSET DETAIL: file sentinel write=%d high=%lu result=%ld/%d position=%ld file=%02x,%02x buffer=%02x,%02x\n', i32(write), high, actual, code, position, i32(data[0]), i32(data[1]), i32(data[2]), i32(data[3])); C.fflush(nil)
		}
		return valid
	}
}

fn pipe_sentinel(write bool, version i32, high u64, verbose bool) bool {
	unsafe {
		mut fds := [2]i32{}
		if C.pipe2(&fds[0], C.O_NONBLOCK) != 0 { return false }
		defer { C.close(fds[0]); C.close(fds[1]) }
		data := &u8(C.alloca(4)); data[0] = 0x41; data[1] = 0x42; data[2] = 0; data[3] = 0
		if !write && C.write(fds[1], data, 2) != 2 { return false }
		mut vector := &C.iovec(C.alloca(usize(2 * sizeof(C.iovec))))
		vector[0] = C.iovec{iov_base: if write { &data[0] } else { &data[2] }, iov_len: 1}
		vector[1] = C.iovec{iov_base: if write { &data[1] } else { &data[3] }, iov_len: 1}
		e := C.__errno_location(); *e = 0
		actual := C.syscall(number(write, version), isize(if write { fds[1] } else { fds[0] }), vector, isize(2), u64(-1), high, isize(0))
		code := *e; mut queued := i32(-1)
		if C.ioctl(fds[0], usize(C.FIONREAD), &queued) != 0 { return false }
		valid := if version == 0 {
			actual == -1 && code == C.EINVAL && queued == if write { 0 } else { 2 } && data[2] == 0 && data[3] == 0
		} else {
			actual == 2 && code == 0 && queued == if write { 2 } else { 0 }
				&& (write || (data[2] == 0x41 && data[3] == 0x42))
		}
		if version == 1 && write && valid && (C.read(fds[0], &data[2], 2) != 2 || data[2] != 0x41 || data[3] != 0x42) { return false }
		if !valid && verbose {
			C.printf(c'LINUX IOVOFFSET DETAIL: pipe sentinel write=%d v=%d high=%lu result=%ld/%d queued=%d buffer=%02x,%02x\n', i32(write), version, high, actual, code, queued, i32(data[2]), i32(data[3])); C.fflush(nil)
		}
		return valid
	}
}

fn storage_cycle(fd i32) bool {
	unsafe {
		for write in [false, true]! {
			for version in [i32(0), 1]! {
				if !positioned(fd, write, version, false, u64(0x10000007b), 0, false)
					|| !negative(fd, write, version, -2, 0, 1, false, false)
					|| !negative(fd, write, version, -2, u64(-1), 0, true, false)
					|| !pipe_sentinel(write, version, 0, false) { return false }
			}
			if !positioned(fd, write, 0, true, u64(0x200000011), 0, false) || !file_sentinel(fd, write, 0, false) { return false }
		}
		return true
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
fn storage(file_fd i32, ordinary bool) bool {
	unsafe {
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { return false }; defer { C.close(fd) }
		for _ in 0 .. 32 { if !storage_cycle(file_fd) { return false } }
		C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}
		if !snapshot(fd, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle(file_fd) { return false } }
		C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}
		if !snapshot(fd, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for i in 0 .. int(before.rows) {
			if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { valid = false }
			C.printf(c'LINUX IOVOFFSET SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i])
		}
		C.printf(c'LINUX IOVOFFSET STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}

fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(150)
		fd := C.open(c'/tmp/linux-iovoffset', C.O_RDWR)
		if fd < 0 { return false }; defer { C.close(fd) }
		mut normal_bad := 0; mut negative_bad := 0; mut sentinel_bad := 0
		for offset in [u64(0x10000007b), 0x1ffffffff, 0x200000011]! {
			for write in [false, true]! {
				for version in [i32(0), 1]! {
					for high in [u64(0), 1, 2, 0xffffffff, 0x80000000, 0x1234567800000000]! {
						if !positioned(fd, write, version, false, offset, high, true) { normal_bad++ }
					}
				}
				if !positioned(fd, write, 0, true, offset, 0, true) { normal_bad++ }
			}
		}
		C.printf(c'LINUX IOVOFFSET NORMAL: ordinary=%d cases=78 failures=%d\n', i32(ordinary), i32(normal_bad)); C.fflush(nil)
		for offset in [i64(-1), -2, i64(u64(1) << 63), i64((u64(1) << 63) + 123)]! {
			for write in [false, true]! { for version in [i32(0), 1]! {
				if version == 1 && offset == -1 { continue }
				for high in [u64(0), 1, 0xffffffff]! { for count in [isize(0), 1, 1025]! { for bad_fd in [false, true]! {
					if !negative(fd, write, version, offset, high, count, bad_fd, true) { negative_bad++ }
				} } }
			} }
		}
		C.printf(c'LINUX IOVOFFSET NEGATIVE: ordinary=%d cases=252 failures=%d\n', i32(ordinary), i32(negative_bad)); C.fflush(nil)
		for high in [u64(0), 1, 0xffffffff]! { for write in [false, true]! {
			if !file_sentinel(fd, write, high, true) { sentinel_bad++ }
			for version in [i32(0), 1]! { if !pipe_sentinel(write, version, high, true) { sentinel_bad++ } }
		} }
		C.printf(c'LINUX IOVOFFSET SENTINEL: ordinary=%d cases=18 failures=%d\n', i32(ordinary), i32(sentinel_bad)); C.fflush(nil)
		if normal_bad != 0 || negative_bad != 0 || sentinel_bad != 0 { return false }
		if !storage(fd, ordinary) { C.puts(c'LINUX IOVOFFSET FAIL: repeated offset-path storage'); C.fflush(nil); return false }
		C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		fd := C.open(c'/tmp/linux-iovoffset', C.O_CREAT | C.O_TRUNC | C.O_RDWR, u32(0o666))
		if fd < 0 || C.close(fd) != 0 || C.chmod(c'/tmp/linux-iovoffset', u32(0o666)) != 0 { return 1 }
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork()
			if child < 0 { return 1 }
			if child == 0 { C._exit(if qualify(ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1)
			if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX IOVOFFSET FAIL: native 64-bit offsets or v1/v2 negative offsets'); C.fflush(nil); return 1 }
		C.puts(c'LINUX IOVOFFSET PASS: root/UID1000 raw preadv/pwritev/preadv2/pwritev2 preserve full native offsets above4GiB and ignore pos_h; public musl wrappers preserve sparse data, lower aliases, size and cursor; signed negative errors precede invalid vectors/descriptors; only v2 minus1 uses and updates the current position on files/pipes; repeated valid/error/sentinel storage stays flat')
		C.puts(c'LINUX IOVOFFSET: PASS'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
