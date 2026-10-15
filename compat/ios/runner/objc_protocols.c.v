// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

struct ObjProtocol {
mut:
	name string
	parents []u64
	index int
}
struct ObjProtocolFailure {}
fn (_ &ObjProtocolFailure) msg() string { return 'iOS: unsupported Objective-C protocol metadata or name' }
fn (_ &ObjProtocolFailure) code() int { return 1 }
__global objc_protocol_failure_value = ObjProtocolFailure{}
fn objc_protocol_failure() IError { return unsafe { &objc_protocol_failure_value } }

// Protocol identities own their name and graph, and remain immortal until
// quiescent runtime shutdown. Image descriptors alias these canonical objects.
fn objc_protocol_define(name string) !u64 {
	if name.len == 0 || name.len > 1023 || !utf8.validate_str(name) { return objc_protocol_failure() }
	for byte in name { if byte == 0 { return objc_protocol_failure() } }
	if known := ios_runtime.protocol_names[name] { return known }
	if ios_runtime.protocols.len == 4096 { return objc_protocol_failure() }
	address := u64(C.calloc(1, 96))
	if address == 0 { return objc_protocol_failure() }
	mut info := unsafe { &ObjProtocol(C.calloc(1, sizeof(ObjProtocol))) }
	if info == unsafe { nil } { C.free(unsafe { voidptr(address) }); return objc_protocol_failure() }
	info.name = name.clone()
	info.index = ios_runtime.protocols.len
	info.parents = []u64{}
	info.parents.flags |= .noslices
	unsafe { *(&u64(address)) = ios_runtime.names['Protocol']; *(&u64(address + 8)) = u64(info.name.str) }
	write32(address + 64, 96)
	ios_runtime.protocol_names[info.name] = address
	ios_runtime.protocols[address] = info
	ios_runtime.constants[address] = true
	return address
}
fn objc_protocols_start() {
	for name in ['NSObject', 'NSCopying', 'NSMutableCopying', 'NSCoding', 'NSSecureCoding', 'NSFastEnumeration']! { objc_protocol_define(name) or { panic(err) } }
	mut secure := ios_runtime.protocols[ios_runtime.protocol_names['NSSecureCoding']] or { panic('iOS: missing secure-coding protocol') }
	secure.parents << ios_runtime.protocol_names['NSCoding']
	mut root := ios_runtime.classes[ios_runtime.names['NSObject']] or { panic('iOS: missing protocol root class') }
	root.protocols.flags |= .noslices
	root.protocols << ios_runtime.protocol_names['NSObject']
}
fn objc_protocol_canonical(protocol u64) u64 {
	if protocol in ios_runtime.protocols { return protocol }
	return ios_runtime.protocol_aliases[protocol]
}
fn objc_get_protocol(name &char) u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || name == unsafe { nil } { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	for i in 0 .. 1024 {
		if unsafe { *(&u8(name) + i) } == 0 { return ios_runtime.protocol_names[unsafe { tos(&u8(name), i) }] }
	}
	return 0
}
fn ns_protocol_from_string_checked(name u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return objc_protocol_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if name == 0 { return 0 }
	if (name !in ios_runtime.objects && name !in ios_runtime.constants) || !objc_is_kind(name, ios_runtime.names['NSString']) { return objc_protocol_failure() }
	text := string_text(name)
	if text.len > 1023 || !utf8.validate_str(text) { return objc_protocol_failure() }
	// Foundation rejects embedded NUL instead of looking up its prefix.
	for byte in text { if byte == 0 { return 0 } }
	return ios_runtime.protocol_names[text]
}
fn ns_protocol_from_string(name u64) u64 { return ns_protocol_from_string_checked(name) or { panic(err) } }
fn objc_protocol_name(protocol u64) &char {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return unsafe { nil } }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	info := ios_runtime.protocols[objc_protocol_canonical(protocol)] or { return unsafe { nil } }
	return unsafe { &char(info.name.str) }
}
fn objc_protocol_equal(left u64, right u64) bool {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return false }
	if left == 0 || right == 0 { return left == right }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	value := objc_protocol_canonical(left)
	return value != 0 && value == objc_protocol_canonical(right)
}

// Mark on enqueue so diamonds cannot grow work exponentially. Each node has
// a bounded index; lookup and conformance scratch never allocate on the heap.
fn objc_protocol_adopts(left u64, target u64) bool {
	if left == 0 || target == 0 { return false }
	work := u64(C.__builtin_alloca(4096 * 8))
	seen := u64(C.__builtin_alloca(4096))
	C.memset(unsafe { voidptr(seen) }, 0, 4096)
	mut count := 1
	first := ios_runtime.protocols[left] or { return false }
	unsafe { *(&u64(work)) = left; *(&u8(seen + u64(first.index))) = 1 }
	for count > 0 {
		count--
		current := read64(work + u64(count * 8))
		if current == target { return true }
		info := ios_runtime.protocols[current] or { return false }
		for parent in info.parents {
			parent_info := ios_runtime.protocols[parent] or { return false }
			index := parent_info.index
			if unsafe { *(&u8(seen + u64(index))) } != 0 { continue }
			unsafe { *(&u8(seen + u64(index))) = 1; *(&u64(work + u64(count * 8))) = parent }
			count++
		}
	}
	return false
}
fn objc_protocol_conforms(left u64, right u64) bool {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return objc_protocol_adopts(objc_protocol_canonical(left), objc_protocol_canonical(right))
}
fn objc_class_conforms(cls u64, protocol u64) bool {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	target := objc_protocol_canonical(protocol)
	if target == 0 { return false }
	info := ios_runtime.classes[cls] or { return false }
	for adopted in info.protocols { if objc_protocol_adopts(adopted, target) { return true } }
	return false
}
// NSObject's method, unlike the C class query, includes superclass adoptions.
fn objc_object_conforms(cls u64, protocol u64) bool {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if objc_class_conforms(current, protocol) { return true }
		current = info.parent
	}
	return false
}
fn objc_class_add_protocol(cls u64, protocol u64) bool {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut info := ios_runtime.classes[cls] or { return false }
	value := objc_protocol_canonical(protocol)
	if value == 0 || objc_class_conforms(cls, value) { return false }
	info.protocols.flags |= .noslices
	info.protocols << value
	return true
}

fn (m ObjMetadata) protocol_validate(address u64, depth int, mut seen map[u64]u8) ! {
	if objc_protocol_canonical(address) != 0 { return }
	if seen[address] == 2 { return }
	if address == 0 || depth > 64 || seen[address] == 1 || seen.len >= 4096 { return objc_protocol_failure() }
	m.range(address, 72, false)!
	size := read32(address + 64)
	if size < 72 || size > 128 { return objc_protocol_failure() }
	m.range(address, size, false)!
	name := m.string_at(read64(address + 8))!
	if name.len == 0 || !utf8.validate_str(name) { return objc_protocol_failure() }
	seen[address] = 1
	list := read64(address + 16)
	if list != 0 {
		m.range(list, 8, false)!
		count := read64(list)
		if count > 4096 { return objc_protocol_failure() }
		m.range(list + 8, count * 8, false)!
		for i in u64(0) .. count { m.protocol_validate(read64(list + 8 + i * 8), depth + 1, mut seen)! }
	}
	seen[address] = 2
}
fn (m ObjMetadata) protocol_publish(address u64) !u64 {
	if address in ios_runtime.protocols { return address }
	if known := ios_runtime.protocol_aliases[address] { return known }
	if ios_runtime.protocol_aliases.len >= 16384 { return objc_protocol_failure() }
	value := objc_protocol_define(m.string_at(read64(address + 8))!)!
	ios_runtime.protocol_aliases[address] = value
	mut info := ios_runtime.protocols[value] or { return objc_protocol_failure() }
	list := read64(address + 16)
	if list != 0 {
		for i in u64(0) .. read64(list) {
			parent := m.protocol_publish(read64(list + 8 + i * 8))!
			if parent !in info.parents { info.parents << parent }
		}
	}
	return value
}
fn (m ObjMetadata) protocol_list(list u64, cls u64) ! {
	if list == 0 { return }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	m.range(list, 8, false)!
	count := read64(list)
	if count > 4096 { return objc_protocol_failure() }
	m.range(list + 8, count * 8, false)!
	mut seen := map[u64]u8{}
	defer { unsafe { seen.free() } }
	for i in u64(0) .. count { m.protocol_validate(read64(list + 8 + i * 8), 0, mut seen)! }
	for i in u64(0) .. count { objc_class_add_protocol(cls, m.protocol_publish(read64(list + 8 + i * 8))!) }
}
fn (m ObjMetadata) protocols_register() ! {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut seen := map[u64]u8{}
	defer { unsafe { seen.free() } }
	// Validate all roots and reference cells before publishing or rewriting.
	for segment in m.image.segments { for section in segment.sections {
		if section.name !in ['__objc_protolist', '__objc_protorefs']! { continue }
		if section.size % 8 != 0 || section.size > 32768 { return objc_protocol_failure() }
		start := m.base + section.address - m.layout.base
		m.range(start, section.size, section.name == '__objc_protorefs')!
		for i := u64(0); i < section.size; i += 8 { m.protocol_validate(read64(start + i), 0, mut seen)! }
	} }
	for segment in m.image.segments { for section in segment.sections {
		if section.name !in ['__objc_protolist', '__objc_protorefs']! { continue }
		start := m.base + section.address - m.layout.base
		for i := u64(0); i < section.size; i += 8 {
			value := m.protocol_publish(read64(start + i))!
			if section.name == '__objc_protorefs' { unsafe { *(&u64(start + i)) = value } }
		}
	} }
}
fn objc_protocols_stop() {
	for address, info in ios_runtime.protocols {
		ios_runtime.constants.delete(address)
		unsafe { info.name.free(); info.parents.free() }
		C.free(info)
		C.free(unsafe { voidptr(address) })
	}
	ios_runtime.protocols.clear()
	ios_runtime.protocol_names.clear()
	ios_runtime.protocol_aliases.clear()
	unsafe { ios_runtime.protocols.free(); ios_runtime.protocol_names.free(); ios_runtime.protocol_aliases.free() }
}
