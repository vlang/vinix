// SPDX-License-Identifier: GPL-2.0-or-later
module scalarabifixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct C.stat { st_size i64 }
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
fn C.dup(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.fstat(i32, &C.stat) i32
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
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn number(method i32) isize {
	return isize(match method { 0 { C.SYS_read } 1 { C.SYS_write } 2 { C.SYS_pread64 } 3 { C.SYS_pwrite64 } 4 { C.SYS_lseek } else { C.SYS_close } })
}
// Assign owners as soon as they are created. The caller closes its initialized
// descriptor slots on every exit; this helper retains no pointer or owner.
fn prepare(kind i32, method i32, anchor &i32, fds &i32) bool {
	unsafe {
		if kind in [i32(0), 2, 3]! {
			*anchor = C.open(c'/tmp/linux-scalarabi', C.O_RDWR); if *anchor < 0 { return false }
			mut data := [u8(0x41), 0x42, 0x43, 0x44]!
			if C.pwrite(*anchor, &data[0], 4, 0) != 4 || C.lseek(*anchor, 1, C.SEEK_SET) != 1 { return false }
			fds[0] = if kind == 0 { C.dup(*anchor) } else { C.open(c'/tmp/linux-scalarabi', if kind == 2 { C.O_PATH } else if method % 2 == 1 { C.O_RDONLY } else { C.O_WRONLY }) }
			if fds[0] < 0 { return false }
			if kind == 3 && C.lseek(fds[0], 1, C.SEEK_SET) != 1 { return false }
		} else if kind in [i32(4), 5]! {
			if C.pipe2(fds, C.O_NONBLOCK) != 0 { return false }
		} else if kind == 6 && C.socketpair(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_NONBLOCK, 0, fds) != 0 { return false }
		return true
	}
}
fn descriptor(fds &i32, kind i32, method i32) i32 {
	unsafe {
		if kind in [i32(4), 5]! { return fds[if method >= 4 { if kind == 5 { 1 } else { 0 } } else if (method % 2 == 1) != (kind == 5) { 1 } else { 0 }] }
		return fds[0]
	}
}
fn io_probe(kind i32, method i32, high u64, variant i32, verbose bool) bool {
	unsafe {
		mut anchor := i32(-1); mut fds := [i32(-1), i32(-1)]!
		defer { for fd in fds { if fd >= 0 { C.close(fd) } }; if anchor >= 0 { C.close(anchor) } }
		if !prepare(kind, method, &anchor, &fds[0]) { return false }
		write := method % 2 == 1; positioned := method >= 2
		mut data := [u8(0x41), 0x42, 0x43, 0x44, 0x58, 0x59, 0, 0]!
		if kind >= 4 && !write && C.write(fds[1], &data[0], 2) != 2 { return false }
		fd := descriptor(&fds[0], kind, method)
		count := if variant == 0 { u64(0) } else if variant in [i32(4), 5]! { u64(1) << 32 } else { u64(2) }
		position := if variant == 2 { i64(-1) } else if variant == 4 { i64(0x7fffffffffffffff) - 16 } else { i64(2) }
		buffer := if variant in [i32(0), 3, 4, 5]! { voidptr(1) } else if write { voidptr(&data[4]) } else { voidptr(&data[6]) }
		code := if variant == 2 || variant == 4 { C.EINVAL }
			else if kind in [i32(1), 2, 3]! || (kind == 5 && !positioned) { C.EBADF }
			else if positioned && kind >= 4 { C.ESPIPE }
			else if variant in [i32(3), 5]! { C.EFAULT } else { 0 }
		wanted := if code != 0 { isize(-1) } else if variant == 0 { isize(0) } else { isize(2) }
		e := C.__errno_location(); *e = 0
		actual := C.syscall(number(method), high | u64(u32(fd)), buffer, count, position); actual_code := *e
		mut valid := actual == wanted && actual_code == code
		if !write && wanted == 2 {
			first := if kind == 0 { if positioned { u8(0x43) } else { u8(0x42) } } else { u8(0x41) }
			second := if kind == 0 { if positioned { u8(0x44) } else { u8(0x43) } } else { u8(0x42) }
			if data[6] != first || data[7] != second { valid = false }
		} else if data[6] != 0 || data[7] != 0 { valid = false }
		if anchor >= 0 {
			mut bytes := [4]u8{}; mut metadata := C.stat{}
			if C.pread(anchor, &bytes[0], 4, 0) != 4 || C.fstat(anchor, &metadata) != 0 || metadata.st_size != 4 { valid = false }
			for index in 0 .. 4 {
				changed := write && wanted == 2 && index >= if positioned { 2 } else { 1 } && index < if positioned { 4 } else { 3 }
				value := if changed { data[4 + index - if positioned { 2 } else { 1 }] } else { data[index] }
				if bytes[index] != value { valid = false }
			}
			if C.lseek(anchor, 0, C.SEEK_CUR) != if kind == 0 && !positioned && wanted == 2 { 3 } else { 1 } { valid = false }
			if kind == 3 && C.lseek(fds[0], 0, C.SEEK_CUR) != 1 { valid = false }
		}
		if kind >= 4 {
			receiver := if write && kind == 6 { fds[1] } else { fds[0] }
			remaining := if write { if wanted == 2 { 2 } else { 0 } } else { if wanted == 2 { 0 } else { 2 } }
			mut queued := i32(-1); mut bytes := [8]u8{}
			if C.ioctl(receiver, usize(C.FIONREAD), &queued) != 0 || queued != remaining { valid = false }
			if remaining == 2 {
				if C.read(receiver, &bytes[0], 8) != 2 || bytes[0] != if write { u8(0x58) } else { u8(0x41) } || bytes[1] != if write { u8(0x59) } else { u8(0x42) } { valid = false }
			} else { *e = 0; if C.read(receiver, &bytes[0], 8) != -1 || *e != C.EAGAIN { valid = false } }
		}
		if !valid && verbose { C.printf(c'LINUX SCALARABI IO: kind=%d method=%d high=%016lx variant=%d result=%ld/%d expected=%ld/%d bytes=%02x,%02x\n', kind, method, high, variant, actual, actual_code, wanted, code, i32(data[6]), i32(data[7])); C.fflush(nil) }
		return valid
	}
}
fn seek_probe(kind i32, high u64, selector_high u64, offset i64, whence i32, verbose bool) bool {
	unsafe {
		mut anchor := i32(-1); mut fds := [i32(-1), i32(-1)]!
		defer { for fd in fds { if fd >= 0 { C.close(fd) } }; if anchor >= 0 { C.close(anchor) } }
		if !prepare(kind, 4, &anchor, &fds[0]) { return false }
		fd := descriptor(&fds[0], kind, 4)
		position := offset + if whence == C.SEEK_CUR { i64(1) } else if whence == C.SEEK_END { i64(4) } else { i64(0) }
		code := if kind in [i32(1), 2]! { C.EBADF } else if kind >= 4 { C.ESPIPE } else if whence !in [i32(0), 1, 2]! || position < 0 { C.EINVAL } else { 0 }
		wanted := if code != 0 { isize(-1) } else { isize(position) }
		e := C.__errno_location(); *e = 0
		actual := C.syscall(isize(C.SYS_lseek), high | u64(u32(fd)), offset, selector_high | u64(u32(whence))); actual_code := *e
		mut valid := actual == wanted && actual_code == code
		if kind in [i32(0), 3]! && C.lseek(fd, 0, C.SEEK_CUR) != if code == 0 { position } else { i64(1) } { valid = false }
		if anchor >= 0 {
			mut bytes := [4]u8{}; if C.pread(anchor, &bytes[0], 4, 0) != 4 { valid = false }
			for index in 0 .. 4 { if bytes[index] != u8(0x41 + index) { valid = false } }
		}
		if !valid && verbose { C.printf(c'LINUX SCALARABI SEEK: kind=%d high=%016lx selector_high=%016lx offset=%ld whence=%d result=%ld/%d expected=%ld/%d\n', kind, high, selector_high, offset, whence, actual, actual_code, wanted, code); C.fflush(nil) }
		return valid
	}
}
fn close_probe(kind i32, high u64, verbose bool) bool {
	unsafe {
		mut anchor := i32(-1); mut fds := [i32(-1), i32(-1)]!; mut alias := i32(-1)
		defer { if alias >= 0 { C.close(alias) }; for fd in fds { if fd >= 0 { C.close(fd) } }; if anchor >= 0 { C.close(anchor) } }
		if !prepare(kind, 5, &anchor, &fds[0]) { return false }
		fd := descriptor(&fds[0], kind, 5)
		if fd >= 0 { alias = C.dup(fd); if alias < 0 { return false } }
		e := C.__errno_location(); *e = 0
		actual := C.syscall(isize(C.SYS_close), high | u64(u32(fd))); actual_code := *e
		wanted := if kind == 1 { isize(-1) } else { isize(0) }; code := if kind == 1 { C.EBADF } else { 0 }
		mut valid := actual == wanted && actual_code == code
		if actual == 0 { for index in 0 .. 2 { if fds[index] == fd { fds[index] = -1 } } }
		if fd >= 0 {
			*e = 0; if C.fcntl(fd, C.F_GETFD) != -1 || *e != C.EBADF { valid = false }
			mut metadata := C.stat{}
			if C.fcntl(alias, C.F_GETFD) < 0 || C.fstat(alias, &metadata) != 0 { valid = false }
		}
		if !valid && verbose { C.printf(c'LINUX SCALARABI CLOSE: kind=%d high=%016lx result=%ld/%d expected=%ld/%d\n', kind, high, actual, actual_code, wanted, code); C.fflush(nil) }
		return valid
	}
}
fn sparse_probe(method i32, high u64, position i64, verbose bool) bool {
	unsafe {
		anchor := C.open(c'/tmp/linux-scalarabi-sparse', C.O_RDWR); if anchor < 0 { return false }; defer { C.close(anchor) }
		fd := C.dup(anchor); if fd < 0 { return false }; defer { C.close(fd) }
		mut seed := u8(0x42); mut byte := u8(if method == 2 { 0 } else { 0x41 })
		if C.pwrite(anchor, &seed, 1, position) != 1 || C.lseek(anchor, 1, C.SEEK_SET) != 1 { return false }
		e := C.__errno_location(); *e = 0
		actual := C.syscall(number(method), high | u64(u32(fd)), &byte, u64(1), position); code := *e
		mut valid := actual == 1 && code == 0 && (method != 2 || byte == 0x42) && C.lseek(anchor, 0, C.SEEK_CUR) == 1
		mut original := u8(0); mut low := u8(1); mut metadata := C.stat{}
		if C.pread(anchor, &original, 1, position) != 1 || original != if method == 2 { u8(0x42) } else { u8(0x41) } || C.pread(anchor, &low, 1, i64(u32(position))) != 1 || low != 0 || C.fstat(anchor, &metadata) != 0 || metadata.st_size < position + 1 { valid = false }
		if !valid && verbose { C.printf(c'LINUX SCALARABI SPARSE: method=%d high=%016lx position=%ld result=%ld/%d byte=%02x original=%02x low=%02x\n', method, high, position, actual, code, i32(byte), i32(original), i32(low)); C.fflush(nil) }
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
		high := u64(0x1234567800000000)
		for kind in [i32(0), 1, 2, 3]! { for method in 0 .. 4 { for variant in 0 .. 6 {
			if variant == 2 && method < 2 { continue }
			if variant == 3 && kind == 0 { continue }
			if variant == 4 && (method < 2 || kind != 0) { continue }
			if variant == 5 { continue }
			if !io_probe(kind, i32(method), high, i32(variant), false) { return false }
		} } }
		for method in [i32(0), 1]! { if !io_probe(4, method, high, 5, false) { return false } }
		for kind in [i32(0), 1, 2]! { for whence in [i32(0), 1, 2]! {
			if !seek_probe(kind, high, high, 1, whence, false) { return false }
		} }
		for kind in [i32(0), 2, 3]! { if !close_probe(kind, high, false) { return false } }
		for method in [i32(2), 3]! { if !sparse_probe(method, high, i64(1) << 32 | 123, false) { return false } }
		return true
	}
}
fn storage(ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY); if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !storage_cycle() { return false } }; C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}; if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle() { return false } }; C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}; if !snapshot(observer, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for index in 0 .. int(before.rows) {
			if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { valid = false }
			C.printf(c'LINUX SCALARABI SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200
', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX SCALARABI STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s
', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(300); mut bad := 0; mut cases := 0
		for kind in 0 .. 7 { for method in 0 .. 4 {
			for high in [u64(0), u64(1) << 32, 0x1234567800000000, 0x8000000000000000, 0xffffffff00000000]! { for variant in 0 .. 6 {
				if variant == 2 && method < 2 { continue }
				if variant == 3 && kind == 0 { continue }
				if variant == 4 && (method < 2 || kind != 0) { continue }
				if variant == 5 && (method >= 2 || kind != 4) { continue }
				cases++; if !io_probe(i32(kind), i32(method), high, i32(variant), true) { bad++ }
			} }
		} }
		for kind in 0 .. 7 { for high in [u64(0), u64(1) << 32, 0x1234567800000000, 0x8000000000000000, 0xffffffff00000000]! {
			for selector_high in [u64(0), u64(1) << 32, 0x1234567800000000, 0x8000000000000000, 0xffffffff00000000]! {
				for offset in [i64(0), 1, i64(1) << 32 | 17, -1]! { for whence in [i32(0), 1, 2]! {
					cases++; if !seek_probe(i32(kind), high, selector_high, offset, whence, true) { bad++ }
				} }
				if kind in [0, 1, 2]! { for whence in [i32(0x7fffffff), -1]! {
					cases++; if !seek_probe(i32(kind), high, selector_high, 0, whence, true) { bad++ }
				} }
			}
			cases++; if !close_probe(i32(kind), high, true) { bad++ }
		} }
		for method in [i32(2), 3]! { for high in [u64(0), u64(1) << 32, 0x1234567800000000, 0x8000000000000000, 0xffffffff00000000]! {
			for position in [i64(1) << 32 | 123, i64(1) << 33 | 17]! { cases++; if !sparse_probe(method, high, position, true) { bad++ } }
		} }
		C.printf(c'LINUX SCALARABI OUTCOMES: ordinary=%d cases=%d failures=%d
', i32(ordinary), i32(cases), i32(bad)); C.fflush(nil)
		if bad != 0 || !storage(ordinary) { return false }; C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		for path in [&char(c'/tmp/linux-scalarabi'), &char(c'/tmp/linux-scalarabi-sparse')]! {
			fd := C.open(path, C.O_CREAT | C.O_TRUNC | C.O_RDWR, u32(0o666)); if fd < 0 { return 1 }; C.close(fd)
			if C.chmod(path, u32(0o666)) != 0 { return 1 }
		}
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { return 1 }; if child == 0 { C._exit(if qualify(ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1); if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX SCALARABI FAIL: native descriptor/whence words or storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX SCALARABI PASS: root/UID1000 scalar read/write/pread64/pwrite64/close/lseek decode low32 descriptor and whence words; counts and signed offsets stay full-width; real bytes/cursors/queues, O_PATH/access/seek errors, alias-preserving closure and sparse positions pass; 200-cycle adapter/callee cleanup retains flat storage')
		C.puts(c'LINUX SCALARABI: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
