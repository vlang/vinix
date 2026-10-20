// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Throwing requires an Objective-C exception record, object ownership and
// cleanup/typeinfo understood by the Mach-O unwinder. Stop before touching
// the object while that path is unsupported. This is not a __cxa_throw alias:
// the C++ entry expects an exception record, typeinfo and destructor arguments.
@[noreturn]
fn objc_throw_unavailable(object u64) {
	_ = object
	panic('iOS: Objective-C exception throwing through Mach-O frames is not implemented')
}
