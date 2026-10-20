// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftKeyedContainerType {
	key u64
	coding_key u64
}
struct SwiftKeyedContainerFailure {}
fn (_ &SwiftKeyedContainerFailure) msg() string { return 'iOS: invalid or retired Swift keyed decoding container metadata' }
fn (_ &SwiftKeyedContainerFailure) code() int { return 1 }
__global swift_keyed_container_failure_value = SwiftKeyedContainerFailure{}
fn swift_keyed_container_failure() IError { return unsafe { &swift_keyed_container_failure_value } }

// The only stored field is a native Swift box reference. Generic identities
// are borrowed; completing this layout does not inspect K or its witness.
fn swift_keyed_container_metadata_checked(_request u64, key u64, coding_key u64) !SwiftAssociatedMetadata {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_keyed_container_retired
		|| ios_runtime.swift_concurrency_retired || key == 0 || coding_key == 0
		|| (key | coding_key) & 7 != 0 { return swift_keyed_container_failure() }
	code := swift_keyed_container_arena()
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	for base, args in ios_runtime.swift_keyed_container_metadata {
		if args.key == key && args.coding_key == coding_key {
			return SwiftAssociatedMetadata{ metadata: base + 8 }
		}
	}
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return swift_keyed_container_failure() }
	base := u64(allocation)
	unsafe {
		*(&u64(base)) = code + u64(page)
		*(&u64(base + 8)) = 0x200
		*(&u64(base + 16)) = code + u64(page) + 160
		*(&u64(base + 24)) = key
		*(&u64(base + 32)) = coding_key
		// The single _box field offset at metadata word four is zero.
	}
	if C.mprotect(allocation, page, C.PROT_READ) != 0 {
		C.munmap(allocation, page)
		return swift_keyed_container_failure()
	}
	ios_runtime.swift_keyed_container_metadata[base] = SwiftKeyedContainerType{key, coding_key}
	return SwiftAssociatedMetadata{ metadata: base + 8 }
}
fn swift_keyed_container_metadata_access(request u64, key u64, coding_key u64) SwiftAssociatedMetadata {
	return swift_keyed_container_metadata_checked(request, key, coding_key) or { panic(err) }
}
fn swift_keyed_container_instantiate_checked(descriptor u64, arguments u64, pattern u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_keyed_container_retired
		|| ios_runtime.swift_concurrency_retired || ios_runtime.swift_keyed_container_arena == 0
		|| arguments == 0 || arguments & 7 != 0 || arguments > ~u64(0) - 15 {
		return swift_keyed_container_failure()
	}
	data := ios_runtime.swift_keyed_container_arena + u64(C.getpagesize())
	if descriptor != data + 160 || pattern != data + 304 { return swift_keyed_container_failure() }
	return swift_keyed_container_metadata_checked(0, read64(arguments), read64(arguments + 8))!.metadata
}
fn swift_keyed_container_instantiate(descriptor u64, arguments u64, pattern u64) u64 {
	return swift_keyed_container_instantiate_checked(descriptor, arguments, pattern) or { panic(err) }
}

fn swift_keyed_container_copy(destination u64, source u64, _metadata u64) u64 {
	owner := swift_retain(read64(source))
	unsafe { *(&u64(destination)) = owner }
	return destination
}
fn swift_keyed_container_destroy(value u64, _metadata u64) { swift_release(read64(value)) }
fn swift_keyed_container_assign_copy(destination u64, source u64, _metadata u64) u64 {
	owner := swift_retain(read64(source))
	previous := read64(destination)
	unsafe { *(&u64(destination)) = owner }
	swift_release(previous)
	return destination
}
fn swift_keyed_container_assign_take(destination u64, source u64, _metadata u64) u64 {
	owner := read64(source)
	previous := read64(destination)
	unsafe { *(&u64(destination)) = owner }
	swift_release(previous)
	return destination
}

fn swift_keyed_container_arena() u64 {
	$if !arm64 { panic('iOS: keyed container metadata requires ARM64') }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_keyed_container_retired
		|| ios_runtime.swift_concurrency_retired { panic('iOS: keyed container metadata outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_keyed_container_arena != 0 { return ios_runtime.swift_keyed_container_arena }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { panic('iOS: cannot allocate keyed container metadata') }
	base := u64(allocation);data := base + u64(page)
	for i, target in [u64(unsafe { voidptr(swift_keyed_container_metadata_access) }),
		u64(unsafe { voidptr(swift_keyed_container_instantiate) })]! {
		entry := base + u64(i * 32)
		write32(entry, 0x58000050);write32(entry + 4, 0xd61f0200)
		unsafe { *(&u64(entry + 8)) = target }
	}
	for i, target in [u64(unsafe { voidptr(swift_keyed_container_copy) }),
		u64(unsafe { voidptr(swift_keyed_container_destroy) }), u64(unsafe { voidptr(swift_keyed_container_copy) }),
		u64(unsafe { voidptr(swift_keyed_container_assign_copy) }), u64(unsafe { voidptr(swift_unknown_value_take) }),
		u64(unsafe { voidptr(swift_keyed_container_assign_take) }), u64(unsafe { voidptr(swift_unknown_value_enum_get) }),
		u64(unsafe { voidptr(swift_unknown_value_enum_store) })]! { unsafe { *(&u64(data + u64(i * 8))) = target } }
	unsafe { *(&u64(data + 64)) = 8;*(&u64(data + 72)) = 8 }
	write32(data + 80, 0x02010007);write32(data + 84, 0x7fffffff)
	descriptor := data + 160
	write32(descriptor, 0xd1)
	swift_protocol_relative(descriptor + 4, data + 224)
	swift_protocol_relative(descriptor + 8, data + 248)
	swift_protocol_relative(descriptor + 12, base)
	// Field reflection is unsupported; preserve the frozen field offset vector.
	write32(descriptor + 20, 1);write32(descriptor + 24, 4)
	swift_protocol_relative(descriptor + 28, base + u64(page * 2))
	swift_protocol_relative(descriptor + 32, data + 304)
	write32(descriptor + 36, 0x10001);write32(descriptor + 40, 2)
	write32(descriptor + 44, 0x80);write32(descriptor + 48, 0x80)
	swift_protocol_relative(descriptor + 52, data + 288)
	swift_protocol_relative(descriptor + 56, data + 384)
	swift_protocol_relative(data + 232, data + 240)
	C.memcpy(voidptr(data + 240), c'Swift', 6)
	C.memcpy(voidptr(data + 248), c'KeyedDecodingContainer', 22)
	C.memcpy(voidptr(data + 288), c'x', 2)
	swift_protocol_relative(data + 304, base + 32)
	write32(data + 312, 0x40000000);swift_protocol_relative(data + 316, data)
	// Private declaration records describe the constraint, not executable
	// CodingKey conformances or defaults. No protocol/witness exports are added.
	for i, name in ['CodingKey', 'CustomDebugStringConvertible', 'CustomStringConvertible']! {
		p := data + [u64(384), 576, 640]![i]
		text := data + [u64(512), 608, 672]![i]
		write32(p, 0x30043);swift_protocol_relative(p + 4, data + 224)
		swift_protocol_relative(p + 8, text)
		write32(p + 16, if i == 0 { u32(6) } else { u32(1) })
		C.memcpy(voidptr(text), name.str, usize(name.len + 1))
		if i != 0 { write32(p + 24, 0x13) }
	}
	write32(data + 396, 2)
	for i, parent in [data + 576, data + 640]! {
		r := data + 408 + u64(i * 12)
		write32(r, 0x80);swift_protocol_relative(r + 4, data + 288);swift_protocol_relative(r + 8, parent)
	}
	for i, flags in [u32(0), 0, 0xdcb00013, 0x32b70002, 0xbeb70013, 0xf36c0002]! { write32(data + 432 + u64(i * 8), flags) }
	C.__builtin___clear_cache(allocation, voidptr(base + 48))
	if C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), page, C.PROT_READ) != 0 {
		C.munmap(allocation, page * 3);panic('iOS: cannot seal keyed container metadata')
	}
	ios_runtime.swift_keyed_container_arena = base
	return base
}
fn swift_keyed_container_metadata_symbol(symbol string) ?u64 {
	if symbol != '_$ss22KeyedDecodingContainerVMa' || ios_runtime == unsafe { nil }
		|| ios_runtime.swift_keyed_container_retired || ios_runtime.swift_concurrency_retired { return none }
	return swift_keyed_container_arena()
}
fn swift_keyed_container_metadata_stop() {
	ios_runtime.swift_keyed_container_retired = true
	page := usize(C.getpagesize())
	for base, _ in ios_runtime.swift_keyed_container_metadata {
		if C.munmap(voidptr(base), page) != 0 { panic('iOS: cannot retire keyed container specialization') }
	}
	unsafe { ios_runtime.swift_keyed_container_metadata.free() }
	if ios_runtime.swift_keyed_container_arena != 0 {
		if C.munmap(voidptr(ios_runtime.swift_keyed_container_arena), page * 3) != 0 { panic('iOS: cannot retire keyed container descriptor') }
		ios_runtime.swift_keyed_container_arena = 0
	}
}
