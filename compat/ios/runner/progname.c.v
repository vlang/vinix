// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Borrow the original argv[0] storage, just like the entry vector. execute's
// arguments outlive binding, initializers, entry, joined workers and teardown.
// Select the basename once: later edits to its bytes remain visible, while
// changing argv[0] or introducing a slash does not move the installed pointer.
fn image_progname_start(argument string) {
	if image_runtime == unsafe { nil } { panic('iOS: program name requires a configured main image') }
	mut offset := 0
	for index in 0 .. argument.len {
		if argument[index] == 0 { break }
		if argument[index] == `/` { offset = index + 1 }
	}
	image_runtime.progname = if argument.str == unsafe { nil } { c'' }
		else { unsafe { &char(argument.str + offset) } }
}

fn darwin_getprogname() &char {
	if image_runtime == unsafe { nil } || image_runtime.progname == unsafe { nil } {
		panic('iOS: program name requires a configured main image')
	}
	return image_runtime.progname
}
