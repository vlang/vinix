// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftObjCClassFromMetadataFailure {}
fn (_ &SwiftObjCClassFromMetadataFailure) msg() string { return 'iOS: unsupported Swift Objective-C class metadata or lifetime' }
fn (_ &SwiftObjCClassFromMetadataFailure) code() int { return 1 }
__global swift_objc_class_from_metadata_failure_value = SwiftObjCClassFromMetadataFailure{}
fn swift_objc_class_from_metadata_failure() IError { return unsafe { &swift_objc_class_from_metadata_failure_value } }

// Metadata is immutable caller-owned storage: an eight-byte kind, extended
// to 16 bytes for an ObjC wrapper or 40 bytes for a Swift class prefix. No
// value witnesses, nominal descriptor, superclass or class realization are
// needed. Callers must drain before metadata/class storage is retired.
fn swift_objc_class_from_metadata_checked(metadata u64) !u64 {
	// Native Swift preserves its historical null-input behavior.
	if metadata == 0 { return u64(0) }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| metadata & 7 != 0 || metadata > ~u64(0) - 8 { return swift_objc_class_from_metadata_failure() }
	kind := read64(metadata)
	if kind == 0x305 {
		if metadata > ~u64(0) - 16 { return swift_objc_class_from_metadata_failure() }
		cls := read64(metadata + 8)
		// Registry identity establishes the lifetime of the unwrapped class;
		// reject unsupported payloads without dereferencing their storage.
		info := ios_runtime.classes[cls] or { return swift_objc_class_from_metadata_failure() }
		if info.meta || (info.dynamic && !info.registered) { return swift_objc_class_from_metadata_failure() }
		return cls
	}
	// A class kind is zero or an isa pointer above LastEnumeratedMetadataKind.
	if (kind != 0 && kind <= 0x7ff) || metadata > ~u64(0) - 40 { return swift_objc_class_from_metadata_failure() }
	if info := ios_runtime.classes[metadata] {
		if info.meta || (info.dynamic && !info.registered) { return swift_objc_class_from_metadata_failure() }
	}
	if read64(metadata + 32) & 2 == 0 { return swift_objc_class_from_metadata_failure() }
	return metadata
}
// Ordinary C ABI: metadata in x0, borrowed Objective-C class identity in x0.
fn swift_objc_class_from_metadata(metadata u64) u64 {
	return swift_objc_class_from_metadata_checked(metadata) or { panic(err) }
}
