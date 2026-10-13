// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftCollectionView {
	element u64
	owner u64
	bytes u64
	stride u64
	start i64
	end i64
	size u64
	kind int // Array = 0, ArraySlice = 1, Range<Int> = 2.
}
struct SwiftCollectionYield { continuation u64 address u64 }

fn swift_collection_kind_checked(metadata u64, iterator bool) !int {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| metadata == 0 || metadata & 7 != 0 { return swift_sequence_failure() }
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	data := ios_runtime.swift_collection_arena + u64(C.getpagesize())
	if ios_runtime.swift_collection_arena != 0 && metadata == data + if iterator {u64(1088)} else {u64(1024)} { return 2 }
	for _, base in ios_runtime.swift_collection_metadata { if metadata == base + if iterator {u64(168)} else {u64(8)} { return 1 } }
	if !iterator { for _, candidate in ios_runtime.swift_array_metadata { if metadata == candidate { return 0 } } }
	return swift_sequence_failure()
}
fn swift_collection_view_checked(metadata u64, receiver u64) !SwiftCollectionView {
	kind := swift_collection_kind_checked(metadata, false)!
	if receiver == 0 || receiver & 7 != 0 { return swift_sequence_failure() }
	if kind == 2 {
		start := i64(read64(receiver)); end := i64(read64(receiver + 8))
		if start > end { return swift_sequence_failure() }
		return SwiftCollectionView{element: swift_integer_metadata(), start: start, end: end, size: 16, stride: 8, kind: 2}
	}
	array_metadata := if kind == 0 { metadata } else { swift_array_access(0, read64(metadata + 16)).metadata }
	array := swift_array_sequence_view_checked(array_metadata, receiver, false)!
	if array.count > 0x7fffffffffffffff { return swift_sequence_failure() }
	bytes := array.owner + array.storage.tail
	if kind == 0 { return SwiftCollectionView{element: array.storage.element, owner: array.owner, bytes: bytes,
		stride: array.storage.stride, end: i64(array.count), size: 8} }
	start := i64(read64(receiver + 16)); flags := read64(receiver + 24); end := i64(flags >> 1)
	if start < 0 || start > end || u64(end) > array.count || flags & 1 == 0 || read64(receiver + 8) != bytes { return swift_sequence_failure() }
	return SwiftCollectionView{element: array.storage.element, owner: array.owner, bytes: bytes,
		stride: array.storage.stride, start: start, end: end, size: 32, kind: 1}
}
fn swift_collection_value_size(metadata u64) u64 { return read64(read64(metadata - 8) + 64) }
fn swift_collection_value_owned(metadata u64) bool { return read32(read64(metadata - 8) + 84) != 0 }
fn swift_collection_buffer_copy(destination u64, source u64, metadata u64) u64 {
	if swift_collection_value_size(metadata) <= 24 { return swift_collection_value_copy(destination, source, metadata) }
	owner := read64(source)
	C.ios_objc_initialize_lock()
	storage := ios_runtime.swift_heap[owner] or { C.ios_objc_initialize_unlock(); panic('iOS: unregistered Collection value buffer') }
	valid := storage.size == swift_collection_value_size(metadata) + 16 && read64(storage.metadata + 8) == metadata
	C.ios_objc_initialize_unlock()
	if !valid { panic('iOS: incompatible Collection value buffer') }
	swift_retain(owner); unsafe { *(&u64(destination)) = owner }; return owner + 16
}
fn swift_collection_box_destroy(owner u64) {
	metadata := read64(read64(owner) + 8); size := swift_collection_value_size(metadata)
	swift_collection_value_destroy(owner + 16, metadata); swift_heap_deallocate(owner, size + 16, 7)
}
fn swift_collection_box_allocate(metadata u64) u64 {
	kind := swift_collection_kind_checked(metadata, false) or { -1 }
	if kind == 1 { return swift_heap_allocate(metadata - 8 + 896, 48, 7) }
	if (swift_collection_kind_checked(metadata, true) or { -1 }) == 1 { return swift_heap_allocate(metadata - 168 + 928, 56, 7) }
	panic('iOS: unsupported Collection value buffer layout')
}
fn swift_collection_value_copy(destination u64, source u64, metadata u64) u64 {
	if swift_collection_value_owned(metadata) { swift_bridge_retain(read64(source)) }
	C.memmove(voidptr(destination), voidptr(source), usize(swift_collection_value_size(metadata))); return destination
}
fn swift_collection_value_destroy(value u64, metadata u64) { if swift_collection_value_owned(metadata) { swift_bridge_release(read64(value)) } }
fn swift_collection_value_assign_copy(destination u64, source u64, metadata u64) u64 {
	previous := if swift_collection_value_owned(metadata) {read64(destination)} else {u64(0)}
	swift_collection_value_copy(destination, source, metadata)
	if previous != 0 { swift_bridge_release(previous) }; return destination
}
fn swift_collection_value_take(destination u64, source u64, metadata u64) u64 {
	C.memmove(voidptr(destination), voidptr(source), usize(swift_collection_value_size(metadata))); return destination
}
fn swift_collection_value_assign_take(destination u64, source u64, metadata u64) u64 {
	previous := if swift_collection_value_owned(metadata) {read64(destination)} else {u64(0)}
	swift_collection_value_take(destination, source, metadata)
	if previous != 0 { swift_bridge_release(previous) }; return destination
}
fn swift_collection_value_tag(value u64, cases u32, metadata u64) u32 {
	if cases == 0 { return 0 }
	size := swift_collection_value_size(metadata)
	if !swift_collection_value_owned(metadata) { return if unsafe { *(&u8(value + size)) } == 0 {u32(0)} else {read32(value) + 1} }
	if cases > 0x7fffffff && unsafe { *(&u8(value + size)) } != 0 { return read32(value) + 0x80000000 }
	owner := read64(value); return if owner >> 32 == 0 {u32(owner) + 1} else {u32(0)}
}
fn swift_collection_value_store(value u64, which u32, cases u32, metadata u64) {
	if cases == 0 { return }
	size := swift_collection_value_size(metadata)
	if !swift_collection_value_owned(metadata) {
		unsafe { *(&u8(value + size)) = if which == 0 {u8(0)} else {u8(1)} }
		if which != 0 { unsafe { *(&u64(value)) = u64(which - 1) } }; return
	}
	if cases > 0x7fffffff { unsafe { *(&u8(value + size)) = if which > 0x7fffffff {u8(1)} else {u8(0)} } }
	if which != 0 { unsafe { *(&u64(value)) = if which <= 0x7fffffff {u64(which - 1)} else {u64(which - 0x80000000)} } }
}
fn swift_collection_index_get(metadata u64, _table u64, receiver u64, output u64, end bool) {
	view := swift_collection_view_checked(metadata, receiver) or {panic(err)}
	unsafe { *(&i64(output)) = if end {view.end} else {view.start} }
}
fn swift_collection_start(metadata u64, table u64, receiver u64, output u64) { swift_collection_index_get(metadata, table, receiver, output, false) }
fn swift_collection_end(metadata u64, table u64, receiver u64, output u64) { swift_collection_index_get(metadata, table, receiver, output, true) }
fn swift_collection_count(metadata u64, _table u64, receiver u64) i64 {
	view := swift_collection_view_checked(metadata, receiver) or {panic(err)}
	if view.start < 0 && view.end > i64(0x7fffffffffffffff) + view.start { panic('iOS: Collection count overflow') }
	return view.end - view.start
}
fn swift_collection_empty(metadata u64, table u64, receiver u64) bool { return swift_collection_count(metadata, table, receiver) == 0 }
fn swift_collection_yield_checked(buffer u64, index u64, metadata u64, receiver u64) !SwiftCollectionYield {
	view := swift_collection_view_checked(metadata, receiver)!
	if buffer == 0 || buffer & 7 != 0 || index == 0 { return swift_sequence_failure() }
	position := i64(read64(index))
	if position < view.start || position >= view.end { return swift_sequence_failure() }
	mut address := buffer + 16
	if view.kind == 2 { unsafe { *(&i64(address)) = position } }
	else { address = view.bytes + u64(position) * view.stride; swift_bridge_retain(view.owner) }
	unsafe { *(&u64(buffer)) = view.owner; *(&u64(buffer + 8)) = 1 }
	return SwiftCollectionYield{continuation: ios_runtime.swift_collection_arena + 1152, address: address}
}
fn swift_collection_yield(buffer u64, index u64, metadata u64, _table u64, receiver u64) SwiftCollectionYield { return swift_collection_yield_checked(buffer, index, metadata, receiver) or {panic(err)} }
fn swift_collection_resume(buffer u64, _aborting u64) {
	if read64(buffer + 8) != 1 { panic('iOS: retired Collection borrow') }
	owner := read64(buffer); unsafe { *(&u64(buffer + 8)) = 0 }
	if owner != 0 { swift_bridge_release(owner) }
}
fn swift_collection_slice_checked(bounds u64, metadata u64, receiver u64, output u64) ! {
	view := swift_collection_view_checked(metadata, receiver)!
	if bounds == 0 || output == 0 { return swift_sequence_failure() }
	start := i64(read64(bounds)); end := i64(read64(bounds + 8))
	if start < view.start || start > end || end > view.end { return swift_sequence_failure() }
	if view.kind == 2 { unsafe { *(&i64(output)) = start; *(&i64(output + 8)) = end }; return }
	swift_bridge_retain(view.owner)
	unsafe { *(&u64(output)) = view.owner; *(&u64(output + 8)) = view.bytes; *(&i64(output + 16)) = start; *(&u64(output + 24)) = u64(end) << 1 | 1 }
}
fn swift_collection_slice(bounds u64, metadata u64, _table u64, receiver u64, output u64) { swift_collection_slice_checked(bounds, metadata, receiver, output) or {panic(err)} }
fn swift_collection_indices(metadata u64, _table u64, receiver u64, output u64) {
	view := swift_collection_view_checked(metadata, receiver) or {panic(err)}
	unsafe { *(&i64(output)) = view.start; *(&i64(output + 8)) = view.end }
}
fn swift_collection_sum_checked(left i64, right i64) !i64 {
	if (right > 0 && left > i64(0x7fffffffffffffff) - right) || (right < 0 && left < (-i64(0x7fffffffffffffff) - 1) - right) { return swift_sequence_failure() }
	return left + right
}
fn swift_collection_offset(index u64, distance i64, _metadata u64, _table u64, output u64) {
	result := swift_collection_sum_checked(i64(read64(index)), distance) or {panic(err)}; unsafe { *(&i64(output)) = result }
}
fn swift_collection_limited(index u64, distance i64, limit u64, _metadata u64, _table u64, output u64) {
	i := i64(read64(index)); bound := i64(read64(limit))
	// Limits behind the direction of travel have no effect. Compare before
	// adding, including overflow beyond a limiting boundary.
	if (distance > 0 && bound >= i && u64(distance) > u64(bound) - u64(i)) || (distance < 0 && bound <= i && u64(0) - u64(distance) > u64(i) - u64(bound)) {
		unsafe { *(&u64(output)) = 0; *(&u8(output + 8)) = 1 }; return
	}
	result := swift_collection_sum_checked(i, distance) or {panic(err)}
	unsafe { *(&i64(output)) = result; *(&u8(output + 8)) = 0 }
}
fn swift_collection_distance(start u64, end u64, _metadata u64, _table u64) i64 {
	left := i64(read64(start)); right := i64(read64(end))
	if (left > 0 && right < (-i64(0x7fffffffffffffff) - 1) + left) || (left < 0 && right > i64(0x7fffffffffffffff) + left) { panic('iOS: Collection distance overflow') }
	return right - left
}
fn swift_collection_closed_check(index u64, bounds u64, _metadata u64, _table u64) {
	i := i64(read64(index)); if i < i64(read64(bounds)) || i > i64(read64(bounds + 8)) { panic('iOS: Collection closed range check failed') }
}
fn swift_collection_after(index u64, _metadata u64, _table u64, output u64) { swift_collection_offset(index, 1, 0, 0, output) }
fn swift_collection_form_after(index u64, _metadata u64, _table u64) { swift_collection_offset(index, 1, 0, 0, index) }
fn swift_collection_find(element u64, metadata u64, _table u64, receiver u64, output u64) {
	view := swift_collection_view_checked(metadata, receiver) or {panic(err)}
	value := i64(read64(element)); found := value >= view.start && value < view.end
	unsafe { *(&i64(output)) = if found {value} else {i64(0)}; *(&u8(output + 8)) = if found {u8(0)} else {u8(1)}; *(&u8(output + 9)) = 0 }
}
fn swift_collection_contains(element u64, metadata u64, _table u64, receiver u64) bool {
	view := swift_collection_view_checked(metadata, receiver) or {panic(err)}; value := i64(read64(element))
	return value >= view.start && value < view.end
}
fn swift_collection_half_check(index u64, bounds u64, _metadata u64, _table u64) {
	value := i64(read64(index)); if value < i64(read64(bounds)) || value >= i64(read64(bounds + 8)) { panic('iOS: Collection half-open range check failed') }
}
fn swift_collection_bounds_check(range u64, bounds u64, _metadata u64, _table u64) {
	if i64(read64(range)) < i64(read64(bounds)) || i64(read64(range + 8)) > i64(read64(bounds + 8)) { panic('iOS: Collection slice bounds check failed') }
}

fn swift_collection_make(metadata u64, _table u64, receiver u64, output u64) {
	view := swift_collection_view_checked(metadata, receiver) or {panic(err)}
	C.memcpy(voidptr(output), voidptr(receiver), usize(view.size)); unsafe { *(&i64(output + view.size)) = view.start }
}
fn swift_collection_next(metadata u64, _table u64, receiver u64, output u64) {
	swift_collection_kind_checked(metadata, true) or {panic(err)}
	view := swift_collection_view_checked(read64(metadata + 16), receiver) or {panic(err)}
	position := i64(read64(receiver + view.size))
	if position < view.start || position > view.end { panic('iOS: invalid Collection iterator position') }
	value := swift_sequence_value_checked(view.element) or {panic(err)}
	store := unsafe { SwiftArraySequenceStore(voidptr(read64(read64(view.element - 8) + 56))) }
	if position == view.end { store(output, 1, 1, view.element); return }
	if view.kind == 2 { unsafe { *(&i64(output)) = position } }
	else { copy_value := unsafe { SwiftSequenceCopy(voidptr(value.copy)) }; copy_value(output, view.bytes + u64(position) * view.stride, view.element) }
	store(output, 0, 1, view.element); unsafe { *(&i64(receiver + view.size)) = position + 1 }
}
fn swift_collection_copy_elements(view SwiftCollectionView, destination u64) {
	value := swift_sequence_value_checked(view.element) or {panic(err)}; copy_value := unsafe { SwiftSequenceCopy(voidptr(value.copy)) }
	for i := view.start; i < view.end; i++ {
		address := destination + (u64(i) - u64(view.start)) * view.stride
		if view.kind == 2 { unsafe { *(&i64(address)) = i } } else { copy_value(address, view.bytes + u64(i) * view.stride, view.element) }
	}
}
fn swift_collection_contiguous(metadata u64, table u64, receiver u64) u64 {
	view := swift_collection_view_checked(metadata, receiver) or {panic(err)}
	allocation := swift_array_allocate(swift_collection_count(metadata, table, receiver), view.element)
	swift_collection_copy_elements(view, allocation.bytes)
	if view.owner != 0 { swift_bridge_release(view.owner) }; return allocation.owner
}
fn swift_collection_contents(output u64, destination u64, capacity i64, metadata u64, _table u64, receiver u64) u64 {
	view := swift_collection_view_checked(metadata, receiver) or {panic(err)}; count := swift_collection_count(metadata, 0, receiver)
	if capacity < count || output == 0 || (count != 0 && destination == 0) { panic('iOS: insufficient Collection copy destination') }
	value := swift_sequence_value_checked(view.element) or {panic(err)}
	if destination & (value.alignment - 1) != 0 || u64(count) > (~u64(0) - destination) / view.stride { panic('iOS: invalid Collection copy destination') }
	swift_collection_copy_elements(view, destination)
	C.memcpy(voidptr(output), voidptr(receiver), usize(view.size)); unsafe { *(&i64(output + view.size)) = view.end }; return u64(count)
}
fn swift_collection_storage(body u64, context u64, result u64, metadata u64, _table u64, receiver u64, output u64) u64 {
	view := swift_collection_view_checked(metadata, receiver) or {panic(err)}; value := swift_sequence_value_checked(result) or {panic(err)}
	store := unsafe { SwiftArraySequenceStore(voidptr(read64(read64(result - 8) + 56))) }
	if view.kind == 2 { store(output, 1, 1, result); return 0 }
	temporary_base := u64(C.__builtin_alloca(usize(value.size + value.alignment + 16))); temporary := (temporary_base + value.alignment - 1) & ~(value.alignment - 1)
	call := unsafe { SwiftArraySequenceBody(voidptr(ios_runtime.swift_array_sequence_arena + 352)) }
	swift_bridge_retain(view.owner); defer { swift_bridge_release(view.owner) }
	error := call(body, context, view.bytes + u64(view.start) * view.stride, u64(view.end - view.start), temporary)
	if error != 0 { return error }
	take := unsafe { SwiftSequenceCopy(voidptr(value.take)) }; take(output, temporary, result); store(output, 0, 1, result); return 0
}
fn swift_collection_less(left u64, right u64, _metadata u64, _table u64) bool { return i64(read64(left)) < i64(read64(right)) }
fn swift_collection_less_equal(left u64, right u64, _metadata u64, _table u64) bool { return i64(read64(left)) <= i64(read64(right)) }
fn swift_collection_greater_equal(left u64, right u64, _metadata u64, _table u64) bool { return i64(read64(left)) >= i64(read64(right)) }
fn swift_collection_greater(left u64, right u64, _metadata u64, _table u64) bool { return i64(read64(left)) > i64(read64(right)) }

fn swift_collection_vwt(address u64, size u64, owned bool) {
	for i, function in [u64(unsafe { voidptr(swift_collection_buffer_copy) }), u64(unsafe { voidptr(swift_collection_value_destroy) }),
		u64(unsafe { voidptr(swift_collection_value_copy) }), u64(unsafe { voidptr(swift_collection_value_assign_copy) }), u64(unsafe { voidptr(swift_collection_value_take) }),
		u64(unsafe { voidptr(swift_collection_value_assign_take) }), u64(unsafe { voidptr(swift_collection_value_tag) }), u64(unsafe { voidptr(swift_collection_value_store) })]! { unsafe { *(&u64(address + u64(i * 8))) = function } }
	unsafe { *(&u64(address + 64)) = size; *(&u64(address + 72)) = size }
	write32(address + 80, if owned {u32(0x30007)} else {u32(7)}); write32(address + 84, if owned {u32(0x7fffffff)} else {u32(0)})
}
fn swift_collection_sequence_emit(address u64, descriptor u64, element u64, iterator u64, iterator_table u64, code u64) {
	for i, entry in [descriptor, iterator_table, element, iterator, code + 1216, code + 1280, code + 1344, code + 1408, code + 1472, code + 1536]! { unsafe { *(&u64(address + u64(i * 8))) = entry } }
}
fn swift_collection_table_checked(metadata u64) !u64 {
	kind := swift_collection_kind_checked(metadata, false)!
	if kind == 2 { return ios_runtime.swift_collection_arena + u64(C.getpagesize()) + 1200 }
	if kind == 1 {
		C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
		for _, base in ios_runtime.swift_collection_metadata { if metadata == base + 8 { return base + 528 } }; return swift_sequence_failure()
	}
	sequence := swift_array_sequence_table_checked(metadata)!; element := read64(metadata + 16); swift_collection_arena()
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if base := ios_runtime.swift_collection_metadata[element] { return base + 320 }
	page := usize(C.getpagesize()); allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == voidptr(-1) { return swift_sequence_failure() }
	base := u64(allocation); code := ios_runtime.swift_collection_arena; data := code + u64(page)
	unsafe {
		*(&u64(base)) = base + 64; *(&u64(base + 8)) = 0x200; *(&u64(base + 16)) = data + 160; *(&u64(base + 24)) = element
		*(&u64(base + 160)) = base + 224; *(&u64(base + 168)) = 0x200; *(&u64(base + 176)) = data + 192; *(&u64(base + 184)) = base + 8
		*(&u64(base + 192)) = base + 528; *(&u64(base + 200)) = u64(32) << 32
		*(&u64(base + 824)) = data + 704; *(&u64(base + 832)) = element; *(&u64(base + 840)) = code + 1600
		*(&u64(base + 880)) = code + 1792; *(&u64(base + 896)) = 0x400; *(&u64(base + 904)) = base + 8
		*(&u64(base + 912)) = code + 1792; *(&u64(base + 928)) = 0x400; *(&u64(base + 936)) = base + 168
	}
	swift_collection_vwt(base + 64, 32, true); swift_collection_vwt(base + 224, 40, true)
	// Cached metadata avoids recursive factory calls under this lock.
	for i, entry in [data + 32, sequence, data + 920, data + 1200, base + 528, ios_runtime.swift_integer_arena + u64(page) + 16, base + 8, data + 1024]! { unsafe { *(&u64(base + 320 + u64(i * 8))) = entry } }
	for i, entry in [data + 64, base + 736, data + 920, data + 1200, base + 528, ios_runtime.swift_integer_arena + u64(page) + 16, base + 8, data + 1024]! { unsafe { *(&u64(base + 528 + u64(i * 8))) = entry } }
	for address in [base + 320, base + 528]! { for i in 0 .. 17 { unsafe { *(&u64(address + u64((i + 8) * 8))) = code + u64(i * 64) } } }
	swift_collection_sequence_emit(base + 736, data + 640, element, base + 168, base + 824, code)
	if C.mprotect(allocation, page, C.PROT_READ) != 0 { C.munmap(allocation, page); return swift_sequence_failure() }
	ios_runtime.swift_collection_metadata[element] = base; return base + 320
}
fn swift_collection_sequence_checked(metadata u64) !u64 {
	kind := swift_collection_kind_checked(metadata, false)!
	if kind == 2 { return ios_runtime.swift_collection_arena + u64(C.getpagesize()) + 1408 }
	if kind != 1 { return swift_sequence_failure() }; return swift_collection_table_checked(metadata)! + 208
}
fn swift_collection_iterator_checked(metadata u64) !u64 {
	kind := swift_collection_kind_checked(metadata, true)!
	if kind == 2 { return ios_runtime.swift_collection_arena + u64(C.getpagesize()) + 1504 }
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	for _, base in ios_runtime.swift_collection_metadata { if metadata == base + 168 { return base + 824 } }; return swift_sequence_failure()
}
fn swift_collection_instantiate(table u64, metadata u64, _arguments u64) { canonical := swift_collection_table_checked(metadata) or {panic(err)}; C.memcpy(voidptr(table), voidptr(canonical), 200) }
fn swift_collection_sequence_instantiate(table u64, metadata u64, _arguments u64) { canonical := swift_collection_sequence_checked(metadata) or {panic(err)}; C.memcpy(voidptr(table), voidptr(canonical), 80) }
fn swift_collection_iterator_instantiate(table u64, metadata u64, _arguments u64) { canonical := swift_collection_iterator_checked(metadata) or {panic(err)}; C.memcpy(voidptr(table), voidptr(canonical), 24) }

fn swift_collection_bridge(address u64, target u64, instructions [2]u32, count int) {
	for i in 0 .. count { write32(address + u64(i * 4), instructions[i]) }
	words := if count == 1 {2} else {count}
	if count == 1 { write32(address + 4, 0xd503201f) }
	write32(address + u64(words * 4), 0x58000050); write32(address + u64(words * 4 + 4), 0xd61f0200)
	unsafe { *(&u64(address + u64(words * 4 + 8))) = target }
}
fn swift_collection_arena() u64 {
	swift_array_arena(); swift_array_sequence_arena(); swift_integer_metadata()
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_collection_arena != 0 { return ios_runtime.swift_collection_arena }
	page := usize(C.getpagesize()); allocation := C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == voidptr(-1) { panic('iOS: cannot allocate Collection records') }
	code := u64(allocation); data := code + u64(page)
	for i, target in [u64(unsafe { voidptr(swift_collection_start) }), u64(unsafe { voidptr(swift_collection_end) })]! { swift_collection_bridge(code + u64(i * 64), target, [u32(0xaa1403e2), 0xaa0803e3]!, 2) }
	swift_collection_bridge(code + 128, u64(unsafe { voidptr(swift_collection_yield) }), [u32(0xaa1403e4), 0]!, 1)
	swift_collection_bridge(code + 192, u64(unsafe { voidptr(swift_collection_slice) }), [u32(0xaa1403e3), 0xaa0803e4]!, 2)
	swift_collection_bridge(code + 256, u64(unsafe { voidptr(swift_collection_indices) }), [u32(0xaa1403e2), 0xaa0803e3]!, 2)
	for i, target in [u64(unsafe { voidptr(swift_collection_empty) }), u64(unsafe { voidptr(swift_collection_count) })]! { swift_collection_bridge(code + 320 + u64(i * 64), target, [u32(0xaa1403e2), 0]!, 1) }
	for offset in [u64(448), 512]! { write32(code + offset, 0xf900011f); write32(code + offset + 4, 0x52802009); write32(code + offset + 8, 0x79001109); write32(code + offset + 12, 0xd65f03c0) }
	swift_collection_bridge(code + 576, u64(unsafe { voidptr(swift_collection_offset) }), [u32(0xaa0803e4), 0]!, 1)
	swift_collection_bridge(code + 640, u64(unsafe { voidptr(swift_collection_limited) }), [u32(0xaa0803e5), 0]!, 1)
	swift_collection_bridge(code + 704, u64(unsafe { voidptr(swift_collection_distance) }), [u32(0), 0]!, 0)
	write32(code + 768, 0xd65f03c0); write32(code + 896, 0xd65f03c0)
	swift_collection_bridge(code + 832, u64(unsafe { voidptr(swift_collection_closed_check) }), [u32(0), 0]!, 0)
	swift_collection_bridge(code + 960, u64(unsafe { voidptr(swift_collection_after) }), [u32(0xaa0803e3), 0]!, 1)
	swift_collection_bridge(code + 1024, u64(unsafe { voidptr(swift_collection_form_after) }), [u32(0), 0]!, 0)
	swift_collection_bridge(code + 1152, u64(unsafe { voidptr(swift_collection_resume) }), [u32(0), 0]!, 0)
	swift_collection_bridge(code + 1216, u64(unsafe { voidptr(swift_collection_make) }), [u32(0xaa1403e2), 0xaa0803e3]!, 2)
	swift_collection_bridge(code + 1280, u64(unsafe { voidptr(swift_collection_count) }), [u32(0xaa1403e2), 0]!, 1)
	write32(code + 1344, 0x52800040); write32(code + 1348, 0xd65f03c0)
	swift_collection_bridge(code + 1408, u64(unsafe { voidptr(swift_collection_contiguous) }), [u32(0xaa1403e2), 0]!, 1)
	swift_collection_bridge(code + 1472, u64(unsafe { voidptr(swift_collection_contents) }), [u32(0xaa1403e5), 0]!, 1)
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e5, 0xaa0803e6, 0x580000b0, 0xd63f0200, 0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! { write32(code + 1536 + u64(i * 4), op) }
	unsafe { *(&u64(code + 1568)) = u64(voidptr(swift_collection_storage)) }
	swift_collection_bridge(code + 1600, u64(unsafe { voidptr(swift_collection_next) }), [u32(0xaa1403e2), 0xaa0803e3]!, 2)
	for i, target in [u64(unsafe { voidptr(swift_collection_instantiate) }), u64(unsafe { voidptr(swift_collection_sequence_instantiate) }), u64(unsafe { voidptr(swift_collection_iterator_instantiate) })]! { swift_collection_bridge(code + 1664 + u64(i * 32), target, [u32(0), 0]!, 0) }
	swift_collection_bridge(code + 1792, u64(unsafe { voidptr(swift_collection_box_destroy) }), [u32(0xaa1403e0), 0]!, 1)
	swift_collection_bridge(code + 1856, u64(unsafe { voidptr(swift_collection_find) }), [u32(0xaa1403e3), 0xaa0803e4]!, 2)
	swift_collection_bridge(code + 1920, u64(unsafe { voidptr(swift_collection_contains) }), [u32(0xaa1403e3), 0]!, 1)
	swift_collection_bridge(code + 1984, u64(unsafe { voidptr(swift_collection_half_check) }), [u32(0), 0]!, 0)
	swift_collection_bridge(code + 2048, u64(unsafe { voidptr(swift_collection_bounds_check) }), [u32(0), 0]!, 0)
	module_descriptor := ios_runtime.swift_array_arena + u64(page) + 224
	for i in 0 .. 3 {
		descriptor := data + 160 + u64(i * 32); write32(descriptor, 0x51)
		swift_protocol_relative(descriptor + 4, module_descriptor); swift_protocol_relative(descriptor + 8, data + 1952 + u64(i * 32))
		write32(descriptor + 20, if i == 0 {u32(1)} else {u32(2)}); write32(descriptor + 24, if i == 0 {u32(3)} else {u32(4)})
	}
	protocol := data + 256; comparable := data + 800
	write32(protocol, 0x30043); swift_protocol_relative(protocol + 4, module_descriptor); swift_protocol_relative(protocol + 8, data + 1888)
	write32(protocol + 12, 10); write32(protocol + 16, 24); swift_protocol_relative(protocol + 20, data + 1920)
	seq_protocol := ios_runtime.swift_array_sequence_arena + u64(page) + 256
	for i, flag in [u32(0x80), 1, 0x80, 1, 0x80, 1, 0x80, 1, 1, 1]! {
		p := protocol + 24 + u64(i * 12); write32(p, flag); swift_protocol_relative(p + 4, data + 2112 + u64(i * 64))
		swift_protocol_relative(p + 8, if flag != 0x80 {data + 2752 + u64(i * 64)} else if i == 0 {seq_protocol} else if i == 2 {comparable} else {protocol})
	}
	for i, flag in [u32(0), 0xd0840008, 0x4e290008, 0xdc110008, 0x93040007, 0x27770007, 0xe2eb0007,
		0x40c80013, 0x1e5e0013, 0x05e60015, 0x61c10013, 0x9b6a0013, 0x98d90013, 0x6a700013, 0x7d040011, 0x3afa0011,
		0x4e970011, 0xdde40011, 0x68e70011, 0x7d500011, 0x40e60011, 0x87b80011, 0x80df0011, 0x84210011]! { write32(protocol + 144 + u64(i * 8), flag) }
	write32(comparable, 0x30043); swift_protocol_relative(comparable + 4, module_descriptor); swift_protocol_relative(comparable + 8, data + 1904)
	write32(comparable + 12, 1); write32(comparable + 16, 5); write32(comparable + 24, 0x80)
	swift_protocol_relative(comparable + 28, data + 2112); swift_protocol_relative(comparable + 32, ios_runtime.swift_integer_arena + u64(page) + 432)
	for i, flag in [u32(0), 0xe8770001, 0x96600001, 0x42270001, 0x9d250001]! { write32(comparable + 36 + u64(i * 8), flag) }
	for i, target in [u64(unsafe { voidptr(swift_collection_less) }), u64(unsafe { voidptr(swift_collection_less_equal) }), u64(unsafe { voidptr(swift_collection_greater_equal) }), u64(unsafe { voidptr(swift_collection_greater) })]! { unsafe { *(&u64(data + 936 + u64(i * 8))) = target } }
	unsafe { *(&u64(data + 920)) = data + 880; *(&u64(data + 928)) = ios_runtime.swift_integer_arena + u64(page) + 296 }
	swift_protocol_relative(data + 880, comparable); swift_protocol_relative(data + 884, ios_runtime.swift_integer_arena + u64(page) + 160); swift_protocol_relative(data + 888, data + 920)
	int_type := ios_runtime.swift_integer_arena + u64(page) + 16
	unsafe {
		*(&u64(data + 1016)) = data + 1600; *(&u64(data + 1024)) = 0x200; *(&u64(data + 1032)) = data + 224
		*(&u64(data + 1040)) = int_type; *(&u64(data + 1048)) = data + 920; *(&u64(data + 1056)) = u64(8) << 32
		*(&u64(data + 1080)) = data + 1696; *(&u64(data + 1088)) = 0x200; *(&u64(data + 1096)) = data + 192
		*(&u64(data + 1104)) = data + 1024; *(&u64(data + 1112)) = data + 1200; *(&u64(data + 1120)) = u64(16) << 32
		*(&u64(data + 1504)) = data + 736; *(&u64(data + 1512)) = int_type; *(&u64(data + 1520)) = code + 1600
	}
	swift_collection_vwt(data + 1600, 16, false); swift_collection_vwt(data + 1696, 24, false)
	for i, entry in [data + 96, data + 1408, data + 920, data + 1200, data + 1200, int_type, data + 1024, data + 1024]! { unsafe { *(&u64(data + 1200 + u64(i * 8))) = entry } }
	for i in 0 .. 17 { unsafe { *(&u64(data + 1200 + u64((i + 8) * 8))) = code + u64(i * 64) } }
	swift_collection_sequence_emit(data + 1408, data + 672, int_type, data + 1088, data + 1504, code)
	unsafe { *(&u64(data + 1200 + 120)) = code + 1856; *(&u64(data + 1200 + 128)) = code + 1856;
		*(&u64(data + 1200 + 160)) = code + 1984; *(&u64(data + 1200 + 176)) = code + 2048; *(&u64(data + 1408 + 48)) = code + 1920 }
	for i, offset in [u64(32), 64, 96, 640, 672, 704, 736]! {
		p := data + offset; is_sequence := i in [3, 4]!; is_iterator := i >= 5
		swift_protocol_relative(p, if is_iterator {seq_protocol + 128} else if is_sequence {seq_protocol} else {protocol})
		swift_protocol_relative(p + 4, if i == 0 {ios_runtime.swift_array_arena + u64(page) + 160} else if i in [1, 3]! {data + 160} else if i in [2, 4]! {data + 224} else {data + 192})
		pattern := data + 3456 + u64(i * 48); swift_protocol_relative(p + 8, pattern); write32(p + 12, 0x20000); unsafe { *(&u64(pattern)) = p }
		write32(p + 16, 0x10000 | if is_iterator {u32(3)} else if is_sequence {u32(10)} else {u32(25)})
		swift_protocol_relative(p + 20, code + if is_iterator {u64(1728)} else if is_sequence {u64(1696)} else {u64(1664)})
		swift_protocol_relative(p + 24, code + u64(page * 2) + u64(i * 128))
	}
	for i, text in ['Collection', 'Comparable', 'Index Indices SubSequence', 'ArraySlice', 'IndexingIterator', 'Range']! { offsets := [u64(1888), 1904, 1920, 1952, 1984, 2016]!; C.memcpy(voidptr(data + offsets[i]), text.str, usize(text.len + 1)) }
	for i, text in ['x', '7ElementSTQz', '5IndexSlQz', '5IndexSlQz', '7IndicesSlQz', '7IndicesSlQz', '11SubSequenceSlQz', '11SubSequenceSlQz', '5IndexSlQz', '5IndexSlQz']! { C.memcpy(voidptr(data + 2112 + u64(i * 64)), text.str, usize(text.len + 1)) }
	for i, text in ['', '11SubSequenceSl_7ElementSTQZ', '', '7IndicesSl_7ElementSTQZ', '', '7IndicesSl_11SubSequenceSlQZ', '', '11SubSequenceSl_AASlQZ', '7IndicesSl_5IndexSlQZ', '11SubSequenceSl_5IndexSlQZ']! { C.memcpy(voidptr(data + 2752 + u64(i * 64)), text.str, usize(text.len + 1)) }
	C.__builtin___clear_cache(allocation, voidptr(code + 2080))
	if C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) != 0 || C.mprotect(voidptr(data), page, C.PROT_READ) != 0 { C.munmap(allocation, page * 3); panic('iOS: cannot seal Collection records') }
	ios_runtime.swift_collection_arena = code; return code
}
fn swift_collection_symbol(symbol string) ?u64 {
	offset := match symbol {
		'_$sSayxGSlsMc' {32} '_$ss10ArraySliceVyxGSlsMc' {64} '_$sSnyxGSlsSxRzSZ6StrideRpzrlMc' {96}
		'_$sSlMp' {256} '_$sSlTL' {392} '_$sSlSTTb' {400} '_$sSl5IndexSl_SLTn' {408}
		'_$sSl7IndicesSl_SlTn' {416} '_$sSl11SubSequenceSl_SlTn' {424}
		'_$s5IndexSlTl' {432} '_$s11SubSequenceSlTl' {440} '_$s7IndicesSlTl' {448}
		'_$sSiSLsMc' {880} '_$sSiSLsWP' {920} '_$sSLMp' {800} '_$sSLTL' {828} '_$sSLSQTb' {836}
		else {return none}
	}
	return swift_collection_arena() + u64(C.getpagesize()) + u64(offset)
}
fn swift_collection_stop() {
	page := usize(C.getpagesize())
	for _, base in ios_runtime.swift_collection_metadata { if C.munmap(voidptr(base), page) != 0 { panic('iOS: cannot retire Collection metadata') } }
	unsafe { ios_runtime.swift_collection_metadata.free() }
	if ios_runtime.swift_collection_arena != 0 { if C.munmap(voidptr(ios_runtime.swift_collection_arena), page * 3) != 0 {panic('iOS: cannot retire Collection records')}; ios_runtime.swift_collection_arena = 0 }
}
