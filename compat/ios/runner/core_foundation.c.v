// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8
import time

struct CFRange {
	location i64
	length i64
}

fn cf_allocator_check(allocator u64) {
	if allocator != 0 && allocator != cf_allocator_default() { panic('iOS: custom CFAllocator is not implemented') }
}

fn cf_allocator_default() u64 {
	return framework_object('_kCFAllocatorSystemDefault')
}

fn cf_type_id(object u64) u64 {
	if object == 0 { return 0 }
	if objc_is_kind(object, ios_runtime.names['NSString']) { return 1 }
	if objc_is_kind(object, ios_runtime.names['NSArray']) { return 2 }
	if objc_is_kind(object, ios_runtime.names['NSDictionary']) { return 3 }
	if objc_is_kind(object, ios_runtime.names['NSData']) { return 4 }
	if objc_is_kind(object, ios_runtime.names['NSNumber']) { return if obj_header(object).cf_boolean { u64(6) } else { u64(5) } }
	// Private IDs need only be stable and distinct; they are not Apple constants.
	return read64(object)
}
fn cf_string_id() u64 { return 1 }
fn cf_array_id() u64 { return 2 }
fn cf_dictionary_id() u64 { return 3 }
fn cf_data_id() u64 { return 4 }
fn cf_number_id() u64 { return 5 }
fn cf_boolean_id() u64 { return 6 }

fn cf_string_create(allocator u64, text &char, encoding u32) u64 {
	if text == unsafe { nil } { return 0 }
	return cf_string_bytes(allocator, u64(text), i64(darwin_strlen(text)), encoding, false)
}

fn cf_string_bytes(allocator u64, bytes u64, length i64, encoding u32, external bool) u64 {
	_ = external
	cf_allocator_check(allocator)
	if length < 0 || length > 16777216 || (bytes == 0 && length != 0) { panic('iOS: invalid CFString byte buffer') }
	if encoding !in [u32(0x08000100), 0x0600] { panic('iOS: CFString encoding is not implemented') }
	mut text := if length == 0 { '' } else { unsafe { tos(&u8(bytes), int(length)) } }
	if encoding == 0x08000100 {
		if !utf8.validate_str(text) { return 0 }
		if text.len >= 3 && text[0] == 0xef && text[1] == 0xbb && text[2] == 0xbf { text = unsafe { tos(text.str + 3, text.len - 3) } }
	} else {
		// The installed CF decoder accepts all 8-bit values for ASCII input,
		// mapping them to U+0000..U+00FF. ASCII output remains strict.
		mut converted := []u8{cap: text.len * 2}
		defer { unsafe { converted.free() } }
		for byte in text {
			if byte < 128 { converted << byte }
			else { converted << (u8(0xc0) | (byte >> 6)); converted << (u8(0x80) | (byte & 0x3f)) }
		}
		return owned_string(if converted.len == 0 { '' } else { unsafe { tos(converted.data, converted.len) } })
	}
	return owned_string(text)
}

fn cf_string_length(object u64) i64 {
	mut length := i64(0)
	for byte in string_text(object) {
		if byte & 0xc0 != 0x80 { length += if byte >= 0xf0 { i64(2) } else { i64(1) } }
	}
	return length
}

// CFRange counts UTF-16 code units; buffers count bytes and have no terminator.
// A sizing call ignores max_length. A partial UTF-8 conversion never splits a
// scalar or consumes half a surrogate pair, even when a loss byte is supplied.
fn cf_string_get_bytes(object u64, range CFRange, encoding u32, loss u8, external bool, buffer u64, max_length i64, used &i64) i64 {
	if encoding !in [u32(0x08000100), 0x0600] { panic('iOS: CFString output encoding is not implemented') }
	length := cf_string_length(object)
	if range.location < 0 || range.length < 0 || range.location > length || range.length > length - range.location || max_length < 0 {
		panic('iOS: invalid CFString range or output buffer')
	}
	_ = external // UTF-8/ASCII output has no byte-order marker.
	text := string_text(object)
	mut offset := 0
	mut unit := i64(0)
	mut converted := i64(0)
	mut written := i64(0)
	query := buffer == 0 || max_length == 0
	for offset < text.len && unit < range.location + range.length {
		start := offset
		first := text[offset]
		width := if first < 0x80 { 1 } else if first < 0xe0 { 2 } else if first < 0xf0 { 3 } else { 4 }
		units := if width == 4 { i64(2) } else { i64(1) }
		offset += width
		if unit + units <= range.location { unit += units; continue }
		selected_start := if unit < range.location { range.location } else { unit }
		selected_end := if unit + units > range.location + range.length { range.location + range.length } else { unit + units }
		selected := selected_end - selected_start
		if encoding == 0x08000100 {
			if selected != units || (!query && i64(width) > max_length - written) { break }
			if !query { unsafe { C.memcpy(voidptr(buffer + u64(written)), text.str + start, usize(width)) } }
			written += width
			converted += units
		} else {
			if first >= 128 && loss == 0 { break }
			for _ in 0 .. int(selected) {
				if !query && written == max_length { if used != unsafe { nil } { unsafe { *used = written } }; return converted }
				if !query { unsafe { *(&u8(buffer + u64(written))) = if first < 128 { first } else { loss } } }
				written++
				converted++
			}
		}
		unit += units
	}
	if used != unsafe { nil } { unsafe { *used = written } }
	return converted
}

fn cf_string_get_cstring(object u64, buffer u64, capacity i64, encoding u32) bool {
	if buffer == 0 || capacity <= 0 { return false }
	mut used := i64(0)
	length := cf_string_length(object)
	// A zero-sized CFStringGetBytes call is a query, so handle capacity == 1 here.
	if capacity == 1 && length != 0 { return false }
	converted := cf_string_get_bytes(object, CFRange{0, length}, encoding, 0, false, buffer, capacity - 1, &used)
	if converted != length { return false }
	unsafe { *(&u8(buffer + u64(used))) = 0 }
	return true
}

fn cf_callbacks_raw(callbacks u64, symbol string, size u64) bool {
	if callbacks == 0 { return true }
	standard := cf_callbacks_constant(symbol)
	if C.memcmp(unsafe { voidptr(callbacks) }, unsafe { voidptr(standard) }, usize(size)) == 0 { return false }
	for index := u64(0); index < size; index += 8 { if read64(callbacks + index) != 0 { panic('iOS: custom CF collection callbacks are not implemented') } }
	return true
}

fn cf_array_create(allocator u64, values u64, count i64, callbacks u64) u64 {
	cf_allocator_check(allocator)
	if count < 0 || count > 65536 || (count != 0 && values == 0) { panic('iOS: invalid CFArray values') }
	raw := cf_callbacks_raw(callbacks, '_kCFTypeArrayCallBacks', 40)
	array := objc_allocate(ios_runtime.names['NSArray'])
	mut header := obj_header(array)
	header.cf_raw_values = raw
	for index := i64(0); index < count; index++ {
		value := read64(values + u64(index) * 8)
		if raw { header.items << value } else { array_append(mut header, value) }
	}
	return array
}
fn cf_array_count(array u64) i64 { return i64(obj_header(array).items.len) }
fn cf_array_value(array u64, index i64) u64 {
	header := obj_header(array)
	if index < 0 || index >= header.items.len { panic('iOS: CFArray index is out of range') }
	return header.items[int(index)]
}

fn cf_dictionary_mutable(allocator u64, capacity i64, keys u64, values u64) u64 {
	cf_allocator_check(allocator)
	if capacity < 0 || capacity > 65536 { panic('iOS: invalid CFDictionary capacity') }
	raw_keys := cf_callbacks_raw(keys, '_kCFTypeDictionaryKeyCallBacks', 48)
	raw_values := cf_callbacks_raw(values, '_kCFTypeDictionaryValueCallBacks', 40)
	object := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	mut header := obj_header(object)
	header.cf_raw_keys = raw_keys
	header.cf_raw_values = raw_values
	return object
}

fn cf_dictionary_create(allocator u64, keys u64, values u64, count i64, key_callbacks u64, value_callbacks u64) u64 {
	if count < 0 || count > 65536 || (count != 0 && (keys == 0 || values == 0)) { panic('iOS: invalid CFDictionary entries') }
	object := cf_dictionary_mutable(allocator, count, key_callbacks, value_callbacks)
	for index := i64(0); index < count; index++ { cf_dictionary_set(object, read64(keys + u64(index) * 8), read64(values + u64(index) * 8)) }
	// It is toll-free bridged, but mutation of the immutable result must fail.
	unsafe { *(&u64(object)) = ios_runtime.names['NSDictionary'] }
	return object
}

fn cf_dictionary_value(object u64, key u64) u64 {
	header := obj_header(object)
	index := dictionary_index(header, key)
	return if index >= 0 { header.items[index] } else { u64(0) }
}

fn cf_dictionary_set(object u64, key u64, value u64) {
	if !objc_is_kind(object, ios_runtime.names['NSMutableDictionary']) { panic('iOS: CFDictionarySetValue requires a mutable dictionary') }
	if key == 0 || value == 0 { panic('iOS: nil CFDictionary entry') }
	mut header := obj_header(object)
	index := dictionary_index(header, key)
	if index >= 0 {
		if header.cf_raw_values { header.items[index] = value } else { objc_store_strong(unsafe { &header.items[index] }, value) }
		header.mutation++
	} else {
		header.keys << if header.cf_raw_keys { key } else { objc_retain(key) }
		array_append(mut header, value)
	}
}

fn cf_data_create(allocator u64, bytes u64, count i64) u64 {
	cf_allocator_check(allocator)
	if count < 0 || count > 16777216 || (count != 0 && bytes == 0) { panic('iOS: invalid CFData buffer') }
	object := objc_allocate(ios_runtime.names['NSData'])
	mut header := obj_header(object)
	header.data = []u8{len: int(count)}
	header.data.flags |= .noslices
	if count != 0 { unsafe { C.memcpy(header.data.data, voidptr(bytes), usize(count)) } }
	return object
}

fn cf_data_mutable(allocator u64, capacity i64) u64 {
	cf_allocator_check(allocator)
	if capacity < 0 || capacity > 16777216 { panic('iOS: invalid CFData capacity') }
	object := objc_allocate(ios_runtime.names['NSMutableData'])
	mut header := obj_header(object)
	header.data = []u8{cap: int(capacity)}
	header.data.flags |= .noslices
	return object
}

fn cf_data_set_length(object u64, length i64) {
	if !objc_is_kind(object, ios_runtime.names['NSMutableData']) || length < 0 || length > 16777216 { panic('iOS: invalid CFMutableData length') }
	mut header := obj_header(object)
	if length < header.data.len { header.data.trim(int(length)) }
	else { for header.data.len < int(length) { header.data << u8(0) } }
}

fn cf_number_create(allocator u64, kind i64, value u64) u64 {
	cf_allocator_check(allocator)
	if value == 0 || kind < 1 || kind > 16 { panic('iOS: invalid CFNumber type or value') }
	object := objc_allocate(ios_runtime.names['NSNumber'])
	mut header := obj_header(object)
	match kind {
		1, 7 { header.number = unsafe { i64(*(&i8(value))) } }
		2, 8 { header.number = unsafe { i64(*(&i16(value))) } }
		3, 9 { header.number = unsafe { i64(*(&i32(value))) } }
		5, 12 { header.is_real = true; header.real_number = unsafe { f64(*(&f32(value))) } }
		6, 13, 16 { header.is_real = true; header.real_number = unsafe { *(&f64(value)) } }
		else { header.number = i64(read64(value)) }
	}
	return object
}

fn cf_boolean_value(object u64) bool { return obj_header(object).number != 0 }
fn cf_absolute_time() f64 { return f64(time.now().unix_micro()) / 1e6 - 978307200.0 }

fn cf_callback_retain(allocator u64, value u64) u64 { _ = allocator; return objc_retain(value) }
fn cf_callback_release(allocator u64, value u64) { _ = allocator; objc_release(value) }

fn cf_hash(object u64) u64 {
	if object == 0 { return 0 }
	if read64(object) == sec_policy_type_id() { return cf_hash(obj_header(object).fields[0]) }
	if objc_is_kind(object, ios_runtime.names['NSIndexPath']) { return u64(obj_header(object).number) ^ (u64(obj_header(object).section) * 1099511628211) }
	if objc_is_kind(object, ios_runtime.names['NSArray']) || objc_is_kind(object, ios_runtime.names['NSDictionary']) { return u64(obj_header(object).items.len) }
	if objc_is_kind(object, ios_runtime.names['NSData']) || read64(object) == sec_certificate_type_id() {
		mut hash := u64(14695981039346656037)
		length := data_length(object)
		bytes := data_pointer(object)
		for i := u64(0); i < length; i++ { hash = (hash ^ unsafe { *(&u8(bytes + i)) }) * 1099511628211 }
		return hash
	}
	if objc_is_kind(object, ios_runtime.names['NSString']) {
		mut hash := u64(14695981039346656037)
		for byte in string_text(object) { hash = (hash ^ byte) * 1099511628211 }
		return hash
	}
	if objc_is_kind(object, ios_runtime.names['NSNumber']) {
		header := obj_header(object)
		value := if header.is_real { header.real_number } else { f64(header.number) }
		// Equal integer/floating NSNumber values must have the same hash.
		if value == 0 { return 0 }
		return unsafe { *(&u64(&value)) }
	}
	return object
}

fn cf_copy_description(object u64) u64 {
	if objc_is_kind(object, ios_runtime.names['NSString']) { return objc_retain(object) }
	mut bytes := [128]u8{}
	if objc_is_kind(object, ios_runtime.names['NSNumber']) {
		header := obj_header(object)
		if header.is_real { unsafe { C.snprintf(&char(&bytes[0]), 128, c'%.17g', header.real_number) } }
		else { unsafe { C.snprintf(&char(&bytes[0]), 128, c'%lld', header.number) } }
	} else {
		info := ios_runtime.classes[read64(object)] or { panic('iOS: unknown CF object') }
		unsafe { C.snprintf(&char(&bytes[0]), 128, c'<%s: 0x%llx>', info.name.str, object) }
	}
	return owned_string(ctext(u64(&bytes[0])))
}

fn cf_callbacks_constant(symbol string) u64 {
	if address := ios_runtime.framework_data[symbol] { return address }
	size := if symbol == '_kCFTypeDictionaryKeyCallBacks' { 48 } else { 40 }
	address := u64(C.calloc(1, usize(size)))
	if address == 0 { panic('iOS: cannot allocate CF collection callbacks') }
	unsafe {
		*(&u64(address + 8)) = u64(voidptr(cf_callback_retain))
		*(&u64(address + 16)) = u64(voidptr(cf_callback_release))
		*(&u64(address + 24)) = u64(voidptr(cf_copy_description))
		*(&u64(address + 32)) = u64(voidptr(object_equal))
		if size == 48 { *(&u64(address + 40)) = u64(voidptr(cf_hash)) }
	}
	ios_runtime.framework_data[symbol] = address
	return address
}

fn core_foundation_symbol(symbol string) ?u64 {
	return match symbol {
		'_CFErrorGetTypeID' { u64(unsafe { voidptr(cf_error_type_id) }) }
		'_CFErrorGetCode' { u64(unsafe { voidptr(cf_error_code) }) }
		'_CFErrorGetDomain' { u64(unsafe { voidptr(cf_error_domain) }) }
		'_CFRelease' { u64(unsafe { voidptr(objc_release) }) }
		'_CFRetain' { u64(unsafe { voidptr(objc_retain) }) }
		'_CFGetTypeID' { u64(unsafe { voidptr(cf_type_id) }) }
		'_CFEqual' { u64(unsafe { voidptr(object_equal) }) }
		'_CFHash' { u64(unsafe { voidptr(cf_hash) }) }
		'_CFCopyDescription' { u64(unsafe { voidptr(cf_copy_description) }) }
		'_CFStringGetTypeID' { u64(unsafe { voidptr(cf_string_id) }) }
		'_CFStringCreateWithCString' { u64(unsafe { voidptr(cf_string_create) }) }
		'_CFStringCreateWithBytes' { u64(unsafe { voidptr(cf_string_bytes) }) }
		'_CFStringGetLength' { u64(unsafe { voidptr(cf_string_length) }) }
		'_CFStringGetBytes' { u64(unsafe { voidptr(cf_string_get_bytes) }) }
		'_CFStringGetCString' { u64(unsafe { voidptr(cf_string_get_cstring) }) }
		'_CFArrayCreate' { u64(unsafe { voidptr(cf_array_create) }) }
		'_CFArrayGetTypeID' { u64(unsafe { voidptr(cf_array_id) }) }
		'_CFArrayGetCount' { u64(unsafe { voidptr(cf_array_count) }) }
		'_CFArrayGetValueAtIndex' { u64(unsafe { voidptr(cf_array_value) }) }
		'_CFDictionaryCreate' { u64(unsafe { voidptr(cf_dictionary_create) }) }
		'_CFDictionaryCreateMutable' { u64(unsafe { voidptr(cf_dictionary_mutable) }) }
		'_CFDictionaryGetValue' { u64(unsafe { voidptr(cf_dictionary_value) }) }
		'_CFDictionaryGetCount' { u64(unsafe { voidptr(cf_array_count) }) }
		'_CFDictionarySetValue' { u64(unsafe { voidptr(cf_dictionary_set) }) }
		'_CFDictionaryGetTypeID' { u64(unsafe { voidptr(cf_dictionary_id) }) }
		'_CFDataCreate' { u64(unsafe { voidptr(cf_data_create) }) }
		'_CFDataCreateMutable' { u64(unsafe { voidptr(cf_data_mutable) }) }
		'_CFDataGetBytePtr', '_CFDataGetMutableBytePtr' { u64(unsafe { voidptr(data_pointer) }) }
		'_CFDataGetLength' { u64(unsafe { voidptr(data_length) }) }
		'_CFDataSetLength' { u64(unsafe { voidptr(cf_data_set_length) }) }
		'_CFDataGetTypeID' { u64(unsafe { voidptr(cf_data_id) }) }
		'_CFNumberCreate' { u64(unsafe { voidptr(cf_number_create) }) }
		'_CFNumberGetTypeID' { u64(unsafe { voidptr(cf_number_id) }) }
		'_CFBooleanGetValue' { u64(unsafe { voidptr(cf_boolean_value) }) }
		'_CFBooleanGetTypeID' { u64(unsafe { voidptr(cf_boolean_id) }) }
		'_CFAllocatorGetDefault' { u64(unsafe { voidptr(cf_allocator_default) }) }
		'_CFAbsoluteTimeGetCurrent' { u64(unsafe { voidptr(cf_absolute_time) }) }
		'_kCFTypeArrayCallBacks', '_kCFTypeDictionaryKeyCallBacks', '_kCFTypeDictionaryValueCallBacks' { cf_callbacks_constant(symbol) }
		else { return none }
	}
}
