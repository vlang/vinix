// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftCollectionFirstLayout {
	self_value SwiftSequenceValue
	index SwiftSequenceValue
	element SwiftSequenceValue
	equatable u64
	equal u64
	start u64
	end u64
	read u64
	store u64
}
type SwiftCollectionFirstCall = fn (u64, u64, u64, u64, u64, u64, u64) SwiftCollectionYield

// Collection's complete direct witnesses provide Sequence at 1, Index:
// Comparable at 2, Index metadata at 5, start/end at 8/9 and _read at 10.
// Sequence.Element is word 2; Comparable.Equatable is word 1. Tagged or
// incomplete associated witnesses must be instantiated before calling us.
fn swift_collection_first_layout_checked(metadata u64, table u64) !SwiftCollectionFirstLayout {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| metadata < 8 || metadata & 7 != 0 || table == 0 || table & 7 != 0 {
		return swift_sequence_failure()
	}
	sequence := C.ios_load_pointer(unsafe { &u64(table + 8) })
	comparable := C.ios_load_pointer(unsafe { &u64(table + 16) })
	index := C.ios_load_pointer(unsafe { &u64(table + 40) })
	if sequence == 0 || sequence & 7 != 0 || comparable == 0 || comparable & 7 != 0
		|| index < 8 || index & 7 != 0 { return swift_sequence_failure() }
	element := C.ios_load_pointer(unsafe { &u64(sequence + 16) })
	equatable := C.ios_load_pointer(unsafe { &u64(comparable + 8) })
	if element < 8 || element & 7 != 0 || equatable == 0 || equatable & 7 != 0 {
		return swift_sequence_failure()
	}
	self_value := swift_sequence_value_checked(metadata)!
	index_value := swift_sequence_value_checked(index)!
	element_value := swift_sequence_value_checked(element)!
	equal := read64(equatable + 8)
	start := read64(table + 64); end := read64(table + 72); read := read64(table + 80)
	store := read64(read64(element - 8) + 56)
	for entry in [equal, start, end, read, store]! {
		if entry == 0 || entry & 3 != 0 { return swift_sequence_failure() }
	}
	return SwiftCollectionFirstLayout{self_value: self_value, index: index_value,
		element: element_value, equatable: equatable, equal: equal,
		start: start, end: end, read: read, store: store}
}

// ARM64 getter: Self metadata x0, Collection table x1, borrowed Self x20,
// indirect Optional<Element> x8. No iterator or consuming Self copy is used.
fn swift_collection_first_checked(metadata u64, table u64, receiver u64, output u64) ! {
	layout := swift_collection_first_layout_checked(metadata, table)!
	if receiver == 0 || receiver & (layout.self_value.alignment - 1) != 0
		|| output == 0 || output & (layout.element.alignment - 1) != 0 {
		return swift_sequence_failure()
	}
	start_base := u64(C.__builtin_alloca(usize(layout.index.size + layout.index.alignment + 16)))
	start := (start_base + layout.index.alignment - 1) & ~(layout.index.alignment - 1)
	end_base := u64(C.__builtin_alloca(usize(layout.index.size + layout.index.alignment + 16)))
	end := (end_base + layout.index.alignment - 1) & ~(layout.index.alignment - 1)
	buffer_base := u64(C.__builtin_alloca(48)); buffer := (buffer_base + 15) & ~u64(15)
	call := unsafe { SwiftCollectionFirstCall(voidptr(swift_collection_arena() + 2176)) }
	destroy := unsafe { SwiftSequenceDestroy(voidptr(layout.index.destroy)) }
	store := unsafe { SwiftArraySequenceStore(voidptr(layout.store)) }
	mut start_live := false; mut end_live := false
	defer {
		if end_live { destroy(end, layout.index.metadata) }
		if start_live { destroy(start, layout.index.metadata) }
	}
	call(layout.start, metadata, table, 0, 0, receiver, start); start_live = true
	call(layout.end, metadata, table, 0, 0, receiver, end); end_live = true
	equal := call(layout.equal, start, end, layout.index.metadata, layout.equatable,
		layout.index.metadata, 0).continuation & 255 != 0
	// The native getter destroys endIndex before branching on equality.
	destroy(end, layout.index.metadata); end_live = false
	if equal {
		destroy(start, layout.index.metadata); start_live = false
		store(output, 1, 1, layout.element.metadata); return
	}
	yielded := call(layout.read, buffer, start, metadata, table, receiver, 0)
	if yielded.continuation == 0 || yielded.continuation & 3 != 0 {
		return swift_sequence_failure()
	}
	if yielded.address == 0 || yielded.address & (layout.element.alignment - 1) != 0 {
		call(yielded.continuation, buffer, 1, 0, 0, 0, 0)
		return swift_sequence_failure()
	}
	copy_value := unsafe { SwiftSequenceCopy(voidptr(layout.element.copy)) }
	copy_value(output, yielded.address, layout.element.metadata)
	call(yielded.continuation, buffer, 0, 0, 0, 0, 0)
	destroy(start, layout.index.metadata); start_live = false
	store(output, 0, 1, layout.element.metadata)
}
fn swift_collection_first(metadata u64, table u64, receiver u64, output u64) {
	swift_collection_first_checked(metadata, table, receiver, output) or { panic(err) }
}
fn swift_collection_first_emit(code u64) {
	swift_collection_bridge(code + 2112, u64(unsafe { voidptr(swift_collection_first) }),
		[u32(0xaa1403e2), 0xaa0803e3]!, 2)
	// C -> Swift requirement/continuation: four arguments, Self x20, result
	// x8. Coroutine results remain in x0/x1; restore the C caller's context.
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0xaa0003f0,
		0xaa0503f4, 0xaa0603e8, 0xaa0103e0, 0xaa0203e1, 0xaa0303e2,
		0xaa0403e3, 0xd63f0200, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! {
		write32(code + 2176 + u64(i * 4), op)
	}
}
