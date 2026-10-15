// SPDX-License-Identifier: GPL-2.0-or-later
// Scalar C truth conversion and task-context observations through V calls.
@[translated]
module sleepfixture

import sleepspy as spy

#include "contract.h"

@[typedef]
struct C.vsl_complex {}

@[c: 'might_sleep_if'] fn C.sleep_bool(bool)
@[c: 'might_sleep_if'] fn C.sleep_i8(i8)
@[c: 'might_sleep_if'] fn C.sleep_i32(i32)
@[c: 'might_sleep_if'] fn C.sleep_i64(i64)
@[c: 'might_sleep_if'] fn C.sleep_u64(u64)
@[c: 'might_sleep_if'] fn C.sleep_float(f64)
@[c: 'might_sleep_if'] fn C.sleep_pointer(voidptr)
@[c: 'might_sleep_if'] fn C.sleep_complex(C.vsl_complex)
fn C.vsl_make_complex(f64, f64) C.vsl_complex
fn C.vsl_condition_value() i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.atoi(&char) i32
fn C.puts(&char) i32

fn floating(bits u64) f64 {
	mut value := f64(0)
	unsafe { C.memcpy(&value, &bits, 8) }
	return value
}

@[direct_array_access]
fn false_contexts() {
	for mode in [i32(0), i32(1), i32(2), i32(3), i32(4)]! {
		spy.configure(mode, 0, true)
		C.sleep_i32(C.vsl_condition_value())
		spy.verify(0, 1)
	}
}

@[direct_array_access]
fn scalar_truth() {
	for value in [i64(0), i64(-1), i64(1), i64(-9223372036854775807), i64(9223372036854775807)]! {
		spy.configure(0, 0, false)
		C.sleep_i64(value)
		spy.verify(if value == 0 { u32(0) } else { u32(1) }, 0)
	}
	for value in [u64(0), u64(1), u64(0x8000000000000000), ~u64(0)]! {
		spy.configure(0, 0, false)
		C.sleep_u64(value)
		spy.verify(if value == 0 { u32(0) } else { u32(1) }, 0)
	}
	for value in [i8(0), i8(-128), i8(127)]! {
		spy.configure(0, 0, false)
		C.sleep_i8(value)
		spy.verify(if value == 0 { u32(0) } else { u32(1) }, 0)
	}
	for bits in [u64(0), u64(0x8000000000000000), u64(0x3ff0000000000000), u64(0xbff0000000000000), u64(0x7ff8000000000001)]! {
		spy.configure(0, 0, false)
		C.sleep_float(floating(bits))
		spy.verify(if bits << 1 == 0 { u32(0) } else { u32(1) }, 0)
	}
	for address in [usize(0), usize(1), usize(16)]! {
		spy.configure(0, 0, false)
		unsafe { C.sleep_pointer(voidptr(address)) }
		spy.verify(if address == 0 { u32(0) } else { u32(1) }, 0)
	}
	for imaginary in [f64(0), f64(1), f64(-1)]! {
		spy.configure(0, 0, false)
		C.sleep_complex(C.vsl_make_complex(0.0, imaginary))
		spy.verify(if imaginary == 0 { u32(0) } else { u32(1) }, 0)
	}
	for condition in [false, true]! {
		spy.configure(0, 0, false)
		if condition { C.sleep_bool(true) } else { C.sleep_bool(false) }
		spy.verify(if condition { u32(1) } else { u32(0) }, 0)
	}
	spy.configure(0, -3, true)
	C.sleep_i32(C.vsl_condition_value())
	spy.verify(1, 1)
}

// The controller applies a #line directive to this unchanged generated body.
fn fatal_case(mode i32) {
	spy.configure(mode, 1, true)
	C.sleep_i32(C.vsl_condition_value())
	spy.require(false, 7)
}

@[export: 'vsl_fixture_entry']
pub fn run(argc i32, argv &&char) i32 {
	if argc > 1 {
		mode := unsafe { C.atoi(argv[1]) }
		spy.require(mode > 0 && mode <= 4, 8)
		fatal_case(mode)
	}
	false_contexts()
	scalar_truth()
	spy.finish()
	C.puts(c'PASS: conditional sleep preserves scalar C truth, single evaluation, context, caller location and scheduling state')
	return 0
}
