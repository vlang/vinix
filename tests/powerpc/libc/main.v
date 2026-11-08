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
		if usize(C.mmap(nil, 32 * 1024 * 1024, 3, 0x22, -1, 0)) != usize(0xffffffff) {
			return fail(c'mapping capacity')
		}
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
