// SPDX-License-Identifier: GPL-2.0-or-later
module main

// _ErrorCodeProtocol.~= borrows indirect match x0, Error x1, Self metadata
// x2 and conformance x3; Bool returns in x0. Specialize the canonical Cocoa
// Code conformance without publishing the wider stored-NSError witnesses.
fn swift_cocoa_match_checked(source u64, owner u64, metadata u64, table u64) !bool {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: error-code matching outside runtime lifetime')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	expected := swift_cocoa_error_table_checked(metadata)!
	if table != expected {
		return error('iOS: error-code matching requires the canonical CocoaError.Code conformance')
	}
	// Registry/ARC validation precedes every object read. Swift error boxes and
	// subclasses with overridable domain/code accessors need separate bridging.
	swift_error_bridge_checked(owner)!
	header := ios_runtime.objects[owner] or { return swift_error_bridge_failure() }
	mut domain := u64(0)
	mut code := i64(0)
	if header.cls == cf_error_type_id() {
		domain = header.fields[0]
		code = header.number
	} else if header.cls == ios_runtime.names['NSError'] {
		record := unsafe { &AbiNSError(owner) }
		domain = record.domain
		code = record.code
	} else {
		return error('iOS: error-code matching does not implement NSError subclass accessors')
	}
	if swift_error_description_text(domain)! != 'NSCocoaErrorDomain' { return false }
	// As in native's failed conditional cast, an unrelated domain never needs
	// the borrowed match bytes. Read exactly one word only on the Cocoa path.
	if source == 0 || source & 7 != 0 {
		return error('iOS: error-code matching requires an aligned indirect Code value')
	}
	return read64(source) == u64(code)
}

fn swift_cocoa_match(source u64, owner u64, metadata u64, table u64) bool {
	return swift_cocoa_match_checked(source, owner, metadata, table) or { panic(err) }
}
