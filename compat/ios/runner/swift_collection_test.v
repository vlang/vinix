// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
	#include <objc/runtime.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.mincore(voidptr, usize, &u8) i32
type CollectionInvoke = fn (u64, &u64, u64, u64, &u64)
type CollectionAccess = fn (u64, u64) SwiftAssociatedMetadata
type CollectionLookup = fn (u64, u64, u64) u64
type CollectionAssociated = fn (u64, u64, u64, u64, u64) SwiftAssociatedMetadata
type CollectionConformance = fn (u64, u64, u64, u64, u64) u64
type CollectionAllocate = fn (i64, u64) SwiftArrayAllocation
type CollectionKeep = fn (u64) u64
type CollectionDrop = fn (u64)
type CollectionObjCMetadata = fn (u64) u64
type CollectionBox = fn (u64) SwiftArrayAllocation
type CollectionSign = fn (u64, u64) u64
type CollectionInstantiate = fn (u64, u64, u64)
struct CollectionApi {
	native bool
	code u64
	core voidptr
	descriptor u64
	int_type u64
	string_type u64
	objc_type u64
	access CollectionAccess = swift_array_access
	lookup CollectionLookup = swift_witness_table
	allocate CollectionAllocate = swift_array_allocate
	keep CollectionKeep = swift_bridge_retain
	drop CollectionDrop = swift_bridge_release
}
fn collection_api(native bool, code u64) CollectionApi {
	$if macos { if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		objc_type := unsafe { CollectionObjCMetadata(C.dlsym(core, c'swift_getObjCClassMetadata')) }
		return CollectionApi{native: true, core: core, code: code, descriptor: u64(C.dlsym(core, c'$sSayxGSlsMc')),
			int_type: u64(C.dlsym(core, c'$sSiN')), string_type: u64(C.dlsym(core, c'$sSSN')), objc_type: objc_type(u64(C.objc_getClass(c'NSString'))),
			access: unsafe { CollectionAccess(C.dlsym(core, c'$sSaMa')) }, lookup: unsafe { CollectionLookup(C.dlsym(core, c'swift_getWitnessTable')) },
			allocate: unsafe { CollectionAllocate(C.dlsym(core, c'$ss27_allocateUninitializedArrayySayxG_BptBwlF')) },
			keep: unsafe { CollectionKeep(C.dlsym(core, c'swift_bridgeObjectRetain')) }, drop: unsafe { CollectionDrop(C.dlsym(core, c'swift_bridgeObjectRelease')) }}
	} }
	return CollectionApi{code: code, descriptor: runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSayxGSlsMc') or {panic(err)},
		int_type: swift_integer_metadata(), string_type: swift_string_metadata(), objc_type: swift_objc_metadata(ios_runtime.names['NSString'])}
}
fn collection_object(api CollectionApi) u64 {
	$if macos { if api.native { return u64(C.CFStringCreateMutable(unsafe { nil }, 0)) } }
	return owned_string('Collection owned Element')
}
fn collection_keep_object(api CollectionApi, value u64) {
	$if macos { if api.native { C.CFRetain(voidptr(value)); return } }; objc_retain(value)
}
fn collection_drop_object(api CollectionApi, value u64) {
	$if macos { if api.native { C.CFRelease(voidptr(value)); return } }; objc_release(value)
}
fn collection_refs(api CollectionApi, value u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(voidptr(value)) } }; return obj_header(value).refs
}
fn collection_call(api CollectionApi, entry u64, args [5]u64, receiver u64, output u64) [4]u64 {
	mut capture := [u64(0), 0, 0, 0]!
	call := unsafe { CollectionInvoke(voidptr(api.code)) }
	call(entry & 0x0000ffffffffffff, unsafe { &args[0] }, receiver, output, unsafe { &capture[0] })
	assert capture[3] == receiver && capture[2] == 0
	return capture
}
fn collection_emit(code u64) {
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e9,
		0xaa0203f4, 0xaa0303e8, 0xaa0403f3, 0xa9400520, 0xa9410d22, 0xf9401124,
		0xaa1f03f5, 0xd63f0200, 0xf9000260, 0xf9000661, 0xf9000a75, 0xf9000e74,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e2, 0xaa0803e3, 0x580000b0, 0xd63f0200, 0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! { write32(code + 128 + u64(i * 4), op) }
	unsafe { *(&u64(code + 160)) = u64(voidptr(collection_body)) }
	write32(code + 192, 0xdac10020); write32(code + 196, 0xd65f03c0)
}
struct CollectionBodyContext {
	api CollectionApi
	kind int
	start i64
	end i64
	object u64
	error u64
	throws bool
mut:
	calls int
}
fn collection_body(bytes u64, count u64, context u64, output u64) u64 {
	mut state := unsafe { &CollectionBodyContext(context) }
	assert count == u64(state.end - state.start); stride := if state.kind == 1 {u64(16)} else {u64(8)}
	for i in u64(0) .. count { collection_value_check(state.api, bytes + i * stride, state.kind, state.start + i64(i), state.object) }
	state.calls++
	if state.throws { collection_keep_object(state.api, state.error); return state.error }
	unsafe { *(&u64(output)) = 100 + count }; return 0
}
fn collection_association(api CollectionApi, table u64, metadata u64, slot int) u64 {
	$if macos { if api.native {
		base := u64(C.dlsym(api.core, c'$sSlTL'))
		if slot in [5, 6, 7]! {
			associated := unsafe { CollectionAssociated(C.dlsym(api.core, c'swift_getAssociatedTypeWitness')) }
			return associated(0, table, metadata, base, base + u64(slot * 8)).metadata
		}
		conformance := unsafe { CollectionConformance(C.dlsym(api.core, c'swift_getAssociatedConformanceWitness')) }
		type_slot := if slot == 2 {5} else if slot == 3 {7} else {6}
		return conformance(table, metadata, collection_association(api, table, metadata, type_slot), base, base + u64(slot * 8))
	} }
	return read64(table + u64(slot * 8))
}
fn collection_iterator(api CollectionApi, sequence u64, metadata u64) [2]u64 {
	$if macos { if api.native {
		associated := unsafe { CollectionAssociated(C.dlsym(api.core, c'swift_getAssociatedTypeWitness')) }
		conformance := unsafe { CollectionConformance(C.dlsym(api.core, c'swift_getAssociatedConformanceWitness')) }
		base := u64(C.dlsym(api.core, c'$sSTTL'))
		iterator := associated(0, sequence, metadata, base, u64(C.dlsym(api.core, c'$s8IteratorSTTl'))).metadata
		return [iterator, conformance(sequence, metadata, iterator, base, u64(C.dlsym(api.core, c'$sST8IteratorST_StTn')))]!
	} }
	return [read64(sequence + 24), read64(sequence + 8)]!
}
fn collection_value_check(api CollectionApi, value u64, kind int, index i64, object u64) {
	if kind == 0 { assert i64(read64(value)) == index }
	else if kind == 1 { assert read64(value) == 0 && read64(value + 8) == object | 0x5000000000000000 }
	else { assert read64(value) == object }
}
fn collection_destroy(value u64, metadata u64) { destroy := unsafe { SwiftSequenceDestroy(voidptr(read64(read64(metadata - 8) + 8))) }; destroy(value, metadata) }
fn collection_value_witnesses(api CollectionApi, metadata u64, source u64) {
	witness := read64(metadata - 8); size := read64(witness + 64)
	mut alias := [8]u64{}; mut moved := [8]u64{}
	a := u64(unsafe { &alias[0] }); m := u64(unsafe { &moved[0] })
	copy_value := unsafe { SwiftSequenceCopy(voidptr(read64(witness + 16))) }
	assign_copy := unsafe { SwiftSequenceCopy(voidptr(read64(witness + 24))) }
	take := unsafe { SwiftSequenceCopy(voidptr(read64(witness + 32))) }
	assign_take := unsafe { SwiftSequenceCopy(voidptr(read64(witness + 40))) }
	copy_value(a, source, metadata); assign_copy(a, a, metadata); take(m, a, metadata)
	copy_value(a, source, metadata); assign_take(a, m, metadata); collection_destroy(a, metadata)
	get_tag := unsafe { SwiftSequenceTag(voidptr(read64(witness + 48))) }
	store := unsafe { SwiftArraySequenceStore(voidptr(read64(witness + 56))) }
	for cases in [u32(1), 7, 0x7fffffff, 0x80000000, 0xffffffff]! {
		for tag in [u32(1), cases]! { C.memset(voidptr(a), 0, 64); store(a, tag, cases, metadata); assert get_tag(a, cases, metadata) == tag }
		copy_value(a, source, metadata); store(a, 0, cases, metadata); assert get_tag(a, cases, metadata) == 0; collection_destroy(a, metadata)
	}
	if size > 24 {
		mut owner := u64(0); mut bytes := u64(0)
		mut release := CollectionDrop(swift_release)
		$if macos { if api.native {
			allocate := unsafe { CollectionBox(C.dlsym(api.core, c'swift_allocBox')) }; box := allocate(metadata); owner = box.owner; bytes = box.bytes
			release = unsafe { CollectionDrop(C.dlsym(api.core, c'swift_release')) }
		} }
		if !api.native { owner = swift_collection_box_allocate(metadata); bytes = owner + 16 }
		copy_value(bytes, source, metadata)
		mut buffer := [owner, u64(0), 0]!; mut copied_buffer := [u64(0), 0, 0]!
		initialize := unsafe { SwiftSequenceCopy(voidptr(read64(witness))) }
		assert initialize(u64(unsafe { &copied_buffer[0] }), u64(unsafe { &buffer[0] }), metadata) == bytes
		assert copied_buffer[0] == owner
		release(owner); release(copied_buffer[0])
	}
}
fn collection_operations(api CollectionApi, metadata u64, table u64, receiver u64, kind int, start i64, end i64, object u64, guard u64) {
	mut result := [u64(0x1234), 0, 0, 0, 0, 0]!
	output := u64(unsafe { &result[0] })
	collection_call(api, read64(table + 64), [metadata, table, 0, 0, 0]!, receiver, output); assert i64(result[0]) == start
	collection_call(api, read64(table + 72), [metadata, table, 0, 0, 0]!, receiver, output); assert i64(result[0]) == end
	assert collection_call(api, read64(table + 104), [metadata, table, 0, 0, 0]!, receiver, guard)[0] == if start == end {u64(1)} else {u64(0)}
	assert i64(collection_call(api, read64(table + 112), [metadata, table, 0, 0, 0]!, receiver, guard)[0]) == end - start
	collection_call(api, read64(table + 96), [metadata, table, 0, 0, 0]!, receiver, output); assert i64(result[0]) == start && i64(result[1]) == end
	mut index := start; mut limit := end
	ip := u64(unsafe { &index }); lp := u64(unsafe { &limit })
	is_range := read64(read64(metadata - 8) + 64) == 16
	for slot in [15, 16]! {
		collection_call(api, read64(table + u64(slot * 8)), [ip, metadata, table, 0, 0]!, receiver, output)
		if is_range { assert result[0] == if start < end {u64(start)} else {u64(0)} && unsafe { *(&u16(output + 8)) } == if start < end {u16(0)} else {u16(1)} }
		else { assert result[0] == 0 && unsafe { *(&u16(output + 8)) } == 256 }
	}
	step := if is_range && end - start < 7 {end - start} else {i64(7)}
	collection_call(api, read64(table + 136), [ip, u64(step), metadata, table, 0]!, receiver, output); assert i64(result[0]) == start + step
	collection_call(api, read64(table + 144), [ip, u64(7), lp, metadata, table]!, receiver, output)
	assert unsafe { *(&u8(output + 8)) } == if end - start < 7 {u8(1)} else {u8(0)}
	if end - start >= 7 { assert i64(result[0]) == start + 7 }
	assert i64(collection_call(api, read64(table + 152), [ip, lp, metadata, table, 0]!, receiver, guard)[0]) == end - start
	if !is_range || start < end {
		collection_call(api, read64(table + 184), [ip, metadata, table, 0, 0]!, receiver, output); assert i64(result[0]) == start + 1
		collection_call(api, read64(table + 192), [ip, metadata, table, 0, 0]!, receiver, guard); assert index == start + 1
	}
	mut bounds := [u64(start), u64(end)]!
	index = start
	if start < end { collection_call(api, read64(table + 160), [ip, u64(unsafe { &bounds[0] }), metadata, table, 0]!, receiver, guard) }
	collection_call(api, read64(table + 176), [u64(unsafe { &bounds[0] }), u64(unsafe { &bounds[0] }), metadata, table, 0]!, receiver, guard)
	collection_call(api, read64(table + 168), [ip, u64(unsafe { &bounds[0] }), metadata, table, 0]!, guard, guard)
	for position := start; position < end; position++ {
		index = position; mut buffer := [u64(0), 0, 0, 0]!
		buffer_pointer := u64(unsafe { &buffer[0] })
		yielded := collection_call(api, read64(table + 80), [buffer_pointer, ip, metadata, table, 0]!, receiver, guard)
		assert yielded[0] != 0 && yielded[1] != 0
		collection_value_check(api, yielded[1], kind, position, object)
		collection_call(api, yielded[0], [buffer_pointer, u64(position & 1), 0, 0, 0]!, guard, guard)
	}
	// Every associated Collection is usable and returns itself for subslicing.
	if end > start { bounds = [u64(start), u64(end - 1)]! }
	collection_call(api, read64(table + 88), [u64(unsafe { &bounds[0] }), metadata, table, 0, 0]!, receiver, output)
	slice_type := collection_association(api, table, metadata, 6); slice_table := collection_association(api, table, metadata, 4)
	assert collection_association(api, slice_table, slice_type, 6) == slice_type
	collection_destroy(output, slice_type)
}
fn collection_sequence(api CollectionApi, metadata u64, table u64, receiver u64, kind int, start i64, end i64, object u64, guard u64) {
	sequence := read64(table + 8); iterator := collection_iterator(api, sequence, metadata)
	size := read64(read64(metadata - 8) + 64); iterator_size := read64(read64(iterator[0] - 8) + 64)
	assert iterator_size == size + 8
	collection_value_witnesses(api, metadata, receiver)
	mut copied := [u64(0), 0, 0, 0, 0]!
	mut iter := [u64(0), 0, 0, 0, 0, 0]!
	mut optional := [u64(0), 0, 0]!
	copy_value := unsafe { SwiftSequenceCopy(voidptr(read64(read64(metadata - 8) + 16))) }
	copy_value(u64(unsafe { &copied[0] }), receiver, metadata)
	collection_call(api, read64(sequence + 32), [metadata, sequence, 0, 0, 0]!, u64(unsafe { &copied[0] }), u64(unsafe { &iter[0] }))
	collection_value_witnesses(api, iterator[0], u64(unsafe { &iter[0] }))
	element := if kind == 0 {api.int_type} else if kind == 1 {api.string_type} else {api.objc_type}
	get_tag := unsafe { SwiftSequenceTag(voidptr(read64(read64(element - 8) + 48))) }
	for position := start; position < end; position++ {
		collection_call(api, read64(iterator[1] + 16), [iterator[0], iterator[1], 0, 0, 0]!, u64(unsafe { &iter[0] }), u64(unsafe { &optional[0] }))
		assert get_tag(u64(unsafe { &optional[0] }), 1, element) == 0
		collection_value_check(api, u64(unsafe { &optional[0] }), kind, position, object)
		collection_destroy(u64(unsafe { &optional[0] }), element)
	}
	for _ in 0 .. 2 { collection_call(api, read64(iterator[1] + 16), [iterator[0], iterator[1], 0, 0, 0]!, u64(unsafe { &iter[0] }), u64(unsafe { &optional[0] })); assert get_tag(u64(unsafe { &optional[0] }), 1, element) == 1 }
	collection_destroy(u64(unsafe { &iter[0] }), iterator[0])
	assert i64(collection_call(api, read64(sequence + 40), [metadata, sequence, 0, 0, 0]!, receiver, guard)[0]) == end - start
	mut probe := start
	assert collection_call(api, read64(sequence + 48), [u64(unsafe { &probe }), metadata, sequence, 0, 0]!, receiver, guard)[0] == if size == 16 {if start < end {u64(1)} else {u64(0)}} else {u64(2)}
	// Both consuming copy operations receive their own owned Sequence value.
	copy_value(u64(unsafe { &copied[0] }), receiver, metadata)
	contiguous := collection_call(api, read64(sequence + 56), [metadata, sequence, 0, 0, 0]!, u64(unsafe { &copied[0] }), guard)[0]
	assert read64(contiguous + 16) == u64(end - start)
	stride := if kind == 1 {u64(16)} else {u64(8)}
	for i := start; i < end; i++ { collection_value_check(api, contiguous + 32 + u64(i - start) * stride, kind, i, object) }
	api.drop(contiguous)
	copy_value(u64(unsafe { &copied[0] }), receiver, metadata)
	mut destination := [66]u64{}
	assert collection_call(api, read64(sequence + 64), [u64(unsafe { &iter[0] }), u64(unsafe { &destination[0] }), u64(end - start), metadata, sequence]!, u64(unsafe { &copied[0] }), guard)[0] == u64(end - start)
	for i := start; i < end; i++ {
		address := u64(unsafe { &destination[0] }) + u64(i - start) * stride
		collection_value_check(api, address, kind, i, object); collection_destroy(address, element)
	}
	collection_destroy(u64(unsafe { &iter[0] }), iterator[0])
	error_owner := collection_object(api)
	for throws in [false, true]! {
		mut state := CollectionBodyContext{api: api, kind: kind, start: start, end: end, object: object, error: error_owner, throws: throws}
		mut body := api.code + 128
		$if macos { if api.native { sign := unsafe { CollectionSign(voidptr(api.code + 192)) }; body = sign(body, 24507) } }
		mut args := [body, u64(unsafe { &state }), api.int_type, metadata, sequence]!
		optional = [u64(0x4545454545454545), 0x4545454545454545, 0x4545454545454545]!
		mut capture := [u64(0), 0, 0, 0]!
		invoke := unsafe { CollectionInvoke(voidptr(api.code)) }
		optional_pointer := u64(unsafe { &optional[0] })
		invoke(read64(sequence + 72), unsafe { &args[0] }, receiver, optional_pointer, unsafe { &capture[0] })
		assert capture[3] == receiver
		if size == 16 { assert state.calls == 0 && capture[2] == 0 && unsafe { *(&u8(optional_pointer + 8)) } == 1 }
		else if throws {
			assert state.calls == 1 && capture[2] == error_owner && optional[0] == 0x4545454545454545 && optional[1] == 0x4545454545454545
			assert collection_refs(api, error_owner) == 2; collection_drop_object(api, error_owner)
		} else { assert state.calls == 1 && capture[2] == 0 && optional[0] == 100 + u64(end - start) && unsafe { *(&u8(optional_pointer + 8)) } == 0 }
	}
	assert collection_refs(api, error_owner) == 1; collection_drop_object(api, error_owner)
}
fn collection_case(api CollectionApi, kind int, count u64, guard u64) {
	element := if kind == 0 {api.int_type} else if kind == 1 {api.string_type} else {api.objc_type}; stride := if kind == 1 {u64(16)} else {u64(8)}
	metadata := api.access(0, element).metadata; table := api.lookup(api.descriptor, metadata, guard)
	assert table != 0 && api.lookup(api.descriptor, metadata, 0) == table
	assert collection_association(api, table, metadata, 5) == api.int_type
	object := collection_object(api); allocation := api.allocate(i64(count), element)
	for i in u64(0) .. count {
		if kind != 0 { collection_keep_object(api, object) }
		if kind == 0 { unsafe { *(&u64(allocation.bytes + i * stride)) = i } }
		else if kind == 1 { unsafe { *(&SwiftStringWords(allocation.bytes + i * stride)) = SwiftStringWords{second: object | 0x5000000000000000} } }
		else { unsafe { *(&u64(allocation.bytes + i * stride)) = object } }
	}
	mut owner := allocation.owner; receiver := u64(unsafe { &owner })
	collection_operations(api, metadata, table, receiver, kind, 0, i64(count), object, guard)
	start := if count > 1 {u64(1)} else {u64(0)}; end := if count > 1 {count - 1} else {count}
	mut bounds := [start, end]!; mut slice := [u64(0), 0, 0, 0]!
	slice_pointer := u64(unsafe { &slice[0] })
	collection_call(api, read64(table + 88), [u64(unsafe { &bounds[0] }), metadata, table, 0, 0]!, receiver, slice_pointer)
	slice_type := collection_association(api, table, metadata, 6); slice_table := collection_association(api, table, metadata, 4)
	assert slice[0] == owner && slice[1] == allocation.bytes && slice[2] == start && slice[3] == end << 1 | 1, 'slice layout ${slice}'
	collection_operations(api, slice_type, slice_table, slice_pointer, kind, i64(start), i64(end), object, guard)
	collection_sequence(api, slice_type, slice_table, slice_pointer, kind, i64(start), i64(end), object, guard)
	mut indices := [start, end]!; range_type := collection_association(api, table, metadata, 7); range_table := collection_association(api, table, metadata, 3)
	collection_operations(api, range_type, range_table, u64(unsafe { &indices[0] }), 0, i64(start), i64(end), object, guard)
	collection_sequence(api, range_type, range_table, u64(unsafe { &indices[0] }), 0, i64(start), i64(end), object, guard)
	collection_destroy(slice_pointer, slice_type); api.drop(owner)
	assert collection_refs(api, object) == 1; collection_drop_object(api, object)
}
fn collection_worker(api CollectionApi, metadata u64) u64 { return api.lookup(api.descriptor, metadata, 0) }
fn collection_comparisons(api CollectionApi, guard u64) {
	metadata := api.access(0, api.int_type).metadata; table := api.lookup(api.descriptor, metadata, 0)
	comparable := collection_association(api, table, metadata, 2)
	for left in [-i64(0x7fffffffffffffff)-1, -1, 0, 1, i64(0x7fffffffffffffff)]! {
		for right in [-i64(0x7fffffffffffffff)-1, -1, 0, 1, i64(0x7fffffffffffffff)]! {
			for i, expected in [left < right, left <= right, left >= right, left > right]! {
				assert collection_call(api, read64(comparable + u64((i + 2) * 8)), [u64(unsafe { &left }), u64(unsafe { &right }), api.int_type, comparable, 0]!, guard, guard)[0] == if expected {u64(1)} else {u64(0)}
			}
		}
	}
}
fn collection_constructors(api CollectionApi, metadata u64, table u64, guard u64) {
	slice_type := read64(table + 48); slice_table := read64(table + 32); range_type := read64(table + 56); range_table := read64(table + 24)
	for pair in [[metadata, table]!, [slice_type, slice_table]!, [range_type, range_table]!]! {
		mut copied := [25]u64{}; control := read64(pair[1]) + 16
		assert read32(control) == 0x10019
		instantiate := unsafe { CollectionInstantiate(voidptr(u64(i64(control + 4) + i64(i32(read32(control + 4)))))) }
		instantiate(u64(unsafe { &copied[0] }), pair[0], guard)
		for i in 0 .. 25 { assert copied[i] == read64(pair[1] + u64(i * 8)) }
		assert api.lookup(read64(pair[1]), pair[0], guard) == pair[1]
		if _ := swift_witness_table_checked(read64(pair[1]), guard, guard) { assert false }
		sequence := read64(pair[1] + 8); iterator_type := read64(sequence + 24); iterator_table := read64(sequence + 8)
		assert api.lookup(read64(sequence), pair[0], guard) == sequence
		assert api.lookup(read64(iterator_table), iterator_type, guard) == iterator_table
	}
	if _ := swift_witness_table_checked(read64(slice_table), metadata, guard) { assert false }
	if _ := swift_witness_table_checked(read64(range_table), slice_type, guard) { assert false }
}
fn test_swift_collection() {
	page := usize(C.getpagesize()); allocation := C.mmap(unsafe {nil}, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert allocation != voidptr(-1); code := u64(allocation); collection_emit(code)
	C.__builtin___clear_cache(allocation, voidptr(code + 200)); assert C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) == 0
	protected := C.mmap(unsafe {nil}, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0); assert protected != voidptr(-1); guard := u64(protected)
	$if macos {
		api := collection_api(true, code)
		collection_comparisons(api, guard)
		for kind in 0 .. 3 { for count in [u64(0), 1, 5, 33]! { collection_case(api, kind, count, guard) } }
		println('IOS-COLLECTION-NATIVE: 12 typed Array fixtures, nested ArraySlice/Range Collection and Sequence operations, borrowed coroutine resume/abort and original indices')
	}
	for _ in 0 .. 2 {
		objc_start(); api := collection_api(false, code)
		metadata := swift_array_access(0, api.int_type).metadata
		mut workers := []thread u64{}
		for _ in 0 .. 4 { workers << spawn collection_worker(api, metadata) }
		tables := workers.wait(); for table in tables { assert table == tables[0] }
		collection_comparisons(api, guard); collection_constructors(api, metadata, tables[0], guard)
		for kind in 0 .. 3 { for count in [u64(0), 1, 5, 33]! { collection_case(api, kind, count, guard) } }
		if _ := swift_collection_table_checked(guard) { assert false }
		assert (swift_collection_kind_checked(guard, false) or { -1 }) == -1
		assert (swift_collection_sum_checked(i64(0x7fffffffffffffff), 1) or { -1 }) == -1
		assert (swift_collection_sum_checked(-i64(0x7fffffffffffffff)-1, -1) or { 1 }) == 1
		assert ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_heap.len == 0
		arena := ios_runtime.swift_collection_arena; bases := ios_runtime.swift_collection_metadata.values()
		objc_stop()
		assert C.mprotect(voidptr(arena), page, C.PROT_READ) != 0
		for base in bases { assert C.mprotect(voidptr(base), page, C.PROT_READ) != 0 }
	}
	assert C.munmap(protected, page) == 0 && C.munmap(allocation, page) == 0
	println('IOS-COLLECTION: complete Array/ArraySlice/Range direct associated tables, usable Sequence iterators, signed indices, nested slices, coroutine ownership, concurrent first specialization and two drained/unmapped lifetimes')
}
