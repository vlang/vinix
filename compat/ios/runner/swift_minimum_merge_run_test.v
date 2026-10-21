// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type MrrRun = fn (i64) i64
type MrrContext = fn (i64, u64, u64, &u64) i64

fn mrr_expected(count i64) i64 {
	if count < 64 { return count }
	divisor := u64(1) << u32(bits.len_64(u64(count)) - 6)
	return i64(u64(count) / divisor + u64(u64(count) % divisor != 0))
}
fn mrr_worker(run MrrRun, initial u64, lookup bool) u64 {
	mut state := initial
	mut checksum := u64(0)
	for i in 0 .. 4096 {
		state ^= state << 13;state ^= state >> 7;state ^= state << 17
		if lookup && i % 512 == 0 {
			assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss22_minimumMergeRunLengthyS2iF') or { panic(err) } == u64(unsafe { voidptr(run) })
		}
		value := run(i64(state));assert value == mrr_expected(i64(state))
		checksum ^= u64(value)
	}
	return checksum
}
fn mrr_cases(run MrrRun, invoke MrrContext, guard u64, lookup bool) {
	for input in i64(-1024) .. 65536 { assert run(input) == mrr_expected(input) }
	for pair in [[i64(-9223372036854775807) - 1, i64(-9223372036854775807) - 1]!,
		[i64(-65), -65]!, [i64(-1), -1]!, [i64(0), 0]!, [i64(1), 1]!, [i64(63), 63]!,
		[i64(64), 32]!, [i64(65), 33]!, [i64(127), 64]!, [i64(128), 32]!, [i64(129), 33]!,
		[i64(9223372036854775807), 64]!]! {
		mut capture := [u64(0xCAFE), 0, 0, 0, 0xBEEF]!
		assert invoke(pair[0], u64(unsafe { voidptr(run) }), guard, unsafe { &capture[1] }) == pair[1]
		assert capture == [u64(0xCAFE), guard, guard + 8, guard + 16, 0xBEEF]!
	}
	// Quotient boundaries exercise every exponent, each retained six-bit
	// prefix and the rounding transition without overflowing signed Int.
	for shift in 0 .. 58 {
		for prefix in u64(32) .. 65 {
			boundary := prefix << u32(shift)
			for offset in [i64(-1), 0, 1]! {
				input := if offset < 0 { boundary - 1 } else { boundary + u64(offset) }
				if input <= 0x7fffffffffffffff { assert run(i64(input)) == mrr_expected(i64(input)) }
			}
		}
	}
	mut workers := []thread u64{}
	for i in 0 .. 8 { workers << spawn mrr_worker(run, 0xa3915d7e00000001 + u64(i), lookup) }
	results := workers.wait();assert results.len == 8
	unsafe { workers.free();results.free() }
}
fn mrr_empty() {
	assert ios_runtime.swift_integer_arena == 0 && ios_runtime.swift_array_arena == 0
	assert ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_hash_code == 0 && ios_runtime.swift_arc_code == 0
	assert ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0
	assert ios_runtime.swift_array_metadata.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
}
fn test_swift_minimum_merge_run() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && guard != u64(-1)
	// Preserve C's callee-saved registers, seed opaque Swift contexts, leave
	// indirect-result storage inaccessible, and capture x20/x21/x22 on return.
	for i, op in [u32(0xa9bc7bfd), 0xa90157f4, 0xa9024ff6, 0xf9001bf7, 0xaa0103f3,
		0xaa0303f7, 0xaa0203f4, 0x91002055, 0x91004056, 0xaa0203e8, 0xaa0203e1,
		0xaa0203e3, 0xd63f0260, 0xa90056f4, 0xf9000af6, 0xa9424ff6, 0xa94157f4,
		0xf9401bf7, 0xa8c47bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 80))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	invoke := unsafe { MrrContext(voidptr(code)) }
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2);assert core != unsafe { nil }
		run := unsafe { MrrRun(C.dlsym(core, c'$ss22_minimumMergeRunLengthyS2iF')) }
		mrr_cases(run, invoke, guard, false)
		println('NATIVE-MINIMUM-MERGE-RUN: exhaustive -1024..65535 counts, signed extrema, every exponent/prefix rounding boundary, protected unused arguments and x20/x21/x22, 32768 concurrent full-width patterns')
	}
	mut canonical := u64(0)
	for _ in 0 .. 2 {
		objc_start();mrr_empty()
		entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss22_minimumMergeRunLengthyS2iF') or { panic(err) }
		if canonical != 0 { assert entry == canonical };canonical = entry
		run := unsafe { MrrRun(voidptr(entry)) };mrr_cases(run, invoke, guard, true)
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library, '_$ss22_minimumMergeRunLengthyS2iF') == none }
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$ss22_minimumMergeRunLengthyS2iF') == none
		mrr_empty();objc_stop();assert run(9223372036854775807) == 64
	}
	assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0
	println('IOS-MINIMUM-MERGE-RUN: exact signed scalar results and sticky-bit rounding through Int.max, protected unused arguments and preserved x20/x21/x22, eight resolver/call workers, no arena/cache/owner, stable entry and two empty teardowns')
}
