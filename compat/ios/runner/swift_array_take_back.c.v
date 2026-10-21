// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftArrayTakeBackFailure {}
fn (_ &SwiftArrayTakeBackFailure) msg() string { return 'iOS: unsupported Swift backward array take initialization' }
fn (_ &SwiftArrayTakeBackFailure) code() int { return 1 }
__global swift_array_take_back_failure_value = SwiftArrayTakeBackFailure{}
fn swift_array_take_back_failure() IError { return unsafe { &swift_array_take_back_failure_value } }

// Source is consumed; the caller must destroy only the initialized result.
// During a rightward element shift each destination slot is uninitialized or
// has already been moved out by a higher-index take. Metadata stays borrowed.
fn swift_array_take_back_checked(destination u64, source u64, count u64, metadata u64) ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return swift_array_take_back_failure() }
	if count == 0 { return }
	value := swift_dynamic_cast_value_checked(metadata)!
	stride := read64(value.witness + 72)
	flags := read32(value.witness + 80)
	if count > 1048576 || stride > 1048576 / count { return swift_array_take_back_failure() }
	bitwise := flags & 0x100000 == 0
	span := if bitwise { count * stride } else { (count - 1) * stride + value.size }
	if destination == 0 || source == 0 || (destination | source) & (value.alignment - 1) != 0
		|| destination > ~u64(0) - span || source > ~u64(0) - span { return swift_array_take_back_failure() }
	if bitwise {
		// Bitwise takability, including non-POD/noncopyable values, transfers
		// ownership with memmove. It never invokes copy/take/ARC callbacks.
		C.memmove(voidptr(destination),voidptr(source),usize(span));return
	}
	overlap := span != 0 && destination < source + span && source < destination + span
	if overlap && (destination <= source || (destination - source) % stride != 0) {
		return swift_array_take_back_failure()
	}
	entry := swift_dynamic_cast_entry(value,4)!
	take := unsafe { SwiftDynamicCastCopy(voidptr(entry)) }
	// Layout resolution released its lock; a take witness may reenter.
	mut i := count
	for i != 0 { i--;take(destination + i * stride,source + i * stride,metadata) }
}

fn swift_array_take_back(destination u64, source u64, count u64, metadata u64) {
	swift_array_take_back_checked(destination,source,count,metadata) or { panic(err) }
}
