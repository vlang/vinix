// SPDX-License-Identifier: GPL-2.0-or-later
module iovrangefixture

#include <errno.h>
#include <alloca.h>
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
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.pipe(&i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C.open(&char, i32, ...) i32
fn C.lseek(i32, i64, i32) i64
fn C.ioctl(i32, usize, ...) i32
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) isize
fn C.memset(voidptr, i32, usize) voidptr
fn C.alloca(usize) voidptr
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.chmod(&char, u32) i32
fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

// Measure the active native address range through fixed mmap probes rather
// than infer it from CPU capability: x86 QEMU can boot four or five levels.
// AArch64's native kernel has a 47-bit range. Tagged pointers are separate.
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
		C.printf(c'LINUX IOVRANGE ADDRESS: user_limit=%lu last_page=mapped next_page=refused\n', limit); C.fflush(nil)
		return limit
	}
}

fn result(fd i32, write bool, vector voidptr, count isize, wanted isize, code i32, label i32, verbose bool) bool {
	unsafe {
		e := C.__errno_location(); *e = 0
		actual := C.syscall(isize(if write { C.SYS_writev } else { C.SYS_readv }), isize(fd), vector, count)
		if actual == wanted && *e == code { return true }
		if verbose {
			C.printf(c'LINUX IOVRANGE DETAIL: label=%d write=%d count=%ld result=%ld/%d expected=%ld/%d\n', label, i32(write), count, actual, *e, wanted, code); C.fflush(nil)
		}
		return false
	}
}

// A later malformed canonical range must be refused before touching the
// first byte, shared offset, pipe queue, or stream/datagram message.
fn range_case(user_limit u64, kind i32, write bool, count i32, variant i32, verbose bool) bool {
	unsafe {
		mut fds := [i32(-1), i32(-1)]!
		if kind == 0 {
			fds[0] = C.open(c'/tmp/linux-iovrange-data', C.O_RDWR)
			if fds[0] < 0 { return false }
		} else if kind == 1 {
			if C.pipe(&fds[0]) != 0 { return false }
		} else if C.socketpair(C.AF_UNIX, if kind == 2 { C.SOCK_STREAM } else { C.SOCK_DGRAM }, 0, &fds[0]) != 0 { return false }
		defer { C.close(fds[0]); if fds[1] >= 0 { C.close(fds[1]) } }
		mut data := [u8(0x41), u8(0x42), u8(0x43), u8(0x44)]!
		if (kind == 0 || !write) && C.write(if kind == 0 { fds[0] } else { fds[1] }, &data[0], 4) != 4 { return false }
		if kind == 0 && C.lseek(fds[0], 0, C.SEEK_SET) != 0 { return false }
		mut byte := if write { u8(0x58) } else { u8(0) }
		mut vector := &IOVec(C.alloca(usize(count) * usize(sizeof(IOVec))))
		C.memset(vector, 0, usize(count) * usize(sizeof(IOVec)))
		vector[0] = IOVec{base: u64(&byte), len: 1}
		vector[count - 1] = match variant {
			0 { IOVec{base: u64(-1)} }
			1 { IOVec{base: user_limit - 1, len: 2} }
			2 { IOVec{base: u64(-2), len: 4} }
			3 { IOVec{base: u64(&byte), len: u64(0x7fffffffffffffff)} }
			else { IOVec{base: u64(&byte), len: u64(1) << 63} }
		}
		// All signed lengths are checked before any payload range: a later
		// negative length takes precedence over an earlier malformed range.
		if variant == 4 { vector[0].base = u64(-1) }
		valid_result := result(if kind == 0 || !write { fds[0] } else { fds[1] }, write, vector, isize(count), -1,
			if variant == 4 { C.EINVAL } else { C.EFAULT }, kind * 10 + variant, verbose)
		mut unchanged := write || byte == 0
		mut remaining := i32(-1)
		if kind == 0 {
			remaining = i32(C.lseek(fds[0], 0, C.SEEK_CUR))
			C.memset(&data[0], 0, 4)
			unchanged = unchanged && remaining == 0 && C.pread(fds[0], &data[0], 4, 0) == 4
				&& data[0] == 0x41 && data[1] == 0x42 && data[2] == 0x43 && data[3] == 0x44
		} else {
			if C.ioctl(fds[0], usize(C.FIONREAD), &remaining) != 0 { return false }
			unchanged = unchanged && remaining == if write { 0 } else { 4 }
			if !write && remaining == 4 {
				C.memset(&data[0], 0, 4)
				unchanged = unchanged && C.read(fds[0], &data[0], 4) == 4 && data[0] == 0x41
					&& data[1] == 0x42 && data[2] == 0x43 && data[3] == 0x44
			}
		}
		if !unchanged && verbose {
			C.printf(c'LINUX IOVRANGE MUTATION: kind=%d write=%d count=%d variant=%d byte=%02x offset_or_queued=%d\n', kind, i32(write), count, variant, i32(byte), remaining); C.fflush(nil)
		}
		return valid_result && unchanged
	}
}

// EOF needs no 2 GiB allocation. A single segment clamps before its range
// check, whereas multiple segments validate their original full ranges.
fn limits(user_limit u64, verbose bool) bool {
	unsafe {
		fd := C.open(c'/tmp/linux-iovrange-empty', C.O_RDONLY)
		if fd < 0 { return false }
		defer { C.close(fd) }
		page := u64(C.sysconf(C._SC_PAGESIZE))
		cap := u64(0x7fffffff) & ~(page - 1)
		mut vector := &IOVec(C.alloca(usize(2 * sizeof(IOVec))))
		C.memset(vector, 0, usize(2 * sizeof(IOVec)))
		mut valid := true
		for count in [isize(1), 2]! {
			for variant in 0 .. 6 {
				vector[0] = match variant {
					0 { IOVec{base: user_limit - cap, len: cap} }
					1 { IOVec{base: user_limit - cap, len: cap + 1} }
					2 { IOVec{base: user_limit - cap + 1, len: cap + 1} }
					3 { IOVec{base: u64(&vector[0]), len: u64(0x7fffffffffffffff)} }
					4 { IOVec{base: user_limit} }
					else { IOVec{base: user_limit + 1} }
				}
				vector[1] = IOVec{}
				fault := variant == 2 || variant == 5 || (count > 1 && variant in [1, 3]!)
				if !result(fd, false, &vector[0], count, if fault { -1 } else { 0 }, if fault { C.EFAULT } else { 0 }, 100 + variant, verbose) { valid = false }
			}
		}
		// A tail beyond the transfer cap still has to pass access_ok.
		vector[0] = IOVec{base: user_limit - cap, len: cap}
		vector[1] = IOVec{base: u64(-1)}
		if !result(fd, false, &vector[0], 2, -1, C.EFAULT, 110, verbose) { valid = false }
		// Valid ranges may sum above the cap; they are truncated, not rejected.
		vector[1] = IOVec{base: user_limit - cap, len: cap}
		if !result(fd, false, &vector[0], 2, 0, 0, 111, verbose) { valid = false }
		if C.lseek(fd, 0, C.SEEK_CUR) != 0 { return false }
		if verbose { C.printf(c'LINUX IOVRANGE LIMIT: page=%lu max_rw_count=%lu checks=14 %s\n', page, cap, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil) }
		return valid
	}
}

// Page permissions are checked at copy time. A readable first iovec followed
// by an in-range PROT_NONE destination returns the copied prefix on a file.
fn payload_control() bool {
	unsafe {
		page := usize(C.sysconf(C._SC_PAGESIZE))
		guard := C.mmap(nil, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(guard) == u64(-1) { return false }
		defer { C.munmap(guard, page) }
		fd := C.open(c'/tmp/linux-iovrange-data', C.O_RDONLY)
		if fd < 0 { return false }
		defer { C.close(fd) }
		mut byte := u8(0)
		vector := [IOVec{base: u64(&byte), len: 1}, IOVec{base: u64(guard), len: 1}]!
		return result(fd, false, &vector[0], 2, 1, 0, 120, true) && byte == 0x41
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
fn storage_cycle(user_limit u64) bool {
	unsafe {
		for count in [i32(2), 8, 9, 513, 1024]! {
			for variant in [i32(0), 3, 4]! {
				for write in [false, true]! {
					if !range_case(user_limit, 1, write, count, variant, false) { return false }
				}
			}
		}
		return limits(user_limit, false)
	}
}
fn storage(user_limit u64, ordinary bool) bool {
	unsafe {
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { return false }
		defer { C.close(fd) }
		for _ in 0 .. 32 { if !storage_cycle(user_limit) { return false } }
		C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}
		if !snapshot(fd, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle(user_limit) { return false } }
		C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}
		if !snapshot(fd, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for i in 0 .. int(before.rows) {
			if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { valid = false }
			C.printf(c'LINUX IOVRANGE SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i])
		}
		C.printf(c'LINUX IOVRANGE STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(120)
		user_limit := native_limit() or { return false }
		mut failures := 0
		for count in [i32(2), 8, 9, 513, 1024]! {
			for kind in 0 .. 4 { for write in [false, true]! { for variant in 0 .. 5 {
				if !range_case(user_limit, i32(kind), write, count, i32(variant), true) { failures++ }
			} } }
		}
		if !limits(user_limit, true) { failures++ }
		if !payload_control() { failures++ }
		C.printf(c'LINUX IOVRANGE CASE: ordinary=%d checks=215 failures=%d\n', i32(ordinary), i32(failures)); C.fflush(nil)
		if failures != 0 { return false }
		if !storage(user_limit, ordinary) { C.puts(c'LINUX IOVRANGE FAIL: range import storage'); C.fflush(nil); return false }
		C.alarm(0); return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		for path in [&char(c'/tmp/linux-iovrange-data'), &char(c'/tmp/linux-iovrange-empty')]! {
			fd := C.open(path, C.O_CREAT | C.O_TRUNC | C.O_RDWR, u32(0o666))
			if fd < 0 || C.close(fd) != 0 || C.chmod(path, u32(0o666)) != 0 { return 1 }
		}
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil); child := C.fork()
			if child < 0 { return 1 }
			if child == 0 { C._exit(if qualify(ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1)
			if C.waitpid(child, &outcome, 0) != child || outcome != 0 { failed = true }
		}
		if failed { C.puts(c'LINUX IOVRANGE FAIL: native range/error/count semantics'); C.fflush(nil); return 1 }
		C.puts(c'LINUX IOVRANGE PASS: root/UID1000 native readv/writev validate all signed lengths and canonical ranges before file/pipe/stream/datagram I/O; zero-length invalid tails fail, original queues/offsets/content survive refusal; single-segment page-size transfer cap precedes range checks, multiple segments validate original ranges; in-range page faults retain copied prefixes; import storage stays flat')
		C.puts(c'LINUX IOVRANGE: PASS'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
