// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Apple's Objective-C catch entries share the C++ ABI's handler stack and
// adjusted exception pointer. Use the backend entries themselves, so a catch
// begun through either language can be ended through the other. This adds no
// exception-header layout, TLS, retain or pointer adjustment of our own.
fn objc_catch_symbol(symbol string) ?u64 {
	if symbol !in ['_objc_begin_catch', '_objc_end_catch']! { return none }
	$if ios_cxx ? {
		backend := if symbol == '_objc_begin_catch' { '___cxa_begin_catch' } else { '___cxa_end_catch' }
		return cxx_symbol(backend) or { panic('iOS: Objective-C catch backend is unavailable') }
	}
	return if symbol == '_objc_begin_catch' {
		u64(unsafe { voidptr(objc_begin_catch_unavailable) })
	} else {
		u64(unsafe { voidptr(objc_end_catch_unavailable) })
	}
}

@[noreturn]
fn objc_begin_catch_unavailable() {
	panic('iOS: objc_begin_catch requires the C++ exception runtime backend')
}

@[noreturn]
fn objc_end_catch_unavailable() {
	panic('iOS: objc_end_catch requires the C++ exception runtime backend')
}
