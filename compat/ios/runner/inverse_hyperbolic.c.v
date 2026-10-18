// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

#include <math.h>
#include <fenv.h>

fn C.acosh(f64) f64
fn C.asinh(f64) f64
fn C.atanh(f64) f64
fn C.fegetround() i32
fn C.fesetround(i32) i32

// Darwin evaluates a scaled expression for tiny asinh/atanh inputs to raise
// inexact and sometimes underflow. In directed rounding this can also move
// the magnitude by one representable value. The native
// expressions subtract/add DBL_MIN before scaling back. Their underflow
// boundaries differ at DBL_MIN/4 and depend on the rounding mode. Classify the
// bits explicitly so the backend's tiny-input expression cannot change them.
fn inverse_hyperbolic_tiny(magnitude u64, asinh bool) u64 {
	rounding := C.fegetround()
	underflow := if asinh {
		if rounding == C.FE_TOWARDZERO || rounding == C.FE_DOWNWARD {
			magnitude <= 0x0010000000000000
		} else {
			magnitude <= 0x0004000000000000
		}
	} else {
		if rounding == C.FE_UPWARD {
			magnitude < 0x0010000000000000
		} else {
			magnitude < 0x0004000000000000
		}
	}
	C.feraiseexcept(int(C.FE_INEXACT) | if underflow { int(C.FE_UNDERFLOW) } else { 0 })
	if asinh && (rounding == C.FE_TOWARDZERO || rounding == C.FE_DOWNWARD) { return magnitude - 1 }
	if !asinh && rounding == C.FE_UPWARD { return magnitude + 1 }
	return magnitude
}

fn inverse_hyperbolic_value(value f64, kind int) f64 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	bits := math.f64_bits(value)
	magnitude := bits & 0x7fffffffffffffff
	if magnitude > 0x7ff0000000000000 {
		if bits & 0x0008000000000000 == 0 { C.feraiseexcept(int(C.FE_INVALID)) }
		return math.f64_from_bits(bits | 0x0008000000000000)
	}
	if (kind == 0 && (bits >> 63 != 0 || magnitude < 0x3ff0000000000000))
		|| (kind == 2 && magnitude > 0x3ff0000000000000) {
		C.feraiseexcept(int(C.FE_INVALID))
		return math.f64_from_bits(0x7ff8000000000000)
	}
	if kind == 2 && magnitude == 0x3ff0000000000000 {
		C.feraiseexcept(int(C.FE_DIVBYZERO))
		return math.f64_from_bits((bits & 0x8000000000000000) | 0x7ff0000000000000)
	}
	if kind == 0 && magnitude == 0x3ff0000000000000 { return 0 }
	if magnitude == 0x7ff0000000000000 { return value }
	if kind != 0 && magnitude < 0x3e40000000000000 {
		if magnitude == 0 { return value }
		adjusted := inverse_hyperbolic_tiny(magnitude, kind == 1)
		return math.f64_from_bits((bits & 0x8000000000000000) | adjusted)
	}
	// The scalar double ABI is shared by Darwin and the native math backend.
	// Preserve Darwin's errno policy while retaining the backend's rounding and
	// exception effects for ordinary finite arguments.
	return match kind {
		0 { C.acosh(value) }
		1 { C.asinh(value) }
		else { C.atanh(value) }
	}
}

fn darwin_acosh(value f64) f64 { return inverse_hyperbolic_value(value, 0) }

fn darwin_asinh(value f64) f64 { return inverse_hyperbolic_value(value, 1) }

fn darwin_atanh(value f64) f64 { return inverse_hyperbolic_value(value, 2) }

fn inverse_hyperbolic_symbol(symbol string) ?u64 {
	return match symbol {
		'_acosh' { u64(unsafe { voidptr(darwin_acosh) }) }
		'_asinh' { u64(unsafe { voidptr(darwin_asinh) }) }
		'_atanh' { u64(unsafe { voidptr(darwin_atanh) }) }
		else { return none }
	}
}
