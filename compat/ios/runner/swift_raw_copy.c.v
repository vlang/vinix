// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftRawCopyFailure {}
fn (_ &SwiftRawCopyFailure) msg() string { return 'iOS: invalid Swift raw copy range' }
fn (_ &SwiftRawCopyFailure) code() int { return 1 }
__global swift_raw_copy_failure_value = SwiftRawCopyFailure{}
fn swift_raw_copy_failure() IError { return unsafe { &swift_raw_copy_failure_value } }

// Native Swift method: source x0, signed byteCount x1, raw Self x2.
// Byte copying accepts unaligned and overlapping ranges; it neither owns
// storage nor performs typed value initialization, destruction or ARC work.
fn swift_raw_pointer_copy_checked(source u64, count i64, destination u64) ! {
	if count < 0 { return swift_raw_copy_failure() }
	if count == 0 { return }
	if source == 0 || destination == 0 || u64(count) > u64(-1) - source
		|| u64(count) > u64(-1) - destination { return swift_raw_copy_failure() }
	C.memmove(unsafe { voidptr(destination) }, unsafe { voidptr(source) }, usize(count))
}
fn swift_raw_pointer_copy(source u64, count i64, destination u64) {
	swift_raw_pointer_copy_checked(source, count, destination) or { panic(err) }
}

fn swift_raw_buffer_count_checked(start u64, end u64) !u64 {
	if start == 0 {
		if end != 0 { return swift_raw_copy_failure() }
		return 0
	}
	if end < start || end - start > 0x7fffffffffffffff { return swift_raw_copy_failure() }
	return end - start
}

// Mutable/immutable count/endIndex getters share one entry: Self x0/x1,
// signed Int result in x0. baseAddress returns the optional pointer word
// unchanged (zero is nil); neither getter reads the viewed memory.
fn swift_raw_buffer_count(start u64, end u64) i64 {
	return i64(swift_raw_buffer_count_checked(start, end) or { panic(err) })
}
fn swift_raw_buffer_base(start u64, _end u64) u64 { return start }

// UnsafeRawBufferPointer is two words: start/end, not pointer/count.
// Source x0/x1 precedes destination Self x2/x3; no x20 or indirect result.
fn swift_raw_buffer_copy_checked(source u64, source_end u64, destination u64, destination_end u64) ! {
	count := swift_raw_buffer_count_checked(source, source_end)!
	capacity := swift_raw_buffer_count_checked(destination, destination_end)!
	if count > capacity { return swift_raw_copy_failure() }
	swift_raw_pointer_copy_checked(source, i64(count), destination)!
}
fn swift_raw_buffer_copy(source u64, source_end u64, destination u64, destination_end u64) {
	swift_raw_buffer_copy_checked(source, source_end, destination, destination_end) or { panic(err) }
}
