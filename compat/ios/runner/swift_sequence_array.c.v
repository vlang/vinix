// SPDX-License-Identifier: GPL-2.0-or-later
module main

type SwiftSequenceArrayWitness = fn (u64, u64, u64, u64, u64) u64

// Borrowed indirect Sequence x0, Self metadata x1, Sequence table x2; the
// result's single owned ContiguousArray storage word returns in x0. Source
// copying precedes consuming makeIterator. No registry lock crosses callbacks.
fn swift_sequence_array_checked(receiver u64, metadata u64, table u64) !u64 {
	if receiver == 0 || table > ~u64(0) - 47 { return swift_sequence_failure() }
	witnesses := swift_sequence_witnesses_checked(metadata, table)!
	if receiver & (witnesses.sequence.alignment - 1) != 0
		|| receiver > ~u64(0) - witnesses.sequence.size { return swift_sequence_failure() }
	count_entry := read64(table + 40)
	if count_entry == 0 || count_entry & 3 != 0 { return swift_sequence_failure() }
	layout := SwiftSequenceLayout{sequence: witnesses.sequence, element: witnesses.element,
		iterator: witnesses.iterator, result: witnesses.element, iterator_table: witnesses.iterator_table,
		make_iterator: witnesses.make_iterator, next: witnesses.next, array: swift_array_layout(0, witnesses.element.metadata)!}
	seq_base := u64(C.__builtin_alloca(usize(layout.sequence.size + layout.sequence.alignment + 16)))
	seq_value := (seq_base + layout.sequence.alignment - 1) & ~(layout.sequence.alignment - 1)
	iter_base := u64(C.__builtin_alloca(usize(layout.iterator.size + layout.iterator.alignment + 16)))
	iter_value := (iter_base + layout.iterator.alignment - 1) & ~(layout.iterator.alignment - 1)
	item_base := u64(C.__builtin_alloca(usize(layout.element.size + layout.element.alignment + 16)))
	item := (item_base + layout.element.alignment - 1) & ~(layout.element.alignment - 1)
	copy_sequence := unsafe { SwiftSequenceCopy(voidptr(layout.sequence.copy)) }
	take := unsafe { SwiftSequenceCopy(voidptr(layout.element.take)) }
	destroy_item := unsafe { SwiftSequenceDestroy(voidptr(layout.element.destroy)) }
	destroy_iterator := unsafe { SwiftSequenceDestroy(voidptr(layout.iterator.destroy)) }
	tag := unsafe { SwiftSequenceTag(voidptr(layout.element.tag)) }
	adapter := swift_sequence_arena() + 64
	count_call := unsafe { SwiftSequenceArrayWitness(voidptr(adapter)) }
	witness := unsafe { SwiftSequenceWitnessCall(voidptr(adapter)) }
	hint := i64(count_call(count_entry, metadata, table, receiver, 0))
	if hint < 0 || u64(hint) > (1048576 - layout.array.storage.tail) / layout.array.storage.stride { return swift_sequence_failure() }
	mut owner := u64(0);mut count := u64(0);mut capacity := u64(hint)
	mut iterator_live := false;mut item_live := false
	defer {
		if item_live { destroy_item(item, layout.element.metadata) }
		if iterator_live { destroy_iterator(iter_value, layout.iterator.metadata) }
		if owner != 0 { swift_release(owner) }
	}
	if capacity != 0 { owner = swift_sequence_grow(0, 0, capacity, layout)! }
	copy_sequence(seq_value, receiver, metadata)
	witness(layout.make_iterator, metadata, table, seq_value, iter_value);iterator_live = true
	for {
		witness(layout.next, layout.iterator.metadata, layout.iterator_table, iter_value, item)
		if tag(item, 1, layout.element.metadata) == 1 { break }
		item_live = true
		if count == capacity {
			capacity = if capacity == 0 { u64(1) } else { capacity * 2 }
			owner = swift_sequence_grow(owner, count, capacity, layout)!
		}
		take(owner + layout.array.storage.tail + count * layout.array.storage.stride, item, layout.element.metadata)
		item_live = false;count++;unsafe { *(&u64(owner + 16)) = count }
	}
	if count < u64(hint) { return swift_sequence_failure() }
	result := if owner == 0 { swift_array_empty() } else { owner };owner = 0
	return result
}

fn swift_sequence_array(receiver u64, metadata u64, table u64) u64 {
	return swift_sequence_array_checked(receiver, metadata, table) or { panic(err) }
}

fn swift_sequence_array_symbol(symbol string) ?u64 {
	if symbol != '_$ss30_copySequenceToContiguousArrayys0dE0Vy7ElementQzGxSTRzlF'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return none }
	return u64(unsafe { voidptr(swift_sequence_array) })
}
