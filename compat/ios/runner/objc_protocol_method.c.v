// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct ObjProtocolMethod {
	types string // Owned, including its C terminator; never replaced after publication.
	has_types bool
}

// objc_method_description is a pair of pointers returned in x0/x1 on ARM64.
struct ObjProtocolDescription {
	name u64
	types u64
}

struct ObjProtocolImageMethod {
	name string // Borrowed only while validating/publishing the image.
	types string
	has_types bool
}

// The six built-in protocol identities have no Mach-O descriptor to import.
// Their ARM64 declarations use the same owned storage as image protocols.
fn objc_protocol_methods_start() {
	for row in [
		['NSObject', 'zone', '^{_NSZone=}16@0:8']!,
		['NSObject', 'conformsToProtocol:', 'B24@0:8@16']!,
		['NSObject', 'autorelease', '@16@0:8']!,
		['NSObject', 'isKindOfClass:', 'B24@0:8#16']!,
		['NSObject', 'isMemberOfClass:', 'B24@0:8#16']!,
		['NSObject', 'isEqual:', 'B24@0:8@16']!,
		['NSObject', 'respondsToSelector:', 'B24@0:8:16']!,
		['NSObject', 'retain', '@16@0:8']!,
		['NSObject', 'hash', 'Q16@0:8']!,
		['NSObject', 'description', '@16@0:8']!,
		['NSObject', 'release', 'Vv16@0:8']!,
		['NSObject', 'isProxy', 'B16@0:8']!,
		['NSObject', 'retainCount', 'Q16@0:8']!,
		['NSObject', 'class', '#16@0:8']!,
		['NSObject', 'performSelector:', '@24@0:8:16']!,
		['NSObject', 'performSelector:withObject:', '@32@0:8:16@24']!,
		['NSObject', 'performSelector:withObject:withObject:', '@40@0:8:16@24@32']!,
		['NSObject', 'self', '@16@0:8']!,
		['NSObject', 'superclass', '#16@0:8']!,
		['NSCopying', 'copyWithZone:', '@24@0:8^{_NSZone=}16']!,
		['NSMutableCopying', 'mutableCopyWithZone:', '@24@0:8^{_NSZone=}16']!,
		['NSCoding', 'encodeWithCoder:', 'v24@0:8@16']!,
		['NSCoding', 'initWithCoder:', '@24@0:8@16']!,
		['NSFastEnumeration', 'countByEnumeratingWithState:objects:count:', 'Q40@0:8^{?=Q^@^Q[5Q]}16^@24Q32']!,
	]! {
		mut info := ios_runtime.protocols[ios_runtime.protocol_names[row[0]]] or { panic('iOS: missing built-in protocol') }
		info.descriptions[0][objc_selector(unsafe { &char(row[1].str) })] = ObjProtocolMethod{row[2].clone(), true}
	}
	mut root := ios_runtime.protocols[ios_runtime.protocol_names['NSObject']] or { panic('iOS: missing NSObject protocol') }
	root.descriptions[2][objc_selector(c'debugDescription')] = ObjProtocolMethod{'@16@0:8'.clone(), true}
	mut secure := ios_runtime.protocols[ios_runtime.protocol_names['NSSecureCoding']] or { panic('iOS: missing secure-coding protocol') }
	secure.descriptions[1][objc_selector(c'supportsSecureCoding')] = ObjProtocolMethod{'B16@0:8'.clone(), true}
}

fn (m ObjMetadata) protocol_method_count(list u64) !u32 {
	if list == 0 { return 0 }
	m.range(list, 8, false)!
	flags := read32(list)
	stride := flags & 0xfffc
	count := read32(list + 4)
	if count > 4096 || stride != if flags & 0x80000000 != 0 { u32(12) } else { u32(24) } { return objc_protocol_failure() }
	m.range(list + 8, u64(count) * stride, false)!
	return count
}

// The list header and all entry bytes have already been checked. Protocol
// declarations have no executable IMP, so the third field is not followed.
fn (m ObjMetadata) protocol_method_at(list u64, index u32) !ObjProtocolImageMethod {
	flags := read32(list)
	entry := list + 8 + u64(index) * (flags & 0xfffc)
	mut name := u64(0)
	mut types := u64(0)
	if flags & 0x80000000 != 0 {
		name = u64(i64(entry) + i64(i32(read32(entry))))
		if flags & 0x40000000 == 0 { m.range(name, 8, false)!; name = read64(name) }
		types = u64(i64(entry + 4) + i64(i32(read32(entry + 4))))
	} else {
		name = read64(entry)
		types = read64(entry + 8)
	}
	return ObjProtocolImageMethod{m.string_at(name)!, if types == 0 { '' } else { m.type_at(types)! }, types != 0}
}

fn (m ObjMetadata) protocol_methods_validate(address u64) ! {
	for slot in 0 .. 4 {
		list := read64(address + 24 + u64(slot * 8))
		count := m.protocol_method_count(list)!
		for i in u32(0) .. count { m.protocol_method_at(list, i)! }
	}
}

fn (m ObjMetadata) protocol_methods_publish(address u64, mut info ObjProtocol) ! {
	for slot in 0 .. 4 {
		list := read64(address + 24 + u64(slot * 8))
		count := m.protocol_method_count(list)!
		for i in u32(0) .. count {
			method := m.protocol_method_at(list, i)!
			selector := objc_selector(unsafe { &char(method.name.str) })
			// Duplicate descriptors alias an immortal canonical protocol. Keep
			// its first declaration so previously returned pointers stay valid.
			if selector in info.descriptions[slot] { continue }
			info.descriptions[slot][selector] = ObjProtocolMethod{method.types.clone(), method.has_types}
		}
	}
}

fn objc_protocol_method_description(protocol u64, selector u64, required bool, instance bool) ObjProtocolDescription {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || protocol == 0 || selector == 0 { return ObjProtocolDescription{} }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	root := objc_protocol_canonical(protocol)
	first := ios_runtime.protocols[root] or { return ObjProtocolDescription{} }
	slot := (if required { 0 } else { 2 }) + if instance { 0 } else { 1 }
	// Explicit DFS preserves the declared parent order, including diamonds.
	// Each frame records its next parent; each canonical node is entered once.
	// The registry has at most 4096 nodes. Scratch is entirely on the stack.
	work := u64(C.__builtin_alloca(4096 * 8))
	next := u64(C.__builtin_alloca(4096 * 4))
	seen := u64(C.__builtin_alloca(4096))
	C.memset(unsafe { voidptr(seen) }, 0, 4096)
	unsafe { *(&u64(work)) = root; *(&u32(next)) = 0; *(&u8(seen + u64(first.index))) = 1 }
	mut depth := 0
	for depth >= 0 {
		current := read64(work + u64(depth * 8))
		info := ios_runtime.protocols[current] or { return ObjProtocolDescription{} }
		cursor := read32(next + u64(depth * 4))
		if cursor == 0 {
			if method := info.descriptions[slot][selector] {
				return ObjProtocolDescription{selector, if method.has_types { u64(method.types.str) } else { u64(0) }}
			}
		}
		if cursor >= u32(info.parents.len) { depth--; continue }
		write32(next + u64(depth * 4), cursor + 1)
		parent := info.parents[int(cursor)]
		parent_info := ios_runtime.protocols[parent] or { return ObjProtocolDescription{} }
		if unsafe { *(&u8(seen + u64(parent_info.index))) } != 0 { continue }
		depth++
		unsafe { *(&u64(work + u64(depth * 8))) = parent; *(&u32(next + u64(depth * 4))) = 0; *(&u8(seen + u64(parent_info.index))) = 1 }
	}
	return ObjProtocolDescription{}
}

fn objc_protocol_methods_free(info &ObjProtocol) {
	for slot in 0 .. 4 {
		for _, method in info.descriptions[slot] { unsafe { method.types.free() } }
		unsafe { info.descriptions[slot].free() }
	}
}
