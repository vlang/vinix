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
#include <poll.h>
#include <sys/stat.h>

struct C.timespec { tv_sec i64 tv_nsec i64 }
struct C.sysinfo { freeram u32 }
fn C.sysinfo(&C.sysinfo) i32
fn C.printf(&char, ...voidptr) i32
fn C.fflush(voidptr) i32
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
struct C.pollfd {
mut:
	fd i32
	events i16
	revents i16
}
fn C.poll(&C.pollfd, usize, i32) i32
fn C.nanosleep(&C.timespec, &C.timespec) i32
fn C.access(&char, i32) i32
struct C.stat { st_mode u32 st_ino u64 st_dev u64 }
fn C.stat(&char, &C.stat) i32
fn C.fstat(i32, &C.stat) i32

fn device_discovery() bool {
	unsafe {
		for path in [c'/dev/fb0', c'/dev/pointer']! {
			mut by_path := C.stat{}
			mut by_fd := C.stat{}
			fd := C.open(path, C.O_RDONLY)
			if fd < 0 {
				// A serial-only firmware boot may provide no framebuffer.
				// Its missing device must also be absent from discovery.
				if C.strcmp(path, c'/dev/fb0') != 0 || *C.__errno_location() != 19
					|| C.access(path, C.F_OK) != -1 || *C.__errno_location() != 2
					|| C.stat(path, &by_path) != -1 || *C.__errno_location() != 2 { return false }
				continue
			}
			if C.access(path, C.F_OK) != 0 || C.access(path, C.R_OK) != 0
				|| C.access(path, C.X_OK) != -1 || *C.__errno_location() != 13
				|| C.stat(path, &by_path) != 0 || by_path.st_mode & 0xf000 != 0x2000 { return false }
			if fd < 0 || C.fstat(fd, &by_fd) != 0 || C.close(fd) != 0
				|| by_path.st_ino != by_fd.st_ino || by_path.st_dev != by_fd.st_dev { return false }
			if C.strcmp(path, c'/dev/fb0') == 0 && C.access(path, C.R_OK | C.W_OK) != 0 { return false }
		}
		mut missing := C.stat{}
		for path in [c'/dev/fb1', c'/dev/fb7']! {
			if C.access(path, C.F_OK) != -1 || *C.__errno_location() != 2
				|| C.stat(path, &missing) != -1 || *C.__errno_location() != 2
				|| C.open(path, C.O_RDONLY) != -1 || *C.__errno_location() != 2 { return false }
		}
		return true
	}
}

fn monotonic_ns() i64 {
	mut stamp := C.timespec{}
	if C.clock_gettime(1, &stamp) != 0 { return -1 }
	return stamp.tv_sec * 1000000000 + stamp.tv_nsec
}

fn wait_services() bool {
	unsafe {
		mut request := C.timespec{tv_nsec: 20000000}
		start := monotonic_ns()
		if C.nanosleep(&request, nil) != 0 || monotonic_ns() - start < 20000000 { return false }
		request.tv_nsec = 1000000000
		if C.nanosleep(&request, nil) != -1 || *C.__errno_location() != 22 { return false }
		request.tv_sec = -1
		request.tv_nsec = 0
		if C.nanosleep(&request, nil) != -1 || *C.__errno_location() != 22 { return false }
		mut fds := [3]C.pollfd{}
		fds[0] = C.pollfd{fd: -1, events: 1, revents: 99}
		fds[1] = C.pollfd{fd: 1, events: 4}
		fds[2] = C.pollfd{fd: 123, events: 0}
		if C.poll(&fds[0], 3, -1) != 2 || fds[0].revents != 0 || fds[1].revents != 4 || fds[2].revents != 32 { return false }
		if C.poll(&C.pollfd(1), 1, 0) != -1 || *C.__errno_location() != 14 { return false }
		if C.poll(&fds[0], 65, 0) != -1 || *C.__errno_location() != 22 { return false }
		before := monotonic_ns()
		if C.poll(nil, 0, 15) != 0 || monotonic_ns() - before < 15000000 { return false }
		file := C.open(c'/etc/motd', C.O_RDONLY)
		if file < 0 { return false }
		fds[0] = C.pollfd{fd: file, events: 1}
		if C.poll(&fds[0], 1, 0) != 1 || fds[0].revents != 1 || C.close(file) != 0 { return false }
		fds[0] = C.pollfd{fd: 0, events: 1}
		if C.poll(&fds[0], 1, 0) != 0 { return false }
		C.printf(c'VINIX-PPC: WAIT libc poll keyboard\n')
		C.fflush(unsafe { nil })
		if C.poll(&fds[0], 1, -1) != 1 || fds[0].revents != 1 { return false }
		// Readiness must leave the byte queued, including on a second poll.
		if C.poll(&fds[0], 1, 0) != 1 { return false }
		mut byte := u8(0)
		if C.read(0, &byte, 1) != 1 || byte != `k` || C.poll(&fds[0], 1, 0) != 0 { return false }
		pointer := C.open(c'/dev/pointer', C.O_RDONLY | C.O_NONBLOCK)
		if pointer < 0 { return false }
		mut packet := [9]u32{}
		if C.read(pointer, &packet[0], 36) != 36 { return false }
		old_x := packet[0]
		old_y := packet[1]
		fds[0] = C.pollfd{fd: pointer, events: 1}
		if C.poll(&fds[0], 1, 0) != 0 { return false }
		C.printf(c'VINIX-PPC: WAIT libc poll pointer\n')
		C.fflush(unsafe { nil })
		if C.poll(&fds[0], 1, 3000) != 1 || C.poll(&fds[0], 1, 0) != 1 { return false }
		if C.read(pointer, &packet[0], 36) != 36 || packet[0] != old_x + 7
			|| packet[1] != old_y - 4 || C.poll(&fds[0], 1, 0) != 0 || C.close(pointer) != 0 { return false }
		return true
	}
}

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
		if argc == 2 && C.strcmp(argv[1], c'--exec-child') == 0 { return exec_child() }
		if argc != 1 || C.strcmp(argv[0], c'/bin/init') != 0 || argv[1] != nil { return fail(c'argv') }
		path := C.getenv(c'PATH')
		if path == nil || C.strcmp(path, c'/bin:/usr/bin') != 0 { return fail(c'environment') }
		if C.getauxval(6) != 4096 || C.getauxval(3) == 0 || C.getauxval(5) == 0 { return fail(c'auxiliary vector') }
		if C.getpid() != 1 || C.close(-1) != -1 || *C.__errno_location() != 9 { return fail(c'TLS errno') }
		if !startup_services() { return fail(c'identity cwd affinity open flags') }
		if !device_discovery() { return fail(c'consistent device discovery') }
		C.printf(c'VINIX-PPC: PASS libc consistent device discovery\n')
		C.printf(c'VINIX-PPC: PASS libc identity cwd affinity open flags\n')
		if !process_services() { return fail(c'fork exec pipes wait isolation and reclamation') }
		C.printf(c'VINIX-PPC: PASS libc fork exec pipes wait isolation and reclamation\n')
		if !terminal_services() { return fail(c'pseudo-terminal lifecycle') }
		C.printf(c'VINIX-PPC: PASS libc pseudo-terminal lifecycle\n')
		if !sandbox_services() { return fail(c'irreversible app sandbox') }
		C.printf(c'VINIX-PPC: PASS libc irreversible app sandbox\n')
		if !wait_services() { return fail(c'poll nanosleep input readiness') }
		C.printf(c'VINIX-PPC: PASS libc poll nanosleep input readiness\n')
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
