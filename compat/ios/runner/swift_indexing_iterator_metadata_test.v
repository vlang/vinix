// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>

fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr

type IiAccess = fn (u64, u64, u64) SwiftAssociatedMetadata
type IiArray = fn (u64, u64) SwiftAssociatedMetadata
type IiLookup = fn (u64, u64, u64) u64
type IiAssociated = fn (u64, u64, u64, u64, u64) SwiftAssociatedMetadata
type IiConformance = fn (u64, u64, u64, u64, u64) u64
type IiFactory = fn (u64, u64, u64) u64

fn ii_relative(address u64) u64 {
	return u64(i64(address) + i64(i32(read32(address))))
}

fn ii_descriptor(descriptor u64) {
	assert read32(descriptor) & 0xffff == 0xd1
	assert unsafe { (&u8(ii_relative(descriptor + 8))).vstring() } == 'IndexingIterator'
	parent := ii_relative(descriptor + 4)
	assert read32(parent) == 0
	assert unsafe { (&u8(ii_relative(parent + 8))).vstring() } == 'Swift'
	assert read32(descriptor + 20) == 2 && read32(descriptor + 24) == 4
	assert read32(descriptor + 36) == 0x10001 && read32(descriptor + 40) == 2
	assert read32(descriptor + 44) == 0x80 && read32(descriptor + 48) == 0x80
	assert unsafe { (&u8(ii_relative(descriptor + 52))).vstring() } == 'x'
	protocol := ii_relative(descriptor + 56)
	assert unsafe { (&u8(ii_relative(protocol + 8))).vstring() } == 'Collection'
}

// Snapshot the exact native single-payload representation, including bytes
// outside the live tag. ASan redzones catch accesses beyond its measured size.
fn ii_enums(metadata u64) []u8 {
	witness := read64(metadata - 8)
	size := read64(witness + 64)
	extra := read32(witness + 84)
	get := unsafe { SwiftSequenceTag(voidptr(read64(witness + 48))) }
	store := unsafe { SwiftArraySequenceStore(voidptr(read64(witness + 56))) }
	mut result := []u8{}
	for cases in [u32(0), 1, 17, 0x7fffffff, 0x80000000, 0xffffffff]! {
		length := usize(size + u64(cases > extra))
		value := u64(C.malloc(length))
		for tag in [u32(0), 1, 17, 0x7fffffff, 0x80000000, 0xffffffff]! {
			if tag > cases { continue }
			C.memset(voidptr(value), 0x5a, length)
			store(value, tag, cases, metadata)
			assert get(value, cases, metadata) == tag
			for i in usize(0) .. length { result << unsafe { *(&u8(value + u64(i))) } }
		}
		C.free(voidptr(value))
	}
	return result
}

fn ii_metadata(descriptor u64, access IiAccess, elements u64, table u64, size u64, flags u32) u64 {
	from_descriptor := unsafe { IiAccess(voidptr(ii_relative(descriptor + 12))) }
	metadata := access(0, elements, table).metadata
	for request in [u64(0), 0x3f, 0xff, 0x100, 0x13f, 0x1ff]! {
		for entry in [access, from_descriptor]! {
			response := entry(request, elements, table)
			assert response.metadata == metadata && response.state == 0
		}
	}
	assert read64(metadata) == 0x200 && read64(metadata + 8) == descriptor
	assert read64(metadata + 16) == elements && read64(metadata + 24) == table
	assert read32(metadata + 32) == 0 && read32(metadata + 36) == u32(size - 8)
	witness := read64(metadata - 8)
	assert read64(witness + 64) == size && read64(witness + 72) == size
	assert read32(witness + 80) == flags
	assert read32(witness + 84) == if size == 24 { u32(0) } else { u32(0x7fffffff) }
	return metadata
}

fn ii_ownership(metadata u64, guard u64) {
	size := read64(read64(metadata - 8) + 64)
	allocation := swift_array_allocate(3, swift_integer_metadata())
	for i in 0 .. 3 {
		unsafe { *(&u64(allocation.bytes + u64(i * 8))) = u64(i + 11) }
	}
	// Value ends at a protected page; the copy uses an exact-size ASan allocation.
	value := guard - size
	copy := u64(C.malloc(usize(size)))
	if size == 16 {
		unsafe {
			*(&u64(value)) = allocation.owner
			*(&u64(value + 8)) = 1
		}
	} else if size == 40 {
		unsafe {
			*(&u64(value)) = allocation.owner
			*(&u64(value + 8)) = allocation.bytes
			*(&u64(value + 16)) = 0
			*(&u64(value + 24)) = 7
			*(&u64(value + 32)) = 1
		}
	} else {
		swift_bridge_release(allocation.owner)
		unsafe {
			*(&u64(value)) = 0
			*(&u64(value + 8)) = 3
			*(&u64(value + 16)) = 1
		}
	}
	witness := read64(metadata - 8)
	initialize := unsafe { SwiftSequenceCopy(voidptr(read64(witness + 16))) }
	assign := unsafe { SwiftSequenceCopy(voidptr(read64(witness + 24))) }
	take := unsafe { SwiftSequenceCopy(voidptr(read64(witness + 40))) }
	destroy := unsafe { SwiftSequenceDestroy(voidptr(read64(witness + 8))) }
	assert initialize(copy, value, metadata) == copy
	assert assign(copy, copy, metadata) == copy
	assert take(value, copy, metadata) == value
	assert read64(value + size - 8) == 1
	if size != 24 {
		assert allocation.owner in ios_runtime.swift_arrays
	}
	destroy(value, metadata)
	assert allocation.owner !in ios_runtime.swift_arrays
	C.free(voidptr(copy))
}

fn ii_publish() u64 {
	descriptor := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss16IndexingIteratorVMn') or { panic(err) }
	array := swift_array_access(0, swift_integer_metadata()).metadata
	table := swift_collection_table_checked(array) or { panic(err) }
	access := unsafe { IiAccess(voidptr(ii_relative(descriptor + 12))) }
	mut metadata := u64(0)
	for _ in 0 .. 64 {
		response := access(0x1ff, array, table)
		metadata = response.metadata
	}
	return metadata
}

fn test_swift_indexing_iterator_metadata() {
	page := usize(C.getpagesize())
	allocation := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert allocation != u64(-1)
	guard := allocation + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	mut native_snapshots := [][]u8{}
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		assert core != unsafe { nil }
		descriptor := u64(C.dlsym(core, c'$ss16IndexingIteratorVMn'))
		ii_descriptor(descriptor)
		access := unsafe { IiAccess(C.dlsym(core, c'$ss16IndexingIteratorVMa')) }
		array := unsafe { IiArray(C.dlsym(core, c'$sSaMa')) }(0, u64(C.dlsym(core, c'$sSiN'))).metadata
		lookup := unsafe { IiLookup(C.dlsym(core, c'swift_getWitnessTable')) }
		table := lookup(u64(C.dlsym(core, c'$sSayxGSlsMc')), array, guard)
		associated := unsafe { IiAssociated(C.dlsym(core, c'swift_getAssociatedTypeWitness')) }
		conformance := unsafe { IiConformance(C.dlsym(core, c'swift_getAssociatedConformanceWitness')) }
		base := u64(C.dlsym(core, c'$sSlTL'))
		slice := associated(0, table, array, base, u64(C.dlsym(core, c'$s11SubSequenceSlTl'))).metadata
		range := associated(0, table, array, base, u64(C.dlsym(core, c'$s7IndicesSlTl'))).metadata
		slice_table := conformance(table, array, slice, base, u64(C.dlsym(core, c'$sSl11SubSequenceSl_SlTn')))
		range_table := conformance(table, array, range, base, u64(C.dlsym(core, c'$sSl7IndicesSl_SlTn')))
		for i, pair in [[array, table]!, [slice, slice_table]!, [range, range_table]!]! {
			size := [u64(16), 40, 24]![i]
			metadata := ii_metadata(descriptor, access, pair[0], pair[1], size, [
				u32(0x10007),
				0x30007,
				7,
			]![i])
			native_snapshots << ii_enums(metadata)
		}
		println('NATIVE-INDEXING-ITERATOR-METADATA: generic Elements/Collection signature, direct/descriptor ARM64 x0/x1 responses, Array/ArraySlice/Range field offsets and exact enum bytes')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn ii_publish() }
		published := workers.wait()
		for metadata in published {
			assert metadata == published[0]
		}
		library := '/usr/lib/swift/libswiftCore.dylib'
		descriptor := runtime_symbol(library, '_$ss16IndexingIteratorVMn') or { panic(err) }
		entry := runtime_symbol(library, '_$ss16IndexingIteratorVMa') or { panic(err) }
		mc := runtime_symbol(library, '_$ss16IndexingIteratorVyxGStsMc') or { panic(err) }
		ii_descriptor(descriptor)
		assert ii_relative(descriptor + 12) == entry
		assert runtime_symbol(library, '_$ss16IndexingIteratorVN') == none
		assert runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_$ss16IndexingIteratorVMn') == none
		array := swift_array_access(0, swift_integer_metadata()).metadata
		table := swift_collection_table_checked(array) or { panic(err) }
		slice := read64(table + 48)
		range := read64(table + 56)
		for i, elements in [array, slice, range]! {
			collection := swift_collection_table_checked(elements) or { panic(err) }
			metadata := ii_metadata(descriptor, unsafe { IiAccess(voidptr(entry)) }, elements, collection, [
				u64(16),
				40,
				24,
			]![i], [u32(0x10007), 0x30007, 7]![i])
			sequence := if i == 0 {
				read64(collection + 8)
			} else {
				swift_collection_sequence_checked(elements) or { panic(err) }
			}
			assert read64(sequence + 24) == metadata
			iterator_table := swift_witness_table(mc, metadata, guard)
			assert read64(sequence + 8) == iterator_table && read64(iterator_table) == mc
			mut args := [elements, collection]!
			pattern := ii_relative(descriptor + 32)
			factory := unsafe { IiFactory(voidptr(ii_relative(pattern))) }
			assert factory(descriptor, u64(unsafe { &args[0] }), pattern) == metadata
			snapshot := ii_enums(metadata)
			if native_snapshots.len != 0 {
				assert snapshot == native_snapshots[i], 'enum bytes differ for kind ${i}'
			}
			ii_ownership(metadata, guard)
		}
		for args in [[guard, guard]!, [array, guard]!, [array, table + 8]!, [array + 1, table]!,
			[u64(0), table]!]! {
			if _ := swift_indexing_iterator_metadata_checked(0, args[0], args[1]) {
				assert false
			}
		}
		// Completing IndexingIterator<Array<T>> never reads or completes T.
		opaque_array := swift_array_access(0, guard).metadata
		opaque_table := swift_collection_table_checked(opaque_array) or { panic(err) }
		opaque := swift_indexing_iterator_metadata_checked(0x1ff, opaque_array, opaque_table) or { panic(err) }
		assert opaque.state == 0 && read64(opaque.metadata + 16) == opaque_array
		if _ := swift_indexing_iterator_metadata_instantiate_checked(guard, guard, guard) {
			assert false
		}
		ios_runtime.swift_concurrency_retired = true
		assert runtime_symbol(library, '_$ss16IndexingIteratorVMn') == none
		if _ := swift_indexing_iterator_metadata_checked(0, array, table) {
			assert false
		}
		ios_runtime.swift_concurrency_retired = false
		mut retired := []u64{}
		for _, base in ios_runtime.swift_array_sequence_metadata { retired << base }
		for _, base in ios_runtime.swift_collection_metadata { retired << base }
		retired << ios_runtime.swift_collection_arena
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		objc_stop()
		assert ios_runtime.swift_collection_arena == 0 && ios_runtime.swift_array_sequence_arena == 0
		assert runtime_symbol(library, '_$ss16IndexingIteratorVMn') == none
		if _ := swift_witness_table_checked(mc, published[0], guard) {
			assert false
		}
		for base in retired {
			assert C.mprotect(voidptr(base), page, C.PROT_READ) == -1
		}
	}
	assert C.munmap(voidptr(allocation), page * 2) == 0
	println('IOS-INDEXING-ITERATOR-METADATA: canonical generic metadata, exact enum bytes, guarded borrowed inputs and witnesses, ownership transfer, eight cold publishers/workers and two drained/unmapped lifetimes')
}
