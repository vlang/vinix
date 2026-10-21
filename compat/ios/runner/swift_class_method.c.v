// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftClassMethodFailure {}
fn (_ &SwiftClassMethodFailure) msg() string { return 'iOS: unsupported Swift class method metadata or lifetime' }
fn (_ &SwiftClassMethodFailure) code() int { return 1 }
__global swift_class_method_failure_value = SwiftClassMethodFailure{}
fn swift_class_method_failure() IError { return unsafe { &swift_class_method_failure_value } }

fn swift_class_method_words(metadata u64) !u64 {
	if metadata == 0 || metadata & 7 != 0 || metadata > ~u64(0) - 80 { return swift_class_method_failure() }
	kind := read64(metadata)
	if (kind != 0 && kind <= 0x7ff) || read64(metadata + 32) & 2 == 0 { return swift_class_method_failure() }
	size := u64(read32(metadata + 56)); point := u64(read32(metadata + 60))
	if size & 7 != 0 || point & 7 != 0 || size < point || size - point < 80
		|| metadata > ~u64(0) - (size - point) { return swift_class_method_failure() }
	return (size - point) / 8
}

// Borrow initialized immutable class metadata and a version-zero, nongeneric
// class descriptor without a resilient superclass or initialization trailer.
// These are the layouts used by all six Fortnite lookup thunks. The descriptor
// identifies the slot; the dynamic metadata supplies the overridden entry.
// Callers must drain readers before unmapping either borrowed allocation.
fn swift_class_method_checked(metadata u64, method u64, description u64) !u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| description == 0 || description & 3 != 0 || description > ~u64(0) - 52 {
		return swift_class_method_failure()
	}
	flags := read32(description)
	if flags & 0x1f != 16 || flags & 0xff80 != 0 || flags & 0x20030000 != 0
		|| flags & 0x80000000 == 0 { return swift_class_method_failure() }
	offset := u64(read32(description + 44)); count := u64(read32(description + 48))
	methods := description + 52
	if count == 0 || methods > ~u64(0) - count * 8 || method < methods
		|| method >= methods + count * 8 || (method - methods) & 7 != 0 {
		return swift_class_method_failure()
	}
	words := swift_class_method_words(metadata)!
	if offset < 10 || offset + count > u64(read32(description + 28)) || offset + count > words {
		return swift_class_method_failure()
	}
	// Establish that description belongs to this class or an ancestor. Bound
	// traversal to reject cycles without allocating a visited set.
	mut ancestor := metadata
	for _ in 0 .. 256 {
		if read64(ancestor + 64) == description {
			return read64(metadata + (offset + (method - methods) / 8) * 8)
		}
		ancestor = read64(ancestor + 8)
		swift_class_method_words(ancestor)!
	}
	return swift_class_method_failure()
}

// Ordinary C ABI: metadata/method/description in x0/x1/x2, entry in x0.
fn swift_class_method(metadata u64, method u64, description u64) u64 {
	return swift_class_method_checked(metadata, method, description) or { panic(err) }
}
