// SPDX-License-Identifier: GPL-2.0-or-later
module main

// swift_unexpectedError consumes an Error in x0, followed by the filename
// pointer/count, ASCII bit and line in x1..x4. Its Swift Never result must trap
// even when reporting fails. General Swift error reflection is not available;
// use the bounded concrete CFError description supported by this runtime.
fn swift_unexpected_error_report(owner u64, filename u64, count u64, ascii u64, line u64) {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		swift_unexpected_error_unsupported()
		return
	}
	words := swift_describing_error(owner) or {
		swift_unexpected_error_unsupported()
		return
	}
	storage := unsafe { &u8(C.__builtin_alloca(16)) }
	message := swift_fatal_string(words.first, words.second, storage)
	prefix := "Fatal error: 'try!' expression unexpectedly raised an error"
	args := SwiftFatalArguments{
		prefix_data: u64(prefix.str), prefix_count: u64(prefix.len)
		file_data: filename, file_count: count, file_flags: (ascii & 1) << 1
		line: line
	}
	swift_fatal_report_parts(unsafe { &args }, message)
	// The description owns its copied bytes. Retire both it and the consumed
	// error after the last read, outside swift_describing_error's registry lock.
	swift_bridge_release(words.second)
	objc_release(owner)
}

fn swift_unexpected_error_unsupported() {
	text := 'Vinix Swift runtime: Fatal error: unexpected error reflection is not implemented for this value\n'
	swift_fatal_write(u64(text.str), u64(text.len))
}

fn swift_unexpected_error_emit(code u64) {
	for i, op in [u32(0xa9bf7bfd), // stp x29,x30,[sp,#-16]!
		0x910003fd, // mov x29,sp
		0x58000090, 0xd63f0200, // load V body from +24 and call it
		0xd4200020, 0x17ffffff]! { // BRK #1; trap again if a handler returns
		write32(code + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 24)) = u64(voidptr(swift_unexpected_error_report)) }
}
