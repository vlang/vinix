// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module runtimefixture

#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/mman.h>
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
		asm amd64 raw {
			"movdqu (%[input]), %%xmm0\n\t"
			"paddd %%xmm0, %%xmm0\n\t"
			"movdqu %%xmm0, (%[output])"
			;
			; [input] "r" (p)
			  [output] "r" (q)
			; xmm0
			  memory
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
		C.puts(c'LINUX RUNTIME: PASS')
		C.fflush(nil)
		if argc == 2 && C.strcmp(argv[1], c'--once') == 0 { return 0 }
		for { C.pause() }
	}
	return 0
}
