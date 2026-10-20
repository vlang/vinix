// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Apple's no-argument entry calls std::terminate. Share the backend address
// and its terminate-handler state rather than duplicating an abort path.
fn objc_terminate_symbol(symbol string) ?u64 {
	if symbol != '_objc_terminate' { return none }
	$if ios_cxx ? {
		return cxx_symbol('__ZSt9terminatev') or { panic('iOS: Objective-C terminate backend is unavailable') }
	}
	return u64(unsafe { voidptr(objc_terminate_unavailable) })
}

@[noreturn]
fn objc_terminate_unavailable() {
	panic('iOS: objc_terminate requires the C++ exception runtime backend')
}
