// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Swift's generic tuple result has an explicitly indirect Iterator in x0;
// buffer base/count and Sequence metadata/table occupy x1..x4. Self in x20
// is consumed, and the initialized count returns in x0. The returned Iterator
// owns that Self, including when the buffer is empty or fills before exhaustion.
fn swift_sequence_contents_checked(output u64, destination u64, capacity i64,
	metadata u64, table u64, receiver u64) !u64 {
	if output == 0 || receiver == 0 || capacity < 0
		|| (capacity != 0 && destination == 0) {
		return swift_sequence_failure()
	}
	layout := swift_sequence_witnesses_checked(metadata, table)!
	stride := read64(read64(layout.element.metadata - 8) + 72)
	if output & (layout.iterator.alignment - 1) != 0
		|| receiver & (layout.sequence.alignment - 1) != 0
		|| output > ~u64(0) - layout.iterator.size
		|| receiver > ~u64(0) - layout.sequence.size
		|| destination & (layout.element.alignment - 1) != 0
		|| u64(capacity) > (~u64(0) - destination) / stride {
		return swift_sequence_failure()
	}
	// next() initializes an owned Optional<Element>. A .some payload is moved
	// directly into the uninitialized destination; no copy or destroy follows.
	base := u64(C.__builtin_alloca(usize(layout.element.size + layout.element.alignment + 16)))
	optional := (base + layout.element.alignment - 1) & ~(layout.element.alignment - 1)
	tag := unsafe { SwiftSequenceTag(voidptr(layout.element.tag)) }
	take := unsafe { SwiftSequenceCopy(voidptr(layout.element.take)) }
	witness := unsafe { SwiftSequenceWitnessCall(voidptr(swift_sequence_arena() + 64)) }
	// Every fallible check precedes this consuming callback. No registry lock
	// crosses makeIterator, next or an Element value witness.
	witness(layout.make_iterator, metadata, table, receiver, output)
	mut count := u64(0)
	for count < u64(capacity) {
		witness(layout.next, layout.iterator.metadata, layout.iterator_table, output, optional)
		if tag(optional, 1, layout.element.metadata) == 1 { break }
		take(destination + count * stride, optional, layout.element.metadata)
		count++
	}
	return count
}

fn swift_sequence_contents(output u64, destination u64, capacity i64,
	metadata u64, table u64, receiver u64) u64 {
	return swift_sequence_contents_checked(output, destination, capacity, metadata, table, receiver) or { panic(err) }
}
