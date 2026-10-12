// SPDX-License-Identifier: GPL-2.0-or-later
module iovimportfixture

#include <errno.h>
#include <alloca.h>
#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
struct C.pollfd { fd i32 events i16 mut: revents i16 }
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
struct Operation {
	fd i32
	write bool
	count i32
	vector &IOVec
mut:
	ready i32
	result isize
	error i32
}
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.pthread_create(&C.pthread_t, voidptr, fn(voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.pipe(&i32) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C.open(&char, i32, ...) i32
fn C.lseek(i32, i64, i32) i64
fn C.poll(&C.pollfd, usize, i32) i32
fn C.ioctl(i32, usize, ...) i32
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.mprotect(voidptr, usize, i32) i32
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
fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn operation(argument voidptr) voidptr {
	unsafe {
		mut request := &Operation(argument)
		e := C.__errno_location(); *e = 0
		C.__atomic_store_n(&request.ready, 1, 5)
		request.result = C.syscall(isize(if request.write { C.SYS_writev } else { C.SYS_readv }), isize(request.fd), request.vector, isize(request.count))
		request.error = *e
	}
	return unsafe { nil }
}
fn ready(request &Operation) bool {
	unsafe {
		for _ in 0 .. 5000 {
			if C.__atomic_load_n(&request.ready, 5) == 1 { return true }
			C.usleep(1000)
		}
		return false
	}
}
fn queued(fd i32) i32 {
	unsafe {
		mut count := i32(-1)
		if C.ioctl(fd, usize(C.FIONREAD), &count) != 0 { return -1 }
		return count
	}
}
// A launched worker borrows the caller's stack and mappings. On a setup or
// join failure, terminate the isolated child rather than unwind that storage.
fn abandon(message &char) {
	unsafe { C.puts(message); C.fflush(nil); C._exit(2) }
}
fn vector_result(fd i32, write bool, pointer voidptr, count isize, wanted isize, error_code i32) bool {
	unsafe {
		e := C.__errno_location(); *e = 0
		actual := C.syscall(isize(if write { C.SYS_writev } else { C.SYS_readv }), isize(fd), pointer, count)
		if actual != wanted || *e != error_code {
			C.printf(c'LINUX IOVIMPORT DETAIL: vector fd=%d write=%d count=%ld result=%ld/%d expected=%ld/%d\n', fd, i32(write), count, actual, *e, wanted, error_code); C.fflush(nil); return false
		}
		return true
	}
}
fn storage_cycle() bool {
	unsafe {
		mut pipes := [2]i32{}
		if C.pipe(&pipes[0]) != 0 { return false }
		defer { C.close(pipes[0]); C.close(pipes[1]) }
		mut data := [u8(0x41), u8(0x42)]!
		mut vector := &IOVec(C.alloca(usize(1024 * sizeof(IOVec))))
		C.memset(vector, 0, usize(1024 * sizeof(IOVec)))
		empty := IOVec{base: 1}
		for write in [false, true]! {
			fd := if write { pipes[1] } else { pipes[0] }
			wrong := if write { pipes[0] } else { pipes[1] }
			if !vector_result(fd, write, nil, 0, 0, 0) || !vector_result(fd, write, &empty, 1, 0, 0)
				|| !vector_result(fd, write, voidptr(1), 1025, -1, C.EINVAL)
				|| !vector_result(fd, write, voidptr(1), 9, -1, C.EFAULT)
				|| !vector_result(fd, write, voidptr(1), 1024, -1, C.EFAULT)
				|| !vector_result(wrong, write, nil, 0, -1, C.EBADF) { return false }
			for count in [isize(2), 8, 9, 513, 1024]! {
				vector[0] = IOVec{base: 1, len: 1}; vector[1] = IOVec{}
				if !vector_result(fd, write, vector, count, -1, C.EFAULT) { return false }
				vector[0] = IOVec{base: u64(&data[0]), len: 1}
				vector[1] = IOVec{base: u64(&data[1]), len: u64(0x7fffffffffffffff)}
				if !vector_result(fd, write, vector, count, -1, C.EINVAL) { return false }
				vector[0].len = 0; vector[1].len = 0
				if !vector_result(fd, write, vector, count, 0, 0) { return false }
			}
		}
		for count in [isize(2), 8, 9, 513, 1024]! {
			data[0] = 0x41; data[1] = 0x42
			vector[0] = IOVec{base: u64(&data[0]), len: 1}; vector[1] = IOVec{base: u64(&data[1]), len: 1}
			if !vector_result(pipes[1], true, vector, count, 2, 0) { return false }
			data[0] = 0; data[1] = 0
			if !vector_result(pipes[0], false, vector, count, 2, 0) || data[0] != 0x41 || data[1] != 0x42 { return false }
		}
		return true
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
fn storage(ordinary bool) bool {
	unsafe {
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { return false }
		defer { C.close(fd) }
		for _ in 0 .. 32 { if !storage_cycle() { return false } }
		C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs))))
		*before = Slabs{}
		if !snapshot(fd, before) { return false }
		for _ in 0 .. 200 { if !storage_cycle() { return false } }
		C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		*after = Slabs{}
		if !snapshot(fd, after) || before.rows != after.rows { return false }
		mut valid := before.large >= after.large
		for i in 0 .. int(before.rows) {
			if before.sizes[i] != after.sizes[i] || after.live[i] > before.live[i] { valid = false }
			C.printf(c'LINUX IOVIMPORT SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i])
		}
		C.printf(c'LINUX IOVIMPORT STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn scratch_bytes(fd i32) ?u64 {
	unsafe {
		mut data := [4096]char{}
		length := C.pread(fd, &data[0], usize(data.len - 1), 0)
		if length <= 0 || length >= data.len { return none }
		data[int(length)] = 0
		mut position := 0
		for position < int(length) {
			mut objects := u64(0); mut bytes := u64(0)
			if C.sscanf(&data[position], c'scratch %lu %lu', &objects, &bytes) == 2 { return bytes }
			for position < int(length) && data[position] != char(10) { position++ }; position++
		}
		return none
	}
}
fn read_case(count i32, protect bool) bool {
	unsafe {
		page := usize(C.sysconf(C._SC_PAGESIZE))
		size := (usize(count) * usize(sizeof(IOVec)) + page - 1) / page * page
		headers := C.mmap(nil, size, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(headers) == u64(-1) { return false }
		defer { C.munmap(headers, size) }
		mut vector := &IOVec(headers)
		mut received := [2]u8{}
		mut alternate := u8(0)
		vector[0] = IOVec{base: u64(&received[0]), len: 1}; vector[1] = IOVec{base: u64(&received[1]), len: 1}
		if C.mprotect(headers, size, C.PROT_READ) != 0 { return false }
		mut pipes := [2]i32{}
		if C.pipe(&pipes[0]) != 0 { return false }
		observer := C.open(c'/proc/kernel-resources', C.O_RDONLY)
		if observer < 0 { return false }
		defer { C.close(observer) }
		baseline := scratch_bytes(observer) or { return false }
		mut request := Operation{fd: pipes[0], vector: vector, count: count}
		mut worker := C.pthread_t{}
		if C.pthread_create(&worker, nil, operation, &request) != 0 { return false }
		if !ready(&request) { abandon(c'LINUX IOVIMPORT FAIL: read worker start') }
		// The first one-byte read reserves 130 scratch bytes after header
		// import; vector reservations are multiples of128. The observer's
		// own read is present in both snapshots. This checkpoint works on
		// the unchanged kernel too, which has no vector reservation.
		mut entered := false
		for _ in 0 .. 5000 {
			current := scratch_bytes(observer) or { abandon(c'LINUX IOVIMPORT FAIL: scratch observer'); u64(0) }
			if current > baseline && (current - baseline) % 128 == 2 { entered = true; break }
			C.usleep(1000)
		}
		if !entered { abandon(c'LINUX IOVIMPORT FAIL: read import checkpoint') }
		if C.close(pipes[0]) != 0 { abandon(c'LINUX IOVIMPORT FAIL: reader close') }
		mut writer := C.pollfd{fd: pipes[1], events: i16(C.POLLOUT)}
		if C.poll(&writer, 1, 0) < 0 || writer.revents & i16(C.POLLERR) != 0 { abandon(c'LINUX IOVIMPORT FAIL: read synchronization') }
		if protect {
			if C.mprotect(headers, size, C.PROT_NONE) != 0 { abandon(c'LINUX IOVIMPORT FAIL: header protection') }
		} else {
			if C.mprotect(headers, size, 3) != 0 { abandon(c'LINUX IOVIMPORT FAIL: header mutation setup') }
			vector[1].base = u64(&alternate)
			if C.mprotect(headers, size, C.PROT_READ) != 0 { abandon(c'LINUX IOVIMPORT FAIL: header mutation protection') }
		}
		mut data := [u8(0x41), u8(0x42)]!
		if C.write(pipes[1], &data[0], 2) != 2 || C.close(pipes[1]) != 0
			|| C.pthread_join(worker, nil) != 0 { abandon(c'LINUX IOVIMPORT FAIL: read delivery or join') }
		valid := request.result == 2 && request.error == 0 && received[0] == 0x41 && received[1] == 0x42 && alternate == 0
		if !valid {
			C.printf(c'LINUX IOVIMPORT DETAIL: read count=%d protect=%d result=%ld/%d bytes=%02x,%02x alternate=%02x\n', count, i32(protect), request.result, request.error, i32(received[0]), i32(received[1]), i32(alternate)); C.fflush(nil)
		}
		return valid
	}
}
fn write_case(count i32, protect bool) bool {
	unsafe {
		page := usize(C.sysconf(C._SC_PAGESIZE))
		size := (usize(count) * usize(sizeof(IOVec)) + page - 1) / page * page
		first := usize(1024 * 1024 + 1)
		length := first + 4096
		headers := C.mmap(nil, size, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(headers) == u64(-1) { return false }
		defer { C.munmap(headers, size) }
		data := C.mmap(nil, length + 4096, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(data) == u64(-1) { return false }
		defer { C.munmap(data, length + 4096) }
		C.memset(data, 0x41, first); C.memset(voidptr(usize(data) + first), 0x42, 4096)
		C.memset(voidptr(usize(data) + length), 0x58, 4096)
		mut vector := &IOVec(headers)
		vector[0] = IOVec{base: u64(data), len: u64(first)}; vector[1] = IOVec{base: u64(data) + u64(first), len: 4096}
		if C.mprotect(headers, size, C.PROT_READ) != 0 { return false }
		mut pipes := [2]i32{}
		if C.pipe(&pipes[0]) != 0 { return false }
		mut request := Operation{fd: pipes[1], vector: vector, count: count, write: true}
		mut worker := C.pthread_t{}
		if C.pthread_create(&worker, nil, operation, &request) != 0 { return false }
		if !ready(&request) { abandon(c'LINUX IOVIMPORT FAIL: write worker start') }
		mut pending := i32(0)
		for _ in 0 .. 5000 { pending = queued(pipes[0]); if pending != 0 { break }; C.usleep(1000) }
		if pending <= 0 || C.close(pipes[1]) != 0 { abandon(c'LINUX IOVIMPORT FAIL: write synchronization or close') }
		if protect {
			if C.mprotect(headers, size, C.PROT_NONE) != 0 { abandon(c'LINUX IOVIMPORT FAIL: write header protection') }
		} else {
			if C.mprotect(headers, size, 3) != 0 { abandon(c'LINUX IOVIMPORT FAIL: write mutation setup') }
			vector[1].base = u64(data) + u64(length)
			if C.mprotect(headers, size, C.PROT_READ) != 0 { abandon(c'LINUX IOVIMPORT FAIL: write mutation protection') }
		}
		mut buffer := [32768]u8{}
		mut total := usize(0)
		mut content := true
		for {
			n := C.read(pipes[0], &buffer[0], usize(buffer.len))
			if n < 0 { abandon(c'LINUX IOVIMPORT FAIL: original pipe drain') }; if n == 0 { break }
			for i in 0 .. int(n) { if buffer[i] != if total + usize(i) < first { u8(0x41) } else { u8(0x42) } { content = false } }
			total += usize(n)
		}
		if C.pthread_join(worker, nil) != 0 { abandon(c'LINUX IOVIMPORT FAIL: write join') }
		if C.close(pipes[0]) != 0 { return false }
		valid := content && total == length && request.result == isize(length) && request.error == 0
		if !valid {
			C.printf(c'LINUX IOVIMPORT DETAIL: write count=%d protect=%d result=%ld/%d bytes=%lu content=%d\n', count, i32(protect), request.result, request.error, total, i32(content)); C.fflush(nil)
		}
		return valid
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(120)
		if !storage(ordinary) { C.puts(c'LINUX IOVIMPORT FAIL: imported-vector storage'); C.fflush(nil); return false }
		mut bad := i32(0)
		for round in 0 .. 2 {
			for count in [i32(2), 8, 9, 513, 1024]! { for protect in [false, true]! {
				if !write_case(count, protect) { bad++ }
				if !read_case(count, protect) { bad++ }
			} }
			C.printf(c'LINUX IOVIMPORT ROUND: ordinary=%d round=%d failures=%d\n', i32(ordinary), i32(round), bad); C.fflush(nil)
		}
		C.alarm(0)
		if bad != 0 { return false }
		C.printf(c'LINUX IOVIMPORT CASE: ordinary=%d reads=20 writes=20 PASS\n', i32(ordinary)); C.fflush(nil)
		return true
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		mut failed := false
		for ordinary in [true, false]! {
			C.fflush(nil)
			child := C.fork()
			if child < 0 { return 1 }
			if child == 0 { C._exit(if qualify(ordinary) { 0 } else { 1 }) }
			mut outcome := i32(-1)
			if C.waitpid(child, &outcome, 0) != child || outcome != 0 {
				C.printf(c'LINUX IOVIMPORT DETAIL: ordinary=%d outcome=%d\n', i32(ordinary), outcome); C.fflush(nil); failed = true
			}
		}
		if failed { C.puts(c'LINUX IOVIMPORT FAIL: vector snapshot or retirement'); C.fflush(nil); return 1 }
		C.puts(c'LINUX IOVIMPORT PASS: root/UID1000 blocked readv and multi-chunk writev use imported readonly 2/8/9/513/1024-entry vectors after user header mutation or protection; valid/empty/error storage stays flat')
		C.puts(c'LINUX IOVIMPORT: PASS'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
