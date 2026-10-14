// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftSetType { element u64 hashable u64 }
struct SwiftSetView {
	base u64
	owner u64
	element u64
	hashable u64
	count u64
	buckets u64
	words u64
	bytes u64
	stride u64
}
type SwiftSetHash = fn (u64, u64, u64, u64, u64) u64
type SwiftSetEqual = fn (u64, u64, u64, u64) bool

// Set's frozen generic arguments are Element and its Hashable conformance.
// Only our complete specializations instantiate these generic witnesses.
fn swift_set_base_checked(metadata u64, iterator bool) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || metadata & 7 != 0 { return swift_sequence_failure() }
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	for base, _ in ios_runtime.swift_set_metadata {
		if metadata == base + if iterator {u64(168)} else {u64(8)} { return base }
	}
	return swift_sequence_failure()
}
fn swift_set_hashable_checked(element u64, hashable u64) ! {
	swift_sequence_value_checked(element)!
	if hashable == 0 || hashable & 7 != 0 { return swift_sequence_failure() }
	equatable := read64(hashable + 8)
	if equatable == 0 || equatable & 7 != 0 { return swift_sequence_failure() }
	for entry in [read64(equatable + 8), read64(hashable + 16), read64(hashable + 24), read64(hashable + 32)]! {
		if entry == 0 || entry & 3 != 0 { return swift_sequence_failure() }
	}
}
fn swift_set_view_checked(metadata u64, receiver u64, iterator bool) !SwiftSetView {
	base := swift_set_base_checked(metadata, iterator)!
	if receiver == 0 || receiver & 7 != 0 { return swift_sequence_failure() }
	owner := read64(receiver)
	return swift_set_owner_view_checked(base, owner, false)
}
fn swift_set_owner_view_checked(base u64, owner u64, deiniting bool) !SwiftSetView {
	// Cocoa variants use high/low pointer tags. Do not interpret ObjC bytes as
	// native hash storage or claim a contiguous layout for them.
	if owner == 0 || owner & 0xf000000000000007 != 0 { return swift_sequence_failure() }
	element := read64(base + 24); hashable := read64(base + 32)
	value := swift_sequence_value_checked(element)!
	stride := read64(read64(element - 8) + 72)
	C.ios_objc_initialize_lock()
	if owner == ios_runtime.swift_empty_set {
		C.ios_objc_initialize_unlock()
		return SwiftSetView{base: base, owner: owner, element: element, hashable: hashable, buckets: 1, words: owner + 56, bytes: 1, stride: stride}
	}
	storage := ios_runtime.swift_heap[owner] or { C.ios_objc_initialize_unlock(); return swift_sequence_failure() }
	C.ios_objc_initialize_unlock()
	if storage.metadata != base + 512 || storage.deiniting != deiniting || read64(owner) != storage.metadata || storage.size < 64 { return swift_sequence_failure() }
	scale := unsafe { *(&u8(owner + 32)) }
	if scale == 0 || scale > 20 { return swift_sequence_failure() }
	buckets := u64(1) << scale; words := (buckets + 63) / 64; bytes := read64(owner + 48)
	tail := (56 + words * 8 + value.alignment - 1) & ~(value.alignment - 1)
	if tail > storage.size || bytes != owner + tail || bytes & (value.alignment - 1) != 0 || buckets > (storage.size - tail) / stride { return swift_sequence_failure() }
	count := read64(owner + 16); capacity := read64(owner + 24)
	if capacity != buckets - buckets / 4 - if buckets == 2 {u64(1)} else {u64(0)} || count > capacity { return swift_sequence_failure() }
	return SwiftSetView{base: base, owner: owner, element: element, hashable: hashable, count: count, buckets: buckets, words: owner + 56, bytes: bytes, stride: stride}
}

fn swift_set_access(_request u64, element u64, hashable u64) SwiftAssociatedMetadata {
	swift_set_hashable_checked(element, hashable) or {panic(err)}
	code := swift_set_arena(); page := usize(C.getpagesize()); data := code + u64(page)
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	for base, pair in ios_runtime.swift_set_metadata { if pair.element == element && pair.hashable == hashable { return SwiftAssociatedMetadata{metadata: base + 8} } }
	allocation := C.mmap(unsafe {nil}, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == voidptr(-1) { panic('iOS: cannot allocate Set metadata') }
	base := u64(allocation)
	unsafe {
		*(&u64(base)) = ios_runtime.swift_array_arena + u64(page) + 64
		*(&u64(base + 8)) = 0x200; *(&u64(base + 16)) = data + 128; *(&u64(base + 24)) = element; *(&u64(base + 32)) = hashable
		*(&u64(base + 160)) = base + 224; *(&u64(base + 168)) = 0x200; *(&u64(base + 176)) = data + 192; *(&u64(base + 184)) = element; *(&u64(base + 192)) = hashable
		*(&u64(base + 320)) = data + 64; *(&u64(base + 328)) = element; *(&u64(base + 336)) = code + 128
		*(&u64(base + 496)) = code + 768; *(&u64(base + 512)) = 0x500; *(&u64(base + 520)) = element
		*(&u64(base + 560)) = code + 832; *(&u64(base + 576)) = 0x400; *(&u64(base + 584)) = base + 168
	}
	for i, entry in [data + 32, base + 320, element, base + 168, code + 64, code + 192, code + 256, code + 320, code + 384, code + 448]! { unsafe { *(&u64(base + 352 + u64(i * 8))) = entry } }
	for i, entry in [u64(unsafe {voidptr(swift_set_buffer_copy)}), u64(unsafe {voidptr(swift_array_destroy)}), u64(unsafe {voidptr(swift_set_iterator_copy)}),
		u64(unsafe {voidptr(swift_set_iterator_assign_copy)}), u64(unsafe {voidptr(swift_set_iterator_take)}), u64(unsafe {voidptr(swift_set_iterator_assign_take)}),
		u64(unsafe {voidptr(swift_set_iterator_tag)}), u64(unsafe {voidptr(swift_set_iterator_store)})]! { unsafe { *(&u64(base + 224 + u64(i * 8))) = entry } }
	unsafe { *(&u64(base + 288)) = 40; *(&u64(base + 296)) = 40 }
	write32(base + 304, 0x30007); write32(base + 308, 126)
	if C.mprotect(allocation, page, C.PROT_READ) != 0 { C.munmap(allocation, page); panic('iOS: cannot seal Set metadata') }
	ios_runtime.swift_set_metadata[base] = SwiftSetType{element: element, hashable: hashable}
	return SwiftAssociatedMetadata{metadata: base + 8}
}
fn swift_set_iterator_access(request u64, element u64, hashable u64) SwiftAssociatedMetadata {
	return SwiftAssociatedMetadata{metadata: swift_set_access(request, element, hashable).metadata + 160}
}
fn swift_set_table_checked(metadata u64, iterator bool) !u64 {
	return swift_set_base_checked(metadata, iterator)! + if iterator {u64(320)} else {u64(352)}
}
fn swift_set_instantiate(table u64, metadata u64, _arguments u64) { C.memcpy(voidptr(table), voidptr(swift_set_table_checked(metadata, false) or {panic(err)}), 80) }
fn swift_set_iterator_instantiate(table u64, metadata u64, _arguments u64) { C.memcpy(voidptr(table), voidptr(swift_set_table_checked(metadata, true) or {panic(err)}), 24) }

fn swift_set_minimum_capacity(capacity i64, element u64, hashable u64) u64 {
	metadata := swift_set_access(0, element, hashable).metadata; base := metadata - 8
	if capacity < 0 || capacity > 786432 { panic('iOS: invalid Set capacity') }
	if capacity == 0 { return ios_runtime.swift_empty_set }
	value := swift_sequence_value_checked(element) or {panic(err)}; stride := read64(read64(element - 8) + 72)
	mut scale := u8(1); mut buckets := u64(2)
	for u64(capacity) > buckets - buckets / 4 - if buckets == 2 {u64(1)} else {u64(0)} { scale++; buckets *= 2 }
	words := (buckets + 63) / 64; tail := (56 + words * 8 + value.alignment - 1) & ~(value.alignment - 1)
	if buckets > (~u64(0) - tail) / stride { panic('iOS: Set storage size overflow') }
	size := tail + buckets * stride; mask := if value.alignment > 8 {value.alignment - 1} else {u64(7)}
	owner := swift_heap_allocate(base + 512, size, mask)
	C.memset(voidptr(owner + 16), 0, usize(size - 16))
	unsafe {
		*(&u64(owner + 24)) = buckets - buckets / 4 - if buckets == 2 {u64(1)} else {u64(0)}
		*(&u8(owner + 32)) = scale; *(&u64(owner + 40)) = if swift_hasher_deterministic() {u64(0)} else {owner}
		*(&u64(owner + 48)) = owner + tail
		if buckets < 64 { *(&u64(owner + 56)) = ~((u64(1) << buckets) - 1) }
	}
	return owner
}
fn swift_set_storage_destroy(owner u64) {
	C.ios_objc_initialize_lock(); storage := ios_runtime.swift_heap[owner] or {panic('iOS: unregistered Set destruction')}; C.ios_objc_initialize_unlock()
	base := storage.metadata - 512
	// Destructor runs after ARC marks the owner deinitializing. Its registered
	// allocation bounds still protect the typed tail; no new owner is published.
	view := swift_set_owner_view_checked(base, owner, true) or {panic(err)}
	value := swift_sequence_value_checked(view.element) or {panic(err)}; destroy := unsafe {SwiftSequenceDestroy(voidptr(value.destroy))}
	mut count := u64(0)
	for bucket in u64(0) .. view.buckets { if read64(view.words + bucket / 64 * 8) & (u64(1) << (bucket & 63)) != 0 { destroy(view.bytes + bucket * view.stride, view.element); count++ } }
	if count != view.count { panic('iOS: inconsistent Set occupancy at destruction') }
	swift_heap_deallocate(owner, storage.size, storage.mask)
}

// The native iterator owns the storage, bitmap pointer/mask and its remaining
// current word. ValueBuffer copies share their separately owned 40-byte box.
fn swift_set_buffer_copy(destination u64, source u64, _metadata u64) u64 {
	box := read64(source); swift_retain(box); unsafe { *(&u64(destination)) = box }; return box + 16
}
fn swift_set_box_destroy(owner u64) { swift_bridge_release(read64(owner + 16)); swift_heap_deallocate(owner, 56, 7) }
fn swift_set_iterator_copy(destination u64, source u64, _metadata u64) u64 { swift_bridge_retain(read64(source)); C.memmove(voidptr(destination), voidptr(source), 40); return destination }
fn swift_set_iterator_assign_copy(destination u64, source u64, metadata u64) u64 { previous := read64(destination); swift_set_iterator_copy(destination, source, metadata); swift_bridge_release(previous); return destination }
fn swift_set_iterator_take(destination u64, source u64, _metadata u64) u64 { C.memmove(voidptr(destination), voidptr(source), 40); return destination }
fn swift_set_iterator_assign_take(destination u64, source u64, metadata u64) u64 { previous := read64(destination); swift_set_iterator_take(destination, source, metadata); swift_bridge_release(previous); return destination }
fn swift_set_iterator_tag(value u64, empty_cases u32, _metadata u64) u32 {
	if empty_cases == 0 { return 0 }
	if empty_cases > 126 && unsafe { *(&u8(value + 40)) } != 0 { return unsafe { *(&u32(value)) } + 127 }
	owner := read64(value); spare := u32(((owner >> 60) & 7) << 3 | (owner & 7)) * 2 + u32(owner >> 63)
	return if spare < 2 {u32(0)} else {u32(128) - spare}
}
fn swift_set_iterator_store(value u64, which_case u32, empty_cases u32, _metadata u64) {
	if empty_cases > 126 { unsafe { *(&u8(value + 40)) = if which_case > 126 {u8(1)} else {u8(0)} } }
	if which_case == 0 { return }
	C.memset(voidptr(value), 0, 40)
	spare := u64(128 - which_case)
	unsafe { *(&u64(value)) = if which_case > 126 {u64(which_case - 127)} else {((spare >> 1) & 7) | (((spare >> 4) & 7) << 60) | ((spare & 1) << 63)} }
}
fn swift_set_make(metadata u64, _table u64, output u64, receiver u64) {
	view := swift_set_view_checked(metadata, receiver, false) or {panic(err)}
	if output == 0 || output & 7 != 0 { panic('iOS: invalid Set iterator result') }
	unsafe { *(&u64(output)) = view.owner; *(&u64(output + 8)) = view.words; *(&u64(output + 16)) = view.buckets - 1; *(&u64(output + 24)) = 0; *(&u64(output + 32)) = read64(view.words) & if view.buckets < 64 {(u64(1) << view.buckets) - 1} else {~u64(0)} }
}
fn swift_set_next_checked(metadata u64, output u64, receiver u64) ! {
	view := swift_set_view_checked(metadata, receiver, true)!
	value := swift_sequence_value_checked(view.element)!
	if output == 0 || output & (value.alignment - 1) != 0 || read64(receiver + 8) != view.words || read64(receiver + 16) != view.buckets - 1 { return swift_sequence_failure() }
	mut index := read64(receiver + 24); mut word := read64(receiver + 32); words := (view.buckets + 63) / 64
	if index >= words { return swift_sequence_failure() }
	store := unsafe {SwiftArraySequenceStore(voidptr(read64(read64(view.element - 8) + 56)))}
	for word == 0 && index + 1 < words { index++; word = read64(view.words + index * 8) }
	unsafe { *(&u64(receiver + 24)) = index; *(&u64(receiver + 32)) = word }
	if word == 0 { store(output, 1, 1, view.element); return }
	mut bit := u64(0); for word & (u64(1) << bit) == 0 { bit++ }
	bucket := index * 64 + bit
	if bucket >= view.buckets { return swift_sequence_failure() }
	copy_value := unsafe {SwiftSequenceCopy(voidptr(value.copy))}; copy_value(output, view.bytes + bucket * view.stride, view.element); store(output, 0, 1, view.element)
	unsafe { *(&u64(receiver + 32)) = word & (word - 1) }
}
fn swift_set_next(metadata u64, _table u64, output u64, receiver u64) { swift_set_next_checked(metadata, output, receiver) or {panic(err)} }
fn swift_set_count(metadata u64, _table u64, receiver u64) u64 { return (swift_set_view_checked(metadata, receiver, false) or {panic(err)}).count }
fn swift_set_contains(member u64, metadata u64, _table u64, receiver u64) u64 {
	view := swift_set_view_checked(metadata, receiver, false) or {panic(err)}
	if view.count == 0 { return 0 }
	value := swift_sequence_value_checked(view.element) or {panic(err)}
	if member == 0 || member & (value.alignment - 1) != 0 { panic('iOS: invalid Set member') }
	hash := unsafe {SwiftSetHash(voidptr(ios_runtime.swift_set_arena + 896))}
	equatable := read64(view.hashable + 8); equals := unsafe {SwiftSetEqual(voidptr(read64(equatable + 8)))}
	swift_bridge_retain(view.owner); defer {swift_bridge_release(view.owner)}
	mut bucket := hash(read64(view.hashable + 32), read64(view.owner + 40), view.element, view.hashable, member) & (view.buckets - 1)
	for _ in u64(0) .. view.buckets {
		if read64(view.words + bucket / 64 * 8) & (u64(1) << (bucket & 63)) == 0 { return 0 }
		if equals(view.bytes + bucket * view.stride, member, view.element, equatable) { return 1 }
		bucket = (bucket + 1) & (view.buckets - 1)
	}
	panic('iOS: Set hash table has no empty bucket')
}
fn swift_set_contiguous(metadata u64, _table u64, receiver u64) u64 {
	view := swift_set_view_checked(metadata, receiver, false) or {panic(err)}; allocation := swift_array_allocate(i64(view.count), view.element)
	swift_set_copy_elements(view, allocation.bytes); swift_bridge_release(view.owner); return allocation.owner
}
fn swift_set_copy_elements(view SwiftSetView, destination u64) {
	value := swift_sequence_value_checked(view.element) or {panic(err)}; copy_value := unsafe {SwiftSequenceCopy(voidptr(value.copy))}; mut count := u64(0)
	for bucket in u64(0) .. view.buckets { if read64(view.words + bucket / 64 * 8) & (u64(1) << (bucket & 63)) != 0 { if count == view.count {panic('iOS: inconsistent Set occupancy')}; copy_value(destination + count * view.stride, view.bytes + bucket * view.stride, view.element); count++ } }
	if count != view.count { panic('iOS: inconsistent Set element count') }
}
fn swift_set_contents(output u64, destination u64, capacity i64, metadata u64, table u64, receiver u64) u64 {
	view := swift_set_view_checked(metadata, receiver, false) or {panic(err)}; value := swift_sequence_value_checked(view.element) or {panic(err)}
	if capacity < 0 || u64(capacity) < view.count || output == 0 || output & 7 != 0 || (view.count != 0 && destination == 0) || destination & (value.alignment - 1) != 0 || view.count > (~u64(0) - destination) / view.stride { panic('iOS: invalid Set copy destination') }
	swift_set_copy_elements(view, destination); swift_set_make(metadata, table, output, receiver)
	unsafe { *(&u64(output + 24)) = (view.buckets + 63) / 64 - 1; *(&u64(output + 32)) = 0 }; return view.count
}
fn swift_set_storage(_body u64, _context u64, result u64, metadata u64, _table u64, receiver u64, output u64) u64 {
	swift_set_view_checked(metadata, receiver, false) or {panic(err)}; swift_sequence_value_checked(result) or {panic(err)}
	store := unsafe {SwiftArraySequenceStore(voidptr(read64(read64(result - 8) + 56)))}; store(output, 1, 1, result); return 0
}

fn swift_set_bridge(address u64, ops []u32, target u64) {
	mut count := ops.len; for i, op in ops {write32(address + u64(i * 4), op)}
	if count & 1 != 0 {write32(address + u64(count * 4), 0xd503201f); count++}
	write32(address + u64(count * 4), 0x58000050); write32(address + u64(count * 4 + 4), 0xd61f0200)
	unsafe { *(&u64(address + u64(count * 4 + 8))) = target }
}

// Generic SetAlgebra.init(Sequence) dispatches through caller witness slot 20.
// Native arm64e authenticates this entry; Vinix uses ordinary ARM64 pointers.
// Preserve x0-x4, x7, indirect result x8, Swift context/error x20/x21 and the
// original stack/LR. Forward the selected slot address in x5, target in x6,
// then tail-branch: the witness consumes the source and initializes Self.
fn swift_set_algebra_emit(entry u64) {
	for i, op in [u32(0xaa0403e5), 0xf84a0ca6, 0xd61f00c0]! {
		write32(entry + u64(i * 4), op)
	}
}
fn swift_set_arena() u64 {
	swift_array_sequence_arena(); swift_integer_metadata()
	C.ios_objc_initialize_lock(); defer {C.ios_objc_initialize_unlock()}
	if ios_runtime.swift_set_arena != 0 {return ios_runtime.swift_set_arena}
	page := usize(C.getpagesize()); allocation := C.mmap(unsafe {nil}, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == voidptr(-1) {panic('iOS: cannot allocate Set records')}
	base := u64(allocation); data := base + u64(page); sequence := ios_runtime.swift_array_sequence_arena + u64(page)
	swift_set_bridge(base, [], u64(unsafe {voidptr(swift_set_access)}))
	for i, target in [u64(unsafe {voidptr(swift_set_make)}), u64(unsafe {voidptr(swift_set_next)})]! {swift_set_bridge(base + u64(64 + i * 64), [u32(0xaa0803e2), 0xaa1403e3], target)}
	swift_set_bridge(base + 192, [u32(0xaa1403e2)], u64(unsafe {voidptr(swift_set_count)}))
	swift_set_bridge(base + 256, [u32(0xaa1403e3)], u64(unsafe {voidptr(swift_set_contains)}))
	swift_set_bridge(base + 320, [u32(0xaa1403e2)], u64(unsafe {voidptr(swift_set_contiguous)}))
	swift_set_bridge(base + 384, [u32(0xaa1403e5)], u64(unsafe {voidptr(swift_set_contents)}))
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e5, 0xaa0803e6, 0x580000b0, 0xd63f0200, 0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! {write32(base + 448 + u64(i * 4), op)}
	unsafe { *(&u64(base + 480)) = u64(voidptr(swift_set_storage)) }
	swift_set_bridge(base + 512, [], u64(unsafe {voidptr(swift_set_iterator_access)}))
	swift_set_bridge(base + 576, [], u64(unsafe {voidptr(swift_set_minimum_capacity)}))
	swift_set_bridge(base + 640, [], u64(unsafe {voidptr(swift_set_instantiate)})); swift_set_bridge(base + 704, [], u64(unsafe {voidptr(swift_set_iterator_instantiate)}))
	swift_set_bridge(base + 768, [u32(0xaa1403e0)], u64(unsafe {voidptr(swift_set_storage_destroy)})); swift_set_bridge(base + 832, [u32(0xaa1403e0)], u64(unsafe {voidptr(swift_set_box_destroy)}))
	// C -> borrowed Swift Hashable witness; preserve x20 and all callee saves.
	for i, op in [u32(0xa9be7bfd),0xa90153f3,0xaa0003f0,0xaa0103e0,0xaa0203e1,0xaa0303e2,0xaa0403f4,0xd63f0200,0xa94153f3,0xa8c27bfd,0xd65f03c0]! {write32(base + 896 + u64(i * 4),op)}
	swift_set_algebra_emit(base + 960)
	module_descriptor := ios_runtime.swift_array_arena + u64(page) + 224
	for i, offset in [u64(128),192]! {
		d := data + offset; write32(d,0xd1); swift_protocol_relative(d + 4,module_descriptor); swift_protocol_relative(d + 8,data + u64(400 + i * 16)); swift_protocol_relative(d + 12,base + if i == 0 {u64(0)} else {u64(512)})
		write32(d + 20,1);write32(d + 24,4)
		// One key type parameter and one key Hashable requirement. Reflection
		// and generic metadata discovery remain unsupported for these records.
		write32(d + 36,0x10001);write32(d + 40,2);write32(d + 44,0x80)
		write32(d + 48,0x80);swift_protocol_relative(d + 52,data + 432);swift_protocol_relative(d + 56,ios_runtime.swift_integer_arena + u64(page) + 352)
	}
	C.memcpy(voidptr(data + 400),c'Set',4);C.memcpy(voidptr(data + 416),c'Iterator',9);C.memcpy(voidptr(data + 432),c'x',2)
	for i, offset in [u64(32),64]! {
		d := data + offset;swift_protocol_relative(d,sequence + if i == 0 {u64(256)} else {u64(384)});swift_protocol_relative(d + 4,data + if i == 0 {u64(128)} else {u64(192)})
		swift_protocol_relative(d + 8,data + u64(512 + i * 128));write32(d + 12,0x20000);write32(d + 16,if i == 0 {u32(0x1000a)} else {u32(0x10003)})
		swift_protocol_relative(d + 20,base + u64(640 + i * 64));swift_protocol_relative(d + 24,base + u64(page * 2) + u64(i * 128))
		unsafe { *(&u64(data + u64(512 + i * 128))) = d }
	}
	// Native singleton header/bitmap. The one sentinel bucket is unoccupied;
	// all padding bits are occupied, matching the installed library.
	unsafe { *(&u64(data + 1024)) = data + 1152; *(&u64(data + 1032)) = 0x80000004ffffffff; *(&u64(data + 1072)) = 1; *(&u64(data + 1080)) = ~u64(1); *(&u64(data + 1152)) = 0x500 }
	C.__builtin___clear_cache(allocation,voidptr(base + 972))
	if C.mprotect(allocation,page,C.PROT_READ | C.PROT_EXEC)!=0 || C.mprotect(voidptr(data),page,C.PROT_READ)!=0 {C.munmap(allocation,page * 3);panic('iOS: cannot seal Set records')}
	ios_runtime.swift_set_arena = base;ios_runtime.swift_empty_set = data + 1024;return base
}
fn swift_set_symbol(symbol string) ?u64 {
	return match symbol {
		'_$ss10SetAlgebraPyxqd__ncSTRd__7ElementQyd__ACRtzlufCTj' {swift_set_arena() + 960}
		'_$sShyxGSTsMc' {swift_set_arena() + u64(C.getpagesize()) + 32}
		'_$sSh8IteratorVyx_GStsMc' {swift_set_arena() + u64(C.getpagesize()) + 64}
		'_$sShMa' {swift_set_arena()}
		'_$sShMn' {swift_set_arena() + u64(C.getpagesize()) + 128}
		'_$sSh8IteratorVMa' {swift_set_arena() + 512}
		'_$sSh8IteratorVMn' {swift_set_arena() + u64(C.getpagesize()) + 192}
		'_$sSh15minimumCapacityShyxGSi_tcfC' {swift_set_arena() + 576}
		'__swiftEmptySetSingleton' {swift_set_arena() + u64(C.getpagesize()) + 1024}
		else {none}
	}
}
fn swift_set_stop() {
	page := usize(C.getpagesize())
	for base, _ in ios_runtime.swift_set_metadata {if C.munmap(voidptr(base),page)!=0 {panic('iOS: cannot retire Set specialization')}}
	unsafe {ios_runtime.swift_set_metadata.free()}
	if ios_runtime.swift_set_arena != 0 {if C.munmap(voidptr(ios_runtime.swift_set_arena),page * 3)!=0 {panic('iOS: cannot retire Set records')};ios_runtime.swift_set_arena = 0;ios_runtime.swift_empty_set = 0}
}
