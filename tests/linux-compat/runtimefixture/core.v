// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module runtimefixture

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/mman.h>
#include <sys/timerfd.h>
#include <time.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}

@[typedef]
struct C.pthread_key_t {}

struct Worker {
mut:
	id            i32
	failed        i32
	errno_address voidptr = unsafe { nil }
	key           C.pthread_key_t
}

__global count u64
__global started i32

fn C.__errno_location() &i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_key_create(&C.pthread_key_t, voidptr) i32
fn C.pthread_setspecific(C.pthread_key_t, voidptr) i32
fn C.pthread_getspecific(C.pthread_key_t) voidptr
fn C.pthread_key_delete(C.pthread_key_t) i32
fn C.__atomic_add_fetch(&u64, u64, i32) u64
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.sched_yield() i32
fn C.sysconf(i32) isize
fn C.getauxval(usize) usize
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.strcmp(&char, &char) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.unlink(&char) i32
fn C.read(i32, voidptr, usize) isize
fn C.lseek(i32, i64, i32) i64

struct C.timespec {
mut:
	tv_sec i64
	tv_nsec isize
}

struct C.itimerspec {
mut:
	it_interval C.timespec
	it_value C.timespec
}

fn C.clock_gettime(i32, &C.timespec) i32
fn C.timerfd_create(i32, i32) i32
fn C.timerfd_settime(i32, i32, &C.itimerspec, &C.itimerspec) i32
fn C.timerfd_gettime(i32, &C.itimerspec) i32

$if !arm64 {
	#include <emmintrin.h>
	@[typedef]
	struct C.__m128i {}
	fn C._mm_loadu_si128(&C.__m128i) C.__m128i
	fn C._mm_add_epi32(C.__m128i, C.__m128i) C.__m128i
	fn C._mm_storeu_si128(&C.__m128i, C.__m128i)
}

fn simd(seed u32) bool {
	input := [seed, seed + 1, seed + 2, seed + 3]!
	mut output := [4]u32{}
	p := unsafe { &input[0] }
	q := unsafe { &output[0] }
	$if arm64 {
		asm arm64 raw {
			"ldr q0, [%[input]]\n\t"
			"add v0.4s, v0.4s, v0.4s\n\t"
			"str q0, [%[output]]"
			;
			; [input] "r" (p)
			  [output] "r" (q)
			; v0
			  memory
		}
	} $else {
		// Compiler intrinsics emit SSE2 in both i386 and x86-64 builds.
		// V's amd64 inline assembly backend cannot target i386.
		unsafe {
			vector := C._mm_loadu_si128(&C.__m128i(p))
			C._mm_storeu_si128(&C.__m128i(q), C._mm_add_epi32(vector, vector))
		}
	}
	unsafe { for i in 0 .. 4 { if output[i] != input[i] * 2 { return false } }
	 }
	return true
}

fn worker(argument voidptr) voidptr {
	unsafe {
		mut state := &Worker(argument)
		errno_ptr := C.__errno_location()
		state.errno_address = errno_ptr
		*errno_ptr = 100 + state.id
		if C.pthread_setspecific(state.key, argument) != 0 { state.failed = 1 }
		for C.__atomic_load_n(&started, 2) == 0 { C.sched_yield() }
		for i in 0 .. 1000 {
			C.__atomic_add_fetch(&count, u64(1), 5)
			if !simd(u32(i + state.id)) || C.pthread_getspecific(state.key) != argument || *errno_ptr != 100 + state.id {
				state.failed = 1
			}
			C.sched_yield()
		}
	}
	return unsafe { nil }
}

type JitFunction = fn () i32

fn clear_cache(begin &char, end &char) {
	$if arm64 {
		mut ctr := u64(0)
		asm arm64 raw {
			"mrs %[ctr], ctr_el0"
			; [ctr] "=r" (ctr)
		}
		dline := u64(4) << ((ctr >> 16) & 15)
		iline := u64(4) << (ctr & 15)
		for p := u64(begin) & ~(dline - 1); p < u64(end); p += dline {
			asm arm64 raw { "dc cvau, %[p]" ; ; [p] "r" (p) ; memory }
		}
		asm arm64 raw { "dsb ish" ; ; ; memory }
		for p := u64(begin) & ~(iline - 1); p < u64(end); p += iline {
			asm arm64 raw { "ic ivau, %[p]" ; ; [p] "r" (p) ; memory }
		}
		asm arm64 raw { "dsb ish\n\tisb" ; ; ; memory }
	}
}

fn jit(page usize) bool {
	unsafe {
		memory := C.mmap(nil, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if memory == voidptr(isize(-1)) { return false }
		defer { C.munmap(memory, page) }
		$if arm64 {
			// mov w0,#42; ret. This is application-generated machine code.
			code := [u32(0x52800540), 0xd65f03c0]!
			C.memcpy(memory, &code[0], sizeof(code))
			clear_cache(&char(memory), &char(memory) + sizeof(code))
		} $else {
			// mov eax,42; ret; valid in both i386 and x86-64 mode.
			code := [u8(0xb8), 42, 0, 0, 0, 0xc3]!
			C.memcpy(memory, &code[0], sizeof(code))
		}
		if C.mprotect(memory, page, C.PROT_READ | C.PROT_EXEC) != 0 { return false }
		function := JitFunction(memory)
		return function() == 42
	}
}

fn wide_offsets_and_time() bool {
	unsafe {
		file := C.open(c'/tmp/linux-compat-wide-file', C.O_CREAT | C.O_EXCL | C.O_RDWR, 0o600)
		if file < 0 { return false }
		defer { C.close(file); C.unlink(c'/tmp/linux-compat-wide-file') }
		// Moving past 8 GiB exercises off_t without allocating a giant file.
		offset := (i64(1) << 33) + 17
		mut byte := u8(0)
		if C.lseek(file, offset, C.SEEK_SET) != offset || C.lseek(file, 0, C.SEEK_CUR) != offset
			|| C.read(file, &byte, 1) != 0 || C.lseek(file, -17, C.SEEK_CUR) != offset - 17 {
			return false
		}
		mut now := C.timespec{}
		if C.clock_gettime(C.CLOCK_REALTIME, &now) != 0 || now.tv_sec < 0
			|| now.tv_nsec < 0 || now.tv_nsec >= 1_000_000_000 {
			return false
		}
		timer := C.timerfd_create(C.CLOCK_REALTIME, C.TFD_NONBLOCK | C.TFD_CLOEXEC)
		if timer < 0 { return false }
		defer { C.close(timer) }
		// A deadline more than 2^32 seconds away cannot fit a signed time32.
		deadline := C.itimerspec{ it_value: C.timespec{tv_sec: now.tv_sec + (i64(1) << 32)} }
		mut remaining := C.itimerspec{}
		mut expirations := u64(0)
		if C.timerfd_settime(timer, C.TFD_TIMER_ABSTIME, &deadline, nil) != 0
			|| C.timerfd_gettime(timer, &remaining) != 0 || remaining.it_value.tv_sec <= (i64(1) << 31)
			|| C.read(timer, &expirations, sizeof(expirations)) != -1 || *C.__errno_location() != C.EAGAIN {
			return false
		}
		return true
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		page := C.sysconf(C._SC_PAGESIZE)
		aux_page := C.getauxval(usize(C.AT_PAGESZ))
		if page < 4096 || page & (page - 1) != 0 || usize(page) != aux_page {
			C.puts(c'LINUX RUNTIME FAIL: page size')
			return 1
		}
		C.printf(c'LINUX RUNTIME page_size=%ld pointer_bits=%zu\n', page, sizeof(voidptr) * 8)
		mut key := C.pthread_key_t{}
		if C.pthread_key_create(&key, nil) != 0 { return 1 }
		mut threads := [4]C.pthread_t{}
		mut states := [4]Worker{}
		for i in 0 .. 4 {
			states[i].id = i32(i)
			states[i].key = key
			if C.pthread_create(&threads[i], nil, worker, &states[i]) != 0 {
				C.puts(c'LINUX RUNTIME FAIL: pthread_create')
				return 1
			}
		}
		C.__atomic_store_n(&started, 1, 3)
		for i in 0 .. 4 {
			if C.pthread_join(threads[i], nil) != 0 || states[i].failed != 0 || states[i].errno_address == C.__errno_location() {
				C.puts(c'LINUX RUNTIME FAIL: TLS/SIMD')
				return 1
			}
			for j in 0 .. i { if states[i].errno_address == states[j].errno_address { return 1 } }
		}
		if count != 4000 || C.pthread_key_delete(key) != 0 {
			C.puts(c'LINUX RUNTIME FAIL: atomic count')
			return 1
		}
		C.puts(c'LINUX RUNTIME PASS: atomics SIMD TLS')
		if !jit(usize(page)) {
			C.printf(c'LINUX RUNTIME FAIL: JIT errno=%d\n', *C.__errno_location())
			return 1
		}
		C.puts(c'LINUX RUNTIME PASS: JIT page sizes')
		if !wide_offsets_and_time() {
			C.printf(c'LINUX RUNTIME FAIL: wide offsets/time64 errno=%d\n', *C.__errno_location())
			return 1
		}
		C.puts(c'LINUX RUNTIME PASS: wide offsets time64')
		C.puts(c'LINUX RUNTIME: PASS')
		C.fflush(nil)
		if argc == 2 && C.strcmp(argv[1], c'--once') == 0 { return 0 }
		for { C.pause() }
	}
	return 0
}
