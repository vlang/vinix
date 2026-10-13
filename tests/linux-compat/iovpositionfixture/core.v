// SPDX-License-Identifier: GPL-2.0-or-later
module iovpositionfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct IOVec {
mut:
	base u64
	len u64
}
struct C.rlimit {
	rlim_cur u64
	rlim_max u64
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
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) isize
fn C.setrlimit(i32, &C.rlimit) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.chmod(&char, u32) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn number(write bool, version i32) isize {
	return isize(if version == 0 { if write { C.SYS_pwritev } else { C.SYS_preadv } }
		else { if write { C.SYS_pwritev2 } else { C.SYS_preadv2 } })
}
fn result(fd i32, write bool, version i32, vector voidptr, count isize, offset i64, wanted isize, code i32, label i32, verbose bool) bool {
	unsafe {
		e := C.__errno_location(); *e = 0
		actual := C.syscall(number(write, version), isize(fd), vector, count, u64(offset), u64(0x1234567800000000), isize(0))
		if actual == wanted && *e == code { return true }
		if verbose {
			C.printf(c'LINUX IOVPOSITION DETAIL: label=%d write=%d v=%d count=%ld offset=%ld result=%ld/%d expected=%ld/%d\n', label, i32(write), version, count, offset, actual, *e, wanted, code); C.fflush(nil)
		}
		return false
	}
}

// All imports are synchronous stack borrows. Unusable descriptors must win
// over bad headers/counts, even when the vector contains no payload bytes.
fn descriptor(kind i32, write bool, version i32, variant i32, sentinel bool, verbose bool) bool {
	unsafe {
		mut fds := [i32(-1), i32(-1)]!
		if kind > 0 && kind <= 3 {
			fds[0] = C.open(if kind == 2 { &char(c'/tmp') } else { &char(c'/tmp/linux-iovposition-data') },
				if kind <= 2 { C.O_PATH } else { if write { C.O_RDONLY } else { C.O_WRONLY } })
			if fds[0] < 0 { return false }
		} else if kind in [i32(4), 5]! {
			if C.pipe2(&fds[0], C.O_NONBLOCK) != 0 { return false }
		} else if kind >= 6 {
			if C.socketpair(C.AF_UNIX, (if kind == 6 { C.SOCK_STREAM } else { C.SOCK_DGRAM }) | C.SOCK_NONBLOCK, 0, &fds[0]) != 0 { return false }
		}
		defer { if fds[0] >= 0 { C.close(fds[0]) }; if fds[1] >= 0 { C.close(fds[1]) } }
		mut data := [u8(0x41), u8(0x42), u8(0), u8(0)]!
		if kind >= 4 && !write && C.write(fds[1], &data[0], 2) != 2 { return false }
		mut vector := &IOVec(C.alloca(usize(1024 * sizeof(IOVec))))
		C.memset(vector, 0, usize(1024 * sizeof(IOVec)))
		vector[0] = IOVec{base: u64(&data[2])}
		count := match variant { 0 { isize(0) } 2 { isize(1024) } 4 { isize(1025) } 5 { isize(2) } else { isize(1) } }
		if variant == 5 { vector[0].len = 1; vector[1] = IOVec{base: u64(&data[3]), len: 1} }
		fd := if kind in [i32(4), 5]! { fds[if write != (kind == 5) { 1 } else { 0 }] } else { fds[0] }
		valid := result(fd, write, version, if variant in [i32(0), 3, 4]! { voidptr(1) } else { vector }, count,
			if sentinel { -1 } else { 5 }, -1, if kind <= 3 || sentinel { C.EBADF } else { C.ESPIPE }, kind * 10 + variant, verbose)
		mut untouched := data[2] == 0 && data[3] == 0
		if kind >= 4 {
			mut queued := i32(-1)
			if C.ioctl(fds[0], usize(C.FIONREAD), &queued) != 0 { return false }
			untouched = untouched && queued == if write { 0 } else { 2 }
		}
		if !untouched && verbose { C.printf(c'LINUX IOVPOSITION MUTATION: descriptor kind=%d write=%d v=%d variant=%d\n', kind, i32(write), version, variant); C.fflush(nil) }
		return valid && untouched
	}
}

fn range_case(fd i32, limit u64, write bool, version i32, count i32, variant i32, verbose bool) bool {
	unsafe {
		mut data := [u8(0x41), u8(0x42), u8(0x43), u8(0x44)]!
		if C.pwrite(fd, &data[0], 4, 0) != 4 || C.lseek(fd, 3, C.SEEK_SET) != 3 { return false }
		mut byte := u8(if write { 0x58 } else { 0 })
		mut vector := &IOVec(C.alloca(usize(count) * sizeof(IOVec)))
		C.memset(vector, 0, usize(count) * sizeof(IOVec)); vector[0] = IOVec{base: u64(&byte), len: 1}
		vector[count - 1] = match variant {
			0 { IOVec{base: u64(-1), len: 1} }
			1 { IOVec{base: u64(-1)} }
			2 { IOVec{base: limit - 1, len: 2} }
			3 { IOVec{base: u64(&byte), len: u64(0x7fffffffffffffff)} }
			else { IOVec{base: u64(&byte), len: u64(1) << 63} }
		}
		if variant == 4 { vector[0].base = u64(-1) }
		valid := result(fd, write, version, vector, isize(count), 0, -1,
			if variant == 4 { C.EINVAL } else { C.EFAULT }, 100 + variant, verbose)
		C.memset(&data[0], 0, 4)
		untouched := (write || byte == 0) && C.lseek(fd, 0, C.SEEK_CUR) == 3 && C.pread(fd, &data[0], 4, 0) == 4
			&& data[0] == 0x41 && data[1] == 0x42 && data[2] == 0x43 && data[3] == 0x44
		if !untouched && verbose { C.printf(c'LINUX IOVPOSITION MUTATION: range write=%d v=%d count=%d variant=%d byte=%02x\n', i32(write), version, count, variant, i32(byte)); C.fflush(nil) }
		return valid && untouched
	}
}

// Read-only header pages must import successfully on both fast and heap paths.
fn normal(fd i32, write bool, version i32, count i32, verbose bool) bool {
	unsafe {
		page := usize(C.sysconf(C._SC_PAGESIZE)); bytes := (usize(count) * sizeof(IOVec) + page - 1) & ~(page - 1)
		mut vector := &IOVec(C.mmap(nil, bytes, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		if u64(vector) == u64(-1) { return false }; defer { C.munmap(vector, bytes) }
		mut data := [u8(0x4c), u8(0x4f), u8(0x41), u8(0x42), u8(0), u8(0)]!
		if C.pwrite(fd, &data[0], 2, 0) != 2 || C.lseek(fd, 3, C.SEEK_SET) != 3 { return false }
		vector[0] = IOVec{base: u64(if write { &data[2] } else { &data[4] }), len: 1}
		vector[count - 1] = IOVec{base: u64(if write { &data[3] } else { &data[5] }), len: 1}
		if C.mprotect(vector, bytes, C.PROT_READ) != 0 { return false }
		valid := result(fd, write, version, vector, isize(count), 0, 2, 0, 200, verbose)
			&& C.lseek(fd, 0, C.SEEK_CUR) == 3
		return valid && if write { C.pread(fd, &data[4], 2, 0) == 2 && data[4] == 0x41 && data[5] == 0x42 }
			else { data[4] == 0x4c && data[5] == 0x4f }
	}
}
fn payload(fd i32, write bool, version i32) bool {
	unsafe {
		page := usize(C.sysconf(C._SC_PAGESIZE))
		guard := C.mmap(nil, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(guard) == u64(-1) { return false }; defer { C.munmap(guard, page) }
		mut seed := [u8(0x41), u8(0x42)]!
		if C.pwrite(fd, &seed[0], 2, 0) != 2 || C.lseek(fd, 3, C.SEEK_SET) != 3 { return false }
		mut byte := u8(if write { 0x41 } else { 0 })
		vector := [IOVec{base: u64(&byte), len: 1}, IOVec{base: u64(guard), len: 1}]!
		return result(fd, write, version, &vector[0], 2, 0, 1, 0, 210, true)
			&& byte == 0x41 && C.lseek(fd, 0, C.SEEK_CUR) == 3
	}
}
fn overflow(fd i32, write bool, version i32, verbose bool) bool {
	unsafe {
		mut byte := u8(0)
		vector := [IOVec{base: u64(&byte), len: 1}, IOVec{base: u64(&byte), len: 1}]!
		return result(fd, write, version, &vector[0], 2, i64(0x7ffffffffffffffe), -1, C.EINVAL, 220, verbose)
			&& byte == 0 && C.lseek(fd, 0, C.SEEK_CUR) == 3
	}
}
fn limits(limit u64, version i32, verbose bool) bool {
	unsafe {
		fd := C.open(c'/tmp/linux-iovposition-empty', C.O_RDONLY)
		if fd < 0 { return false }; defer { C.close(fd) }
		page := u64(C.sysconf(C._SC_PAGESIZE)); cap := u64(0x7fffffff) & ~(page - 1)
		mut vector := &IOVec(C.alloca(usize(2 * sizeof(IOVec)))); C.memset(vector, 0, usize(2 * sizeof(IOVec)))
		mut valid := true
		for count in [isize(1), 2]! { for variant in 0 .. 6 {
			vector[0] = match variant {
				0 { IOVec{base: limit - cap, len: cap} }
				1 { IOVec{base: limit - cap, len: cap + 1} }
				2 { IOVec{base: limit - cap + 1, len: cap + 1} }
				3 { IOVec{base: u64(&vector[0]), len: u64(0x7fffffffffffffff)} }
				4 { IOVec{base: limit} }
				else { IOVec{base: limit + 1} }
			}
			vector[1] = IOVec{}
			fault := variant == 2 || variant == 5 || (count > 1 && variant in [1, 3]!)
			if !result(fd, false, version, vector, count, 0, if fault { -1 } else { 0 }, if fault { C.EFAULT } else { 0 }, 300 + variant, verbose) { valid = false }
		} }
		vector[0] = IOVec{base: u64(&vector[0]), len: cap}; vector[1] = IOVec{base: u64(-1), len: 1}
		if !result(fd, false, version, vector, 2, 0, -1, C.EFAULT, 310, verbose) { valid = false }
		vector[1] = IOVec{base: limit - cap, len: cap}
		if !result(fd, false, version, vector, 2, 0, 0, 0, 311, verbose) { valid = false }
		if verbose { C.printf(c'LINUX IOVPOSITION LIMIT: v=%d page=%lu max_rw_count=%lu checks=14 %s\n', version, page, cap, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil) }
		return valid
	}
}

fn native_limit() ?u64 {
	unsafe {
		page := usize(C.sysconf(C._SC_PAGESIZE))
		mut limit := u64(1) << 47
		$if amd64 {
			e := C.__errno_location(); *e = 0
			upper := C.mmap(voidptr(u64(1) << 55), page, C.PROT_NONE,
				C.MAP_PRIVATE | C.MAP_ANONYMOUS | C.MAP_FIXED_NOREPLACE, -1, 0)
			if u64(upper) != u64(-1) {
				valid := u64(upper) == u64(1) << 55
				if C.munmap(upper, page) != 0 || !valid { return none }
				limit = u64(1) << 56
			} else if *e != C.EINVAL && *e != C.ENOMEM { return none }
		}
		// Verify the last user page can be mapped, and the next cannot. These
		// probes are independent of vector import, and precede retention warmup.
		last := C.mmap(voidptr(limit - u64(page)), page, C.PROT_NONE,
			C.MAP_PRIVATE | C.MAP_ANONYMOUS | C.MAP_FIXED_NOREPLACE, -1, 0)
		if u64(last) == u64(-1) { return none }
		valid := u64(last) == limit - u64(page)
		if C.munmap(last, page) != 0 || !valid { return none }
		e := C.__errno_location(); *e = 0
		outside := C.mmap(voidptr(limit), page, C.PROT_NONE,
			C.MAP_PRIVATE | C.MAP_ANONYMOUS | C.MAP_FIXED_NOREPLACE, -1, 0)
		if u64(outside) != u64(-1) { C.munmap(outside, page); return none }
		if *e != C.EINVAL && *e != C.ENOMEM { return none }
		C.printf(c'LINUX IOVPOSITION ADDRESS: user_limit=%lu last_page=mapped next_page=refused\n', limit); C.fflush(nil)
		return limit
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

fn storage_cycle(fd i32, limit u64) bool {
	unsafe {
		for count in [i32(2), 8, 9, 513, 1024]! { for write in [false, true]! { for version in [i32(0), 1]! {
			if !normal(fd, write, version, count, false) { return false }
			for variant in [i32(0), 1, 4]! { if !range_case(fd, limit, write, version, count, variant, false) { return false } }
		} } }
		for write in [false, true]! {
			if !descriptor(1, write, 1, 0, false, false) || !descriptor(3, write, 1, 3, false, false)
				|| !descriptor(5, write, 1, 3, true, false) || !overflow(fd, write, 1, false) { return false }
		}
		return limits(limit, 1, false)
	}
}
fn storage(file_fd i32, limit u64, ordinary bool) bool {
	unsafe {
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { return false }; defer { C.close(fd) }
		for _ in 0 .. 32 { if !storage_cycle(file_fd, limit) { return false } }
		C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}
		if !snapshot(fd, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle(file_fd, limit) { return false } }
		C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}
		if !snapshot(fd, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for i in 0 .. int(before.rows) {
			if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { valid = false }
			C.printf(c'LINUX IOVPOSITION SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i])
		}
		C.printf(c'LINUX IOVPOSITION STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		// Bound file growth on the unchanged overflow control. Linux verifies
		// the vector's complete offset range before applying this resource limit.
		limit_size := C.rlimit{rlim_cur: 1024, rlim_max: 1024}
		if C.setrlimit(C.RLIMIT_FSIZE, &limit_size) != 0 { return false }
		C.alarm(240); limit := native_limit() or { return false }
		fd := C.open(c'/tmp/linux-iovposition-data', C.O_RDWR)
		if fd < 0 { return false }; defer { C.close(fd) }
		mut descriptor_bad := 0; mut sentinel_bad := 0; mut range_bad := 0; mut normal_bad := 0; mut partial_bad := 0; mut overflow_bad := 0; mut limits_bad := 0
		for kind in 0 .. 8 { for write in [false, true]! { for version in [i32(0), 1]! { for variant in 0 .. 6 {
			if !descriptor(i32(kind), write, version, i32(variant), false, true) { descriptor_bad++ }
		} } } }
		for kind in [i32(0), 1, 3, 5]! { for write in [false, true]! { for variant in 0 .. 6 {
			if !descriptor(kind, write, 1, i32(variant), true, true) { sentinel_bad++ }
		} } }
		for count in [i32(2), 8, 9, 513, 1024]! { for write in [false, true]! { for version in [i32(0), 1]! {
			if !normal(fd, write, version, count, true) { normal_bad++ }
			for variant in 0 .. 5 { if !range_case(fd, limit, write, version, count, i32(variant), true) { range_bad++ } }
		} } }
		for write in [false, true]! { for version in [i32(0), 1]! {
			if !payload(fd, write, version) { partial_bad++ }
			if !overflow(fd, write, version, true) { overflow_bad++ }
		} }
		for version in [i32(0), 1]! { if !limits(limit, version, true) { limits_bad++ } }
		C.printf(c'LINUX IOVPOSITION OUTCOMES: ordinary=%d descriptor=192/%d sentinel=48/%d range=100/%d normal=20/%d partial=4/%d overflow=4/%d limit_checks=28 failed_limit_groups=%d\n', i32(ordinary), i32(descriptor_bad), i32(sentinel_bad), i32(range_bad), i32(normal_bad), i32(partial_bad), i32(overflow_bad), i32(limits_bad)); C.fflush(nil)
		if descriptor_bad != 0 || sentinel_bad != 0 || range_bad != 0 || normal_bad != 0 || partial_bad != 0 || overflow_bad != 0 || limits_bad != 0 { return false }
		if !storage(fd, limit, ordinary) { C.puts(c'LINUX IOVPOSITION FAIL: repeated positioned-vector storage'); C.fflush(nil); return false }
		C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		for path in [&char(c'/tmp/linux-iovposition-data'), &char(c'/tmp/linux-iovposition-empty')]! {
			fd := C.open(path, C.O_CREAT | C.O_TRUNC | C.O_RDWR, u32(0o666))
			if fd < 0 { return 1 }; if C.close(fd) != 0 || C.chmod(path, u32(0o666)) != 0 { return 1 }
		}
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork(); if child < 0 { return 1 }
			if child == 0 { C._exit(if qualify(ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1)
			if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX IOVPOSITION FAIL: positioned vector errors, ranges or storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX IOVPOSITION PASS: root/UID1000 native positioned vectors check descriptor/access/seek before headers, reject every original range and signed length before I/O, cap EOF transfers, validate the whole signed position, accept read-only fast/large headers and return copied payload prefixes without moving the cursor; repeated valid/error imports release all measured storage')
		C.puts(c'LINUX IOVPOSITION: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
