// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftArrayInitCopyFailure {}
fn (_ &SwiftArrayInitCopyFailure) msg() string { return 'iOS: unsupported Swift array copy initialization' }
fn (_ &SwiftArrayInitCopyFailure) code() int { return 1 }
__global swift_array_init_copy_failure_value = SwiftArrayInitCopyFailure{}
fn swift_array_init_copy_failure() IError { return unsafe { &swift_array_init_copy_failure_value } }

// The caller owns initialized Source, uninitialized disjoint Destination, and
// complete immutable value metadata for the entire call, including callbacks.
// No Array owner is created and no count/capacity or source ownership changes.
fn swift_array_init_copy_checked(destination u64, source u64, count u64, metadata u64) ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return swift_array_init_copy_failure() }
	// Native zero-count calls do not inspect any pointer or metadata.
	if count == 0 { return }
	value := swift_dynamic_cast_value_checked(metadata)!
	stride := read64(value.witness + 72)
	flags := read32(value.witness + 80)
	if flags & 0x00800000 != 0 || count > 1048576 || stride > 1048576 / count {
		return swift_array_init_copy_failure()
	}
	pod := flags & 0x10000 == 0
	// POD bulk copying includes all stride padding. Witness copying only
	// accesses Size bytes in the last element; its final padding may be guarded.
	span := if pod { count * stride } else { (count - 1) * stride + value.size }
	if destination == 0 || source == 0 || (destination | source) & (value.alignment - 1) != 0
		|| destination > ~u64(0) - span || source > ~u64(0) - span
		|| (span != 0 && destination < source + span && source < destination + span) {
		return swift_array_init_copy_failure()
	}
	if pod { C.memcpy(voidptr(destination),voidptr(source),usize(span));return }
	entry := swift_dynamic_cast_entry(value,2)!
	initialize := unsafe { SwiftDynamicCastCopy(voidptr(entry)) }
	// Layout resolution released its registry lock. The borrowed witness may
	// reenter symbol lookup or other runtime work for every initialized value.
	for i in u64(0)..count { initialize(destination + i * stride,source + i * stride,metadata) }
}

// Darwin exports an ordinary C function returning void, not the destination.
fn swift_array_init_copy(destination u64, source u64, count u64, metadata u64) {
	swift_array_init_copy_checked(destination,source,count,metadata) or { panic(err) }
}
