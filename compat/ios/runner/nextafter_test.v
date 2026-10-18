// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

#include <dlfcn.h>
fn C.dlsym(voidptr, &char) voidptr

// REFERENCE PROFILE BEGIN
type NextTestCall = fn (f32, f32) f32

fn next_test_control_read() u64 {
	mut value := u64(0)
	$if arm64 { asm volatile aarch64 { mrs value, FPCR; =r(value) } }
	return value
}
fn next_test_control_write(value u64) {
	$if arm64 { asm volatile aarch64 { msr FPCR, value; ; r(value); memory } }
}
fn next_test_status_read() u64 {
	mut value := u64(0)
	$if arm64 { asm volatile aarch64 { mrs value, FPSR; =r(value) } }
	return value
}
fn next_test_status_write(value u64) {
	$if arm64 { asm volatile aarch64 { msr FPSR, value; ; r(value); memory } }
}

fn next_test_pairs() []u64 {
	mut pairs := []u64{ cap: 4096 }
	values := [u32(0), 0x80000000, 1, 2, 0x3fffff, 0x7ffffe, 0x7fffff,
		0x80000001, 0x807fffff, 0x00800000, 0x00800001, 0x80800000,
		0x3f7fffff, 0x3f800000, 0x3f800001, 0xbf800000, 0xbf800001,
		0x7f7ffffe, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000,
		0x7fc00000, 0x7fc12345, 0xffc54321, 0x7fffffff, 0x7f800001,
		0xff800001, 0x7f812345, 0xff812345, 0x7fbfffff, 0xffbfffff]!
	for left in values { for right in values { pairs << u64(left) | (u64(right) << 32) } }
	// Both signs of every finite normal exponent, on either side of its
	// mantissa boundary, stepping toward zero and toward signed infinity.
	for exponent in u32(1) .. 255 {
		for sign in [u32(0), 0x80000000]! {
			for fraction in [u32(0), 0x7fffff]! {
				left := sign | (exponent << 23) | fraction
				for right in [sign, sign | 0x7f800000]! { pairs << u64(left) | (u64(right) << 32) }
			}
		}
	}
	mut state := u32(0x17a9c83d)
	for _ in 0 .. 256 {
		state ^= state << 13; state ^= state >> 17; state ^= state << 5; left := state
		state ^= state << 13; state ^= state >> 17; state ^= state << 5
		pairs << u64(left) | (u64(state) << 32)
	}
	return pairs
}

fn next_test_profile(call NextTestCall, index int) u64 {
	control := next_test_control_read(); status := next_test_status_read()
	ep := C.ios_errno_address(); saved := unsafe { *ep }
	defer { next_test_control_write(control); next_test_status_write(status); unsafe { *ep = saved } }
	selected := (control & ~u64(0x3c00000)) | (u64(index / 16) << 24) | (u64((index / 4) % 4) << 22)
	next_test_control_write(selected)
	preset := [u64(0), 1, 2, 0x14]![index % 4]
	mut digest := u64(0xcbf29ce484222325)
	pairs := next_test_pairs()
	defer { unsafe { pairs.free() } }
	for pair in pairs {
		next_test_status_write(preset)
		unsafe { *ep = i32(70 + index) }
		output := math.f32_bits(call(math.f32_from_bits(u32(pair)), math.f32_from_bits(u32(pair >> 32))))
		flags := next_test_status_read()
		assert unsafe { *ep } == i32(70 + index) && next_test_control_read() == selected
		word := u64(output) | ((flags & 0x9f) << 32)
		for shift in [u32(0), 8, 16, 24, 32, 40, 48, 56]! { digest = (digest ^ u8(word >> shift)) * 0x100000001b3 }
	}
	return digest
}
// REFERENCE PROFILE END

fn next_test_worker(context voidptr) voidptr {
	first := int(u64(context)) - 1
	call := unsafe { NextTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_nextafterf') or { panic(err) })) }
	for index := first; index < 64; index += 8 { assert next_test_profile(call, index) == next_golden[index], 'profile=${index}' }
	return unsafe { nil }
}

fn test_nextafter() {
	$if !arm64 { return }
	call := unsafe { NextTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_nextafterf')!)) }
	pairs := next_test_pairs(); assert pairs.len == 3312; unsafe { pairs.free() }
	for _ in 0 .. 2 {
		system_data_start()!
		for index in 0 .. 64 { assert next_test_profile(call, index) == next_golden[index], 'profile=${index}' }
		$if macos {
			native := unsafe { NextTestCall(C.dlsym(voidptr(-2), c'nextafterf')) }
			for index in 0 .. 64 { assert next_test_profile(native, index) == next_golden[index], 'native profile=${index}' }
		}
		control := next_test_control_read(); status := next_test_status_read(); saved := unsafe { *C.ios_errno_address() }
		mut handles := [8]u64{}
		for index in 0 .. 8 { assert C.pthread_create(unsafe { voidptr(&handles[index]) }, unsafe { nil }, unsafe { voidptr(next_test_worker) }, voidptr(u64(index + 1))) == 0 }
		for handle in handles { assert C.pthread_join(voidptr(handle), unsafe { nil }) == 0 }
		assert next_test_control_read() == control && next_test_status_read() == status && unsafe { *C.ios_errno_address() } == saved
		mut rejected := false; runtime_symbol('/usr/lib/libobjc.A.dylib', '_nextafterf') or { rejected = true }; assert rejected
		system_data_stop()
	}
	println('IOS-NEXTAFTER: 3312 native-reference input pairs, four rounding modes, FZ/default-NaN controls, sticky FPSR flags, NaN priority/payloads, errno, eight callers and two images')
}

// NATIVE GOLDEN BEGIN
const next_golden = [
	u64(0xe8bed2b28fca220f),
	u64(0xfe2876db2baf19e3),
	u64(0x81a263c914b82093),
	u64(0x13b0b0027e0ffb47),
	u64(0xe8bed2b28fca220f),
	u64(0xfe2876db2baf19e3),
	u64(0x81a263c914b82093),
	u64(0x13b0b0027e0ffb47),
	u64(0xe8bed2b28fca220f),
	u64(0xfe2876db2baf19e3),
	u64(0x81a263c914b82093),
	u64(0x13b0b0027e0ffb47),
	u64(0xe8bed2b28fca220f),
	u64(0xfe2876db2baf19e3),
	u64(0x81a263c914b82093),
	u64(0x13b0b0027e0ffb47),
	u64(0xe620f2bf83556a),
	u64(0xcd62c07208d89cb6),
	u64(0x10db61aba940f422),
	u64(0xf2fd8b6192dafa5a),
	u64(0xe620f2bf83556a),
	u64(0xcd62c07208d89cb6),
	u64(0x10db61aba940f422),
	u64(0xf2fd8b6192dafa5a),
	u64(0xe620f2bf83556a),
	u64(0xcd62c07208d89cb6),
	u64(0x10db61aba940f422),
	u64(0xf2fd8b6192dafa5a),
	u64(0xe620f2bf83556a),
	u64(0xcd62c07208d89cb6),
	u64(0x10db61aba940f422),
	u64(0xf2fd8b6192dafa5a),
	u64(0x3f8d675dfe17d6eb),
	u64(0xac4c72236fcc8103),
	u64(0x5b1b6de538e7d4a7),
	u64(0x2e86b2b16dc0d5e3),
	u64(0x3f8d675dfe17d6eb),
	u64(0xac4c72236fcc8103),
	u64(0x5b1b6de538e7d4a7),
	u64(0x2e86b2b16dc0d5e3),
	u64(0x3f8d675dfe17d6eb),
	u64(0xac4c72236fcc8103),
	u64(0x5b1b6de538e7d4a7),
	u64(0x2e86b2b16dc0d5e3),
	u64(0x3f8d675dfe17d6eb),
	u64(0xac4c72236fcc8103),
	u64(0x5b1b6de538e7d4a7),
	u64(0x2e86b2b16dc0d5e3),
	u64(0x7b0f5e142ae84886),
	u64(0x313594ee44e5bbb6),
	u64(0x3afd2205ecb01dd6),
	u64(0xe1e7d47699e3c056),
	u64(0x7b0f5e142ae84886),
	u64(0x313594ee44e5bbb6),
	u64(0x3afd2205ecb01dd6),
	u64(0xe1e7d47699e3c056),
	u64(0x7b0f5e142ae84886),
	u64(0x313594ee44e5bbb6),
	u64(0x3afd2205ecb01dd6),
	u64(0xe1e7d47699e3c056),
	u64(0x7b0f5e142ae84886),
	u64(0x313594ee44e5bbb6),
	u64(0x3afd2205ecb01dd6),
	u64(0xe1e7d47699e3c056),
]!
// NATIVE GOLDEN END
