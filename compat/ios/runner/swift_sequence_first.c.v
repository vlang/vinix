// SPDX-License-Identifier: GPL-2.0-or-later
module main

type SwiftSequenceStoreTag = fn (u64, u32, u32, u64)
type SwiftSequencePredicateCall = fn (u64, u64, u64) SwiftSequenceResult

// predicate/context x0/x1, Sequence metadata/witnesses x2/x3, borrowed self
// x20, indirect Optional result x8; the original owned error returns in x21.
fn swift_sequence_first_checked(predicate u64, context u64, sequence u64,
	table u64, receiver u64, output u64) !u64 {
	if predicate == 0 || receiver == 0 || output == 0 { return swift_sequence_failure() }
	layout := swift_sequence_witnesses_checked(sequence, table)!
	store_address := read64(read64(layout.element.metadata - 8) + 56)
	if store_address == 0 || store_address & 3 != 0 { return swift_sequence_failure() }
	store_tag := unsafe { SwiftSequenceStoreTag(voidptr(store_address)) }
	seq_base := u64(C.__builtin_alloca(usize(layout.sequence.size + layout.sequence.alignment + 16)))
	seq_value := (seq_base + layout.sequence.alignment - 1) & ~(layout.sequence.alignment - 1)
	iter_base := u64(C.__builtin_alloca(usize(layout.iterator.size + layout.iterator.alignment + 16)))
	iter_value := (iter_base + layout.iterator.alignment - 1) & ~(layout.iterator.alignment - 1)
	input_base := u64(C.__builtin_alloca(usize(layout.element.size + layout.element.alignment + 16)))
	input_optional := (input_base + layout.element.alignment - 1) & ~(layout.element.alignment - 1)
	item_base := u64(C.__builtin_alloca(usize(layout.element.size + layout.element.alignment + 16)))
	item := (item_base + layout.element.alignment - 1) & ~(layout.element.alignment - 1)
	copy_sequence := unsafe { SwiftSequenceCopy(voidptr(layout.sequence.copy)) }
	take_input := unsafe { SwiftSequenceCopy(voidptr(layout.element.take)) }
	destroy_input := unsafe { SwiftSequenceDestroy(voidptr(layout.element.destroy)) }
	destroy_iterator := unsafe { SwiftSequenceDestroy(voidptr(layout.iterator.destroy)) }
	input_tag := unsafe { SwiftSequenceTag(voidptr(layout.element.tag)) }
	witness := unsafe { SwiftSequenceWitnessCall(voidptr(swift_sequence_arena() + 64)) }
	call := unsafe { SwiftSequencePredicateCall(voidptr(swift_sequence_arena() + 320)) }
	mut iterator_live := false; mut item_live := false
	defer {
		if item_live { destroy_input(item, layout.element.metadata) }
		if iterator_live { destroy_iterator(iter_value, layout.iterator.metadata) }
	}
	copy_sequence(seq_value, receiver, sequence)
	witness(layout.make_iterator, sequence, table, seq_value, iter_value)
	iterator_live = true
	for {
		witness(layout.next, layout.iterator.metadata, layout.iterator_table, iter_value, input_optional)
		if input_tag(input_optional, 1, layout.element.metadata) == 1 {
			destroy_iterator(iter_value, layout.iterator.metadata); iterator_live = false
			store_tag(output, 1, 1, layout.element.metadata)
			return 0
		}
		take_input(item, input_optional, layout.element.metadata); item_live = true
		observed := call(predicate, context, item)
		if observed.error != 0 { return observed.error }
		if observed.array & 1 != 0 {
			// Native destroys Iterator before constructing the returned Optional.
			destroy_iterator(iter_value, layout.iterator.metadata); iterator_live = false
			take_input(output, item, layout.element.metadata); item_live = false
			store_tag(output, 0, 1, layout.element.metadata)
			return 0
		}
		destroy_input(item, layout.element.metadata); item_live = false
	}
	return 0
}

fn swift_sequence_first(predicate u64, context u64, sequence u64, table u64,
	receiver u64, output u64) u64 {
	return swift_sequence_first_checked(predicate, context, sequence, table, receiver, output) or { panic(err) }
}
