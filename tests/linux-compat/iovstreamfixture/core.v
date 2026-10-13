// SPDX-License-Identifier: GPL-2.0-or-later
module iovstreamfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
struct IOVec { mut: base u64 len u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Operation {
	fd i32
	version i32
	count i32
	vector &IOVec
mut:
	done i32
	result isize
	error i32
}
fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.pipe2(&i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.ioctl(i32, usize, ...) i32
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) isize
fn C.pthread_create(&C.pthread_t, voidptr, fn(voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.usleep(u32) i32
fn C.alarm(u32) u32
fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn receive(fd i32, version i32, vector voidptr, count i32) isize {
	return unsafe { C.syscall(isize(if version == 0 { C.SYS_readv } else { C.SYS_preadv2 }), isize(fd), vector, isize(count), u64(-1), u64(0x1234567800000000), u64(0)) }
}
fn operation(argument voidptr) voidptr {
	unsafe {
		mut request := &Operation(argument); e := C.__errno_location(); *e = 0
		request.result = receive(request.fd, request.version, request.vector, request.count)
		request.error = *e; C.__atomic_store_n(&request.done, 1, 5)
	}
	return unsafe { nil }
}
fn abandon(message &char) {
	unsafe { C.puts(message); C.fflush(nil); C._exit(2) }
}
fn endpoints(kind i32, blocking bool, fds &i32) bool {
	unsafe {
		if kind == 0 { return C.pipe2(fds, if blocking { 0 } else { C.O_NONBLOCK }) == 0 }
		return C.socketpair(C.AF_UNIX, (if kind == 1 { C.SOCK_STREAM } else if kind == 2 { C.SOCK_DGRAM } else { C.SOCK_SEQPACKET }) | if blocking { 0 } else { C.SOCK_NONBLOCK }, 0, fds) == 0
	}
}
fn queued(fd i32) i32 {
	unsafe { mut n := i32(-1); return if C.ioctl(fd, usize(C.FIONREAD), &n) == 0 { n } else { -1 } }
}
fn probe(kind i32, version i32, count i32, variant i32, verbose bool) bool {
	unsafe {
		mut fds := [i32(-1), i32(-1)]!
		if !endpoints(kind, variant == 1, &fds[0]) { return false }
		defer { C.close(fds[0]); C.close(fds[1]) }
		// Pipes read from their first endpoint; socket pairs receive at the peer.
		reader := fds[0]; writer := fds[1]
		mut input := [u8(0x41), 0x42, 0x43, 0x44, 0x58, 0x59]!
		length := if variant in [i32(2), 3]! { 4 } else { 2 }
		if C.write(writer, &input[0], usize(length)) != length { return false }
		if variant != 1 && C.write(writer, &input[4], 2) != 2 { return false }
		mut output := [8]u8{}
		vector := &IOVec(C.alloca(usize(count) * usize(sizeof(IOVec))))
		C.memset(vector, 0, usize(count) * usize(sizeof(IOVec)))
		first := if count == 2 { 0 } else { count / 2 }
		vector[first] = IOVec{base: u64(&output[0]), len: if variant == 1 { 2 } else { 1 }}
		vector[count - 1] = IOVec{base: u64(&output[4]), len: if variant == 2 { 3 } else if variant in [i32(1), 3]! { 2 } else { 1 }}
		page := usize(C.sysconf(C._SC_PAGESIZE))
		mut inaccessible := voidptr(nil)
		if variant == 4 {
			inaccessible = C.mmap(nil, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
			if u64(inaccessible) == u64(-1) { return false }
			vector[first].base = u64(inaccessible)
		} else if variant == 5 { vector[first].len = 0; vector[count - 1].len = 0 }
		defer { if inaccessible != nil { C.munmap(inaccessible, page) } }
		mut early := true
		mut actual := isize(-1); mut code := i32(0)
		if variant == 1 {
			mut request := Operation{fd: reader, version: version, vector: vector, count: count}
			mut worker := C.pthread_t{}
			if C.pthread_create(&worker, nil, operation, &request) != 0 { return false }
			early = false
			for _ in 0 .. 1000 {
				if C.__atomic_load_n(&request.done, 5) != 0 { early = true; break }
				C.usleep(1000)
			}
			// A baseline stuck on its second read is released before joining.
			// Never unwind storage still borrowed by the worker.
			if !early && C.write(writer, &input[4], 2) != 2 { abandon(c'LINUX IOVSTREAM FAIL: late delivery') }
			if C.pthread_join(worker, nil) != 0 { abandon(c'LINUX IOVSTREAM FAIL: worker join') }
			actual = request.result; code = request.error
		} else {
			e := C.__errno_location(); *e = 0; actual = receive(reader, version, vector, count); code = *e
		}
		wanted := if variant == 4 { isize(-1) } else if variant == 5 { isize(0) } else if variant == 2 { isize(4) } else if variant == 3 { isize(3) } else { isize(2) }
		mut valid := early && actual == wanted && code == if variant == 4 { C.EFAULT } else { 0 }
		if variant == 1 { valid = valid && output[0] == 0x41 && output[1] == 0x42 && output[4] == 0 && output[5] == 0 && queued(reader) == 0 }
		else if variant in [i32(4), 5]! {
			for x in output { if x != 0 { valid = false } }
			mut remaining := [8]u8{}
			n := C.read(reader, &remaining[0], 8)
			if kind >= 2 {
				if n != 2 || remaining[0] != 0x41 || remaining[1] != 0x42 || C.read(reader, &remaining[0], 8) != 2 || remaining[0] != 0x58 || remaining[1] != 0x59 { valid = false }
			} else if n != 4 || remaining[0] != 0x41 || remaining[1] != 0x42 || remaining[2] != 0x58 || remaining[3] != 0x59 { valid = false }
		} else {
			if output[0] != 0x41 || output[4] != 0x42 { valid = false }
			if variant == 2 && (output[5] != 0x43 || output[6] != 0x44) { valid = false }
			if variant == 3 && output[5] != 0x43 { valid = false }
			mut remaining := [8]u8{}
			n := C.read(reader, &remaining[0], 8)
			if variant == 3 && kind < 2 {
				if n != 3 || remaining[0] != 0x44 || remaining[1] != 0x58 || remaining[2] != 0x59 { valid = false }
			} else if n != 2 || remaining[0] != 0x58 || remaining[1] != 0x59 { valid = false }
		}
		if variant != 1 && queued(reader) != 0 { valid = false }
		if !valid && verbose { C.printf(c'LINUX IOVSTREAM DETAIL: kind=%d version=%d count=%d variant=%d early=%d result=%ld/%d expected=%ld/%d bytes=%02x,%02x,%02x,%02x\n', kind, version, count, variant, i32(early), actual, code, wanted, if variant == 4 { C.EFAULT } else { 0 }, i32(output[0]), i32(output[4]), i32(output[5]), i32(output[6])); C.fflush(nil) }
		return valid
	}
}
fn large_probe(kind i32, version i32, count i32, verbose bool) bool {
	unsafe {
		length := usize(1024 * 1024)
		data := C.mmap(nil, length * 2 + 4096, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(data) == u64(-1) { return false }; defer { C.munmap(data, length * 2 + 4096) }
		C.memset(data, 0x41, length / 2); C.memset(voidptr(usize(data) + length / 2), 0x42, length / 2)
		C.memset(voidptr(usize(data) + length), 0, length + 4096)
		mut fds := [2]i32{}; if !endpoints(kind, false, &fds[0]) { return false }; defer { C.close(fds[0]); C.close(fds[1]) }
		if C.write(fds[1], data, length) != isize(length) { return false }
		vector := &IOVec(C.alloca(usize(count) * usize(sizeof(IOVec)))); C.memset(vector, 0, usize(count) * usize(sizeof(IOVec)))
		vector[0] = IOVec{base: u64(data) + u64(length), len: u64(length / 2)}
		vector[count - 2] = IOVec{base: u64(data) + u64(length + length / 2), len: u64(length / 2)}
		vector[count - 1] = IOVec{base: u64(data) + u64(length * 2), len: 1}
		e := C.__errno_location(); *e = 0; n := receive(fds[0], version, vector, count); code := *e
		mut valid := n == isize(length) && code == 0 && queued(fds[0]) == 0
		out := &u8(usize(data) + length)
		for i in 0 .. int(length) { if out[i] != if usize(i) < length / 2 { u8(0x41) } else { u8(0x42) } { valid = false; break } }
		if out[length] != 0 { valid = false }
		if !valid && verbose { C.printf(c'LINUX IOVSTREAM LARGE: kind=%d version=%d count=%d result=%ld/%d expected=1048576/0\n', kind, version, count, n, code); C.fflush(nil) }
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


fn storage(ordinary bool) bool {
	unsafe {
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY); if fd < 0 { return false }; defer { C.close(fd) }
		// Keep endpoint identities stable while measuring receive/import
		// scratch. Thousands of closed sockets await the VFS grace period
		// and can exhaust the separate 4096-object socket budget in a burst.
		mut fds := [8]i32{}; mut opened := 0
		defer { for i in 0 .. opened { C.close(fds[i]) } }
		for kind in 0 .. 4 { if !endpoints(i32(kind), false, &fds[kind * 2]) { return false }; opened += 2 }
		length := usize(1024 * 1024)
		data := C.mmap(nil, length * 2 + 4096, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if u64(data) == u64(-1) { return false }; defer { C.munmap(data, length * 2 + 4096) }
		C.memset(data, 0x41, length / 2); C.memset(voidptr(usize(data) + length / 2), 0x42, length / 2)
		for cycle in 0 .. 32 { if !storage_cycle(&fds[0], data) { storage_failure(0, i32(cycle)); return false } }
		C.usleep(13000000)
		mut before := &Slabs(C.alloca(usize(sizeof(Slabs)))); *before = Slabs{}
		if !snapshot(fd, before) { return false }
		for cycle in 0 .. 200 { if !storage_cycle(&fds[0], data) { storage_failure(1, i32(cycle)); return false } }
		C.usleep(13000000)
		mut after := &Slabs(C.alloca(usize(sizeof(Slabs)))); *after = Slabs{}
		if !snapshot(fd, after) || before.rows != after.rows { return false }
		mut valid := before.large == after.large
		for i in 0 .. int(before.rows) {
			if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { valid = false }
			C.printf(c'LINUX IOVSTREAM SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[i], before.live[i], after.live[i])
		}
		C.printf(c'LINUX IOVSTREAM STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if valid { &char(c'PASS') } else { &char(c'FAIL') }); C.fflush(nil)
		return valid
	}
}
fn storage_failure(phase i32, cycle i32) {
	unsafe {
		C.printf(c'LINUX IOVSTREAM STORAGE SETUP: phase=%d cycle=%d errno=%d\n', phase, cycle, *C.__errno_location())
		fd := C.open(c'/proc/kernel-resources', C.O_RDONLY)
		if fd >= 0 {
			mut data := [4096]char{}; n := C.read(fd, &data[0], usize(data.len - 1)); C.close(fd)
			if n > 0 { data[int(n)] = 0; C.printf(c'%s\n', &data[0]) }
		}
		C.fflush(nil)
	}
}
fn retained_receive(reader i32, writer i32, version i32, count i32, data voidptr) bool {
	unsafe {
		large := data != nil; length := if large { usize(1024 * 1024) } else { usize(4) }
		mut input := [u8(0x41), 0x42, 0x43, 0x44, 0x58, 0x59]!
		mut output := [8]u8{}
		vector := &IOVec(C.alloca(usize(count) * usize(sizeof(IOVec)))); C.memset(vector, 0, usize(count) * usize(sizeof(IOVec)))
		first := if count == 8 { 3 } else { 0 }
		vector[first] = IOVec{base: if large { u64(data) + u64(length) } else { u64(&output[0]) }, len: if large { u64(length / 2) } else { 1 }}
		vector[count - 2] = IOVec{base: if large { u64(data) + u64(length + length / 2) } else { u64(&output[4]) }, len: if large { u64(length / 2) } else { 3 }}
		vector[count - 1] = IOVec{base: if large { u64(data) + u64(length * 2) } else { u64(&output[7]) }, len: if large { 1 } else { 0 }}
		if large { C.memset(voidptr(u64(data) + u64(length)), 0, length + 1) }
		if C.write(writer, if large { data } else { &input[0] }, length) != isize(length) { return false }
		if !large && C.write(writer, &input[4], 2) != 2 { return false }
		e := C.__errno_location(); *e = 0
		if receive(reader, version, vector, count) != isize(length) || *e != 0 { return false }
		if large {
			if C.memcmp(data, voidptr(u64(data) + u64(length)), length) != 0 || *(&u8(u64(data) + u64(length * 2))) != 0 { return false }
		} else {
			if output[0] != 0x41 || output[4] != 0x42 || output[5] != 0x43 || output[6] != 0x44 || C.read(reader, &output[0], 2) != 2 || output[0] != 0x58 || output[1] != 0x59 { return false }
		}
		// An empty nonblocking callback exercises buffer/charge retirement.
		*e = 0; if receive(reader, version, vector, count) != -1 || *e != C.EAGAIN { return false }
		vector[first].len = 0; vector[count - 2].len = 0; vector[count - 1].len = 0
		*e = 0; if receive(reader, version, vector, count) != 0 || *e != 0 { return false }
		*e = 0; if receive(reader, version, vector, 1025) != -1 || *e != C.EINVAL { return false }
		return queued(reader) == 0
	}
}
fn storage_cycle(fds &i32, data voidptr) bool {
	unsafe {
		for kind in 0 .. 4 { for version in [i32(0), 1]! { for count in [i32(8), 9, 1024]! {
			if !retained_receive(fds[kind * 2], fds[kind * 2 + 1], version, count, nil) { return false }
		} } }
		return retained_receive(fds[4], fds[5], 0, 9, data) && retained_receive(fds[6], fds[7], 1, 9, data)
	}
}
fn qualify(ordinary bool) bool {
	unsafe {
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return false }
		C.alarm(300); mut bad := 0; mut cases := 0
		for kind in 0 .. 4 { for version in [i32(0), 1]! {
			for count in [i32(2), 8, 9, 513, 1024]! { for variant in 0 .. 6 {
				if variant == 1 && count != 2 { continue }; cases++
				if !probe(i32(kind), version, count, i32(variant), true) { bad++ }
			} }
		} }
		for kind in [i32(2), 3]! { for version in [i32(0), 1]! { for count in [i32(3), 9, 1024]! {
			cases++; if !large_probe(kind, version, count, true) { bad++ }
		} } }
		C.printf(c'LINUX IOVSTREAM OUTCOMES: ordinary=%d cases=%d failures=%d\n', i32(ordinary), i32(cases), i32(bad)); C.fflush(nil)
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
		if failed { C.puts(c'LINUX IOVSTREAM FAIL: record boundaries, available data or storage'); C.fflush(nil); return 1 }
		C.puts(c'LINUX IOVSTREAM PASS: root/UID1000 readv and current-position preadv2 scatter one pipe/socket read; UNIX datagram/seqpacket boundaries and truncation retain the next message; available bytes return with the writer open; empty and first inaccessible destinations preserve queues; 1MiB records and repeated fast/heap receives release storage')
		C.puts(c'LINUX IOVSTREAM: PASS'); C.fflush(nil); for { C.pause() }
	}
	return 0
}
