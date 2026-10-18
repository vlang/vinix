// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

#include <dlfcn.h>
fn C.dlsym(voidptr, &char) voidptr
type LogbFloat = fn (f32) f32

fn lgb_control_read() u64 {
	$if arm64 { mut value := u64(0); asm volatile aarch64 { mrs value, FPCR; =r(value) }; return value }
	return 0
}

fn lgb_control_write(value u64) {
	$if arm64 { asm volatile aarch64 { msr FPCR, value; ; r(value); memory } }
}

fn lgb_case(get LogbFloat, input u32, expected u32, added int, preset int, sentinel int) {
	assert C.feclearexcept(int(C.FE_ALL_EXCEPT)) == 0
	assert C.feraiseexcept(preset) == 0
	baseline := C.fetestexcept(int(C.FE_ALL_EXCEPT)); control := lgb_control_read(); rounding := C.fegetround()
	darwin_set_errno(sentinel)
	result := math.f32_bits(get(math.f32_from_bits(input)))
	assert result == expected, 'input=${input.hex()} result=${result.hex()} expected=${expected.hex()} control=${control.hex()}'
	assert C.fetestexcept(int(C.FE_ALL_EXCEPT)) == (baseline | added)
	assert unsafe { *C.ios_errno_address() } == sentinel && C.fegetround() == rounding && lgb_control_read() == control
}

fn lgb_profile(get LogbFloat, preset int, sentinel int) {
	previous := lgb_control_read()
	defer { lgb_control_write(previous) }
	for controls in [u64(0), 1 << 24, 1 << 25, (1 << 24) | (1 << 25)]! {
		lgb_control_write((previous & ~u64(0x3000000)) | controls)
		for rounding in [i32(C.FE_TONEAREST), C.FE_UPWARD, C.FE_DOWNWARD, C.FE_TOWARDZERO]! {
			assert C.fesetround(rounding) == 0
			for sign in [u32(0), 0x80000000]! {
				lgb_case(get, sign, 0xff800000, int(C.FE_DIVBYZERO), preset, sentinel)
				lgb_case(get, sign | 0x7f800000, 0x7f800000, 0, preset, sentinel)
				for payload in [u32(1), 0x12345, 0x3fffff, 0x400000, 0x412345, 0x7fffff]! {
					expected := if controls & (1 << 25) != 0 { u32(0x7fc00000) } else { sign | 0x7fc00000 | payload }
					lgb_case(get, sign | 0x7f800000 | payload, expected, if payload & 0x400000 == 0 { int(C.FE_INVALID) } else { 0 }, preset, sentinel)
				}
				// Every normal exponent, with both ends and two interior mantissas.
				for exponent in i32(-126) .. 128 {
					for fraction in [u32(0), 1, 0x345678, 0x7fffff]! {
						input := sign | (u32(exponent + 127) << 23) | fraction
						lgb_case(get, input, math.f32_bits(f32(exponent)), 0, preset, sentinel)
					}
				}
				// Subnormal powers and their upper neighbors exercise each leading bit.
				for bit in 0 .. 23 {
					for fraction in [u32(1) << bit, (u32(1) << (bit + 1)) - 1]! {
						lgb_case(get, sign | fraction, math.f32_bits(f32(bit - 149)), 0, preset, sentinel)
					}
				}
			}
		}
	}
}

fn lgb_worker(get LogbFloat, id int) {
	mut environment := [32]u64{}
	assert C.fegetenv(unsafe { voidptr(&environment[0]) }) == 0
	previous := unsafe { *C.ios_errno_address() }
	defer { C.fesetenv(unsafe { voidptr(&environment[0]) }); darwin_set_errno(previous) }
	lgb_profile(get, if id % 2 == 0 { int(C.FE_INEXACT) } else { int(C.FE_UNDERFLOW) }, 70 + id)
}

fn test_logbf() {
	mut environment := [32]u64{}
	assert C.fegetenv(unsafe { voidptr(&environment[0]) }) == 0
	previous := unsafe { *C.ios_errno_address() }
	defer { C.fesetenv(unsafe { voidptr(&environment[0]) }); darwin_set_errno(previous) }
	get := unsafe { LogbFloat(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_logbf')!)) }
	for preset in [0, int(C.FE_INEXACT), int(C.FE_OVERFLOW) | int(C.FE_UNDERFLOW)]! { lgb_profile(get, preset, 42) }
	$if macos {
		native := unsafe { LogbFloat(C.dlsym(voidptr(-2), c'logbf')) }; assert native != unsafe { nil }
		lgb_profile(native, 0, 42); lgb_profile(native, int(C.FE_INEXACT), 42)
	}
	for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! {
		mut rejected := false; runtime_symbol(library, '_logbf') or { rejected = true }; assert rejected
	}
	assert C.fesetround(C.FE_DOWNWARD) == 0; C.feclearexcept(int(C.FE_ALL_EXCEPT)); C.feraiseexcept(int(C.FE_DIVBYZERO)); flags := C.fetestexcept(int(C.FE_ALL_EXCEPT)); control := lgb_control_read()
	darwin_set_errno(29)
	mut workers := []thread{cap: 8}; for id in 0 .. 8 { workers << spawn lgb_worker(get, id) }; workers.wait(); unsafe { workers.free() }
	assert unsafe { *C.ios_errno_address() } == 29 && C.fetestexcept(int(C.FE_ALL_EXCEPT)) == flags && lgb_control_read() == control
	println('IOS-LOGB: native float ABI, all finite exponent classes, both signs, subnormal boundaries, zero poles, NaN payloads/signaling/default-NaN, four rounding/control modes, sticky flags, errno and eight callers passed')
}
