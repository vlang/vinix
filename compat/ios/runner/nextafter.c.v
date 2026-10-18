// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

fn nextafter_underflow() {
	$if arm64 {
		// Execute the native tiny product even when its value is discarded.
		// A constant V expression could be folded away. FZ changes whether
		// this raises underflow alone or underflow together with inexact.
		raw := u64(0x00800000)
		asm volatile aarch64 {
			fmov d16, raw
			fmul s16, s16, s16
			; ; r(raw); v16, memory
		}
	} $else { C.feraiseexcept(int(C.FE_UNDERFLOW) | int(C.FE_INEXACT)) }
}

fn nextafter_overflow() {
	$if arm64 {
		raw := u64(0x7f000000)
		asm volatile aarch64 {
			fmov d16, raw
			fadd s16, s16, s16
			; ; r(raw); v16, memory
		}
	} $else { C.feraiseexcept(int(C.FE_OVERFLOW) | int(C.FE_INEXACT)) }
}

fn darwin_nextafterf(value f32, direction f32) f32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	bits := math.f32_bits(value)
	target := math.f32_bits(direction)
	// A real float add preserves ARM's signaling-NaN priority, payloads and
	// default-NaN control behavior. Integer classification does not quiet NaNs.
	if bits & 0x7fffffff > 0x7f800000 || target & 0x7fffffff > 0x7f800000 {
		return value + direction
	}
	// Use floating comparisons: Darwin honors FZ for subnormal operands and
	// sets the input-denormal status bit, while returning the original target
	// representation when the comparison says equal (including signed zero).
	if direction == value { return direction }
	if value == 0 {
		nextafter_underflow()
		return math.f32_from_bits((target & 0x80000000) | 1)
	}
	up := direction > value
	result := if up == (bits >> 31 == 0) { bits + 1 } else { bits - 1 }
	magnitude := result & 0x7fffffff
	if magnitude < 0x00800000 { nextafter_underflow() }
	else if magnitude == 0x7f800000 { nextafter_overflow() }
	return math.f32_from_bits(result)
}
