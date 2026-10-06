// SPDX-License-Identifier: GPL-2.0-or-later
module main

import plist

fn plist_object(value plist.Value) u64 {
	match value.kind {
		.string { return make_string(unsafe { &char(value.text.str) }) }
		.integer, .boolean, .real {
			object := objc_allocate(ios_runtime.names['NSNumber'])
			mut header := obj_header(object)
			header.number = if value.kind == .boolean { i64(value.boolean) } else { value.integer }
			header.real_number = value.real
			header.is_real = value.kind == .real
			return objc_autorelease(object)
		}
		.data {
			object := objc_allocate(ios_runtime.names['NSData'])
			mut header := obj_header(object)
			header.data = value.data.clone()
			return objc_autorelease(object)
		}
		.array {
			object := objc_allocate(ios_runtime.names['NSArray'])
			mut header := obj_header(object)
			for item in value.values { array_append(mut header, plist_object(item)) }
			return objc_autorelease(object)
		}
		.dictionary {
			object := objc_allocate(ios_runtime.names['NSDictionary'])
			mut header := obj_header(object)
			for key, item in value.fields {
				header.keys << objc_retain(make_string(unsafe { &char(key.str) }))
				array_append(mut header, plist_object(item))
			}
			return objc_autorelease(object)
		}
	}
}

fn data_pointer(object u64) u64 {
	header := obj_header(object)
	return if header.external_data != 0 { header.external_data } else { u64(header.data.data) }
}

fn data_length(object u64) u64 {
	header := obj_header(object)
	return if header.external_data != 0 { header.external_size } else { u64(header.data.len) }
}

fn propertylist_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object !in ios_runtime.classes { return false }
	info := ios_runtime.classes[object] or { return false }
	if info.name == 'NSData' && selector in ['dataWithBytes:length:', 'dataWithBytesNoCopy:length:freeWhenDone:'] {
		if frame.x[3] > 16777216 || (frame.x[3] != 0 && frame.x[2] == 0) { panic('iOS: invalid NSData buffer') }
		data := objc_allocate(object)
		mut header := obj_header(data)
		if selector == 'dataWithBytesNoCopy:length:freeWhenDone:' {
			header.external_data = frame.x[2]
			header.external_size = frame.x[3]
			header.free_data = frame.x[4] != 0
		} else {
			header.data = []u8{len: int(frame.x[3])}
			if header.data.len != 0 { unsafe { C.memcpy(header.data.data, voidptr(frame.x[2]), usize(header.data.len)) } }
		}
		frame.x[0] = objc_autorelease(data)
		return true
	}
	if info.name == 'NSPropertyListSerialization' && selector == 'propertyListWithData:options:format:error:' {
		if frame.x[3] != 0 { panic('iOS: mutable property lists are not implemented') }
		if frame.x[2] == 0 || data_length(frame.x[2]) > 16777216 { panic('iOS: invalid property list data') }
		length := data_length(frame.x[2])
		mut bytes := []u8{len: int(length)}
		defer { unsafe { bytes.free() } }
		if length != 0 { unsafe { C.memcpy(bytes.data, voidptr(data_pointer(frame.x[2])), usize(length)) } }
		value := plist.parse(bytes) or {
			if frame.x[5] != 0 { panic('iOS: property list NSError output is not implemented: ${err}') }
			frame.x[0] = 0
			return true
		}
		defer { value.free() }
		if frame.x[4] != 0 { unsafe { *(&u64(frame.x[4])) = if bytes.len >= 8 && bytes[..8] == 'bplist00'.bytes() { u64(200) } else { u64(100) } } }
		if frame.x[5] != 0 { unsafe { *(&u64(frame.x[5])) = 0 } }
		frame.x[0] = plist_object(value)
		return true
	}
	return false
}
