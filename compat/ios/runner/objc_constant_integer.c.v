// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

// Compiler-emitted NSConstantIntegerNumber records are isa/encoding/value.
// Only the separately owned metadata is writable; record and encoding bytes
// stay borrowed from the image until quiescent runtime shutdown.
fn (m ObjMetadata) integer_address(object u64) bool {
	for segment in m.image.segments {
		for section in segment.sections {
			if section.name != '__objc_intobj' { continue }
			start := m.base + section.address - m.layout.base
			if object >= start && object - start < section.size
				&& (object - start) % 24 == 0 { return true }
		}
	}
	return false
}

fn (m ObjMetadata) integer_validate(object u64) ! {
	if object & 7 != 0 { return error('iOS: unaligned constant integer') }
	m.range(object, 24, false)!
	if read64(object) != ios_runtime.names['NSConstantIntegerNumber'] {
		return error('iOS: unsupported constant integer class')
	}
	encoding := read64(object + 8)
	m.range(encoding, 2, false)!
	kind := unsafe { *(&u8(encoding)) }
	if unsafe { *(&u8(encoding + 1)) } != 0 || kind !in [`c`, `s`, `i`, `l`, `q`, `C`, `S`, `I`, `L`, `Q`, `B`]! {
		return error('iOS: unsupported constant integer encoding')
	}
	if header := ios_runtime.objects[object] {
		if !header.image_integer || header.image_integer_encoding != kind
			|| u64(header.number) != read64(object + 16) {
			return error('iOS: conflicting constant integer registration')
		}
	}
}

fn (m ObjMetadata) integers_validate() ! {
	for segment in m.image.segments {
		for section in segment.sections {
			if section.name != '__objc_intobj' { continue }
			if section.size % 24 != 0 || section.size > 24 * 4096 {
				return error('iOS: invalid constant integer section')
			}
			start := m.base + section.address - m.layout.base
			m.range(start, section.size, false)!
			for offset := u64(0); offset < section.size; offset += 24 { m.integer_validate(start + offset)! }
		}
	}
}

fn (m ObjMetadata) integers_publish() {
	for segment in m.image.segments {
		for section in segment.sections {
			if section.name != '__objc_intobj' { continue }
			start := m.base + section.address - m.layout.base
			for offset := u64(0); offset < section.size; offset += 24 {
				object := start + offset
				if object in ios_runtime.objects { continue }
				mut header := unsafe { &ObjHeader(C.calloc(1, sizeof(ObjHeader))) }
				if header == unsafe { nil } { panic('iOS: cannot allocate constant integer metadata') }
				header.refs = 1
				header.cls = read64(object)
				header.native_size = 24
				header.caller_storage = true
				header.image_integer = true
				header.image_integer_encoding = unsafe { *(&u8(read64(object + 8))) }
				// Numeric equality uses the full signed field except for Q;
				// source-width formatting is handled separately below.
				header.unsigned_number = header.image_integer_encoding == `Q`
				header.number = i64(read64(object + 16))
				header.image_integer_next = ios_runtime.image_integers
				ios_runtime.objects[object] = header
				ios_runtime.constants[object] = true
				ios_runtime.image_integers = object
				mut info := ios_runtime.classes[header.cls] or { panic('iOS: missing constant integer class') }
				C.ios_ref_change(unsafe { &info.instances }, 1)
				C.ios_ref_change(unsafe { &ios_runtime.live }, 1)
			}
		}
	}
}

fn (m ObjMetadata) constant_integers() ! {
	m.constant_collections()!
}

fn objc_constant_integers_stop() {
	for ios_runtime.image_integers != 0 {
		object := ios_runtime.image_integers
		mut header := obj_header(object)
		ios_runtime.image_integers = header.image_integer_next
		objc_destroy_contents(object, mut header, false)
		objc_forget_storage(object, header)
		ios_runtime.constants.delete(object)
	}
}

fn constant_integer_types(name string, meta bool, selector string) ?string {
	if name != 'NSConstantIntegerNumber' || meta { return none }
	return match selector {
		'charValue' { 'c16@0:8' }
		'unsignedCharValue' { 'C16@0:8' }
		'shortValue' { 's16@0:8' }
		'unsignedShortValue' { 'S16@0:8' }
		'intValue' { 'i16@0:8' }
		'unsignedIntValue' { 'I16@0:8' }
		'longValue', 'longLongValue', 'integerValue' { 'q16@0:8' }
		'unsignedLongValue', 'unsignedLongLongValue', 'unsignedIntegerValue', 'retainCount', 'hash', '_cfTypeID' { 'Q16@0:8' }
		'boolValue', '_tryRetain', '_isDeallocating' { 'B16@0:8' }
		'floatValue' { 'f16@0:8' }
		'doubleValue' { 'd16@0:8' }
		'objCType' { 'r*16@0:8' }
		'getValue:' { 'v24@0:8^v16' }
		'getValue:size:' { 'v32@0:8^v16Q24' }
		'init', 'copy', 'stringValue', 'description' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'isEqual:', 'isEqualToNumber:' { 'B24@0:8@16' }
		else { return none }
	}
}

fn constant_integer_format(header &ObjHeader, buffer &char, capacity usize) {
	match header.image_integer_encoding {
		`C` { unsafe { C.snprintf(buffer, capacity, c'%llu', u64(u8(header.number))) } }
		`S` { unsafe { C.snprintf(buffer, capacity, c'%llu', u64(u16(header.number))) } }
		`I` { unsafe { C.snprintf(buffer, capacity, c'%llu', u64(u32(header.number))) } }
		`L`, `Q` { unsafe { C.snprintf(buffer, capacity, c'%llu', u64(header.number)) } }
		`c`, `B` { unsafe { C.snprintf(buffer, capacity, c'%lld', i64(i8(header.number))) } }
		`s` { unsafe { C.snprintf(buffer, capacity, c'%lld', i64(i16(header.number))) } }
		`i` { unsafe { C.snprintf(buffer, capacity, c'%lld', i64(i32(header.number))) } }
		else { unsafe { C.snprintf(buffer, capacity, c'%lld', header.number) } }
	}
}

fn constant_integer_receiver(object u64) ?&ObjHeader {
	// Every framework message probes this registry, including messages sent
	// while other threads allocate or dispose ordinary Objective-C objects.
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[object] or { return none }
	if !header.image_integer { return none }
	// Image integer metadata remains alive until quiescent runtime shutdown.
	return header
}

fn constant_integer_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	header := constant_integer_receiver(object) or { return false }
	match selector {
		'init' { panic('iOS: cannot initialize image integer storage') }
		'setObject:forKeyedSubscript:', 'setObject:forKey:', 'removeObjectForKey:',
		'removeAllObjects', 'addObject:', 'removeObjectAtIndex:', 'setObject:atIndexedSubscript:',
		'setValue:forKey:' { panic('iOS: mutation of an immutable image integer') }
		'charValue' { frame.x[0] = u64(u32(i32(i8(header.number)))) }
		'unsignedCharValue' { frame.x[0] = u64(u8(header.number)) }
		'shortValue' { frame.x[0] = u64(u32(i32(i16(header.number)))) }
		'unsignedShortValue' { frame.x[0] = u64(u16(header.number)) }
		'intValue', 'unsignedIntValue' { frame.x[0] = u64(u32(header.number)) }
		'longValue', 'unsignedLongValue', 'longLongValue', 'unsignedLongLongValue', 'integerValue', 'unsignedIntegerValue' { frame.x[0] = u64(header.number) }
		'boolValue' { frame.x[0] = u64(header.number != 0) }
		// Apple's constant-integer getters convert the signed value field even
		// when objCType advertises an unsigned source type.
		'floatValue' { frame.q[0] = u64(bits.f32_bits(f32(header.number))); frame.q[1] = 0 }
		'doubleValue' { frame_float_return(mut frame, 0, f64(header.number)) }
		'objCType' { frame.x[0] = read64(object + 8) }
		'getValue:', 'getValue:size:' {
			count := match header.image_integer_encoding { `c`, `C`, `B` { u64(1) } `s`, `S` { u64(2) } `i`, `I` { u64(4) } else { u64(8) } }
			if frame.x[2] == 0 || (selector == 'getValue:size:' && frame.x[3] != count) {
				panic('iOS: constant integer destination size must match exactly')
			}
			value := u64(header.number)
			unsafe { C.memmove(voidptr(frame.x[2]), &value, usize(count)) }
		}
		'copy', 'copyWithZone:' { frame.x[0] = object }
		'retainCount' { frame.x[0] = ~u64(0) }
		'_tryRetain' { frame.x[0] = 1 }
		'_isDeallocating' { frame.x[0] = 0 }
		'_cfTypeID' { frame.x[0] = cf_number_id() }
		'isEqual:', 'isEqualToNumber:' {
			if selector == 'isEqualToNumber:' && frame.x[2] == 0 {
				panic('iOS: constant integer comparison requires a number')
			}
			frame.x[0] = u64(object_equal(object, frame.x[2]))
		}
		'hash' { frame.x[0] = cf_hash(object) }
		'stringValue', 'description' { frame.x[0] = objc_autorelease(cf_copy_description(object)) }
		else { return false }
	}
	return true
}
