// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftSequenceFailure {}
fn (_ &SwiftSequenceFailure) msg() string { return 'iOS: unsupported Swift Sequence representation' }
fn (_ &SwiftSequenceFailure) code() int { return 1 }
__global swift_sequence_failure_value = SwiftSequenceFailure{}
fn swift_sequence_failure() IError { return unsafe { &swift_sequence_failure_value } }

struct SwiftSequenceValue {
	metadata u64
	size u64
	alignment u64
	copy u64
	take u64
	destroy u64
	tag u64
}
struct SwiftSequenceLayout {
	sequence SwiftSequenceValue
	element SwiftSequenceValue
	iterator SwiftSequenceValue
	result SwiftSequenceValue
	iterator_table u64
	make_iterator u64
	next u64
	array SwiftArrayLayout
}
struct SwiftSequenceWitnesses {
	sequence SwiftSequenceValue
	element SwiftSequenceValue
	iterator SwiftSequenceValue
	iterator_table u64
	make_iterator u64
	next u64
}
struct SwiftSequenceResult {
	array u64
	error u64
}
type SwiftSequenceCopy = fn (u64, u64, u64) u64
type SwiftSequenceDestroy = fn (u64, u64)
type SwiftSequenceTag = fn (u64, u32, u64) u32
type SwiftSequenceWitnessCall = fn (u64, u64, u64, u64, u64)
type SwiftSequenceTransformCall = fn (u64, u64, u64, u64) SwiftSequenceResult

fn swift_sequence_value_checked(metadata u64) !SwiftSequenceValue {
	if metadata < 8 || metadata & 7 != 0 { return swift_sequence_failure() }
	witness := read64(metadata - 8)
	if witness == 0 || witness & 7 != 0 { return swift_sequence_failure() }
	size := read64(witness + 64)
	stride := read64(witness + 72)
	flags := read32(witness + 80)
	alignment := u64(flags & 255) + 1
	copy := read64(witness + 16); take := read64(witness + 32)
	destroy := read64(witness + 8); tag := read64(witness + 48)
	if size > 65536 || size > stride || stride == 0 || stride & (alignment - 1) != 0
		|| alignment & (alignment - 1) != 0 || flags & 0x00400000 != 0
		|| copy == 0 || take == 0 || destroy == 0 || tag == 0
		|| copy & 3 != 0 || take & 3 != 0 || destroy & 3 != 0 || tag & 3 != 0 {
		return swift_sequence_failure()
	}
	return SwiftSequenceValue{ metadata: metadata, size: size, alignment: alignment,
		copy: copy, take: take, destroy: destroy, tag: tag }
}

// Measured Swift 6 Sequence slots: associated Iterator:IteratorProtocol at 1,
// Element metadata at 2, Iterator metadata at 3, makeIterator at 4. Complete
// direct associated witnesses are supported; tagged mangled/accessor entries
// must be instantiated separately, never mistaken for metadata or code.
fn swift_sequence_witnesses_checked(sequence u64, table u64) !SwiftSequenceWitnesses {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| sequence < 8 || sequence & 7 != 0
		|| table == 0 || table & 7 != 0 { return swift_sequence_failure() }
	iterator_table := C.ios_load_pointer(unsafe { &u64(table + 8) })
	element := C.ios_load_pointer(unsafe { &u64(table + 16) })
	iterator := C.ios_load_pointer(unsafe { &u64(table + 24) })
	if iterator_table == 0 || iterator_table & 7 != 0 || element == 0 || element & 7 != 0
		|| iterator == 0 || iterator & 7 != 0
		|| C.ios_load_pointer(unsafe { &u64(iterator_table + 8) }) != element {
		return swift_sequence_failure()
	}
	make_iterator := read64(table + 32); next := read64(iterator_table + 16)
	if make_iterator == 0 || next == 0 || make_iterator & 3 != 0 || next & 3 != 0 { return swift_sequence_failure() }
	return SwiftSequenceWitnesses{ sequence: swift_sequence_value_checked(sequence)!,
		element: swift_sequence_value_checked(element)!, iterator: swift_sequence_value_checked(iterator)!,
		iterator_table: iterator_table, make_iterator: make_iterator, next: next }
}

fn swift_sequence_layout_checked(sequence u64, result u64, table u64) !SwiftSequenceLayout {
	if result < 8 || result & 7 != 0 { return swift_sequence_failure() }
	witnesses := swift_sequence_witnesses_checked(sequence, table)!
	return SwiftSequenceLayout{ sequence: witnesses.sequence, element: witnesses.element,
		iterator: witnesses.iterator, iterator_table: witnesses.iterator_table,
		make_iterator: witnesses.make_iterator, next: witnesses.next,
		result: swift_sequence_value_checked(result)!, array: swift_array_layout(0, result)! }
}

fn swift_sequence_grow(owner u64, count u64, capacity u64, layout SwiftSequenceLayout) !u64 {
	stride := layout.array.storage.stride
	if capacity == 0 || capacity > (1024 * 1024 - layout.array.storage.tail) / stride {
		return swift_sequence_failure()
	}
	allocation := swift_array_allocate(i64(capacity), layout.result.metadata)
	unsafe { *(&u64(allocation.owner + 16)) = 0 }
	if owner != 0 {
		take := unsafe { SwiftSequenceCopy(voidptr(layout.result.take)) }
		for i in u64(0) .. count {
			take(allocation.bytes + i * stride, owner + layout.array.storage.tail + i * stride,
				layout.result.metadata)
			unsafe { *(&u64(allocation.owner + 16)) = i + 1 }
		}
		// All old elements were moved, so releasing the old tail destroys none.
		unsafe { *(&u64(owner + 16)) = 0 }
		swift_release(owner)
	}
	return allocation.owner
}

// ARM64 entry: transform/context x0/x1, Sequence/Result metadata x2/x3,
// Sequence witnesses x4, borrowed indirect self x20; owned Array in x0 and
// thrown error in x21. No registry lock crosses a witness or closure call.
fn swift_compact_map_checked(transform u64, context u64, sequence u64, result u64,
	table u64, receiver u64) !SwiftSequenceResult {
	if transform == 0 || receiver == 0 { return swift_sequence_failure() }
	layout := swift_sequence_layout_checked(sequence, result, table)!
	// Reserve aligned scratch in this frame; no helper returns an alloca view.
	seq_base := u64(C.__builtin_alloca(usize(layout.sequence.size + layout.sequence.alignment + 16)))
	seq_value := (seq_base + layout.sequence.alignment - 1) & ~(layout.sequence.alignment - 1)
	iter_base := u64(C.__builtin_alloca(usize(layout.iterator.size + layout.iterator.alignment + 16)))
	iter_value := (iter_base + layout.iterator.alignment - 1) & ~(layout.iterator.alignment - 1)
	input_base := u64(C.__builtin_alloca(usize(layout.element.size + layout.element.alignment + 16)))
	input_optional := (input_base + layout.element.alignment - 1) & ~(layout.element.alignment - 1)
	item_base := u64(C.__builtin_alloca(usize(layout.element.size + layout.element.alignment + 16)))
	item := (item_base + layout.element.alignment - 1) & ~(layout.element.alignment - 1)
	output_base := u64(C.__builtin_alloca(usize(layout.result.size + layout.result.alignment + 16)))
	output_optional := (output_base + layout.result.alignment - 1) & ~(layout.result.alignment - 1)
	copy_sequence := unsafe { SwiftSequenceCopy(voidptr(layout.sequence.copy)) }
	take_input := unsafe { SwiftSequenceCopy(voidptr(layout.element.take)) }
	take_result := unsafe { SwiftSequenceCopy(voidptr(layout.result.take)) }
	destroy_input := unsafe { SwiftSequenceDestroy(voidptr(layout.element.destroy)) }
	destroy_iterator := unsafe { SwiftSequenceDestroy(voidptr(layout.iterator.destroy)) }
	input_tag := unsafe { SwiftSequenceTag(voidptr(layout.element.tag)) }
	output_tag := unsafe { SwiftSequenceTag(voidptr(layout.result.tag)) }
	witness := unsafe { SwiftSequenceWitnessCall(voidptr(swift_sequence_arena() + 64)) }
	call := unsafe { SwiftSequenceTransformCall(voidptr(swift_sequence_arena() + 128)) }
	mut owner := u64(0); mut count := u64(0); mut capacity := u64(0)
	mut iterator_live := false; mut item_live := false
	defer {
		if item_live { destroy_input(item, layout.element.metadata) }
		if iterator_live { destroy_iterator(iter_value, layout.iterator.metadata) }
		if owner != 0 { swift_release(owner) }
	}
	copy_sequence(seq_value, receiver, sequence)
	// makeIterator consumes this copied Sequence and returns an owned Iterator.
	witness(layout.make_iterator, sequence, table, seq_value, iter_value)
	iterator_live = true
	for {
		witness(layout.next, layout.iterator.metadata, layout.iterator_table, iter_value, input_optional)
		if input_tag(input_optional, 1, layout.element.metadata) == 1 { break }
		take_input(item, input_optional, layout.element.metadata); item_live = true
		observed := call(transform, context, item, output_optional)
		destroy_input(item, layout.element.metadata); item_live = false
		if observed.error != 0 { return SwiftSequenceResult{ error: observed.error } }
		if output_tag(output_optional, 1, layout.result.metadata) == 1 { continue }
		if count == capacity {
			// A produced Result is owned until appended, including growth failure.
			next_capacity := if capacity == 0 { u64(1) } else { capacity * 2 }
			owner = swift_sequence_grow(owner, count, next_capacity, layout) or {
				destroy_result := unsafe { SwiftSequenceDestroy(voidptr(layout.result.destroy)) }
				destroy_result(output_optional, layout.result.metadata)
				return err
			}
			capacity = next_capacity
		}
		take_result(owner + layout.array.storage.tail + count * layout.array.storage.stride,
			output_optional, result)
		count++; unsafe { *(&u64(owner + 16)) = count }
	}
	value := if owner == 0 { swift_array_empty() } else { owner }
	owner = 0 // Transfer the initialized result; defer still destroys Iterator.
	return SwiftSequenceResult{ array: value }
}
fn swift_compact_map(transform u64, context u64, sequence u64, result u64, table u64, receiver u64) SwiftSequenceResult {
	return swift_compact_map_checked(transform, context, sequence, result, table, receiver) or { panic(err) }
}

fn swift_sequence_arena() u64 {
	$if !arm64 { panic('iOS: Swift Sequence calls require ARM64') }
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_sequence_arena != 0 { return ios_runtime.swift_sequence_arena }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { panic('iOS: cannot allocate Swift Sequence adapters') }
	base := u64(allocation)
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e5, 0x580000d0, 0xd63f0200, 0xaa0103f5,
		0xa8c17bfd, 0xd65f03c0, 0xd503201f]! { write32(base + u64(i * 4), op) }
	unsafe { *(&u64(base + 32)) = u64(voidptr(swift_compact_map)) }
	// C -> consuming/mutating Swift witness: metadata/table x0/x1, self x20,
	// indirect result x8, caller's context restored after the call.
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1,
		0xaa0303f4, 0xaa0403e8, 0xd63f0200, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! {
		write32(base + 64 + u64(i * 4), op)
	}
	// C -> throwing transform: borrowed Element x0, context x20, Optional
	// result x8. Capture x21 as the second C result word, then restore it.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103f4,
		0xaa0203e0, 0xaa0303e8, 0xaa1f03f5, 0xd63f0200, 0xaa1503e1,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(base + 128 + u64(i * 4), op)
	}
	// Swift first(where:) -> C: borrowed self x20, indirect Optional x8;
	// C returns the original owned error, published in Swift's x21.
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e4, 0xaa0803e5, 0x580000b0,
		0xd63f0200, 0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! {
		write32(base + 256 + u64(i * 4), op)
	}
	unsafe { *(&u64(base + 288)) = u64(voidptr(swift_sequence_first)) }
	// C -> throwing predicate: Element x0, context x20, Bool x0/error x21.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0,
		0xaa0103f4, 0xaa0203e0, 0xaa1f03f5, 0xd63f0200, 0xaa1503e1,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(base + 320 + u64(i * 4), op)
	}
	C.__builtin___clear_cache(allocation, unsafe { voidptr(base + 372) })
	if C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) != 0 {
		C.munmap(allocation, page); panic('iOS: cannot seal Swift Sequence adapters')
	}
	ios_runtime.swift_sequence_arena = base
	return base
}
fn swift_sequence_stop() {
	if ios_runtime.swift_sequence_arena != 0 {
		if C.munmap(unsafe { voidptr(ios_runtime.swift_sequence_arena) }, usize(C.getpagesize())) != 0 {
			panic('iOS: cannot retire Swift Sequence adapters')
		}
		ios_runtime.swift_sequence_arena = 0
	}
}
