// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

fn cf_type_id(object u64) u64 {
	if object == 0 { return 0 }
	if objc_is_kind(object, ios_runtime.names['NSString']) { return 1 }
	if objc_is_kind(object, ios_runtime.names['NSArray']) { return 2 }
	if objc_is_kind(object, ios_runtime.names['NSDictionary']) { return 3 }
	// Private IDs need only be stable and distinct; they are not Apple constants.
	return read64(object)
}
fn cf_string_id() u64 { return 1 }
fn cf_string_create(allocator u64, text &char, encoding u32) u64 {
	if allocator != 0 || encoding != 0x08000100 { panic('iOS: unsupported CFString allocator or encoding') }
	if text == unsafe { nil } || !utf8.validate_str(ctext(u64(text))) { return 0 }
	return objc_retain(make_string(text))
}
fn cf_array_count(array u64) i64 { return i64(obj_header(array).items.len) }
fn cf_array_value(array u64, index i64) u64 {
	header := obj_header(array)
	if index < 0 || index >= header.items.len { panic('iOS: CFArray index is out of range') }
	return header.items[int(index)]
}
fn core_foundation_symbol(symbol string) ?u64 {
	return match symbol {
		'_CFRelease' { u64(unsafe { voidptr(objc_release) }) }
		'_CFRetain' { u64(unsafe { voidptr(objc_retain) }) }
		'_CFGetTypeID' { u64(unsafe { voidptr(cf_type_id) }) }
		'_CFStringGetTypeID' { u64(unsafe { voidptr(cf_string_id) }) }
		'_CFStringCreateWithCString' { u64(unsafe { voidptr(cf_string_create) }) }
		'_CFArrayGetCount' { u64(unsafe { voidptr(cf_array_count) }) }
		'_CFArrayGetValueAtIndex' { u64(unsafe { voidptr(cf_array_value) }) }
		else { return none }
	}
}
