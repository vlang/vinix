// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

fn C.puts(&char) int
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, int, usize) voidptr

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

// Fixed-argument AAPCS64 calls with compatible Apple and musl layouts.
// Variadic calls (printf), Darwin FILE*, errno/TLS, and Objective-C dispatch
// cannot be forwarded this way and deliberately have no symbol here.
fn libsystem_symbol(library string, symbol string) !u64 {
	if library != '/usr/lib/libSystem.B.dylib' {
		return error('iOS: library is not implemented: ${library} (${symbol})')
	}
	address := match symbol {
		'_puts' { unsafe { voidptr(darwin_puts) } }
		'_atoi' { unsafe { voidptr(darwin_atoi) } }
		'_malloc' { unsafe { voidptr(darwin_malloc) } }
		'_free' { unsafe { voidptr(darwin_free) } }
		'_strlen' { unsafe { voidptr(darwin_strlen) } }
		'_strcmp' { unsafe { voidptr(darwin_strcmp) } }
		'_memcpy' { unsafe { voidptr(C.memcpy) } }
		'_memset' { unsafe { voidptr(C.memset) } }
		else { return error('iOS: libSystem symbol is not implemented: ${symbol}') }
	}
	return u64(address)
}
