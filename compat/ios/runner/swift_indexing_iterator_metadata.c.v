// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Share the existing Collection/Sequence specializations. Elements and its
// Collection witness are both generic key arguments; a foreign witness must
// never be treated as one of our complete, directly indexed tables.
fn swift_indexing_iterator_metadata_checked(_request u64, elements u64, collection u64) !SwiftAssociatedMetadata {
	if elements == 0 || collection == 0 || (elements | collection) & 7 != 0 {
		return swift_sequence_failure()
	}
	kind := swift_collection_kind_checked(elements, false)!
	table := swift_collection_table_checked(elements)!
	if collection != table { return swift_sequence_failure() }
	sequence := if kind == 0 {
		read64(table + 8)
	} else {
		swift_collection_sequence_checked(elements)!
	}
	return SwiftAssociatedMetadata{ metadata: read64(sequence + 24) }
}

fn swift_indexing_iterator_metadata_access(request u64, elements u64, collection u64) SwiftAssociatedMetadata {
	return swift_indexing_iterator_metadata_checked(request, elements, collection) or { panic(err) }
}

fn swift_indexing_iterator_metadata_instantiate_checked(descriptor u64, arguments u64, pattern u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| ios_runtime.swift_collection_arena == 0 || arguments == 0 || arguments & 7 != 0
		|| arguments > ~u64(0) - 15 {
		return swift_sequence_failure()
	}
	data := ios_runtime.swift_collection_arena + u64(C.getpagesize())
	if descriptor != data + 3840 || pattern != data + 3920 { return swift_sequence_failure() }
	return swift_indexing_iterator_metadata_checked(0, read64(arguments), read64(arguments + 8))!.metadata
}

fn swift_indexing_iterator_metadata_instantiate(descriptor u64, arguments u64, pattern u64) u64 {
	return swift_indexing_iterator_metadata_instantiate_checked(descriptor, arguments, pattern) or { panic(err) }
}

fn swift_indexing_iterator_table_checked(metadata u64) !u64 {
	if table := swift_array_iterator_table_checked(metadata) { return table }
	return swift_collection_iterator_checked(metadata)
}

fn swift_indexing_iterator_instantiate(table u64, metadata u64, _arguments u64) {
	canonical := swift_indexing_iterator_table_checked(metadata) or { panic(err) }
	C.memcpy(voidptr(table), voidptr(canonical), 24)
}

// Called while the Collection arena is writable, before publishing any of its
// tables. Fits within a 4 KiB data page and uses its existing writable cache page.
fn swift_indexing_iterator_metadata_emit(code u64, data u64) {
	for i, target in [
		u64(unsafe { voidptr(swift_indexing_iterator_metadata_access) }),
		u64(unsafe { voidptr(swift_indexing_iterator_metadata_instantiate) }),
		u64(unsafe { voidptr(swift_indexing_iterator_instantiate) }),
	]! {
		swift_collection_bridge(code + 2240 + u64(i * 32), target, [u32(0), 0]!, 0)
	}
	descriptor := data + 3840
	write32(descriptor, 0xd1)
	swift_protocol_relative(descriptor + 4, ios_runtime.swift_array_arena + u64(C.getpagesize()) + 224)
	swift_protocol_relative(descriptor + 8, data + 1984)
	swift_protocol_relative(descriptor + 12, code + 2240)
	write32(descriptor + 20, 2)
	write32(descriptor + 24, 4)
	swift_protocol_relative(descriptor + 28, code + u64(C.getpagesize()) * 2 + 896)
	swift_protocol_relative(descriptor + 32, data + 3920)
	write32(descriptor + 36, 0x10001) // One parameter, one protocol requirement.
	write32(descriptor + 40, 2) // Elements and Elements: Collection.
	write32(descriptor + 44, 0x80)
	write32(descriptor + 48, 0x80)
	swift_protocol_relative(descriptor + 52, data + 2112) // x
	swift_protocol_relative(descriptor + 56, data + 256) // Collection
	swift_protocol_relative(data + 3920, code + 2272)
	write32(data + 3928, 0x40000000) // Struct; factory supplies complete witnesses.
	// One canonical IteratorProtocol conformance for every supported Elements.
	swift_protocol_relative(data + 3968, ios_runtime.swift_array_sequence_arena + u64(C.getpagesize()) + 384)
	swift_protocol_relative(data + 3972, descriptor)
	swift_protocol_relative(data + 3976, data + 4000)
	write32(data + 3980, 0x20000)
	write32(data + 3984, 0x10003)
	swift_protocol_relative(data + 3988, code + 2304)
	swift_protocol_relative(data + 3992, code + u64(C.getpagesize()) * 2 + 1024)
	unsafe { *(&u64(data + 4000)) = data + 3968 }
	ios_runtime.swift_indexing_iterator_conformance_descriptor = data + 3968
}

fn swift_indexing_iterator_metadata_symbol(symbol string) ?u64 {
	if symbol !in ['_$ss16IndexingIteratorVMn', '_$ss16IndexingIteratorVMa',
		'_$ss16IndexingIteratorVyxGStsMc']!
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return none
	}
	base := swift_collection_arena()
	return match symbol {
		'_$ss16IndexingIteratorVMa' { base + 2240 }
		'_$ss16IndexingIteratorVMn' { base + u64(C.getpagesize()) + 3840 }
		else { base + u64(C.getpagesize()) + 3968 }
	}
}
