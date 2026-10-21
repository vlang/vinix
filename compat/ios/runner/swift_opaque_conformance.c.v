// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftOpaqueConformanceFailure {}
fn (_ &SwiftOpaqueConformanceFailure) msg() string { return 'iOS: unsupported Swift opaque conformance descriptor or accessor expression' }
fn (_ &SwiftOpaqueConformanceFailure) code() int { return 1 }
__global swift_opaque_conformance_failure_value = SwiftOpaqueConformanceFailure{}
fn swift_opaque_conformance_failure() IError { return unsafe { &swift_opaque_conformance_failure_value } }
type SwiftOpaqueConformanceAccessor = fn (u64) u64

fn swift_opaque_conformance_relative(field u64, bits u32) !u64 {
	delta := i64(i32(bits))
	if delta == 0 || (delta > 0 && field > ~u64(0) - u64(delta))
		|| (delta < 0 && field <= u64(-delta)) { return swift_opaque_conformance_failure() }
	return if delta > 0 { field + u64(delta) } else { field - u64(-delta) }
}

fn swift_opaque_conformance_accessor(descriptor u64, index u32) !u64 {
	if descriptor == 0 || descriptor & 3 != 0 || descriptor > ~u64(0) - 8 { return swift_opaque_conformance_failure() }
	flags := read32(descriptor); count := flags >> 16
	if flags & 0xffff !in [u32(4), 0x44, 0x84, 0xc4]! || count == 0 || count > 64 || index >= count { return swift_opaque_conformance_failure() }
	mut offset := u64(8)
	if flags & 0x80 != 0 {
		if descriptor > ~u64(0) - 16 { return swift_opaque_conformance_failure() }
		sizes := read32(descriptor + 8); arguments := read32(descriptor + 12)
		parameters := sizes & 0xffff; requirements := sizes >> 16
		// Pack shapes change the trailing layout. Ordinary generic parameter
		// and requirement bodies are unused by a standalone accessor reference.
		if parameters > 64 || requirements > 64 || arguments & 0xffff > 128 || arguments >> 16 != 0 { return swift_opaque_conformance_failure() }
		offset = 16 + ((u64(parameters) + 3) & ~u64(3)) + u64(requirements) * 12
	}
	offset += u64(index) * 4
	if descriptor > ~u64(0) - offset - 4 { return swift_opaque_conformance_failure() }
	field := descriptor + offset
	name := swift_opaque_conformance_relative(field, read32(field))!
	mut cursor := name
	// Swift mangled names allow 0xff alignment padding before a reference.
	// Accept at most 64 bytes before one 0x09 + signed rel32 reference.
	for _ in 0..64 {
		if cursor == ~u64(0) { return swift_opaque_conformance_failure() }
		if unsafe { *(&u8(cursor)) } != 0xff { break }
		cursor++
	}
	if cursor > ~u64(0) - 6 || unsafe { *(&u8(cursor)) } != 9 { return swift_opaque_conformance_failure() }
	mut bits := u32(0)
	for i in 0..4 { bits |= u32(unsafe { *(&u8(cursor + 1 + u64(i))) }) << u32(i * 8) }
	accessor := swift_opaque_conformance_relative(cursor + 1, bits)!
	if accessor == 0 || accessor & 3 != 0 { return swift_opaque_conformance_failure() }
	cursor += 5
	if unsafe { *(&u8(cursor)) } != 0 { return swift_opaque_conformance_failure() }
	return accessor
}

// SwiftCC's three scalar arguments/result use x0/x1/x2 and x0 on ARM64.
// The runtime's index is unsigned 32-bit. The selected symbolic accessor is
// an ordinary C call receiving the original argument-vector pointer unchanged.
// All descriptor/name/code/result storage is borrowed until callers drain.
fn swift_opaque_conformance_checked(arguments u64, descriptor u64, index u32) !u64 {
	C.ios_objc_initialize_lock()
	active := ios_runtime != unsafe { nil } && !ios_runtime.swift_concurrency_retired
	C.ios_objc_initialize_unlock()
	if !active { return swift_opaque_conformance_failure() }
	entry := swift_opaque_conformance_accessor(descriptor, index)!
	// No lock spans caller code; no argument, witness or result bytes are read.
	return unsafe { SwiftOpaqueConformanceAccessor(voidptr(entry))(arguments) }
}
fn swift_opaque_conformance(arguments u64, descriptor u64, index u32) u64 {
	return swift_opaque_conformance_checked(arguments, descriptor, index) or { panic(err) }
}
