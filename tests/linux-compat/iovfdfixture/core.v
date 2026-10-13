// SPDX-License-Identifier: GPL-2.0-or-later
module iovfdfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct IOVec {
mut:
	base u64
	len u64
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
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.lseek(i32, i64, i32) i64
fn C.pipe2(&i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.ioctl(i32, usize, ...) i32
fn C.chmod(&char, u32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.memset(voidptr, i32, usize) voidptr
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

// Native fdget consumes unsigned-int descriptor numbers, even when a vector
// syscall declares an unsigned-long argument. Preserve the full vector count.
fn probe(kind i32, write bool, version i32, high u64, variant i32, count_override i32, verbose bool) bool {
	unsafe {
		current_position := version == 0 || version == 3
		mut fds := [i32(-1), i32(-1)]!
		mut anchor := i32(-1)
		if kind in [i32(0), 2, 3]! {
			anchor = C.open(c'/tmp/linux-iovfd', C.O_RDWR)
			if anchor < 0 { return false }
		}
		defer { if anchor >= 0 { C.close(anchor) } }
		if kind == 0 { fds[0] = anchor }
		else if kind in [i32(2), 3]! {
			fds[0] = C.open(c'/tmp/linux-iovfd', if kind == 2 { C.O_PATH } else { if write { C.O_RDONLY } else { C.O_WRONLY } })
			if fds[0] < 0 { return false }
		} else if kind in [i32(4), 5]! {
			if C.pipe2(&fds[0], C.O_NONBLOCK) != 0 { return false }
		} else if kind == 6 && C.socketpair(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_NONBLOCK, 0, &fds[0]) != 0 { return false }
		defer { if fds[0] >= 0 && fds[0] != anchor { C.close(fds[0]) }; if fds[1] >= 0 { C.close(fds[1]) } }
		mut data := [u8(0x41), u8(0x42), u8(0x43), u8(0x44), u8(0x58), u8(0x59), u8(0), u8(0)]!
		if anchor >= 0 && (C.pwrite(anchor, &data[0], 4, 0) != 4 || C.lseek(anchor, 1, C.SEEK_SET) != 1) { return false }
		if kind >= 4 && !write && C.write(fds[1], &data[0], 2) != 2 { return false }
		mut vector := &IOVec(C.alloca(usize(1024 * sizeof(IOVec))))
		C.memset(vector, 0, usize(1024 * sizeof(IOVec)))
		mut count := if count_override >= 0 { isize(count_override) } else if variant == 10 { isize(0x100000001) } else { match variant { 0 { isize(0) } 2 { isize(1024) } 4 { isize(1025) } 6, 7, 8, 10 { isize(2) } else { isize(1) } } }
		if count_override < 0 && variant in [i32(5), 6, 7, 8, 10]! {
			vector[0] = IOVec{base: u64(if write { &data[4] } else { &data[6] }), len: 1}
			vector[1] = IOVec{base: u64(if write { &data[5] } else { &data[7] }), len: 1}
			if variant == 5 { vector[0].base = u64(-1) }
			if variant == 6 { vector[1] = IOVec{base: u64(-1)} }
			if variant == 7 { vector[0].base = u64(-1); vector[1].len = u64(1) << 63 }
		}
		if version == 0 && variant == 9 { count = -1 }
		header := if count_override < 0 && variant in [i32(0), 3, 4, 9]! { voidptr(1) } else { vector }
		offset := if variant == 9 { i64(-2) } else { if version == 3 { i64(-1) } else { i64(0) } }
		fd := if kind in [i32(4), 5]! { fds[if write != (kind == 5) { 1 } else { 0 }] } else { fds[0] }
		mut wanted := isize(-1)
		code := if variant == 9 && version != 0 { C.EINVAL }
			else if kind in [i32(1), 2, 3]! || (kind == 5 && current_position) { C.EBADF }
			else if kind >= 4 && !current_position { C.ESPIPE }
			else if count_override < 0 && variant in [i32(3), 5, 6]! { C.EFAULT }
			else if count_override < 0 && variant in [i32(4), 7, 9, 10]! { C.EINVAL }
			else if variant <= 2 || count_override >= 0 { 0 }
			else { 0 }
		if code == 0 { wanted = if variant == 8 && count_override < 0 { 2 } else { 0 } }
		e := C.__errno_location(); *e = 0
		raw_fd := high | u64(u32(fd))
		number := if version == 0 { if write { C.SYS_writev } else { C.SYS_readv } }
			else if version == 1 { if write { C.SYS_pwritev } else { C.SYS_preadv } }
			else { if write { C.SYS_pwritev2 } else { C.SYS_preadv2 } }
		actual := C.syscall(isize(number), raw_fd, header, count, u64(offset), u64(0x1234567800000000), u64(0))
		actual_code := *e
		mut valid := actual == wanted && actual_code == code
		if anchor >= 0 {
			position := C.lseek(anchor, 0, C.SEEK_CUR)
			if position != if kind == 0 && wanted == 2 && current_position { i64(3) } else { i64(1) } { valid = false }
			if C.pread(anchor, &data[0], 4, 0) != 4 { return false }
			if kind == 0 && wanted == 2 && write {
				if current_position { if data[0] != 0x41 || data[1] != 0x58 || data[2] != 0x59 || data[3] != 0x44 { valid = false } }
				else if data[0] != 0x58 || data[1] != 0x59 || data[2] != 0x43 || data[3] != 0x44 { valid = false }
			} else if data[0] != 0x41 || data[1] != 0x42 || data[2] != 0x43 || data[3] != 0x44 { valid = false }
		}
		if !write && wanted == 2 {
			if data[6] != if kind == 0 && current_position { u8(0x42) } else { u8(0x41) }
				|| data[7] != if kind == 0 && current_position { u8(0x43) } else { u8(0x42) } { valid = false }
		} else if data[6] != 0 || data[7] != 0 { valid = false }
		if kind >= 4 {
			receiver := if kind == 6 && write { fds[1] } else { fds[0] }; mut queued := i32(-1)
			if C.ioctl(receiver, usize(C.FIONREAD), &queued) != 0 { return false }
			if queued != if wanted == 2 { if write { 2 } else { 0 } } else { if write { 0 } else { 2 } } { valid = false }
			if wanted == 2 && write && (C.read(receiver, &data[6], 2) != 2 || data[6] != 0x58 || data[7] != 0x59) { valid = false }
		}
		if !valid && verbose {
			C.printf(c'LINUX IOVFD DETAIL: kind=%d write=%d version=%d high=%lu variant=%d count=%ld result=%ld/%d expected=%ld/%d\n', kind, i32(write), version, high, variant, count, actual, actual_code, wanted, code); C.fflush(nil)
		}
		return valid
	}
}

fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination)
		mut data := [4096]char{}
		length := C.pread(fd, &data[0], usize(data.len - 1), 0)
		if length <= 0 || length >= data.len { return false }
		data[int(length)] = 0
		mut position := 0
		mut large := false
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

fn storage_cycle() bool {
	unsafe {
		for write in [false, true]! { for version in [i32(0), 1, 2, 3]! {
			for count in [i32(0), 8, 9, 1024]! {
				if !probe(0, write, version, u64(0x1234567800000000), 0, count, false) { return false }
			}
			for variant in [i32(3), 4, 6, 7, 8, 9, 10]! {
				if !probe(0, write, version, u64(0x1234567800000000), variant, -1, false) { return false }
			}
		} }
		return true
	}
}
fn storage(ordinary bool) bool {
	unsafe {
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY); if fd < 0 { return false }; defer { C.close(fd) }
		for _ in 0 .. 32 { if !storage_cycle() { return false } }
		C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}
		if !snapshot(fd, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle() { return false } }
		C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}
		if !snapshot(fd, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for i in 0 .. int(before.rows) {
			if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { valid = false }
			C.printf(c'LINUX IOVFD SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i])
		}
		C.printf(c'LINUX IOVFD STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(300); mut bad := 0
		for kind in 0 .. 7 { for write in [false, true]! { for version in [i32(0), 1, 2, 3]! {
			for high in [u64(0), u64(1) << 32, 0x1234567800000000, 0x8000000000000000, 0xffffffff00000000]! { for variant in 0 .. 11 {
				if !probe(i32(kind), write, version, high, i32(variant), -1, true) { bad++ }
			} }
		} } }
		C.printf(c'LINUX IOVFD OUTCOMES: ordinary=%d cases=3080 failures=%d\n', i32(ordinary), i32(bad)); C.fflush(nil)
		if bad != 0 || !storage(ordinary) { return false }
		C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		fd := C.open(c'/tmp/linux-iovfd', C.O_CREAT | C.O_TRUNC | C.O_RDWR, u32(0o666))
		if fd < 0 { return 1 }; if C.close(fd) != 0 || C.chmod(c'/tmp/linux-iovfd', u32(0o666)) != 0 { return 1 }
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { return 1 }
			if child == 0 { C._exit(if qualify(ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1)
			if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX IOVFD FAIL: native vector descriptor width or storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX IOVFD PASS: root/UID1000 native readv/writev/preadv/pwritev/preadv2/pwritev2 use low32 descriptor bits; high patterns preserve valid I/O and descriptor/access/seek/import/negative-offset errors without altering data/cursors/queues on refusal; full-width vector counts remain invalid; repeated fast/heap/error imports release storage')
		C.puts(c'LINUX IOVFD: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
