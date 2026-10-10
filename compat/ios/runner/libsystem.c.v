// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.rand

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>

fn C.posix_memalign(voidptr, usize, usize) i32

fn C.puts(&char) int
fn C.abort()
fn C.ios_chkstk_darwin()
fn C._Exit(i32)
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, int, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) int
fn C.memchr(voidptr, int, usize) voidptr
fn C.memmove(voidptr, voidptr, usize) voidptr
fn C.floorf(f32) f32

fn darwin_random_uniform(bound u32) u32 {
	if bound < 2 { return 0 }
	// Rejection sampling avoids modulo bias; crypto.rand uses each host's OS RNG.
	threshold := (u32(0) - bound) % bound
	for {
		bytes := rand.bytes(4) or { panic('iOS: random source failed') }
		value := u32(bytes[0]) | u32(bytes[1]) << 8 | u32(bytes[2]) << 16 | u32(bytes[3]) << 24
		unsafe { bytes.free() }
		if value >= threshold { return value % bound }
	}
}

fn darwin_strlen(text &char) usize {
	mut length := usize(0)
	unsafe {
		for text[length] != 0 { length++ }
	}
	return length
}

fn darwin_strcmp(left &char, right &char) int {
	mut index := usize(0)
	unsafe {
		for left[index] != 0 && left[index] == right[index] { index++ }
		return int(u8(left[index])) - int(u8(right[index]))
	}
}

fn darwin_atoi(text &char) int {
	mut position := usize(0)
	mut sign := i64(1)
	mut value := i64(0)
	unsafe {
		for (u8(text[position]) >= 9 && u8(text[position]) <= 13) || text[position] == 32 {
			position++
		}
		if text[position] == 45 {
			sign = -1
			position++
		} else if text[position] == 43 {
			position++
		}
		for text[position] >= 48 && text[position] <= 57 {
			value = value * 10 + i64(text[position]) - 48
			// atoi has undefined behavior outside int's range. Saturate
			// deterministically, and never overflow the parser's accumulator.
			if value > 2147483647 {
				return if sign < 0 { int(-2147483647 - 1) } else { 2147483647 }
			}
			position++
		}
	}
	return int(sign * value)
}

fn darwin_puts(text &char) int {
	return C.puts(text)
}

fn darwin_malloc(size usize) voidptr {
	return C.malloc(size)
}

fn darwin_free(pointer voidptr) {
	C.free(pointer)
}

fn darwin_lazy_binder() {
	panic('iOS: unsupported invocation of dyld_stub_binder')
}

fn darwin_bzero(pointer voidptr, size usize) {
	C.memset(pointer, 0, size)
}

// Fixed-argument AAPCS64 calls with compatible Apple and musl layouts.
// Varargs, Darwin FILE*, errno/TLS and pthread objects use explicit adapters.
fn libsystem_symbol(library string, symbol string) !u64 {
	if library == '/usr/lib/libSystem.B.dylib' && symbol == '_posix_memalign' { return u64(unsafe { voidptr(C.posix_memalign) }) }
	if library != '/usr/lib/libSystem.B.dylib' {
		return error('iOS: library is not implemented: ${library} (${symbol})')
	}
	if address := pthread_symbol(symbol) { return address }
	if address := stdio_symbol(symbol) { return address }
	if address := dyld_symbol(symbol) { return address }
	if address := fixed_symbol(symbol) { return address }
	if address := dispatch_symbol(symbol) { return address }
	if address := time_symbol(symbol) { return address }
	if address := files_symbol(symbol) { return address }
	if address := sockets_symbol(symbol) { return address }
	if address := netdb_symbol(symbol) { return address }
	if address := interfaces_symbol(symbol) { return address }
	if address := system_queries_symbol(symbol) { return address }
	if address := process_symbol(symbol) { return address }
	if address := mach_memory_symbol(symbol) { return address }
	if address := common_crypto_symbol(symbol) { return address }
	address := match symbol {
		'___assert_rtn' { unsafe { voidptr(darwin_assert_rtn) } }
		'___chkstk_darwin' { unsafe { voidptr(C.ios_chkstk_darwin) } }
		'___maskrune' { unsafe { voidptr(darwin_maskrune) } }
		'_isspace' { unsafe { voidptr(darwin_isspace) } }
		'_OSAtomicEnqueue' { unsafe { voidptr(darwin_atomic_enqueue) } }
		'_OSAtomicDequeue' { unsafe { voidptr(darwin_atomic_dequeue) } }
		'___tolower', '_tolower' { unsafe { voidptr(darwin_rune_lower) } }
		'___toupper', '_toupper' { unsafe { voidptr(darwin_rune_upper) } }
		'_opendir' { unsafe { voidptr(darwin_opendir) } }
		'_readdir' { unsafe { voidptr(darwin_readdir) } }
		'_closedir' { unsafe { voidptr(darwin_closedir) } }
		'_sysconf' { unsafe { voidptr(darwin_sysconf) } }
		'_sysctlbyname' { unsafe { voidptr(darwin_sysctlbyname) } }
		'___error' { unsafe { voidptr(darwin_errno) } }
		'_abort' { unsafe { voidptr(C.abort) } }
		'dyld_stub_binder' { unsafe { voidptr(darwin_lazy_binder) } }
		'_pthread_create' { unsafe { voidptr(darwin_pthread_create) } }
		'_pthread_join' { unsafe { voidptr(darwin_pthread_join) } }
		'__tlv_bootstrap' { unsafe { voidptr(C.ios_tlv_get_addr) } }
		'___cxa_atexit' { unsafe { voidptr(image_cxa_atexit) } }
		'___cxa_finalize' { unsafe { voidptr(image_cxa_finalize) } }
		'_atexit' { unsafe { voidptr(image_atexit) } }
		'_exit' { unsafe { voidptr(image_exit) } }
		'__exit' { unsafe { voidptr(image_immediate_exit) } }
		'_puts' { unsafe { voidptr(darwin_puts) } }
		'_atoi' { unsafe { voidptr(darwin_atoi) } }
		'_malloc' { unsafe { voidptr(darwin_malloc) } }
		'_free' { unsafe { voidptr(darwin_free) } }
		'_strlen' { unsafe { voidptr(darwin_strlen) } }
		'_strcmp' { unsafe { voidptr(darwin_strcmp) } }
		'_memcpy' { unsafe { voidptr(C.memcpy) } }
		'_memset' { unsafe { voidptr(C.memset) } }
		'_memmove' { unsafe { voidptr(C.memmove) } }
		'_memcmp' { unsafe { voidptr(C.memcmp) } }
		'_memchr' { unsafe { voidptr(C.memchr) } }
		'_bzero' { unsafe { voidptr(darwin_bzero) } }
		'_arc4random_uniform' { unsafe { voidptr(darwin_random_uniform) } }
		'_floorf' { unsafe { voidptr(C.floorf) } }
		else { return error('iOS: libSystem symbol is not implemented: ${symbol}') }
	}
	return u64(address)
}
