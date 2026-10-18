// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Darwin exposes the writable process environment cell, not a snapshot of its
// vector. Share the libc cell used by the existing getenv/setenv/unsetenv imports
// so vector replacement and libc growth remain visible through the same address.
fn darwin_ns_get_environ() &&&char {
	return unsafe { &C.environ }
}
