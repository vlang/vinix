// SPDX-License-Identifier: GPL-2.0-or-later
module main

// NSUUID is an 8-byte class-cluster base; alloc returns __NSConcreteUUID (24).
// Keep its sixteen immutable-value bytes in existing object metadata, without
// emulating Apple's private native ivars or allocating a separate sidecar.
fn ns_uuid_name(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSUUID' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic UUID superclass chain')
}

fn ns_uuid_allocation_class(cls u64) u64 {
	if cls == ios_runtime.names['NSUUID'] { return ios_runtime.names['__NSConcreteUUID'] }
	if ns_uuid_name(cls) && cls != ios_runtime.names['__NSConcreteUUID'] {
		panic('iOS: abstract or custom UUID subclass construction is not implemented')
	}
	return cls
}

fn ns_uuid_state(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.uuid_owned || header.cls != ios_runtime.names['__NSConcreteUUID'] {
		panic('iOS: UUID operation requires concrete UUID storage')
	}
	return header
}

fn ns_uuid_initialize(object u64, bytes u64, random bool) {
	mut header := ns_uuid_state(object)
	if random { darwin_uuid_generate(unsafe { &header.uuid_bytes[0] }); return }
	if bytes == 0 { unsafe { C.memset(&header.uuid_bytes[0], 0, 16) } }
	else { unsafe { C.memmove(&header.uuid_bytes[0], voidptr(bytes), 16) } }
}

fn ns_uuid_hex(byte u8) int {
	return if byte >= `0` && byte <= `9` { int(byte - `0`) }
	else if byte >= `a` && byte <= `f` { int(byte - `a`) + 10 }
	else if byte >= `A` && byte <= `F` { int(byte - `A`) + 10 }
	else { -1 }
}

fn ns_uuid_parse(text string, output &u8) bool {
	if text.len != 36 { return false }
	mut position := 0
	for i in 0 .. 16 {
		if position in [8, 13, 18, 23]! {
			if text[position] != `-` { return false }
			position++
		}
		hi := ns_uuid_hex(text[position]); lo := ns_uuid_hex(text[position + 1])
		if hi < 0 || lo < 0 { return false }
		unsafe { output[i] = u8(hi * 16 + lo) }
		position += 2
	}
	return true
}

fn ns_uuid_string(object u64) u64 {
	header := ns_uuid_state(object)
	mut buffer := [36]u8{}
	mut position := 0
	for i in 0 .. 16 {
		if position in [8, 13, 18, 23]! { buffer[position] = `-`; position++ }
		byte := header.uuid_bytes[i]
		buffer[position] = '0123456789ABCDEF'[byte >> 4]
		buffer[position + 1] = '0123456789ABCDEF'[byte & 15]
		position += 2
	}
	return owned_string(unsafe { tos(&buffer[0], 36) })
}

fn ns_uuid_equal(left u64, right u64) bool {
	if right == 0 || !objc_is_kind(right, ios_runtime.names['NSUUID']) { return false }
	a := ns_uuid_state(left); b := ns_uuid_state(right)
	mut difference := u8(0)
	for i in 0 .. 16 { difference |= a.uuid_bytes[i] ^ b.uuid_bytes[i] }
	return difference == 0
}

fn ns_uuid_compare(left u64, right u64) i64 {
	if right == 0 || !objc_is_kind(right, ios_runtime.names['NSUUID']) { panic('iOS: UUID comparison requires another UUID') }
	a := ns_uuid_state(left); b := ns_uuid_state(right)
	mut result := i64(0)
	// Inspect all sixteen bytes; later differences cannot replace the first.
	for i in 0 .. 16 {
		difference := i64(a.uuid_bytes[i] > b.uuid_bytes[i]) - i64(a.uuid_bytes[i] < b.uuid_bytes[i])
		result += (difference - result) * i64(result == 0)
	}
	return result
}

fn ns_uuid_hash(object u64) u64 {
	header := ns_uuid_state(object)
	mut hash := u64(14695981039346656037)
	for i in 0 .. 16 { hash = (hash ^ u64(header.uuid_bytes[i])) * 1099511628211 }
	return hash
}

fn ns_uuid_types(name string, meta bool, selector string) ?string {
	if name != 'NSUUID' && name != '_NSUUIDBridge' && name != '__NSConcreteUUID' { return none }
	if meta {
		return match selector { 'UUID', 'alloc', 'new' { '@16@0:8' } 'allocWithZone:' { '@24@0:8^{_NSZone=}16' } else { return none } }
	}
	return match selector {
		'init', 'UUIDString', 'description', 'copy' { '@16@0:8' }
		'initWithUUIDString:' { '@24@0:8@16' }
		'initWithUUIDBytes:' { if name == '__NSConcreteUUID' { '@24@0:8r*16' } else { '@24@0:8[16C]16' } }
		'getUUIDBytes:' { if name == '__NSConcreteUUID' { 'v24@0:8*16' } else { 'v24@0:8[16C]16' } }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'isEqual:' { 'B24@0:8@16' }
		'compare:' { 'q24@0:8@16' }
		'hash' { 'Q16@0:8' }
		'classForCoder' { '#16@0:8' }
		else { return none }
	}
}

fn ns_uuid_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	return ns_uuid_name(if meta { object } else { read64(object) }) && ns_uuid_types('NSUUID', meta, selector) != none
}

fn ns_uuid_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !ns_uuid_name(if meta { object } else { read64(object) }) { return false }
	match selector {
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'mutableCopy', 'mutableCopyWithZone:' {
			panic('iOS: UUID coding and mutable copies are not implemented')
		}
		else {}
	}
	if ns_uuid_types('NSUUID', meta, selector) == none { return false }
	if meta {
		match selector {
			'UUID' { frame.x[0] = objc_autorelease(objc_new(object)) }
			'new' { frame.x[0] = objc_new(object) }
			'alloc', 'allocWithZone:' { frame.x[0] = objc_allocate(object) }
			else { return false }
		}
		return true
	}
	header := ns_uuid_state(object)
	match selector {
		'init' { ns_uuid_initialize(object, 0, true) }
		'initWithUUIDBytes:' { ns_uuid_initialize(object, frame.x[2], false) }
		'initWithUUIDString:' {
			if frame.x[2] != 0 && !objc_is_kind(frame.x[2], ios_runtime.names['NSString']) { panic('iOS: UUID string initializer requires NSString') }
			mut bytes := [16]u8{}
			if !ns_uuid_parse(string_text(frame.x[2]), unsafe { &bytes[0] }) {
				if header.caller_storage { panic('iOS: invalid UUID initializer cannot consume caller-owned storage') }
				objc_release(object); frame.x[0] = 0
			} else { ns_uuid_initialize(object, u64(unsafe { &bytes[0] }), false) }
		}
		'getUUIDBytes:' {
			if frame.x[2] == 0 { panic('iOS: UUID byte output must not be nil') }
			unsafe { C.memmove(voidptr(frame.x[2]), &header.uuid_bytes[0], 16) }
		}
		'UUIDString', 'description' { frame.x[0] = objc_autorelease(ns_uuid_string(object)) }
		'copy', 'copyWithZone:' { frame.x[0] = objc_retain(object) }
		'classForCoder' { frame.x[0] = ios_runtime.names['NSUUID'] }
		'isEqual:' { frame.x[0] = u64(ns_uuid_equal(object, frame.x[2])) }
		'compare:' { frame.x[0] = u64(ns_uuid_compare(object, frame.x[2])) }
		'hash' { frame.x[0] = ns_uuid_hash(object) }
		else { return false }
	}
	return true
}
