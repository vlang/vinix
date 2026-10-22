// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

$if track_heap ? {
	#include "heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

// Exercise the registration scope's successful and early-return cleanup with
// shared caller-owned strings. Array storage must be retired independently of
// both the compiler's array allocation layout and the strings' lifetime.
fn graphical_arguments_scope(desktop string, fallback string, refuse bool) bool {
	arguments := [desktop, '--register-only']
	alternative := if fallback == '' { []string{} } else { [fallback, '--register-only'] }
	defer {
		retire_graphical_arguments(alternative)
		retire_graphical_arguments(arguments)
	}
	if refuse { return false }
	return arguments[0] == desktop && (alternative.len == 0 || alternative[0] == fallback)
}

fn test_graphical_command_storage_preserves_borrowed_strings() {
	desktop := '/usr/bin/vinix-desktop'.clone()
	fallback := '/usr/bin/vinix-desktop-software'.clone()
	defer { unsafe { desktop.free(); fallback.free() } }
	for _ in 0 .. 1000 {
		$if track_heap ? { C.vinix_heap_begin() }
		assert graphical_arguments_scope(desktop, '', false)
		assert !graphical_arguments_scope(desktop, '', true)
		assert graphical_arguments_scope(desktop, fallback, false)
		assert !graphical_arguments_scope(desktop, fallback, true)
		assert desktop == '/usr/bin/vinix-desktop'
		assert fallback == '/usr/bin/vinix-desktop-software'
		$if track_heap ? { assert C.vinix_heap_end() == 0 }
	}
}
