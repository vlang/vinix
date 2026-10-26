// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native NSConstantDictionary is isa/options/count/keys/objects. The compiler
// emits these forty-byte objects in __objc_dictobj; member arrays are borrowed
// for the image lifetime. Validate the whole image's collection records before
// publishing any owned metadata. No mapped object or array bytes are changed.
fn (m ObjMetadata) dictionary_address(object u64) bool {
	for segment in m.image.segments {
		for section in segment.sections {
			if section.name != '__objc_dictobj' { continue }
			start := m.base + section.address - m.layout.base
			if object >= start && object - start < section.size
				&& (object - start) % 40 == 0 { return true }
		}
	}
	return false
}

fn (m ObjMetadata) dictionary_validate(object u64) ! {
	if object & 7 != 0 { return error('iOS: unaligned constant dictionary') }
	m.range(object, 40, false)!
	if read64(object) != ios_runtime.names['NSConstantDictionary'] || read64(object + 8) != 1 {
		return error('iOS: unsupported constant dictionary class/options')
	}
	count := read64(object + 16)
	if count > 65536 { return error('iOS: constant dictionary count exceeds limits') }
	keys := read64(object + 24)
	values := read64(object + 32)
	if count != 0 {
		if keys & 7 != 0 || values & 7 != 0 { return error('iOS: unaligned constant dictionary members') }
		m.range(keys, count * 8, false)!
		m.range(values, count * 8, false)!
	}
	for i := u64(0); i < count; i++ {
		key := read64(keys + i * 8)
		value := read64(values + i * 8)
		// The sorted-key format emits string keys. Check registration before
		// reading an isa, so malformed member pointers cannot escape the image.
		if key !in ios_runtime.constants || !objc_is_kind(key, ios_runtime.names['NSString']) {
			return error('iOS: unsupported constant dictionary key')
		}
		if value == 0 { return error('iOS: nil constant dictionary value') }
		if value !in ios_runtime.constants && !m.integer_address(value) && !m.dictionary_address(value) && !m.array_address(value) {
			info := ios_runtime.classes[value] or { return error('iOS: unsupported constant dictionary value') }
			// Compiled class descriptors share the image lifetime. Disposable
			// classes and ordinary owned objects cannot be borrowed safely.
			if info.dynamic { return error('iOS: disposable constant dictionary value') }
		}
	}
	if header := ios_runtime.objects[object] {
		if !header.image_dictionary || header.items.len != int(count) {
			return error('iOS: conflicting constant dictionary registration')
		}
		for i in 0 .. int(count) {
			if header.keys[i] != read64(keys + u64(i) * 8) || header.items[i] != read64(values + u64(i) * 8) {
				return error('iOS: changed constant dictionary registration')
			}
		}
	}
}

fn (m ObjMetadata) constant_dictionaries() ! {
	m.constant_collections()!
}

fn (m ObjMetadata) dictionaries_validate() ! {
	for segment in m.image.segments {
		for section in segment.sections {
			if section.name != '__objc_dictobj' { continue }
			if section.size % 40 != 0 || section.size > 40 * 4096 {
				return error('iOS: invalid constant dictionary section')
			}
			start := m.base + section.address - m.layout.base
			m.range(start, section.size, false)!
			for offset := u64(0); offset < section.size; offset += 40 { m.dictionary_validate(start + offset)! }
		}
	}
}

fn (m ObjMetadata) dictionaries_publish() {
	for segment in m.image.segments {
		for section in segment.sections {
			if section.name != '__objc_dictobj' { continue }
			start := m.base + section.address - m.layout.base
			for offset := u64(0); offset < section.size; offset += 40 {
				object := start + offset
				if object in ios_runtime.objects { continue }
				count := int(read64(object + 16))
				mut header := unsafe { &ObjHeader(C.calloc(1, sizeof(ObjHeader))) }
				if header == unsafe { nil } { panic('iOS: cannot allocate constant dictionary metadata') }
				header.refs = 1
				header.cls = read64(object)
				header.native_size = 40
				header.caller_storage = true
				header.image_dictionary = true
				header.items = []u64{len: count}
				header.keys = []u64{len: count}
				header.items.flags |= .noslices
				header.keys.flags |= .noslices
				for i in 0 .. count {
					header.keys[i] = read64(read64(object + 24) + u64(i) * 8)
					header.items[i] = read64(read64(object + 32) + u64(i) * 8)
				}
				header.image_dictionary_next = ios_runtime.image_dictionaries
				ios_runtime.objects[object] = header
				ios_runtime.constants[object] = true
				ios_runtime.image_dictionaries = object
				mut info := ios_runtime.classes[header.cls] or { panic('iOS: missing constant dictionary class') }
				C.ios_ref_change(unsafe { &info.instances }, 1)
				C.ios_ref_change(unsafe { &ios_runtime.live }, 1)
			}
		}
	}
}

fn objc_constant_dictionaries_stop() {
	for ios_runtime.image_dictionaries != 0 {
		object := ios_runtime.image_dictionaries
		mut header := obj_header(object)
		ios_runtime.image_dictionaries = header.image_dictionary_next
		objc_destroy_contents(object, mut header, false)
		objc_forget_storage(object, header)
		ios_runtime.constants.delete(object)
	}
}

fn constant_dictionary_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	header := obj_header(object)
	match selector {
		'copyWithZone:' { frame.x[0] = objc_retain(object) }
		'mutableCopy', 'mutableCopyWithZone:' {
			copy := objc_allocate(ios_runtime.names['NSMutableDictionary'])
			mut target := obj_header(copy)
			for i, key in header.keys { cf_dictionary_insert(mut target, key, header.items[i]) }
			frame.x[0] = copy
		}
		'allKeys', 'allValues' {
			frame.x[0] = dictionary_snapshot(header, selector == 'allKeys')
		}
		'getObjects:andKeys:count:' {
			// Native NSConstantDictionary fills all pairs even when the count
			// argument is zero. Its caller provisions complete output arrays.
			for i in 0 .. header.items.len {
				unsafe {
					if frame.x[2] != 0 { *(&u64(frame.x[2] + u64(i) * 8)) = header.items[i] }
					if frame.x[3] != 0 { *(&u64(frame.x[3] + u64(i) * 8)) = header.keys[i] }
				}
			}
		}
		else { return false }
	}
	return true
}
