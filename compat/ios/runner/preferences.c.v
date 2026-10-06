// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import plist

fn object_plist(object u64, depth int) !plist.Value {
	if object == 0 || depth > 64 { return error('iOS: invalid/cyclic preference object') }
	if objc_is_kind(object, ios_runtime.names['NSString']) { return plist.Value{kind: .string, text: string_text(object).clone()} }
	header := obj_header(object)
	if objc_is_kind(object, ios_runtime.names['NSNumber']) {
		return if header.is_real { plist.Value{kind: .real, real: header.real_number} } else { plist.Value{kind: .integer, integer: header.number} }
	}
	if objc_is_kind(object, ios_runtime.names['NSData']) {
		length := data_length(object)
		if length > 16777216 { return error('iOS: preference data exceeds limit') }
		mut bytes := []u8{len: int(length)}
		if length != 0 { unsafe { C.memcpy(bytes.data, voidptr(data_pointer(object)), usize(length)) } }
		return plist.Value{kind: .data, data: bytes}
	}
	if objc_is_kind(object, ios_runtime.names['NSArray']) {
		mut values := []plist.Value{cap: header.items.len}
		mut complete := false
		defer { if !complete { for value in values { value.free() }; unsafe { values.free() } } }
		for item in header.items { values << object_plist(item, depth + 1)! }
		complete = true
		return plist.Value{kind: .array, values: values}
	}
	if objc_is_kind(object, ios_runtime.names['NSDictionary']) {
		mut fields := map[string]plist.Value{}
		mut complete := false
		defer { if !complete { for _, value in fields { value.free() }; unsafe { fields.free() } } }
		for i, key in header.keys {
			if !objc_is_kind(key, ios_runtime.names['NSString']) { return error('iOS: preference dictionary keys must be strings') }
			fields[string_text(key)] = object_plist(header.items[i], depth + 1)!
		}
		complete = true
		return plist.Value{kind: .dictionary, fields: fields}
	}
	return error('iOS: unsupported preference object type')
}

fn defaults_start() u64 {
	if ios_runtime.defaults != 0 { return ios_runtime.defaults }
	defaults := objc_allocate(ios_runtime.names['NSUserDefaults'])
	dictionary := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	store_field(defaults, 0, dictionary)
	objc_release(dictionary)
	registration := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	store_field(defaults, 1, registration)
	objc_release(registration)
	mut identifier := os.file_name(ios_runtime.bundle)
	info_path := os.join_path(ios_runtime.bundle, 'Info.plist')
	if os.is_file(info_path) {
		bytes := os.read_bytes(info_path) or { panic('iOS: cannot read bundle preferences identity: ${err}') }
		defer { unsafe { bytes.free() } }
		info := plist.parse(bytes) or { panic('iOS: invalid bundle preferences identity: ${err}') }
		defer { info.free() }
		if info.fields['CFBundleIdentifier'].text != '' { identifier = info.fields['CFBundleIdentifier'].text.clone() }
	}
	if identifier == '' || identifier.len > 255 || identifier in ['.', '..'] { panic('iOS: invalid preference identifier') }
	for c in identifier {
		if !((c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) || c in [u8(`.`), `-`, `_`]) { panic('iOS: unsafe preference identifier') }
	}
	root := os.getenv('VINIX_IOS_DOCUMENTS')
	documents := if root != '' { root } else { os.join_path(os.dir(ios_runtime.bundle), 'Documents') }
	directory := os.join_path(documents, 'Library', 'Preferences')
	os.mkdir_all(directory) or { panic('iOS: cannot create preferences directory: ${err}') }
	path := os.join_path(directory, identifier + '.plist')
	store_field(defaults, 2, make_string(unsafe { &char(path.str) }))
	if os.is_file(path) {
		bytes := os.read_bytes(path) or { panic('iOS: cannot read preferences: ${err}') }
		defer { unsafe { bytes.free() } }
		value := plist.parse(bytes) or { panic('iOS: invalid preferences: ${err}') }
		defer { value.free() }
		if value.kind != .dictionary { panic('iOS: preferences root is not a dictionary') }
		store_field(defaults, 0, plist_object(value))
	}
	ios_runtime.defaults = defaults
	return defaults
}

fn defaults_save(defaults u64) bool {
	header := obj_header(defaults)
	value := object_plist(header.fields[0], 0) or { panic(err) }
	defer { value.free() }
	text := plist.encode_xml(value) or { panic(err) }
	defer { unsafe { text.free() } }
	path := string_text(header.fields[2])
	temporary := path + '.tmp'
	defer { unsafe { temporary.free() } }
	os.write_file(temporary, text) or { return false }
	os.rename(temporary, path) or { os.rm(temporary) or {}; return false }
	return true
}

fn dictionary_put(dictionary u64, key u64, value u64) {
	if !objc_is_kind(key, ios_runtime.names['NSString']) { panic('iOS: preferences require a string key') }
	mut header := obj_header(dictionary)
	index := dictionary_index(header, key)
	if value == 0 { if index >= 0 { collection_remove(mut header, index) }; return }
	if index >= 0 { objc_store_strong(unsafe { &header.items[index] }, value) }
	else { header.keys << objc_retain(key); array_append(mut header, value) }
}

fn defaults_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object == ios_runtime.names['NSUserDefaults'] {
		if selector != 'standardUserDefaults' { return false }
		frame.x[0] = defaults_start()
		return true
	}
	if !objc_is_kind(object, ios_runtime.names['NSUserDefaults']) { return false }
	if object != ios_runtime.defaults { panic('iOS: custom user defaults suites are not implemented') }
	header := obj_header(object)
	match selector {
		'objectForKey:', 'stringForKey:', 'dictionaryForKey:', 'arrayForKey:', 'dataForKey:', 'boolForKey:', 'integerForKey:' {
			mut value := u64(0)
			for dictionary in [header.fields[0], header.fields[1]]! {
				stored := obj_header(dictionary)
				index := dictionary_index(stored, frame.x[2])
				if index >= 0 { value = stored.items[index]; break }
			}
			frame.x[0] = value
			if selector in ['stringForKey:', 'dictionaryForKey:', 'arrayForKey:', 'dataForKey:'] {
				name := match selector { 'stringForKey:' { 'NSString' } 'dictionaryForKey:' { 'NSDictionary' } 'arrayForKey:' { 'NSArray' } else { 'NSData' } }
				if !objc_is_kind(value, ios_runtime.names[name]) { frame.x[0] = 0 }
			} else if selector in ['boolForKey:', 'integerForKey:'] {
				if value == 0 { frame.x[0] = 0 }
				else if objc_is_kind(value, ios_runtime.names['NSNumber']) { frame.x[0] = u64(obj_header(value).number) }
				else if objc_is_kind(value, ios_runtime.names['NSString']) { frame.x[0] = u64(darwin_atoi(unsafe { &char(string_text(value).str) })) }
				else { frame.x[0] = 0 }
				if selector == 'boolForKey:' { frame.x[0] = u64(frame.x[0] != 0) }
			}
		}
		'setObject:forKey:' {
			if frame.x[2] == 0 { dictionary_put(header.fields[0], frame.x[3], 0) }
			else {
				value := object_plist(frame.x[2], 0) or { panic(err) }
				defer { value.free() }
				dictionary_put(header.fields[0], frame.x[3], plist_object(value))
			}
			if !defaults_save(object) { panic('iOS: cannot save user defaults') }
		}
		'setBool:forKey:', 'setInteger:forKey:' {
			number := objc_allocate(ios_runtime.names['NSNumber'])
			mut value := obj_header(number)
			value.number = if selector == 'setBool:forKey:' { i64(frame.x[2] != 0) } else { i64(frame.x[2]) }
			dictionary_put(header.fields[0], frame.x[3], number)
			objc_release(number)
			if !defaults_save(object) { panic('iOS: cannot save user defaults') }
		}
		'removeObjectForKey:' { dictionary_put(header.fields[0], frame.x[2], 0); if !defaults_save(object) { panic('iOS: cannot save user defaults') } }
		'registerDefaults:' {
			registered := obj_header(frame.x[2])
			for i, key in registered.keys { dictionary_put(header.fields[1], key, registered.items[i]) }
		}
		'synchronize' { frame.x[0] = u64(defaults_save(object)) }
		else { return false }
	}
	return true
}
