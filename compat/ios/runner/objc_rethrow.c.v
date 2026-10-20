// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Apple delegates this no-argument entry to the shared C++ handler state.
// Use the backend entry itself, including its current terminal diagnostic for
// unsupported Mach-O unwinding. Never call a native host unwinder directly.
fn objc_rethrow_symbol(symbol string) ?u64 {
	if symbol != '_objc_exception_rethrow' { return none }
	$if ios_cxx ? {
		return cxx_symbol('___cxa_rethrow') or { panic('iOS: Objective-C rethrow backend is unavailable') }
	}
	return u64(unsafe { voidptr(objc_rethrow_unavailable) })
}

@[noreturn]
fn objc_rethrow_unavailable() {
	panic('iOS: objc_exception_rethrow requires the C++ exception runtime backend')
}
