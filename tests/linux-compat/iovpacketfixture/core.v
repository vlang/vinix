// SPDX-License-Identifier: GPL-2.0-or-later
module iovpacketfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct IOVec { mut: base u64 len u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.ioctl(i32, usize, ...) i32
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.mprotect(voidptr, usize, i32) i32
fn C.sysconf(i32) isize
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

fn receive(fd i32, version i32, vector voidptr, count i32, flags u64) isize {
	return unsafe { C.syscall(isize(if version == 0 { C.SYS_readv } else { C.SYS_preadv2 }), isize(fd), vector, isize(count), u64(-1), u64(0x1234567800000000), flags) }
}
fn queued(fd i32) i32 {
	unsafe { mut n := i32(-1); return if C.ioctl(fd, usize(C.FIONREAD), &n) == 0 { n } else { -1 } }
}
fn probe(kind i32, version i32, count i32, variant i32, verbose bool) bool {
	unsafe {
		mut fds := [2]i32{}
		if C.socketpair(C.AF_UNIX, (if kind == 0 { C.SOCK_DGRAM } else { C.SOCK_SEQPACKET }) | C.SOCK_NONBLOCK, 0, &fds[0]) != 0 { return false }
		defer { C.close(fds[0]); C.close(fds[1]) }
		page := usize(C.sysconf(C._SC_PAGESIZE))
		mapping := C.mmap(nil, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(mapping) == u64(-1) { return false }; defer { C.munmap(mapping, page * 2) }
		return transfer(&fds[0], mapping, page, version, count, variant, verbose)
	}
}
// The caller retains both endpoints and the mapping for this synchronous
// transfer. Retention cycles can reuse them without socket-object churn.
fn transfer(fds &i32, mapping voidptr, page usize, version i32, count i32, variant i32, verbose bool) bool {
	unsafe {
		if C.mprotect(mapping, page * 2, C.PROT_READ | C.PROT_WRITE) != 0 { return false }
		C.memset(mapping, 0, page * 2)
		if C.mprotect(voidptr(u64(mapping) + u64(page)), page, C.PROT_NONE) != 0 { return false }
		if variant == 2 && C.mprotect(mapping, page, C.PROT_READ) != 0 { return false }
		mut input := [u8(0x41), 0x42, 0x43, 0x44, 0x58, 0x59]!
		mut output := [8]u8{}
		length := if variant == 7 { 0 } else if variant in [i32(4), 5]! { 4 } else if variant in [i32(15), 17]! { 1 } else { 2 }
		empty_queue := variant in [i32(6), 13]!
		if !empty_queue && (C.write(fds[1], &input[0], usize(length)) != length || C.write(fds[1], &input[4], 2) != 2) { return false }
		vector := &IOVec(C.alloca(usize(count) * usize(sizeof(IOVec)))); C.memset(vector, 0, usize(count) * usize(sizeof(IOVec)))
		first := if count == 2 { 0 } else { count / 2 }
		vector[first] = IOVec{base: u64(&output[0]), len: if variant == 17 { 2 } else { 1 }}
		vector[count - 1] = IOVec{base: u64(&output[4]), len: 1}
		if variant in [i32(0), 6, 7, 12]! { vector[first].base = 1 }
		if variant == 1 { vector[first].base = u64(mapping) + u64(page) }
		if variant == 2 { vector[first].base = u64(mapping) }
		if variant in [i32(3), 15, 17]! { vector[count - 1].base = u64(mapping) + u64(page) }
		if variant == 4 { vector[first] = IOVec{base: u64(mapping) + u64(page - 1), len: 2}; vector[count - 1].len = 2 }
		if variant == 5 { vector[count - 1] = IOVec{base: u64(mapping) + u64(page - 1), len: 3} }
		if variant == 8 { vector[first].len = 0; vector[count - 1].len = 0 }
		if variant == 9 { vector[count - 1] = IOVec{base: u64(-1)} }
		if variant == 11 { vector[first].base = u64(-1); vector[count - 1].len = u64(1) << 63 }
		header := if variant in [i32(10), 16]! { voidptr(1) } else { vector }
		flags := if variant == 12 { u64(0x80000000) } else { u64(0) }
		e := C.__errno_location(); *e = 0
		actual := receive(fds[0], version, header, if variant == 16 { 1025 } else { count }, flags); code := *e
		wanted := if variant in [i32(7), 8]! { isize(0) } else if variant == 14 { isize(2) } else if variant in [i32(15), 17]! { isize(1) } else { isize(-1) }
		wanted_code := if variant in [i32(6), 13]! { C.EAGAIN } else if variant in [i32(11), 16]! { C.EINVAL } else if variant == 12 { C.EOPNOTSUPP } else if wanted >= 0 { 0 } else { C.EFAULT }
		mut valid := actual == wanted && code == wanted_code
		if output[0] != if variant in [i32(3), 5, 14, 15, 17]! { u8(0x41) } else { u8(0) } { valid = false }
		if output[4] != if variant == 14 { u8(0x42) } else { u8(0) } { valid = false }
		for i in [i32(1), 2, 3, 5, 6, 7]! { if output[i] != 0 { valid = false } }
		if *(&u8(u64(mapping) + u64(page - 1))) != if variant == 4 { u8(0x41) } else if variant == 5 { u8(0x42) } else { u8(0) } { valid = false }
		if variant == 2 && *(&u8(mapping)) != 0 { valid = false }
		mut remaining := [8]u8{}
		preserved := variant in [i32(8), 9, 10, 11, 12, 16]!
		if !empty_queue {
			n := C.read(fds[0], &remaining[0], 8)
			if preserved {
				if n != 2 || remaining[0] != 0x41 || remaining[1] != 0x42 { valid = false }
				if C.read(fds[0], &remaining[0], 8) != 2 || remaining[0] != 0x58 || remaining[1] != 0x59 { valid = false }
			} else if n != 2 || remaining[0] != 0x58 || remaining[1] != 0x59 { valid = false }
		}
		if queued(fds[0]) != 0 { valid = false }
		if !valid && verbose { C.printf(c'LINUX IOVPACKET DETAIL: version=%d count=%d variant=%d result=%ld/%d expected=%ld/%d bytes=%02x,%02x boundary=%02x\n', version, count, variant, actual, code, wanted, wanted_code, i32(output[0]), i32(output[4]), i32(*(&u8(u64(mapping) + u64(page - 1))))); C.fflush(nil) }
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
fn storage_cycle(fds &i32, mapping voidptr, page usize) bool {
	unsafe {
		for kind in 0 .. 2 { for version in [i32(0), 1]! { for count in [i32(8), 9, 1024]! {
			for variant in 0 .. 18 {
				if variant == 12 && version == 0 { continue }
				if !transfer(&fds[kind * 2], mapping, page, version, count, i32(variant), false) { return false }
			}
		} } }
		return true
	}
}
fn storage(ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		mut fds := [4]i32{}; mut opened := 0
		defer { for i in 0 .. opened { C.close(fds[i]) } }
		for kind in 0 .. 2 {
			if C.socketpair(C.AF_UNIX, (if kind == 0 { C.SOCK_DGRAM } else { C.SOCK_SEQPACKET }) | C.SOCK_NONBLOCK, 0, &fds[kind * 2]) != 0 { return false }; opened += 2
		}
		page := usize(C.sysconf(C._SC_PAGESIZE))
		mapping := C.mmap(nil, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(mapping) == u64(-1) { return false }; defer { C.munmap(mapping, page * 2) }
		for _ in 0 .. 32 { if !storage_cycle(&fds[0], mapping, page) { return false } }
		C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}
		if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle(&fds[0], mapping, page) { return false } }
		C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}
		if !snapshot(observer, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for i in 0 .. int(before.rows) {
			if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { valid = false }
			C.printf(c'LINUX IOVPACKET SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i])
		}
		C.printf(c'LINUX IOVPACKET STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(300); mut bad := 0; mut cases := 0
		for kind in 0 .. 2 { for version in [i32(0), 1]! { for count in [i32(2), 8, 9, 513, 1024]! {
			for variant in 0 .. 18 {
				if variant == 12 && version == 0 { continue }; cases++
				if !probe(i32(kind), version, count, i32(variant), true) { bad++ }
			}
		} } }
		C.printf(c'LINUX IOVPACKET OUTCOMES: ordinary=%d cases=%d failures=%d\n', i32(ordinary), i32(cases), i32(bad)); C.fflush(nil)
		if bad != 0 || !storage(ordinary) { return false }; C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { return 1 }
			if child == 0 { C._exit(if qualify(ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1)
			if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX IOVPACKET FAIL: UNIX record copy faults or storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX IOVPACKET PASS: root/UID1000 readv/current-position preadv2 UNIX datagram and seqpacket copy faults consume only their selected record and return EFAULT even after committed prefixes; empty records and empty queues precede unmapped destinations; header/range/flag/empty-vector errors preserve queues; later untouched destinations do not fault; 200-cycle borrowed record queries and buffer/import cleanup retain flat storage')
		C.puts(c'LINUX IOVPACKET: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
