// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn error_description_append(mut bytes []u8, text string) ! {
	if text.len > 1024 * 1024 - bytes.len { return error('iOS: excessive NSError description') }
	for byte in text { bytes << byte }
}

// NSError's diagnostic description differs from localizedDescription: absent
// diagnostic text is printed as "(null)", rather than the generic sentence.
// UserInfo's dictionary is copied at creation, but its mutable string values
// are shared. Build an independent result on each call under the runtime lock.
// Arbitrary userInfo object descriptions and platform catalogs remain partial.
fn ns_error_description(object u64) !u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !objc_is_kind(object, ios_runtime.names['NSError']) { return error('iOS: description requires NSError') }
	record := unsafe { &AbiNSError(object) }
	info := obj_header(record.user_info)
	if info.keys.len != info.items.len { return error('iOS: invalid NSError userInfo') }
	mut detail := u64(0)
	mut debug := u64(0)
	// Diagnostic precedence is independent of dictionary enumeration order.
	for name in ['NSDescription', 'NSDebugDescription', 'NSLocalizedDescription', 'NSLocalizedFailureReason']! {
		for i, key in info.keys {
			if !objc_is_kind(key, ios_runtime.names['NSString'])
				|| !objc_is_kind(info.items[i], ios_runtime.names['NSString']) {
				return error('iOS: NSError description supports string userInfo values')
			}
			if string_text(key) == name {
				if detail == 0 { detail = info.items[i] }
				else if name == 'NSDebugDescription' { debug = info.items[i] }
			}
		}
	}
	domain := string_text(record.domain)
	mut catalog := '(null)'
	if domain == 'NSCocoaErrorDomain' && record.code == 3840 {
		catalog = 'The data couldn’t be read because it isn’t in the correct format.'
	} else if domain == 'NSOSStatusErrorDomain' && record.code == -50 {
		catalog = 'paramErr: error in user parameter list'
	}
	mut code := [32]u8{}
	count := C.snprintf(unsafe { &char(&code[0]) }, code.len, c'%lld', record.code)
	if count <= 0 || count >= code.len { return error('iOS: cannot format NSError code') }
	mut bytes := []u8{cap: 256}
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	for part in ['Error Domain=', domain, ' Code=', unsafe { tos(&code[0], count) }, ' "',
		if detail == 0 { catalog } else { string_text(detail) }, '"']! {
		error_description_append(mut bytes, part)!
	}
	if debug != 0 {
		error_description_append(mut bytes, ' (')!
		error_description_append(mut bytes, string_text(debug))!
		error_description_append(mut bytes, ')')!
	}
	if info.keys.len != 0 {
		error_description_append(mut bytes, ' UserInfo={')!
		for i, key in info.keys {
			if i != 0 { error_description_append(mut bytes, ', ')! }
			error_description_append(mut bytes, string_text(key))!
			error_description_append(mut bytes, '=')!
			error_description_append(mut bytes, string_text(info.items[i]))!
		}
		error_description_append(mut bytes, '}')!
	}
	return owned_string(unsafe { tos(&bytes[0], bytes.len) })
}
