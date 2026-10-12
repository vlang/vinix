// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Called under the recursive runtime lock. Fields and constant text stay
// borrowed until an independent Swift String has been constructed.
fn swift_error_description_text(object u64) !string {
	if object == 0 || (object !in ios_runtime.objects && object !in ios_runtime.constants) {
		return error('iOS: error description requires registered NSString storage')
	}
	if !objc_is_kind(object, ios_runtime.names['NSString']) {
		return error('iOS: error description fields require NSString')
	}
	text := string_text(object)
	if text.len > 1024 * 1024 { return error('iOS: excessive error description field') }
	return text
}
fn swift_error_description_field(info u64, name string) !u64 {
	if info == 0 { return 0 }
	header := ios_runtime.objects[info] or { return error('iOS: error userInfo requires registered dictionary storage') }
	if !objc_is_kind(info, ios_runtime.names['NSDictionary']) || header.cf_raw_keys || header.cf_raw_values
		|| header.keys.len != header.items.len || header.keys.len > 65536 {
		return error('iOS: unsupported error userInfo dictionary')
	}
	for index, key in header.keys {
		text := swift_error_description_text(key)!
		if text == name { return header.items[index] }
	}
	return 0
}
fn swift_error_description_join(parts [7]string) !SwiftStringWords {
	mut length := 0
	for text in parts {
		if text.len > 1024 * 1024 - length { return error('iOS: excessive error description') }
		length += text.len
	}
	destination := u64(C.__builtin_alloca(16))
	unsafe { *(&SwiftStringWords(destination)) = swift_interpolation_init(i64(length), 0) }
	for text in parts { swift_string_append_bytes(destination, u64(text.str), u64(text.len)) }
	return unsafe { *(&SwiftStringWords(destination)) }
}

// This runtime's Error extraction supports the concrete CFError conformance.
// Validate metadata/table before reading indirect Self or any object bytes;
// native Swift error boxes and arbitrary value Error conformances stay explicit
// unsupported cases. No guest callbacks or temporary NSError objects are used.
fn swift_error_description_checked(metadata u64, table u64, source u64) !SwiftStringWords {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: Swift error description outside runtime lifetime')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	known := ios_runtime.swift_objc_metadata[cf_error_type_id()] or {
		return error('iOS: Swift error description requires extracted CFError metadata')
	}
	if metadata != known || ios_runtime.swift_error_arena == 0
		|| table != ios_runtime.swift_error_arena + u64(C.getpagesize()) + 160 {
		return error('iOS: Swift error description supports the concrete CFError conformance')
	}
	if source == 0 || source & 7 != 0 { return error('iOS: invalid indirect Swift error value') }
	owner := read64(source)
	header := ios_runtime.objects[owner] or { return error('iOS: Swift error description requires live CFError') }
	if header.cls != cf_error_type_id() || C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		return error('iOS: Swift error description requires live CFError')
	}
	info := header.fields[1]
	description := swift_error_description_field(info, 'NSLocalizedDescription')!
	if description != 0 {
		text := swift_error_description_text(description)!
		return swift_error_description_join([text, '', '', '', '', '', '']!)
	}
	domain := swift_error_description_text(header.fields[0])!
	reason_object := swift_error_description_field(info, 'NSLocalizedFailureReason')!
	mut reason := if reason_object != 0 { swift_error_description_text(reason_object)! } else { '' }
	mut has_reason := reason_object != 0
	// Cocoa and Mach catalog callbacks need platform-specific resources. Their
	// explicit localized fields work; manufacturing missing catalog text does
	// not silently fall back to an inaccurate generic message.
	if domain in ['NSCocoaErrorDomain', 'NSMachErrorDomain'] && !has_reason {
		return error('iOS: Cocoa/Mach error description catalogs are not implemented')
	}
	posix_scratch := u64(C.__builtin_alloca(32))
	mut posix_detail := ''
	if domain == 'NSPOSIXErrorDomain' && !has_reason {
		code := i32(header.number)
		message := ctext(u64(error_message(code, unsafe { &u8(posix_scratch) })))
		if code >= 0 && code < darwin_error_messages.len { reason = message; has_reason = true }
		else { posix_detail = message }
	}
	failure := swift_error_description_field(info, 'NSLocalizedFailure')!
	if failure != 0 {
		text := swift_error_description_text(failure)!
		return swift_error_description_join([text, if has_reason { ' ' } else { '' }, reason, '', '', '', '']!)
	}
	prefix := 'The operation couldn’t be completed. '
	if has_reason { return swift_error_description_join([prefix, reason, '', '', '', '', '']!) }
	detail_object := swift_error_description_field(info, 'NSDescription')!
	detail := if detail_object != 0 { swift_error_description_text(detail_object)! } else { posix_detail }
	has_detail := detail_object != 0 || posix_detail != ''
	short_domain := match domain { 'NSOSStatusErrorDomain' { 'OSStatus' } 'NSPOSIXErrorDomain' { 'POSIX' } else { domain } }
	number := u64(C.__builtin_alloca(32))
	count := C.snprintf(unsafe { &char(number) }, 32, c'%lld', header.number)
	if count <= 0 || count >= 32 { return error('iOS: cannot format error code') }
	digits := unsafe { tos(&u8(number), count) }
	return swift_error_description_join(['The operation couldn’t be completed. (', short_domain, ' error ',
		digits, if has_detail { ' - ' } else { '' }, detail, if has_detail { ')' } else { '.)' }]!)
}
fn swift_error_description(metadata u64, table u64, source u64) SwiftStringWords {
	return swift_error_description_checked(metadata, table, source) or { panic(err) }
}
