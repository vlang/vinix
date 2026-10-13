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

type ArraySequenceInvoke = fn (u64, &u64, u64, u64, &u64)
type ArraySequenceAccess = fn (u64, u64) SwiftAssociatedMetadata
type ArraySequenceAssociated = fn (u64, u64, u64, u64, u64) SwiftAssociatedMetadata
type ArraySequenceLookup = fn (u64, u64, u64) u64
type ArraySequenceConformance = fn (u64, u64, u64, u64, u64) u64
type ArraySequenceAllocate = fn (i64, u64) SwiftArrayAllocation
type ArraySequenceKeep = fn (u64) u64
type ArraySequenceDrop = fn (u64)
type ArraySequenceObjCMetadata = fn (u64) u64
type ArraySequenceSign = fn (u64, u64) u64
type ArraySequenceInstantiate = fn (u64, u64, u64)
struct ArraySequenceApi {
	native bool
	code u64
	descriptor u64
	int_type u64
	string_type u64
	objc_type u64
	lookup ArraySequenceLookup = swift_witness_table
	access ArraySequenceAccess = swift_array_access
	allocate ArraySequenceAllocate = swift_array_allocate
	keep ArraySequenceKeep = swift_bridge_retain
	drop ArraySequenceDrop = swift_bridge_release
}
fn array_sequence_api(native bool, code u64) ArraySequenceApi {
	$if macos { if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		objc_type := unsafe { ArraySequenceObjCMetadata(C.dlsym(core, c'swift_getObjCClassMetadata')) }
		return ArraySequenceApi{native: true, code: code, descriptor: u64(C.dlsym(core, c'$sSayxGSTsMc')),
			int_type: u64(C.dlsym(core, c'$sSiN')), string_type: u64(C.dlsym(core, c'$sSSN')), objc_type: objc_type(u64(C.objc_getClass(c'NSString'))),
			lookup: unsafe { ArraySequenceLookup(C.dlsym(core, c'swift_getWitnessTable')) }, access: unsafe { ArraySequenceAccess(C.dlsym(core, c'$sSaMa')) },
			allocate: unsafe { ArraySequenceAllocate(C.dlsym(core, c'$ss27_allocateUninitializedArrayySayxG_BptBwlF')) },
			keep: unsafe { ArraySequenceKeep(C.dlsym(core, c'swift_bridgeObjectRetain')) }, drop: unsafe { ArraySequenceDrop(C.dlsym(core, c'swift_bridgeObjectRelease')) }}
	} }
	return ArraySequenceApi{code: code, descriptor: runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSayxGSTsMc') or {panic(err)},
		int_type: swift_integer_metadata(), string_type: swift_string_metadata(), objc_type: swift_objc_metadata(ios_runtime.names['NSString'])}
}
fn array_sequence_object_keep(api ArraySequenceApi, object u64) {
	$if macos { if api.native { C.CFRetain(unsafe { voidptr(object) }); return } }
	objc_retain(object)
}
fn array_sequence_object_drop(api ArraySequenceApi, object u64) {
	$if macos { if api.native { C.CFRelease(unsafe { voidptr(object) }); return } }
	objc_release(object)
}
fn array_sequence_object_refs(api ArraySequenceApi, object u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(unsafe { voidptr(object) }) } }
	return obj_header(object).refs
}
fn array_sequence_object(api ArraySequenceApi) u64 {
	$if macos { if api.native { return u64(C.CFStringCreateMutable(unsafe { nil }, 0)) } }
	return owned_string('Array Sequence owned Element')
}
fn array_sequence_emit(code u64) {
	// C arguments: entry, five Swift arguments, self, indirect result, capture.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e9,
		0xaa0203f4, 0xaa0303e8, 0xaa0403f3, 0xa9400520, 0xa9410d22, 0xf9401124,
		0xaa1f03f5, 0xd63f0200, 0xf9000260, 0xf9000675, 0xf9000a74,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	// Swift UnsafeBufferPointer closure -> C fixture; error returns in x21.
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e2, 0xaa0803e3, 0x580000b0,
		0xd63f0200, 0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! { write32(code + 128 + u64(i * 4), op) }
	unsafe { *(&u64(code + 160)) = u64(voidptr(array_sequence_body)) }
	write32(code + 192, 0xdac10020); write32(code + 196, 0xd65f03c0)
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e1, 0x580000d0, 0xd63f0200, 0xaa0103f5, 0xa8c17bfd, 0xd65f03c0]! { write32(code + 224 + u64(i * 4), op) }
	unsafe { *(&u64(code + 256)) = u64(voidptr(array_sequence_predicate)) }
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e1, 0xaa0803e2, 0x580000b0,
		0xd63f0200, 0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! { write32(code + 288 + u64(i * 4), op) }
	unsafe { *(&u64(code + 320)) = u64(voidptr(array_sequence_transform)) }
}
fn array_sequence_call(api ArraySequenceApi, entry u64, args [5]u64, receiver u64, output u64) [3]u64 {
	mut capture := [u64(0), 0, 0]!
	invoke := unsafe { ArraySequenceInvoke(voidptr(api.code)) }
	invoke(entry, unsafe { &args[0] }, receiver, output, unsafe { &capture[0] })
	assert capture[2] == receiver
	return capture
}
fn array_sequence_type(api ArraySequenceApi, kind int) u64 {
	return if kind == 0 {api.int_type} else if kind == 1 {api.string_type} else {api.objc_type}
}
fn array_sequence_value(value u64, kind int, index u64, object u64) {
	if kind == 0 { assert read64(value) == index }
	else if kind == 1 { assert read64(value) == 0 && read64(value + 8) == object | 0x5000000000000000 }
	else { assert read64(value) == object }
}
fn array_sequence_lookup_worker(api ArraySequenceApi, metadata u64, table u64) {
	for _ in 0 .. 64 { assert api.lookup(api.descriptor, metadata, 0) == table }
}
struct ArraySequenceBodyContext {
	api ArraySequenceApi
	metadata u64
	table u64
	count u64
	kind int
	object u64
	error_owner u64
	string_result bool
	throws bool
mut:
	calls int
}
fn array_sequence_body(bytes u64, count u64, context u64, output u64) u64 {
	mut value := unsafe { &ArraySequenceBodyContext(context) }
	assert count == value.count
	stride := if value.kind == 1 {u64(16)} else {u64(8)}
	for i in u64(0) .. count { array_sequence_value(bytes + i * stride, value.kind, i, value.object) }
	assert array_sequence_object_refs(value.api, value.object) == 1 + if value.kind == 0 {i64(0)} else {i64(count)}
	worker := spawn array_sequence_lookup_worker(value.api, value.metadata, value.table); worker.wait()
	value.calls++
	if value.throws { array_sequence_object_keep(value.api, value.error_owner); return value.error_owner }
	if value.string_result {
		array_sequence_object_keep(value.api, value.object)
		unsafe { *(&SwiftStringWords(output)) = SwiftStringWords{second: value.object | 0x5000000000000000} }
	} else { unsafe { *(&u64(output)) = 100 + count } }
	return 0
}
fn array_sequence_predicate(input u64, context u64) SwiftSequenceResult {
	mut value := unsafe { &ArraySequenceBodyContext(context) }
	index := u64(value.calls); array_sequence_value(input, value.kind, index, value.object)
	assert array_sequence_object_refs(value.api, value.object) == 1 + if value.kind == 0 {i64(0)} else {i64(value.count + 1)}
	value.calls++
	if value.throws { array_sequence_object_keep(value.api, value.error_owner); return SwiftSequenceResult{error: value.error_owner} }
	return SwiftSequenceResult{array: if index == 1 {u64(1)} else {u64(0)}}
}
fn array_sequence_transform(input u64, context u64, output u64) u64 {
	mut value := unsafe { &ArraySequenceBodyContext(context) }
	index := u64(value.calls); array_sequence_value(input, value.kind, index, value.object)
	assert array_sequence_object_refs(value.api, value.object) == 1 + if value.kind == 0 {i64(0)} else {i64(value.count + 1)}
	value.calls++
	if value.throws { array_sequence_object_keep(value.api, value.error_owner); return value.error_owner }
	unsafe { *(&u64(output)) = if index % 2 == 0 {u64(0)} else {index * 3}; *(&u8(output + 8)) = if index % 2 == 0 {u8(1)} else {u8(0)} }
	get_tag := unsafe { SwiftSequenceTag(voidptr(read64(read64(value.api.int_type - 8) + 48))) }
	assert get_tag(output, 1, value.api.int_type) == if index % 2 == 0 {u32(1)} else {u32(0)}, 'transform index=${index} tag=${get_tag(output, 1, value.api.int_type)}'
	return 0
}
fn array_sequence_case(api ArraySequenceApi, kind int, count u64, guard u64) {
	element := array_sequence_type(api, kind); stride := if kind == 1 {u64(16)} else {u64(8)}
	metadata := api.access(0, element).metadata
	table := api.lookup(api.descriptor, metadata, guard)
	assert table != 0 && api.lookup(api.descriptor, metadata, 0) == table
	mut iterator_type := u64(0); mut iterator_table := u64(0)
	$if macos { if api.native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		associated := unsafe { ArraySequenceAssociated(C.dlsym(core, c'swift_getAssociatedTypeWitness')) }
		conformance := unsafe { ArraySequenceConformance(C.dlsym(core, c'swift_getAssociatedConformanceWitness')) }
		base := u64(C.dlsym(core, c'$sSTTL'))
		iterator_type = associated(0, table, metadata, base, u64(C.dlsym(core, c'$s8IteratorSTTl'))).metadata
		iterator_table = conformance(table, metadata, iterator_type, base, u64(C.dlsym(core, c'$sST8IteratorST_StTn')))
	} }
	if !api.native { iterator_type = read64(table + 24); iterator_table = read64(table + 8) }
	iterator_witness := read64(iterator_type - 8)
	assert read64(iterator_witness + 64) == 16 && read64(iterator_witness + 72) == 16
	object := array_sequence_object(api); error_owner := array_sequence_object(api)
	allocation := api.allocate(i64(count), element); owner := allocation.owner
	for i in u64(0) .. count {
		if kind != 0 { array_sequence_object_keep(api, object) }
		if kind == 0 { unsafe { *(&u64(allocation.bytes + i * stride)) = i } }
		else if kind == 1 { unsafe { *(&SwiftStringWords(allocation.bytes + i * stride)) = SwiftStringWords{second: object | 0x5000000000000000} } }
		else { unsafe { *(&u64(allocation.bytes + i * stride)) = object } }
	}
	mut source := owner; mut iterator := [u64(0), 0]!
	count_result := array_sequence_call(api, read64(table + 40), [metadata, table, 0, 0, 0]!, u64(unsafe { &source }), guard)
	assert count_result[0] == count && count_result[1] == 0
	contains := array_sequence_call(api, read64(table + 48), [guard, metadata, table, 0, 0]!, guard, guard)
	assert contains[0] == 2 && contains[1] == 0
	api.keep(owner)
	array_sequence_call(api, read64(table + 32), [metadata, table, 0, 0, 0]!, u64(unsafe { &source }), u64(unsafe { &iterator[0] }))
	assert iterator[0] == owner && iterator[1] == 0
	copy_value := unsafe { SwiftSequenceCopy(voidptr(read64(iterator_witness + 16))) }
	destroy_iterator := unsafe { SwiftSequenceDestroy(voidptr(read64(iterator_witness + 8))) }
	mut alias := [u64(0), 0]!
	copy_value(u64(unsafe { &alias[0] }), u64(unsafe { &iterator[0] }), iterator_type)
	assert alias == iterator
	assign_copy := unsafe { SwiftSequenceCopy(voidptr(read64(iterator_witness + 24))) }
	assign_copy(u64(unsafe { &alias[0] }), u64(unsafe { &alias[0] }), iterator_type)
	mut moved := [u64(0), 0]!
	take_value := unsafe { SwiftSequenceCopy(voidptr(read64(iterator_witness + 32))) }
	take_value(u64(unsafe { &moved[0] }), u64(unsafe { &alias[0] }), iterator_type)
	assign_take := unsafe { SwiftSequenceCopy(voidptr(read64(iterator_witness + 40))) }
	copy_value(u64(unsafe { &alias[0] }), u64(unsafe { &iterator[0] }), iterator_type)
	assign_take(u64(unsafe { &alias[0] }), u64(unsafe { &moved[0] }), iterator_type)
	iterator_tag := unsafe { SwiftSequenceTag(voidptr(read64(iterator_witness + 48))) }
	iterator_store := unsafe { SwiftArraySequenceStore(voidptr(read64(iterator_witness + 56))) }
	for empty_cases in [u32(1), 7, 0x7fffffff, 0x80000000, 0xffffffff]! {
		for which_case in [u32(0), 1, empty_cases]! {
			mut enum_value := [owner, u64(123), 0x7777777777777777, 0x8888888888888888]!
			iterator_store(u64(unsafe { &enum_value[0] }), which_case, empty_cases, iterator_type)
			assert iterator_tag(u64(unsafe { &enum_value[0] }), empty_cases, iterator_type) == which_case
			assert enum_value[3] == 0x8888888888888888
			if which_case == 0 { assert enum_value[0] == owner && enum_value[1] == 123 }
		}
	}
	mut optional := [u64(0), 0, 0, 0]!
	tag := unsafe { SwiftSequenceTag(voidptr(read64(read64(element - 8) + 48))) }
	destroy_element := unsafe { SwiftSequenceDestroy(voidptr(read64(read64(element - 8) + 8))) }
	for i in u64(0) .. count + 2 {
		array_sequence_call(api, read64(iterator_table + 16), [iterator_type, iterator_table, 0, 0, 0]!, u64(unsafe { &iterator[0] }), u64(unsafe { &optional[0] }))
		assert tag(u64(unsafe { &optional[0] }), 1, element) == if i >= count {u32(1)} else {u32(0)}
		if i < count { array_sequence_value(u64(unsafe { &optional[0] }), kind, i, object); destroy_element(u64(unsafe { &optional[0] }), element) }
		assert iterator[1] == if i < count {i + 1} else {count}
	}
	assert alias[1] == 0
	destroy_iterator(u64(unsafe { &alias[0] }), iterator_type); destroy_iterator(u64(unsafe { &iterator[0] }), iterator_type)
	api.keep(owner)
	contiguous := array_sequence_call(api, read64(table + 56), [metadata, table, 0, 0, 0]!, u64(unsafe { &source }), guard)
	assert contiguous[1] == 0 && read64(contiguous[0] + 16) == count
	for i in u64(0) .. count { array_sequence_value(contiguous[0] + 32 + i * stride, kind, i, object) }
	api.drop(contiguous[0])
	destination := u64(C.__builtin_alloca(usize((count + 2) * stride)))
	mut output_iterator := [u64(0), 0, 0x3131313131313131]!
	api.keep(owner)
	copied := array_sequence_call(api, read64(table + 64), [u64(unsafe { &output_iterator[0] }), destination, count + 2, metadata, table]!, u64(unsafe { &source }), guard)
	assert copied[0] == count && copied[1] == 0 && output_iterator[0] == owner && output_iterator[1] == count && output_iterator[2] == 0x3131313131313131
	for i in u64(0) .. count { array_sequence_value(destination + i * stride, kind, i, object); destroy_element(destination + i * stride, element) }
	destroy_iterator(u64(unsafe { &output_iterator[0] }), iterator_type)
	for string_result in [false, true]! { for throws in [false, true]! {
		mut context := ArraySequenceBodyContext{api: api, metadata: metadata, table: table, count: count, kind: kind, object: object, error_owner: error_owner, string_result: string_result, throws: throws}
		result_type := if string_result {api.string_type} else {api.int_type}
		mut result := [u64(0x7171717171717171), 0x7171717171717171, 0x7171717171717171, 0x7171717171717171]!
		mut body := api.code + 128
		$if macos { if api.native { sign := unsafe { ArraySequenceSign(voidptr(api.code + 192)) }; body = sign(body, 24507) } }
		observed := array_sequence_call(api, read64(table + 72), [body, u64(unsafe { &context }), result_type, metadata, table]!, u64(unsafe { &source }), u64(unsafe { &result[0] }))
		assert context.calls == 1
		if throws {
			assert observed[1] == error_owner && result.all(it == 0x7171717171717171)
			assert array_sequence_object_refs(api, error_owner) == 2
			array_sequence_object_drop(api, error_owner)
		} else {
			assert observed[1] == 0
			result_tag := unsafe { SwiftSequenceTag(voidptr(read64(read64(result_type - 8) + 48))) }
			assert result_tag(u64(unsafe { &result[0] }), 1, result_type) == 0
			if string_result { array_sequence_value(u64(unsafe { &result[0] }), 1, 0, object) } else { assert result[0] == 100 + count }
			destroy_result := unsafe { SwiftSequenceDestroy(voidptr(read64(read64(result_type - 8) + 8))) }
			destroy_result(u64(unsafe { &result[0] }), result_type)
		}
	} }
	for throws in [false, true]! {
		mut context := ArraySequenceBodyContext{api: api, metadata: metadata, table: table, count: count, kind: kind, object: object, error_owner: error_owner, throws: throws}
		mut predicate := api.code + 224; mut entry := u64(0)
		$if macos { if api.native {
			core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			entry = u64(C.dlsym(core, c'$sSTsE5first5where7ElementQzSgSbADKXE_tKF'))
			sign := unsafe { ArraySequenceSign(voidptr(api.code + 192)) }; predicate = sign(predicate, 8404)
		} }
		if !api.native { entry = swift_sequence_arena() + 256 }
		mut result := [u64(0x7171717171717171), 0x7171717171717171, 0x7171717171717171, 0x7171717171717171]!
		observed := array_sequence_call(api, entry, [predicate, u64(unsafe { &context }), metadata, table, 0]!, u64(unsafe { &source }), u64(unsafe { &result[0] }))
		if throws && count != 0 {
			assert observed[1] == error_owner && context.calls == 1 && result.all(it == 0x7171717171717171)
			array_sequence_object_drop(api, error_owner)
		} else {
			assert observed[1] == 0 && tag(u64(unsafe { &result[0] }), 1, element) == if count < 2 {u32(1)} else {u32(0)}
			if count >= 2 { assert context.calls == 2; array_sequence_value(u64(unsafe { &result[0] }), kind, 1, object); destroy_element(u64(unsafe { &result[0] }), element) }
			else { assert context.calls == int(count) }
		}
	}
	for throws in [false, true]! {
		mut context := ArraySequenceBodyContext{api: api, metadata: metadata, table: table, count: count, kind: kind, object: object, error_owner: error_owner, throws: throws}
		mut transform := api.code + 288; mut entry := u64(0)
		$if macos { if api.native {
			core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			entry = u64(C.dlsym(core, c'$sSTsE10compactMapySayqd__Gqd__Sg7ElementQzKXEKlF'))
			sign := unsafe { ArraySequenceSign(voidptr(api.code + 192)) }; transform = sign(transform, 55683)
		} }
		if !api.native { entry = swift_sequence_arena() }
		observed := array_sequence_call(api, entry, [transform, u64(unsafe { &context }), metadata, api.int_type, table]!, u64(unsafe { &source }), guard)
		if throws && count != 0 {
			assert observed[1] == error_owner && context.calls == 1
			array_sequence_object_drop(api, error_owner)
		} else {
			assert observed[1] == 0 && context.calls == int(count) && read64(observed[0] + 16) == count / 2, 'native=${api.native} kind=${kind} count=${count} calls=${context.calls} result=${read64(observed[0] + 16)} error=${observed[1].hex()}'
			for i in u64(0) .. count / 2 { assert read64(observed[0] + 32 + i * 8) == (i * 2 + 1) * 3 }
			api.drop(observed[0])
		}
	}
	api.drop(owner)
	assert array_sequence_object_refs(api, object) == 1 && array_sequence_object_refs(api, error_owner) == 1
	array_sequence_object_drop(api, object); array_sequence_object_drop(api, error_owner)
}
fn array_sequence_run(api ArraySequenceApi, guard u64) {
	for kind in 0 .. 3 { for count in [u64(0), 1, 5, 33]! { array_sequence_case(api, kind, count, guard) } }
}
fn array_sequence_first_lookup(descriptor u64, metadata u64, guard u64) u64 {
	return swift_witness_table(descriptor, metadata, guard)
}
fn array_sequence_rejections(api ArraySequenceApi, guard u64) {
	for metadata in [u64(0), 1, guard, api.int_type]! {
		if _ := swift_witness_table_checked(api.descriptor, metadata, guard) { assert false }
	}
	element := swift_objc_metadata(ios_runtime.names['NSObject'])
	metadata := swift_array_access(0, element).metadata
	mut readers := []thread u64{}
	for _ in 0 .. 4 { readers << spawn array_sequence_first_lookup(api.descriptor, metadata, guard) }
	results := readers.wait(); assert results.all(it == results[0])
	table := results[0]; iterator_type := read64(table + 24); iterator_table := read64(table + 8)
	assert swift_witness_table(read64(iterator_table), iterator_type, guard) == iterator_table
	if _ := swift_witness_table_checked(read64(iterator_table), metadata, guard) { assert false }
	mut instantiated := [10]u64{}
	control := api.descriptor + 16
	assert read32(control) == 0x1000a
	instantiate := unsafe { ArraySequenceInstantiate(voidptr(u64(i64(control + 4) + i64(i32(read32(control + 4)))))) }
	instantiate(u64(unsafe { &instantiated[0] }), metadata, guard)
	for i in 0 .. 10 { assert instantiated[i] == read64(table + u64(i * 8)) }
	mut instantiated_iterator := [3]u64{}
	iterator_control := read64(iterator_table) + 16
	assert read32(iterator_control) == 0x10003
	instantiate_iterator := unsafe { ArraySequenceInstantiate(voidptr(u64(i64(iterator_control + 4) + i64(i32(read32(iterator_control + 4)))))) }
	instantiate_iterator(u64(unsafe { &instantiated_iterator[0] }), iterator_type, guard)
	for i in 0 .. 3 { assert instantiated_iterator[i] == read64(iterator_table + u64(i * 8)) }
	mut counterfeit := [u64(0), 0, 0, 0]!
	write32(u64(unsafe { &counterfeit[0] }) + 12, 0x20000)
	if _ := swift_witness_table_checked(u64(unsafe { &counterfeit[0] }), metadata, guard) { assert false }
	mut invalid_owner := u64(0)
	if _ := swift_array_sequence_view_checked(metadata, u64(unsafe { &invalid_owner }), false) { assert false }
	mut readonly_result := [u64(0x5151515151515151), 0x5151515151515151]!
	owner := swift_array_allocate(1, api.int_type).owner
	mut source := owner
	int_metadata := swift_array_access(0, api.int_type).metadata
	if _ := swift_array_sequence_contents_checked(u64(unsafe { &readonly_result[0] }), guard, 0, int_metadata, u64(unsafe { &source })) { assert false }
	assert readonly_result[0] == 0x5151515151515151 && readonly_result[1] == 0x5151515151515151
	unsafe { *(&u64(owner + 16)) = 0 }; swift_release(owner)
	ios_runtime.swift_concurrency_retired = true
	if _ := swift_array_sequence_table_checked(metadata) { assert false }
	ios_runtime.swift_concurrency_retired = false
}
fn test_swift_array_sequence() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe {nil}, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1); guard := code + u64(page)
	array_sequence_emit(code); C.__builtin___clear_cache(unsafe {voidptr(code)}, unsafe {voidptr(code + 328)})
	assert C.mprotect(unsafe {voidptr(code)}, page, C.PROT_READ | C.PROT_EXEC) == 0
	assert C.mprotect(unsafe {voidptr(guard)}, page, C.PROT_NONE) == 0
	$if macos { array_sequence_run(array_sequence_api(true, code), guard); println('IOS-ARRAY-SEQUENCE-NATIVE: 12 Int/String/ObjC Array fixtures, all six Sequence operations, Iterator value witnesses and repeated exhaustion, explicit indirect copyContents, contiguous callbacks, first(where:) and compactMap integration, owned results, reentrant lookup and x21 throws') }
	for _ in 0 .. 2 {
		objc_start(); api := array_sequence_api(false, code); array_sequence_run(api, guard); array_sequence_rejections(api, guard)
		assert ios_runtime.swift_arrays.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0
		arena := ios_runtime.swift_array_sequence_arena
		metadata_base := ios_runtime.swift_array_sequence_metadata[api.int_type] or {panic('missing Int iterator')}
		objc_stop(); assert ios_runtime.swift_array_sequence_arena == 0 && ios_runtime.swift_array_sequence_metadata.len == 0
		for retired in [arena, metadata_base]! {
			$if macos { assert C.mprotect(unsafe {voidptr(retired)}, page, C.PROT_READ) == -1 }
			$else { mut resident := u8(0); assert C.mincore(unsafe {voidptr(retired)}, page, &resident) == -1 }
		}
	}
	assert C.munmap(unsafe {voidptr(code)}, page * 2) == 0
	println('IOS-ARRAY-SEQUENCE: canonical generic specialization and instantiation callbacks, complete direct associated witnesses, owned iterator and Element copies, all Sequence methods and helper integration, original errors, concurrent first lookup, guarded/forged/retired rejection, no locks across callbacks and two drained/unmapped lifetimes')
}
