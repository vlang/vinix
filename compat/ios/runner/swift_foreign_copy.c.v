// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Optional<Int> returns its payload in x0 and nil tag in the low byte of x1.
struct SwiftOptionalInt {
	value i64
	is_nil u64
}

// Native ARM64: destination/count x0/x1, borrowed _StringGuts x2/x3.
// Registered foreign NSString/decoded constants use the existing checked
// UTF-16 extent and UTF-8 validation. Hold that borrow until copying finishes.
fn swift_foreign_copy_checked(destination u64, capacity i64, first u64, second u64) !SwiftOptionalInt {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_foreign_count_failure()
	}
	if capacity < 0 || (destination == 0 && capacity != 0)
		|| u64(capacity) > u64(-1) - destination { return swift_raw_copy_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	count := swift_foreign_count_checked(first,second)!
	if count > capacity { return SwiftOptionalInt{is_nil:1} }
	if count != 0 {
		text := swift_foreign_count_text(second & swift_address_mask)!
		C.memmove(unsafe { voidptr(destination) },text.str,usize(count))
	}
	return SwiftOptionalInt{value:count}
}
fn swift_foreign_copy(destination u64, capacity i64, first u64, second u64) SwiftOptionalInt {
	return swift_foreign_copy_checked(destination,capacity,first,second) or { panic(err) }
}
