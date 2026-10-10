// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

#include <fenv.h>

fn C.fegetenv(voidptr) int
fn C.feholdexcept(voidptr) int
fn C.fesetenv(voidptr) int
fn C.feclearexcept(int) int
fn C.fetestexcept(int) int
fn C.feraiseexcept(int) int

fn numeric_hex_input(text &char) bool {
	unsafe {
		mut position := 0
		for text[position] == 32 || (text[position] >= 9 && text[position] <= 13) { position++ }
		if text[position] == 43 || text[position] == 45 { position++ }
		return text[position] == 48 && (text[position + 1] == 120 || text[position + 1] == 88)
	}
}

fn darwin_atof(text &char) f64 {
	// Darwin keeps errno on no conversion; musl's strtod sets EINVAL.
	previous := unsafe { *C.ios_errno_address() }
	// Native fenv_t is opaque (16 bytes on the Mac, 8 on the ARM64 guest).
	// Preserve status and rounding mode, while observing this conversion's
	// inexact flag. Darwin's parser leaves the caller's environment unchanged.
	mut environment := [32]u64{}
	C.feholdexcept(unsafe { voidptr(&environment[0]) })
	mut end := unsafe { &char(nil) }
	value := C.strtod(text, unsafe { &end })
	mut conversion_error := unsafe { *C.ios_errno_address() }
	inexact := C.fetestexcept(int(C.FE_INEXACT)) != 0
	if end == text { conversion_error = previous }
	// Observed Darwin policy: decimal subnormals always report ERANGE;
	// hexadecimal subnormals do so only if rounding loses precision.
	magnitude := if value < 0 { -value } else { value }
	if magnitude < 2.2250738585072014e-308 && (inexact || (magnitude > 0 && !numeric_hex_input(text))) {
		conversion_error = 34
	}
	C.fesetenv(unsafe { voidptr(&environment[0]) })
	darwin_set_errno(conversion_error)
	return value
}

fn darwin_atoll(text &char) i64 {
	// Darwin uses the checked decimal conversion: saturation and ERANGE on
	// overflow, EINVAL when there are no digits. musl's atoll omits those checks.
	return C.strtoll(text, unsafe { nil }, 10)
}

fn numeric_nan_payload(text &char) u64 {
	// The installed Darwin library accepts unsigned base-0 integer tags,
	// wraps overflow, and discards the entire payload on any invalid byte.
	// Parse in integer registers: neither errno nor the floating environment
	// may change, including when a tag is much larger than u64.
	mut position := usize(0)
	mut base := u64(10)
	unsafe {
		if text[0] == 48 {
			base = 8
			if text[1] == 120 || text[1] == 88 {
				base = 16
				position = 2
			}
		}
		mut payload := u64(0)
		for text[position] != 0 {
			byte := u8(text[position])
			digit := match true {
				byte >= 48 && byte <= 57 { u64(byte - 48) }
				byte >= 65 && byte <= 70 { u64(byte - 65 + 10) }
				byte >= 97 && byte <= 102 { u64(byte - 97 + 10) }
				else { return 0 }
			}
			if digit >= base { return 0 }
			payload = payload * base + digit
			position++
		}
		return payload
	}
}

fn darwin_nan(text &char) f64 {
	return math.f64_from_bits(u64(0x7ff8000000000000) | (numeric_nan_payload(text) & u64(0x0007ffffffffffff)))
}

fn darwin_nanf(text &char) f32 {
	return math.f32_from_bits(u32(0x7fc00000) | (u32(numeric_nan_payload(text)) & u32(0x003fffff)))
}
