// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The unwinder passes version/actions, exception class, exception storage and
// context in x0..x4. Mach-O unwind registration, LSDA interpretation and
// Objective-C alternate handlers are not supported. Stop before reading or
// modifying any exception/context state or claiming a handler was found.
@[noreturn]
fn objc_personality_unavailable() {
	panic('iOS: Objective-C exception unwinding through Mach-O frames is not implemented')
}
