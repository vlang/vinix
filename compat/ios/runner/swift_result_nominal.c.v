// SPDX-License-Identifier: GPL-2.0-or-later
module main

// This export supplies Result's nominal identity and the copyable generic
// signature Success, Failure: Error. Metadata specialization, value witnesses
// and newer invertible-protocol trailers remain separate runtime features.
fn swift_result_nominal_unavailable(_request u64, _success u64, _failure u64, _conformance u64) SwiftAssociatedMetadata {
	panic('iOS: Swift Result generic instantiation is not implemented')
}

// Share Error's sealed arena, canonical Swift module and Error protocol. No
// separate allocation or lifetime is needed; Error retires after users drain.
fn swift_result_nominal_emit(code u64, data u64, protocol u64) {
	descriptor := data + 896
	entry := code + 640
	write32(entry, 0x58000050)
	write32(entry + 4, 0xd61f0200)
	unsafe { *(&u64(entry + 8)) = u64(voidptr(swift_result_nominal_unavailable)) }
	write32(descriptor, 0xd2) // Unique generic enum, no invertible trailers.
	swift_protocol_relative(descriptor + 4, data + 320)
	swift_protocol_relative(descriptor + 8, data + 960)
	swift_protocol_relative(descriptor + 12, entry)
	write32(descriptor + 20, 0x05000002) // Two payloads, payload size at word five.
	// No field reflection, instantiation cache, pattern or complete metadata.
	write32(descriptor + 36, 0x00010002) // Two parameters, one requirement.
	write32(descriptor + 40, 3) // Two type arguments and Failure's Error witness.
	write32(descriptor + 44, 0x8080)
	write32(descriptor + 48, 0x80) // Key protocol-conformance requirement.
	swift_protocol_relative(descriptor + 52, data + 968)
	swift_protocol_relative(descriptor + 56, protocol)
	C.memcpy(voidptr(data + 960), c'Result', 7)
	C.memcpy(voidptr(data + 968), c'q_', 3) // Failure is generic parameter one.
}

fn swift_result_nominal_symbol(symbol string) ?u64 {
	if symbol != '_$ss6ResultOMn' { return none }
	$if !arm64 { return none }
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// Draining callbacks may borrow an already published identity, but cannot
	// create the Error arena after runtime retirement starts.
	if ios_runtime.swift_error_arena == 0 && ios_runtime.swift_concurrency_retired { return none }
	return swift_error_metadata_arena() + u64(C.getpagesize()) + 896
}
