// SPDX-License-Identifier: GPL-2.0-or-later
// A normal musl crt1 main written in V, with no freestanding replacement libc.
module main

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/mman.h>
#include <sys/auxv.h>
#include <sys/sysinfo.h>
#include <time.h>
#include <math.h>
#include <fcntl.h>
#include <sched.h>

struct C.timespec { tv_sec i64 tv_nsec i64 }
struct C.sysinfo { freeram u32 }
fn C.sysinfo(&C.sysinfo) i32
fn C.printf(&char, ...voidptr) i32
fn C.strcmp(&char, &char) i32
fn C.getenv(&char) &char
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.getpid() i32
fn C.close(i32) i32
fn C.__errno_location() &i32
fn C.getauxval(usize) usize
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.clock_gettime(i32, &C.timespec) i32
fn C.sin(f64) f64
fn C.getuid() u32
fn C.getgid() u32
fn C.geteuid() u32
fn C.getegid() u32
fn C.getcwd(&char, usize) &char
fn C.open(&char, i32, ...voidptr) i32
fn C.read(i32, voidptr, usize) i32
fn C.sched_getaffinity(i32, usize, voidptr) i32

fn startup_services() bool {
	unsafe {
		if C.getuid() != 0 || C.geteuid() != 0 || C.getgid() != 0 || C.getegid() != 0 { return false }
		mut cwd := [8]char{}
		if C.getcwd(&cwd[0], 8) != &cwd[0] || C.strcmp(&cwd[0], c'/') != 0 { return false }
		if C.getcwd(&cwd[0], 1) != nil || *C.__errno_location() != 34 { return false }
		if C.getcwd(&char(1), 8) != nil || *C.__errno_location() != 14 { return false }
		mut cpus := [4]u32{init: 0xffffffff}
		if C.sched_getaffinity(0, 16, voidptr(&cpus[0])) != 0 || cpus[0] != 1
			|| cpus[1] != 0 || cpus[2] != 0 || cpus[3] != 0 { return false }
		if C.sched_getaffinity(2, 16, voidptr(&cpus[0])) != -1 || *C.__errno_location() != 3 { return false }
		if C.sched_getaffinity(1, 3, voidptr(&cpus[0])) != -1 || *C.__errno_location() != 22 { return false }
		if C.sched_getaffinity(1, 16, voidptr(1)) != -1 || *C.__errno_location() != 14 { return false }
		for _ in 0 .. 200 {
			fd := C.open(c'/etc/motd', C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NOCTTY)
			if fd < 3 || C.read(fd, &cwd[0], 8) != 8 || C.close(fd) != 0 { return false }
		}
		fd := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		if fd < 3 || C.close(fd) != 0 { return false }
		if C.open(c'/etc/motd', C.O_RDONLY | C.O_DIRECTORY) != -1 || *C.__errno_location() != 20 { return false }
		if C.open(c'/etc/motd', C.O_WRONLY | C.O_CLOEXEC) != -1 || *C.__errno_location() != 30 { return false }
		return true
	}
}

fn fail(stage &char) i32 {
	C.printf(c'VINIX-PPC: FAIL libc %s\n', stage)
	return 1
}

@[export: 'main']
fn entry(argc i32, argv &&char) i32 {
	unsafe {
		if argc != 1 || C.strcmp(argv[0], c'/bin/init') != 0 || argv[1] != nil { return fail(c'argv') }
		path := C.getenv(c'PATH')
		if path == nil || C.strcmp(path, c'/bin:/usr/bin') != 0 { return fail(c'environment') }
		if C.getauxval(6) != 4096 || C.getauxval(3) == 0 || C.getauxval(5) == 0 { return fail(c'auxiliary vector') }
		if C.getpid() != 1 || C.close(-1) != -1 || *C.__errno_location() != 9 { return fail(c'TLS errno') }
		if !startup_services() { return fail(c'identity cwd affinity open flags') }
		C.printf(c'VINIX-PPC: PASS libc identity cwd affinity open flags\n')
		mut start := C.timespec{}
		if C.clock_gettime(1, &start) != 0 { return fail(c'monotonic clock') }
		mut stable_free := u32(0)
		// Repeated allocations cross page boundaries and exercise musl's heap
		// metadata. Every newly mapped page must be zero, including after reuse.
		for round in 0 .. 200 {
			p := &u8(C.malloc(32771))
			if p == nil { return fail(c'malloc') }
			for i in 0 .. 32771 { p[i] = u8(i + round) }
			for i in 0 .. 32771 { if p[i] != u8(i + round) { return fail(c'heap contents') } }
			C.free(p)
			q := &u8(C.mmap(nil, 8193, 3, 0x22, -1, 0))
			if usize(q) == usize(0xffffffff) { return fail(c'mmap') }
			for i in 0 .. 8193 { if q[i] != 0 { return fail(c'mmap zero fill') }; q[i] = 0x5a }
			if C.munmap(q, 8193) != 0 { return fail(c'munmap') }
			mut info := C.sysinfo{}
			if C.sysinfo(&info) != 0 { return fail(c'memory accounting') }
			if round == 0 { stable_free = info.freeram }
			else if info.freeram != stable_free { return fail(c'heap page leak') }
		}
		// Failures must neither replace text nor consume physical pages.
		if usize(C.mmap(nil, 4096, 7, 0x22, -1, 0)) != usize(0xffffffff)
			|| C.munmap(voidptr(0x40000000), 4096) != -1 { return fail(c'mapping permissions') }
		large := C.mmap(nil, 32 * 1024 * 1024, 3, 0x22, -1, 0)
		if usize(large) == usize(0xffffffff) { return fail(c'large mapping') }
		(&u8(large))[32 * 1024 * 1024 - 1] = 0xa5
		if C.munmap(large, 32 * 1024 * 1024) != 0 { return fail(c'large unmap') }
		mut blocks := [32]voidptr{}
		mut count := 0
		for count < blocks.len {
			block := C.mmap(nil, 4 * 1024 * 1024, 3, 0x22, -1, 0)
			if usize(block) == usize(0xffffffff) { break }
			blocks[count] = block
			count++
		}
		if count == 0 || count == blocks.len { return fail(c'mapping exhaustion') }
		for i in 0 .. count { if C.munmap(blocks[i], 4 * 1024 * 1024) != 0 { return fail(c'exhaustion cleanup') } }
		mut after_failure := C.sysinfo{}
		if C.sysinfo(&after_failure) != 0 || after_failure.freeram != stable_free { return fail(c'failed mapping rollback') }
		// Force an actual libm operation with a runtime argument, and keep its
		// result live across a syscall. No Altivec support is advertised.
		value := C.sin(f64(argc))
		if C.getpid() != 1 || value < 0.841470984 || value > 0.841470986 { return fail(c'floating point') }
		mut end := C.timespec{}
		if C.clock_gettime(1, &end) != 0 || end.tv_sec < start.tv_sec
			|| (end.tv_sec == start.tv_sec && end.tv_nsec < start.tv_nsec) { return fail(c'clock progression') }
		C.printf(c'VINIX-PPC: PASS libc argv auxv TLS heap mmap FPU clock\n')
		return 0
	}
}
