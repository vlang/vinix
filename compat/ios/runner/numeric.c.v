// SPDX-License-Identifier: GPL-2.0-or-later
module main

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
