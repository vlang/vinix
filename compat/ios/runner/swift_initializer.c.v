// SPDX-License-Identifier: GPL-2.0-or-later
module main

// AssertionReporting.h and calls into the installed Swift library show an
// ordinary C ABI: signed CInt lengths and UInt32 line/column/flags. Both
// reporters print and return; Swift's _unimplementedInitializer caller traps.
fn swift_initializer_invalid() {
	text := 'Vinix Swift runtime: Fatal error: invalid initializer arguments\n'
	swift_fatal_write(u64(text.str), u64(text.len))
}

fn swift_initializer_line(line u32) {
	storage := unsafe { &u8(C.__builtin_alloca(16)) }
	mut number := line
	mut start := u64(16)
	for {
		start--
		unsafe { *(&u8(u64(storage) + start)) = u8(48 + number % 10) }
		number /= 10
		if number == 0 { break }
	}
	swift_fatal_write(u64(storage) + start, 16 - start)
}

fn swift_initializer_parts(class_name u64, class_length i32, init_name u64,
	init_length i32, file u64, file_length i32, line u32) {
	// Swift's checked conversions produce nonnegative CInt lengths. Reject
	// invalid unsafe inputs before reading any pointer. Zero-length spans
	// are never dereferenced, including spans ending at a protected page.
	if class_name == 0 || init_name == 0 || class_length < 0 || init_length < 0
		|| file_length < 0 {
		swift_initializer_invalid()
		return
	}
	if file != 0 {
		swift_fatal_text(SwiftFatalBytes{ address: file, count: u64(file_length) })
		colon := ':'
		swift_fatal_write(u64(colon.str), 1)
		swift_initializer_line(line)
		swift_fatal_write(u64(c': '), 2)
	}
	prefix := "Fatal error: Use of unimplemented initializer '"
	swift_fatal_write(u64(prefix.str), u64(prefix.len))
	swift_fatal_text(SwiftFatalBytes{ address: init_name, count: u64(init_length) })
	separator := "' for class '"
	swift_fatal_write(u64(separator.str), u64(separator.len))
	swift_fatal_text(SwiftFatalBytes{ address: class_name, count: u64(class_length) })
	swift_fatal_write(u64(c"'\n"), 2)
}

fn swift_initializer_report_in_file(class_name u64, class_length i32, init_name u64,
	init_length i32, file u64, file_length i32, line u32, _column u32, _flags u32) {
	if file == 0 {
		swift_initializer_invalid()
		return
	}
	// The native diagnostic omits column, and flags do not change stderr.
	// Debugger crash annotations/backtraces are not part of this V shim.
	swift_initializer_parts(class_name, class_length, init_name, init_length,
		file, file_length, line)
}

fn swift_initializer_report(class_name u64, class_length i32, init_name u64,
	init_length i32, _flags u32) {
	swift_initializer_parts(class_name, class_length, init_name, init_length, 0, 0, 0)
}
