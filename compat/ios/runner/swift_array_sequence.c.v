// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftArraySequenceView {
	owner u64
	count u64
	storage SwiftArrayStorage
}
type SwiftArraySequenceStore = fn (u64, u32, u32, u64)
type SwiftArraySequenceBody = fn (u64, u64, u64, u64, u64) u64

// Only canonical Array metadata from our factory can instantiate this
// unconditional generic conformance. Foreign/generic records still reject.
fn swift_array_sequence_element_checked(metadata u64, iterator bool) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| metadata == 0 || metadata & 7 != 0 { return swift_sequence_failure() }
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_array_sequence_retired { return swift_sequence_failure() }
	if iterator {
		for element, base in ios_runtime.swift_array_sequence_metadata {
			if metadata == base + 8 { return element }
		}
	} else {
		for element, candidate in ios_runtime.swift_array_metadata {
			if metadata == candidate { return element }
		}
	}
	return swift_sequence_failure()
}

fn swift_array_sequence_view_checked(metadata u64, receiver u64, iterator bool) !SwiftArraySequenceView {
	element := swift_array_sequence_element_checked(metadata, iterator)!
	if receiver == 0 || receiver & 7 != 0 { return swift_sequence_failure() }
	owner := read64(receiver)
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if owner != 0 && owner == ios_runtime.swift_empty_array {
		return SwiftArraySequenceView{owner: owner, storage: swift_array_layout(0, element)!.storage}
	}
	storage := ios_runtime.swift_arrays[owner] or { return swift_sequence_failure() }
	count := read64(owner + 16)
	if storage.element != element || count > storage.capacity { return swift_sequence_failure() }
	return SwiftArraySequenceView{owner: owner, count: count, storage: storage}
}

fn swift_array_iterator_copy(destination u64, source u64, _metadata u64) u64 {
	owner := read64(source); position := read64(source + 8)
	swift_bridge_retain(owner)
	unsafe { *(&u64(destination)) = owner; *(&u64(destination + 8)) = position }
	return destination
}
fn swift_array_iterator_assign_copy(destination u64, source u64, metadata u64) u64 {
	previous := read64(destination)
	swift_array_iterator_copy(destination, source, metadata)
	swift_bridge_release(previous); return destination
}
fn swift_array_iterator_take(destination u64, source u64, _metadata u64) u64 {
	owner := read64(source); position := read64(source + 8)
	unsafe { *(&u64(destination)) = owner; *(&u64(destination + 8)) = position }
	return destination
}
fn swift_array_iterator_assign_take(destination u64, source u64, metadata u64) u64 {
	previous := read64(destination)
	swift_array_iterator_take(destination, source, metadata)
	swift_bridge_release(previous); return destination
}
fn swift_array_iterator_enum_get(value u64, empty_cases u32, _metadata u64) u32 {
	if empty_cases > 0x7fffffff && unsafe { *(&u8(value + 16)) } != 0 { return unsafe { *(&u32(value)) } + 0x80000000 }
	owner := read64(value)
	return if owner >> 32 == 0 { u32(owner) + 1 } else { u32(0) }
}
fn swift_array_iterator_enum_store(value u64, which_case u32, empty_cases u32, _metadata u64) {
	if empty_cases > 0x7fffffff { unsafe { *(&u8(value + 16)) = if which_case > 0x7fffffff { u8(1) } else { u8(0) } } }
	if which_case > 0x7fffffff { C.memset(voidptr(value), 0, 16) }
	if which_case != 0 { unsafe { *(&u64(value)) = if which_case <= 0x7fffffff { u64(which_case - 1) } else { u64(which_case - 0x80000000) } } }
}

fn swift_array_sequence_make(metadata u64, _table u64, output u64, receiver u64) {
	view := swift_array_sequence_view_checked(metadata, receiver, false) or { panic(err) }
	// Consumes the caller's Array value; ownership transfers without a retain.
	unsafe { *(&u64(output)) = view.owner; *(&u64(output + 8)) = 0 }
}
fn swift_array_sequence_next_checked(metadata u64, output u64, receiver u64) ! {
	view := swift_array_sequence_view_checked(metadata, receiver, true)!
	position := read64(receiver + 8)
	if output == 0 || position > view.count { return swift_sequence_failure() }
	value := swift_sequence_value_checked(view.storage.element)!
	store_address := read64(read64(value.metadata - 8) + 56)
	if store_address == 0 || store_address & 3 != 0 { return swift_sequence_failure() }
	store := unsafe { SwiftArraySequenceStore(voidptr(store_address)) }
	if position == view.count { store(output, 1, 1, value.metadata); return }
	copy_value := unsafe { SwiftSequenceCopy(voidptr(value.copy)) }
	copy_value(output, view.owner + view.storage.tail + position * view.storage.stride, value.metadata)
	store(output, 0, 1, value.metadata)
	unsafe { *(&u64(receiver + 8)) = position + 1 }
}
fn swift_array_sequence_next(metadata u64, _table u64, output u64, receiver u64) {
	swift_array_sequence_next_checked(metadata, output, receiver) or { panic(err) }
}
fn swift_array_sequence_count(metadata u64, _table u64, receiver u64) u64 {
	return (swift_array_sequence_view_checked(metadata, receiver, false) or { panic(err) }).count
}
fn swift_array_sequence_contiguous(metadata u64, _table u64, receiver u64) u64 {
	// Native typed tails are already contiguous. Consume and transfer ownership.
	return (swift_array_sequence_view_checked(metadata, receiver, false) or { panic(err) }).owner
}

// This tuple's generic Iterator component is explicitly indirect in x0;
// destination/count/Array metadata/table are x1..x4 and the Index returns x0.
fn swift_array_sequence_contents_checked(output u64, destination u64, capacity i64,
	metadata u64, receiver u64) !u64 {
	view := swift_array_sequence_view_checked(metadata, receiver, false)!
	if output == 0 || capacity < 0 || u64(capacity) < view.count
		|| (view.count != 0 && destination == 0) { return swift_sequence_failure() }
	value := swift_sequence_value_checked(view.storage.element)!
	if destination & (value.alignment - 1) != 0
		|| (view.count != 0 && destination > ~u64(0) - (view.count - 1) * view.storage.stride - value.size) {
		return swift_sequence_failure()
	}
	copy_value := unsafe { SwiftSequenceCopy(voidptr(value.copy)) }
	for i in u64(0) .. view.count {
		copy_value(destination + i * view.storage.stride, view.owner + view.storage.tail + i * view.storage.stride, value.metadata)
	}
	unsafe { *(&u64(output)) = view.owner; *(&u64(output + 8)) = view.count }
	return view.count
}
fn swift_array_sequence_contents(output u64, destination u64, capacity i64,
	metadata u64, _table u64, receiver u64) u64 {
	return swift_array_sequence_contents_checked(output, destination, capacity, metadata, receiver) or { panic(err) }
}

fn swift_array_sequence_storage_checked(body u64, context u64, result u64, metadata u64,
	receiver u64, output u64) !u64 {
	if body == 0 || output == 0 { return swift_sequence_failure() }
	view := swift_array_sequence_view_checked(metadata, receiver, false)!
	value := swift_sequence_value_checked(result)!
	store_address := read64(read64(result - 8) + 56)
	if store_address == 0 || store_address & 3 != 0 { return swift_sequence_failure() }
	temporary_base := u64(C.__builtin_alloca(usize(value.size + value.alignment + 16)))
	temporary := (temporary_base + value.alignment - 1) & ~(value.alignment - 1)
	call := unsafe { SwiftArraySequenceBody(voidptr(ios_runtime.swift_array_sequence_arena + 352)) }
	// Pin the borrowed contiguous owner across reentrant closure calls.
	swift_bridge_retain(view.owner); defer { swift_bridge_release(view.owner) }
	error := call(body, context, view.owner + view.storage.tail, view.count, temporary)
	if error != 0 { return error }
	take := unsafe { SwiftSequenceCopy(voidptr(value.take)) }
	take(output, temporary, result)
	store := unsafe { SwiftArraySequenceStore(voidptr(store_address)) }
	store(output, 0, 1, result)
	return 0
}
fn swift_array_sequence_storage(body u64, context u64, result u64, metadata u64,
	_table u64, receiver u64, output u64) u64 {
	return swift_array_sequence_storage_checked(body, context, result, metadata, receiver, output) or { panic(err) }
}

fn swift_array_sequence_table_checked(metadata u64) !u64 {
	return read64(swift_collection_table_checked(metadata)! + 8)
}

fn swift_array_sequence_build_checked(metadata u64, collection u64) !u64 {
	element := swift_array_sequence_element_checked(metadata, false)!
	// Iterator layout depends on Array and Int, never on completing Element.
	// Operations that actually read elements validate their witnesses separately.
	swift_array_sequence_arena()
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if base := ios_runtime.swift_array_sequence_metadata[element] { return base + 256 }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return swift_sequence_failure() }
	base := u64(allocation); code := ios_runtime.swift_array_sequence_arena; data := code + u64(page)
	unsafe {
		*(&u64(base)) = base + 64
		*(&u64(base + 8)) = 0x200
		*(&u64(base + 16)) = ios_runtime.swift_collection_arena + u64(page) + 3840
		*(&u64(base + 24)) = metadata
		*(&u64(base + 32)) = collection
		*(&u32(base + 44)) = 8 // Frozen field offsets: owner at zero, position at eight.
	}
	for i, witness in [u64(unsafe { voidptr(swift_array_iterator_copy) }),
		u64(unsafe { voidptr(swift_array_destroy) }), u64(unsafe { voidptr(swift_array_iterator_copy) }),
		u64(unsafe { voidptr(swift_array_iterator_assign_copy) }), u64(unsafe { voidptr(swift_array_iterator_take) }),
		u64(unsafe { voidptr(swift_array_iterator_assign_take) }), u64(unsafe { voidptr(swift_array_iterator_enum_get) }),
		u64(unsafe { voidptr(swift_array_iterator_enum_store) })]! { unsafe { *(&u64(base + 64 + u64(i * 8))) = witness } }
	unsafe { *(&u64(base + 128)) = 16; *(&u64(base + 136)) = 16 }
	write32(base + 144, 0x10007); write32(base + 148, 0x7fffffff)
	unsafe { *(&u64(base + 160)) = ios_runtime.swift_collection_arena + u64(page) + 3968; *(&u64(base + 168)) = element; *(&u64(base + 176)) = code + 64 }
	for i, word in [data + 128, base + 160, element, base + 8, code, code + 128,
		code + 160, code + 192, code + 224, code + 288]! { unsafe { *(&u64(base + 256 + u64(i * 8))) = word } }
	if C.mprotect(allocation, page, C.PROT_READ) != 0 {
		C.munmap(allocation, page); return swift_sequence_failure()
	}
	ios_runtime.swift_array_sequence_metadata[element] = base
	return base + 256
}

fn swift_array_sequence_instantiate(table u64, metadata u64, _arguments u64) {
	canonical := swift_array_sequence_table_checked(metadata) or { panic(err) }
	C.memcpy(unsafe { voidptr(table) }, unsafe { voidptr(canonical) }, 80)
}
fn swift_array_iterator_table_checked(metadata u64) !u64 {
	element := swift_array_sequence_element_checked(metadata, true)!
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	base := ios_runtime.swift_array_sequence_metadata[element] or { return swift_sequence_failure() }
	return base + 160
}
fn swift_array_iterator_instantiate(table u64, metadata u64, _arguments u64) {
	canonical := swift_array_iterator_table_checked(metadata) or { panic(err) }
	C.memcpy(unsafe { voidptr(table) }, unsafe { voidptr(canonical) }, 24)
}

fn swift_array_sequence_arena() u64 {
	return swift_array_sequence_arena_checked() or { panic(err) }
}

fn swift_array_sequence_arena_checked() !u64 {
	$if !arm64 { return swift_sequence_failure() }
	if ios_runtime == unsafe { nil } { return swift_sequence_failure() }
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_array_sequence_retired || ios_runtime.swift_concurrency_retired {
		return swift_sequence_failure()
	}
	if ios_runtime.swift_array_sequence_arena != 0 { return ios_runtime.swift_array_sequence_arena }
	// Borrow Array's module while holding the recursive publication lock.
	// Collection retires first, then these records, then Array's module page.
	swift_array_arena()
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return swift_sequence_failure() }
	base := u64(allocation); data := base + u64(page)
	for i, target in [u64(unsafe { voidptr(swift_array_sequence_make) }), u64(unsafe { voidptr(swift_array_sequence_next) })]! {
		offset := u64(i * 64)
		for j, op in [u32(0xaa0803e2), 0xaa1403e3, 0x58000090, 0xd61f0200]! { write32(base + offset + u64(j * 4), op) }
		unsafe { *(&u64(base + offset + 24)) = target }
	}
	for i, target in [u64(unsafe { voidptr(swift_array_sequence_count) }), u64(unsafe { voidptr(swift_array_sequence_contiguous) })]! {
		offset := u64(128 + i * 64)
		write32(base + offset, 0xaa1403e2); write32(base + offset + 4, 0x58000070); write32(base + offset + 8, 0xd61f0200)
		unsafe { *(&u64(base + offset + 16)) = target }
	}
	write32(base + 160, 0x52800040); write32(base + 164, 0xd65f03c0) // Native Optional<Bool>.none.
	write32(base + 224, 0xaa1403e5); write32(base + 228, 0x58000070); write32(base + 232, 0xd61f0200)
	unsafe { *(&u64(base + 240)) = u64(voidptr(swift_array_sequence_contents)) }
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e5, 0xaa0803e6, 0x580000b0, 0xd63f0200, 0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! { write32(base + 288 + u64(i * 4), op) }
	unsafe { *(&u64(base + 320)) = u64(voidptr(swift_array_sequence_storage)) }
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103f4,
		0xaa0203e0, 0xaa0303e1, 0xaa0403e8, 0xaa1f03f5, 0xd63f0200, 0xaa1503e0,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! { write32(base + 352 + u64(i * 4), op) }
	for i, target in [u64(unsafe { voidptr(swift_array_sequence_instantiate) }), u64(unsafe { voidptr(swift_array_iterator_instantiate) })]! {
		offset := u64(448 + i * 32)
		write32(base + offset, 0x58000050); write32(base + offset + 4, 0xd61f0200)
		unsafe { *(&u64(base + offset + 8)) = target }
	}
	// Sequence's two generic requirements and nine witness requirements retain
	// their measured layout. Complete per-Element tables replace tagged patterns.
	protocol := data + 256; iterator_protocol := data + 384
	module_descriptor := ios_runtime.swift_array_arena + u64(page) + 224
	write32(protocol, 0x30043); swift_protocol_relative(protocol + 4, module_descriptor)
	swift_protocol_relative(protocol + 8, data + 448); write32(protocol + 12, 2); write32(protocol + 16, 9)
	swift_protocol_relative(protocol + 20, data + 640)
	write32(protocol + 24, 1); swift_protocol_relative(protocol + 28, data + 512); swift_protocol_relative(protocol + 32, data + 544)
	write32(protocol + 36, 0x80); swift_protocol_relative(protocol + 40, data + 576); swift_protocol_relative(protocol + 44, iterator_protocol)
	for i, flags in [u32(0xb7340008), 0xb6c50007, 0x0cbc0007, 0x6d280011, 0x44000013, 0x01300011, 0x37910011, 0x8bad0011, 0x888a0011]! { write32(protocol + 48 + u64(i * 8), flags) }
	// Generic default witness synthesis remains unsupported. Array's complete
	// tables supply these operations explicitly; makeIterator has no default.
	write32(iterator_protocol, 0x30043); swift_protocol_relative(iterator_protocol + 4, module_descriptor)
	swift_protocol_relative(iterator_protocol + 8, data + 464); write32(iterator_protocol + 16, 2)
	swift_protocol_relative(iterator_protocol + 20, data + 664); write32(iterator_protocol + 24, 7); write32(iterator_protocol + 32, 0x11)
	for i, text in ['Sequence', 'IteratorProtocol', 'Element Iterator', 'Element',
		'7ElementSTQz', '8IteratorST_7ElementStQZ', '8IteratorSTQz', 'IndexingIterator']! {
		offsets := [u64(448), 464, 640, 664, 512, 544, 576, 608]!
		offset := offsets[i]
		C.memcpy(unsafe { voidptr(data + offset) }, text.str, usize(text.len + 1))
	}
	// Independent descriptor/pattern for the canonical Array specialization.
	swift_protocol_relative(data + 128, protocol)
	swift_protocol_relative(data + 132, ios_runtime.swift_array_arena + u64(page) + 160)
	swift_protocol_relative(data + 136, data + 704); write32(data + 140, 0x20000)
	for i, entry in [data + 128, u64(0), 0, 0, base, base + 128, base + 160, base + 192, base + 224, base + 288]! {
		unsafe { *(&u64(data + 704 + u64(i * 8))) = entry }
	}
	write32(data + 144, 0x1000a); swift_protocol_relative(data + 148, base + 448); swift_protocol_relative(data + 152, base + u64(page * 2))
	write32(data + 160, 0x51); swift_protocol_relative(data + 164, module_descriptor); swift_protocol_relative(data + 168, data + 608)
	write32(data + 180, 2); write32(data + 184, 4)
	swift_protocol_relative(data + 192, iterator_protocol); swift_protocol_relative(data + 196, data + 160)
	swift_protocol_relative(data + 200, data + 800); write32(data + 204, 0x20000)
	write32(data + 208, 0x10003); swift_protocol_relative(data + 212, base + 480); swift_protocol_relative(data + 216, base + u64(page * 2) + 128)
	unsafe { *(&u64(data + 800)) = data + 192; *(&u64(data + 816)) = base + 64 }
	C.__builtin___clear_cache(allocation, unsafe { voidptr(base + 496) })
	if C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) != 0 || C.mprotect(unsafe { voidptr(data) }, page, C.PROT_READ) != 0 {
		if C.munmap(allocation, page * 3) != 0 { panic('iOS: cannot retire unsealed Array Sequence records') }
		return swift_sequence_failure()
	}
	ios_runtime.swift_array_sequence_arena = base; return base
}

fn swift_array_sequence_symbol(symbol string) ?u64 {
	offset := match symbol {
		'_$sSayxGSTsMc' { 128 }
		'_$sSTMp' { 256 }
		'_$sSTTL' { 296 }
		'_$sST8IteratorST_StTn' { 304 }
		'_$s7ElementSTTl' { 312 }
		'_$s8IteratorSTTl' { 320 }
		// Resilient requirement aliases identify descriptor records, not calls.
		'_$sST12makeIterator0B0QzyFTq' { 328 }
		'_$sST19underestimatedCountSivgTq' { 336 }
		'_$sST31_customContainsEquatableElementySbSg0D0QzFTq' { 344 }
		'_$sST22_copyToContiguousArrays0cD0Vy7ElementQzGyFTq' { 352 }
		'_$sST13_copyContents12initializing8IteratorQz_SitSry7ElementQzG_tFTq' { 360 }
		'_$sST32withContiguousStorageIfAvailableyqd__Sgqd__SRy7ElementQzGKXEKlFTq' { 368 }
		'_$sStMp' { 384 }
		'_$sStTL' { 400 }
		'_$s7ElementStTl' { 408 }
		'_$sSt4next7ElementQzSgyFTq' { 416 }
		else { return none }
	}
	base := swift_array_sequence_arena_checked() or { return none }
	return base + u64(C.getpagesize()) + u64(offset)
}
fn swift_array_sequence_stop() {
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	ios_runtime.swift_array_sequence_retired = true
	page := usize(C.getpagesize())
	for _, base in ios_runtime.swift_array_sequence_metadata { if C.munmap(unsafe { voidptr(base) }, page) != 0 { panic('iOS: cannot retire Array Sequence metadata') } }
	unsafe { ios_runtime.swift_array_sequence_metadata.free() }
	if ios_runtime.swift_array_sequence_arena != 0 {
		if C.munmap(unsafe { voidptr(ios_runtime.swift_array_sequence_arena) }, page * 3) != 0 { panic('iOS: cannot retire Array Sequence records') }
		ios_runtime.swift_array_sequence_arena = 0
	}
}
