// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native NSConstantArray is isa/count/objects, with no options word. Its
// twenty-four-byte image records and member arrays remain untouched. Owned
// metadata snapshots borrow members for the image lifetime, including other
// constant collections and static classes.
fn (m ObjMetadata) array_address(object u64) bool {
	for segment in m.image.segments {
		for section in segment.sections {
			if section.name != '__objc_arrayobj' { continue }
			start := m.base + section.address - m.layout.base
			if object >= start && object - start < section.size
				&& (object - start) % 24 == 0 { return true }
		}
	}
	return false
}

fn (m ObjMetadata) array_validate(object u64) ! {
	if object & 7 != 0 { return error('iOS: unaligned constant array') }
	m.range(object, 24, false)!
	if read64(object) != ios_runtime.names['NSConstantArray'] {
		return error('iOS: unsupported constant array class')
	}
	count := read64(object + 8)
	if count > 65536 { return error('iOS: constant array count exceeds limits') }
	values := read64(object + 16)
	if count != 0 {
		if values & 7 != 0 { return error('iOS: unaligned constant array members') }
		m.range(values, count * 8, false)!
	}
	for i := u64(0); i < count; i++ {
		value := read64(values + i * 8)
		if value == 0 { return error('iOS: nil constant array value') }
		if value !in ios_runtime.constants && !m.array_address(value) && !m.dictionary_address(value) {
			info := ios_runtime.classes[value] or { return error('iOS: unsupported constant array value') }
			if info.dynamic { return error('iOS: disposable constant array value') }
		}
	}
	if header := ios_runtime.objects[object] {
		if !header.image_array || header.items.len != int(count) {
			return error('iOS: conflicting constant array registration')
		}
		for i in 0 .. int(count) {
			if header.items[i] != read64(values + u64(i) * 8) {
				return error('iOS: changed constant array registration')
			}
		}
	}
}

fn (m ObjMetadata) arrays_validate() ! {
	for segment in m.image.segments {
		for section in segment.sections {
			if section.name != '__objc_arrayobj' { continue }
			if section.size % 24 != 0 || section.size > 24 * 4096 {
				return error('iOS: invalid constant array section')
			}
			start := m.base + section.address - m.layout.base
			m.range(start, section.size, false)!
			for offset := u64(0); offset < section.size; offset += 24 { m.array_validate(start + offset)! }
		}
	}
}

fn (m ObjMetadata) arrays_publish() {
	for segment in m.image.segments {
		for section in segment.sections {
			if section.name != '__objc_arrayobj' { continue }
			start := m.base + section.address - m.layout.base
			for offset := u64(0); offset < section.size; offset += 24 {
				object := start + offset
				if object in ios_runtime.objects { continue }
				count := int(read64(object + 8))
				mut header := unsafe { &ObjHeader(C.calloc(1, sizeof(ObjHeader))) }
				if header == unsafe { nil } { panic('iOS: cannot allocate constant array metadata') }
				header.refs = 1
				header.cls = read64(object)
				header.native_size = 24
				header.caller_storage = true
				header.image_array = true
				header.items = []u64{len: count}
				header.items.flags |= .noslices
				for i in 0 .. count { header.items[i] = read64(read64(object + 16) + u64(i) * 8) }
				header.image_array_next = ios_runtime.image_arrays
				ios_runtime.objects[object] = header
				ios_runtime.constants[object] = true
				ios_runtime.image_arrays = object
				mut info := ios_runtime.classes[header.cls] or { panic('iOS: missing constant array class') }
				C.ios_ref_change(unsafe { &info.instances }, 1)
				C.ios_ref_change(unsafe { &ios_runtime.live }, 1)
			}
		}
	}
}

fn (m ObjMetadata) constant_arrays() ! {
	m.constant_collections()!
}

fn (m ObjMetadata) constant_collections() ! {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// Both families can borrow one another. Validate every record before
	// publishing either family, so a malformed later record leaves no owners.
	m.arrays_validate()!
	m.dictionaries_validate()!
	m.arrays_publish()
	m.dictionaries_publish()
}

fn objc_constant_arrays_stop() {
	for ios_runtime.image_arrays != 0 {
		object := ios_runtime.image_arrays
		mut header := obj_header(object)
		ios_runtime.image_arrays = header.image_array_next
		objc_destroy_contents(object, mut header, false)
		objc_forget_storage(object, header)
		ios_runtime.constants.delete(object)
	}
}

fn constant_array_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	header := obj_header(object)
	match selector {
		'copyWithZone:' { frame.x[0] = objc_retain(object) }
		'mutableCopy', 'mutableCopyWithZone:' {
			copy := objc_allocate(ios_runtime.names['NSMutableArray'])
			mut target := obj_header(copy)
			for value in header.items { array_append(mut target, value) }
			frame.x[0] = copy
		}
		'lastObject' { frame.x[0] = if header.items.len == 0 { u64(0) } else { header.items.last() } }
		'getObjects:range:' {
			start := frame.x[3]
			count := frame.x[4]
			if start > u64(header.items.len) || count > u64(header.items.len) - start {
				panic('iOS: constant array range out of bounds')
			}
			if count != 0 && frame.x[2] == 0 { panic('iOS: nil constant array output') }
			for i := u64(0); i < count; i++ {
				unsafe { *(&u64(frame.x[2] + i * 8)) = header.items[int(start + i)] }
			}
		}
		else { return false }
	}
	return true
}
