// SPDX-License-Identifier: GPL-2.0-or-later
module iovpinfixture

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
struct IOVec { base u64 len u64 }
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
		request.result = C.syscall(isize(if request.write { C.SYS_writev } else { C.SYS_readv }), isize(request.fd), request.vector, isize(2))
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
			C.printf(c'LINUX IOVPIN DETAIL: vector fd=%d write=%d count=%ld result=%ld/%d expected=%ld/%d\n', fd, i32(write), count, actual, *e, wanted, error_code); C.fflush(nil); return false
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
		mut vector := [IOVec{base: u64(&data[0]), len: 1}, IOVec{base: u64(&data[1]), len: 1}]!
		empty := IOVec{base: 1}
		bad := IOVec{base: 1, len: 1}
		for write in [false, true]! {
			fd := if write { pipes[1] } else { pipes[0] }
			wrong := if write { pipes[0] } else { pipes[1] }
			if !vector_result(fd, write, nil, 0, 0, 0) || !vector_result(fd, write, &empty, 1, 0, 0)
				|| !vector_result(fd, write, voidptr(1), 1025, -1, C.EINVAL)
				|| !vector_result(fd, write, voidptr(1), 1, -1, C.EFAULT)
				|| !vector_result(fd, write, &bad, 1, -1, C.EFAULT)
				|| !vector_result(wrong, write, nil, 0, -1, C.EBADF) { return false }
		}
		if !vector_result(pipes[1], true, &vector[0], 2, 2, 0) { return false }
		data[0] = 0; data[1] = 0
		if !vector_result(pipes[0], false, &vector[0], 2, 2, 0) || data[0] != 0x41 || data[1] != 0x42 { return false }
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
			C.printf(c'LINUX IOVPIN SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i])
		}
		C.printf(c'LINUX IOVPIN STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn read_case(kind i32) bool {
	unsafe {
		mut original := [2]i32{}
		mut other := [2]i32{}
		if C.pipe(&original[0]) != 0 || C.pipe(&other[0]) != 0 { return false }
		mut replacement := [u8(0x58), u8(0x59)]!
		if C.write(other[1], &replacement[0], 2) != 2 || C.close(other[1]) != 0 { return false }
		mut received := [2]u8{}
		mut vector := [IOVec{base: u64(&received[0]), len: 1}, IOVec{base: u64(&received[1]), len: 1}]!
		mut request := Operation{fd: original[0], vector: &vector[0]}
		mut worker := C.pthread_t{}
		if C.pthread_create(&worker, nil, operation, &request) != 0 { return false }
		if !ready(&request) { abandon(c'LINUX IOVPIN FAIL: read worker did not start') }
		// A settling delay alone is not the synchronization oracle. After
		// dropping the only user reader, POLLERR must still be absent: only
		// the running syscall's reference can keep that reader alive.
		C.usleep(20000)
		mut file := i32(-1)
		if kind == 0 {
			if C.dup2(other[0], original[0]) != original[0] { abandon(c'LINUX IOVPIN FAIL: read replacement setup') }
		} else if kind == 1 {
			file = i32(C.syscall(isize(C.SYS_memfd_create), c'iovpin-replacement', isize(0)))
			if file < 0 || C.write(file, &replacement[0], 2) != 2 || C.lseek(file, 0, C.SEEK_SET) != 0
				|| C.dup2(file, original[0]) != original[0] { abandon(c'LINUX IOVPIN FAIL: file replacement setup') }
		} else if kind == 2 {
			if C.dup2(original[1], original[0]) != original[0] { abandon(c'LINUX IOVPIN FAIL: wrong-mode read replacement') }
		} else if C.close(original[0]) != 0 { abandon(c'LINUX IOVPIN FAIL: reader close') }
		mut writer := C.pollfd{fd: original[1], events: i16(C.POLLOUT)}
		if C.poll(&writer, 1, 0) < 0 || writer.revents & i16(C.POLLERR) != 0 {
			abandon(c'LINUX IOVPIN FAIL: read did not hold the original endpoint before replacement')
		}
		mut input := [u8(0x41), u8(0x42)]!
		if C.write(original[1], &input[0], 2) != 2 || C.close(original[1]) != 0
			|| C.pthread_join(worker, nil) != 0 { abandon(c'LINUX IOVPIN FAIL: read delivery or join') }
		mut valid := request.result == 2 && request.error == 0 && received[0] == 0x41 && received[1] == 0x42
		mut untouched := [2]u8{}
		if C.read(other[0], &untouched[0], 2) != 2 || untouched[0] != 0x58 || untouched[1] != 0x59 { valid = false }
		if file >= 0 {
			if C.lseek(file, 0, C.SEEK_CUR) != 0 || C.read(file, &untouched[0], 2) != 2
				|| untouched[0] != 0x58 || untouched[1] != 0x59 { valid = false }
			if C.close(file) != 0 { return false }
		}
		if kind != 3 && C.close(original[0]) != 0 { return false }
		if C.close(other[0]) != 0 { return false }
		if !valid {
			C.printf(c'LINUX IOVPIN DETAIL: read kind=%d result=%ld/%d bytes=%02x,%02x expected=2/0 41,42\n', kind, request.result, request.error, i32(received[0]), i32(received[1])); C.fflush(nil)
		}
		return valid
	}
}
fn write_case(kind i32) bool {
	unsafe {
		length := usize(1024 * 1024 + 1 + 4096)
		first := usize(512 * 1024)
		data := C.mmap(nil, length, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(data) == u64(-1) { return false }
		// The mapping and both vectors remain live until the worker joins.
		defer { C.munmap(data, length) }
		C.memset(data, 0x41, first); C.memset(voidptr(usize(data) + first), 0x42, length - first)
		mut original := [2]i32{}
		mut other := [2]i32{}
		if C.pipe(&original[0]) != 0 || C.pipe(&other[0]) != 0 { return false }
		mut vector := [IOVec{base: u64(data), len: u64(first)}, IOVec{base: u64(data) + u64(first), len: u64(length - first)}]!
		mut request := Operation{fd: original[1], write: true, vector: &vector[0]}
		mut worker := C.pthread_t{}
		if C.pthread_create(&worker, nil, operation, &request) != 0 { return false }
		if !ready(&request) { abandon(c'LINUX IOVPIN FAIL: write worker did not start') }
		// No reader has drained the original pipe. Queued bytes prove the
		// oversized first write has entered it and is blocked holding its FD.
		mut pending := i32(0)
		for _ in 0 .. 5000 {
			pending = queued(original[0]); if pending != 0 { break }; C.usleep(1000)
		}
		if pending <= 0 { abandon(c'LINUX IOVPIN FAIL: write did not enter the original pipe') }
		if kind == 0 {
			if C.dup2(other[1], original[1]) != original[1] { abandon(c'LINUX IOVPIN FAIL: write replacement setup') }
		} else if kind == 1 {
			if C.dup2(other[0], original[1]) != original[1] { abandon(c'LINUX IOVPIN FAIL: wrong-mode write replacement') }
		} else if C.close(original[1]) != 0 { abandon(c'LINUX IOVPIN FAIL: writer close') }
		mut buffer := [32768]u8{}
		mut total := usize(0)
		mut content := true
		for {
			n := C.read(original[0], &buffer[0], usize(buffer.len))
			if n < 0 { abandon(c'LINUX IOVPIN FAIL: original pipe drain') }; if n == 0 { break }
			for i in 0 .. int(n) { if buffer[i] != if total + usize(i) < first { u8(0x41) } else { u8(0x42) } { content = false } }
			total += usize(n)
		}
		// EOF also proves the final syscall reference was released after all
		// writes, rather than leaking an open writer after the call returns.
		if C.pthread_join(worker, nil) != 0 { abandon(c'LINUX IOVPIN FAIL: write join') }
		other_bytes := queued(other[0])
		valid := content && total == length && request.result == isize(length) && request.error == 0 && other_bytes == 0
		if kind != 2 && C.close(original[1]) != 0 { return false }
		if C.close(original[0]) != 0 || C.close(other[0]) != 0 || C.close(other[1]) != 0 { return false }
		if !valid {
			C.printf(c'LINUX IOVPIN DETAIL: write kind=%d result=%ld/%d original=%lu replacement=%d expected=%lu/0 original=%lu replacement=0\n', kind, request.result, request.error, total, other_bytes, length, length); C.fflush(nil)
		}
		return valid
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(90)
		if !storage(ordinary) { C.puts(c'LINUX IOVPIN FAIL: retained vector storage or result'); C.fflush(nil); return false }
		mut bad := i32(0)
		for round in 0 .. 4 {
			for kind in 0 .. 3 { if !write_case(i32(kind)) { bad++ } }
			for kind in 0 .. 4 { if !read_case(i32(kind)) { bad++ } }
			C.printf(c'LINUX IOVPIN ROUND: ordinary=%d round=%d failures=%d\n', i32(ordinary), i32(round), bad); C.fflush(nil)
		}
		C.alarm(0)
		if bad != 0 { return false }
		C.printf(c'LINUX IOVPIN CASE: ordinary=%d reads=16 writes=12 PASS\n', i32(ordinary)); C.fflush(nil)
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
				C.printf(c'LINUX IOVPIN DETAIL: ordinary=%d outcome=%d\n', i32(ordinary), outcome); C.fflush(nil); failed = true
			}
		}
		if failed { C.puts(c'LINUX IOVPIN FAIL: vector descriptor identity or reference release'); C.fflush(nil); return 1 }
		C.puts(c'LINUX IOVPIN PASS: root/UID1000 blocked readv and multi-chunk writev retain the original open description through close/dup2, never consume or modify replacements, and release the final writer reference')
		C.puts(c'LINUX IOVPIN: PASS'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
