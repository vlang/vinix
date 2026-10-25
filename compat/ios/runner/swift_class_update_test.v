// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

#include <dlfcn.h>
$if macos {
	#include <objc/runtime.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.sel_registerName(&char) voidptr

type CuEntry = fn (u64, u64, u64, u64, u64) SwiftAssociatedMetadata
type CuProbe = fn (u64, u64, u64, u64, u64, u64, &u64)
type CuRealize = fn (u64, u64) u64
type CsGet = fn (u64, u64) SwiftAssociatedMetadata
struct CuField { size u64 stride u64 flags u32 extra u32 }
struct CuInput { base u64 page u64 metadata u64 ro u64 descriptor u64 types u64 list u64 cells u64 count int }
__global cu_sequence = u64(0)
__global cu_initializations = i64(0)
__global cu_metadata_initializations = i64(0)
fn cu_initialize(_cls u64, _selector &char) { C.ios_ref_change(unsafe { &cu_initializations }, 1) }
fn cu_metadata_initialize(cls u64, _argument u64) u64 {
	C.ios_ref_change(unsafe { &cu_metadata_initializations }, 1)
	return cls
}
fn cu_write(address u64, value u64) { unsafe { *(&u64(address)) = value } }

fn cu_input(fields []CuField, native bool, start u32, matching_sizes bool) CuInput {
	return cu_input_kind(fields, native, start, matching_sizes, true)
}
fn cu_input_kind(fields []CuField, native bool, start u32, matching_sizes bool, registered bool) CuInput {
	page := u64(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, usize(page * 6), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != ~u64(0)
	b := base + page
	assert C.mprotect(voidptr(b), usize(page * 4), C.PROT_READ | C.PROT_WRITE) == 0
	m := b + 32; meta := b + 1024; ro := b + 1280; mr := b + 1408; d := b + 1536
	list := if fields.len == 0 { u64(0) } else { b + 5120 }
	types := b + 4096; cells := b + 7680
	mut parent := b + 12288
	mut parent_meta := b + 12544
	$if macos { if native { parent = u64(C.objc_getClass(c'_TtCs12_SwiftObject')); parent_meta = u64(C.object_getClass(voidptr(parent))); assert parent != 0 } }
	cu_write(m, meta); cu_write(m + 8, parent); cu_write(m + 32, ro | 2)
	write32(m + 40, 2); write32(m + 48, start); write32(m + 52, 7)
	write32(m + 56, u32(96 + fields.len * 8)); write32(m + 60, 16); cu_write(m + 64, d)
	cu_write(meta, if native { read64(parent_meta) } else { parent_meta }); cu_write(meta + 8, parent_meta); cu_write(meta + 32, mr | 2)
	write32(ro, 0x80); write32(ro + 4, start); write32(ro + 8, start); cu_write(ro + 48, list)
	write32(mr, 0x81)
	cu_sequence++
	name := 'VinixSwiftClassUpdate${cu_sequence}'
	C.memcpy(voidptr(b + 11008), name.str, usize(name.len + 1)); unsafe { name.free() }
	cu_write(ro + 24, b + 11008); cu_write(mr + 24, b + 11008)
	write32(b + 11200, 64) // Image-owned, NUL-terminated "@" ivar encoding.
	C.memcpy(voidptr(b + 11328), c'initialize', 11)
	C.memcpy(voidptr(b + 11360), c'v16@0:8', 8)
	// An absolute Objective-C method list proves class realization does not
	// send +initialize. The shim uses the same IMP in its separate registry.
	methods := b + 11520; write32(methods, 24); write32(methods + 4, 1)
	mut selector := b + 11328
	$if macos { if native { selector = u64(C.sel_registerName(c'initialize')) } }
	cu_write(methods + 8, selector); cu_write(methods + 16, b + 11360); cu_write(methods + 24, u64(unsafe { voidptr(cu_initialize) })); cu_write(mr + 32, methods)
	write32(d, 0x10010); write32(d + 24, 2); write32(d + 28, u32(10 + fields.len))
	write32(d + 32, u32(fields.len)); write32(d + 36, u32(fields.len)); write32(d + 40, 10)
	cu_write(m + 80 + u64(fields.len * 8), 0xcafef00dfeedface)
	cu_write(cells + u64(fields.len * 8), 0x12345678abcdef01)
	if list != 0 { write32(list, 32); write32(list + 4, u32(fields.len)) }
	if !native {
		cu_write(parent, parent_meta)
		ios_runtime.classes[parent] = &ObjClass{name: '_TtCs12_SwiftObject', size: 16}
		ios_runtime.classes[parent_meta] = &ObjClass{name: '_TtCs12_SwiftObject', meta: true}
	}
	if !native && registered {
		ios_runtime.classes[meta] = &ObjClass{name: 'ClassUpdateFixture', parent: parent_meta, meta: true}
		ios_runtime.classes[m] = &ObjClass{name: 'ClassUpdateFixture', parent: parent, size: start}
		objc_record_method(meta, c'initialize', u64(unsafe { voidptr(cu_initialize) }), c'v16@0:8', false)
	}
	for i, f in fields {
		layout := b + 2048 + u64(i * 24); entry := list + 8 + u64(i * 32)
		cu_write(types + u64(i * 8), layout); cu_write(layout, f.size); cu_write(layout + 8, f.stride)
		write32(layout + 16, f.flags); write32(layout + 20, f.extra)
		cu_write(m + 80 + u64(i * 8), if f.size == 0 { u64(0) } else { u64(0xfeeddeed00000001) })
		cu_write(cells + u64(i * 8), 0xffffffff00000001)
		field_name := 'field${i}'
		C.memcpy(voidptr(b + 8448 + u64(i * 32)), field_name.str, usize(field_name.len + 1))
		cu_write(entry, cells + u64(i * 8)); cu_write(entry + 8, b + 8448 + u64(i * 32)); cu_write(entry + 16, b + 11200)
		write32(entry + 24, 3); write32(entry + 28, if matching_sizes { u32(f.size) } else { u32(99) })
		if !native && registered { ios_runtime.classes[m].ivars[field_name] = &ObjIvar{name: field_name.clone(), types: '@'.clone(), offset: 1, size: if matching_sizes { f.size } else { u64(99) }} }
		unsafe { field_name.free() }
	}
	return CuInput{base, page, m, ro, d, types, list, cells, fields.len}
}
fn cu_free(input CuInput) { assert C.munmap(voidptr(input.base), usize(input.page * 6)) == 0 }
fn cu_call(input CuInput, entry u64, probe CuProbe) {
	mut output := [u64(0xcafe), ~u64(0), ~u64(0), 0, 0, 0xbeef]!
	probe(input.metadata, 0x100, u64(input.count), input.types, input.metadata + 80, entry, unsafe { &output[1] })
	assert output[0] == 0xcafe && output[5] == 0xbeef && output[1] == 0 && output[3] == 0x5020 && output[4] == 0x5021
	// Native leaves the state register unspecified when dependency metadata is nil.
}
fn cu_check(input CuInput, positions []u64, size u32, mask u32, fields []CuField, native bool, matching_sizes bool, initialize bool) {
	m := input.metadata; list := read64(input.ro + 48)
	assert read32(m + 44) == 0 && read32(m + 48) == size && read32(m + 52) == mask
	assert read32(input.ro + 8) == size && read32(m + 56) == read32(m + 60) + read32(input.descriptor + 28) * 8 && read64(m + 64) == input.descriptor
	assert read64(m + 80 + u64(fields.len * 8)) == 0xcafef00dfeedface
	assert read64(input.cells + u64(fields.len * 8)) == 0x12345678abcdef01
	assert (list == input.list) == (matching_sizes || fields.len == 0)
	for i, position in positions {
		entry := list + 8 + u64(i * 32)
		assert read64(m + 80 + u64(i * 8)) == position && read64(input.cells + u64(i * 8)) == position
		assert read32(entry + 28) == fields[i].size
		if matching_sizes { assert read64(entry + 16) == input.base + input.page + 11200 && read32(entry + 24) == 3 }
		else {
			assert read64(entry + 16) == 0
			assert u32(1) << read32(entry + 24) == (fields[i].flags & 255) + 1
			// A copied table does not mutate borrowed image ivar records.
			assert read32(input.list + 8 + u64(i * 32) + 28) == 99
			assert read64(input.list + 8 + u64(i * 32) + 16) == input.base + input.page + 11200
		}
		if !native {
			name := 'field${i}'; ivar := ios_runtime.classes[m].ivars[name]
			assert ivar.offset == i64(position) && ivar.size == fields[i].size && ivar.types == if matching_sizes { '@' } else { '' }
			unsafe { name.free() }
		}
	}
	// Objective-C reports pointer-rounded allocation size; Swift retains the
	// unrounded field layout size in the class header and read-only data.
	$if macos { if native {
		if initialize {
			// swift_initClassMetadata2 uses objc_readClassPair. These synthetic
			// classes have no registered Mach-O image, so explicitly realize them
			// only after checking the initializer's layout and normalized bit.
			// This step is fixture setup, not evidence of image registration.
			assert read64(m + 32) & 7 == 2
			objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
			realize := u64(C.dlsym(objc, c'_objc_realizeClassFromSwift')); assert realize != 0
			assert unsafe { CuRealize(voidptr(realize))(m, m) } == m
		}
		assert C.class_getInstanceSize(voidptr(m)) == usize((size + 7) & ~u32(7))
	} }
	if !native { assert ios_runtime.classes[m].size == size && ios_runtime.classes[m].swift_layout_complete && !ios_runtime.classes[m].initialized }
	assert cu_initializations == 0 && cu_metadata_initializations == 0
}
fn cu_headers(entry u64, probe CuProbe, native bool, initialize bool) []CuInput {
	mut fixtures := []CuInput{}
	fields := [CuField{8, 8, 0x10007, 0}, CuField{8, 8, 7, 0}]
	for address_point in [u32(16), 24]! {
		for unique in [u32(0), 0x40]! {
			for initializer in [u32(0), 0x40]! {
				for vtable in [u32(0), 0x80000000]! {
					input := cu_input(fields, native, 16, false)
					m := input.metadata; d := input.descriptor
					positive := u32(12) + if vtable == 0 { u32(0) } else { u32(1) }
					write32(m + 56, address_point + positive * 8); write32(m + 60, address_point)
					write32(d, 0x10010 | unique | vtable); write32(d + 24, address_point / 8); write32(d + 28, positive)
					write32(input.ro, 0x80 | initializer)
					cu_write(input.ro + 72, u64(unsafe { voidptr(cu_metadata_initialize) }))
					for i in 1 .. 4 { cu_write(m - u64(i * 8), 0x12340000 + u64(i)) }
					cu_call(input, entry, probe)
					cu_check(input, [u64(16), 24], 32, 7, fields, native, false, initialize)
					assert read32(m + 56) == address_point + positive * 8 && read32(m + 60) == address_point
					assert read32(d) == 0x10010 | unique | vtable && read32(d + 24) == address_point / 8 && read32(d + 28) == positive
					assert read64(input.ro + 72) == u64(unsafe { voidptr(cu_metadata_initialize) })
					for i in 1 .. 4 { assert read64(m - u64(i * 8)) == 0x12340000 + u64(i) }
					fixtures << input
				}
			}
		}
	}
	return fixtures
}
fn cu_case(entry u64, probe CuProbe, native bool, fields []CuField, positions []u64, size u32, mask u32, start u32, matching bool, initialize bool) CuInput {
	input := cu_input(fields, native, start, matching)
	cu_call(input, entry, probe)
	cu_check(input, positions, size, mask, fields, native, matching, initialize)
	return input
}
fn cu_matrix(entry u64, probe CuProbe, native bool, initialize bool) []CuInput {
	mut fixtures := []CuInput{}
	fixtures << cu_case(entry, probe, native, []CuField{}, []u64{}, 16, 7, 16, true, initialize)
	for matching in [false, true]! {
		// Same two-field pointer-layout shape as the observed URL/NativeObject call.
		fixtures << cu_case(entry, probe, native, [CuField{8, 8, 0x10007, 0}, CuField{8, 8, 7, 0}], [u64(16), 24], 32, 7, 16, matching, initialize)
	}
	fixtures << cu_case(entry, probe, native, [CuField{1, 1, 0, 0}, CuField{8, 8, 7, 0}, CuField{2, 2, 1, 0}], [u64(16), 24, 32], 34, 7, 16, false, initialize)
	fixtures << cu_case(entry, probe, native, [CuField{3, 4, 3, 0}, CuField{1, 1, 0, 0}], [u64(16), 19], 20, 7, 16, false, initialize)
	fixtures << cu_case(entry, probe, native, [CuField{8, 32, 31, 0}], [u64(32)], 40, 31, 16, false, initialize)
	fixtures << cu_case(entry, probe, native, [CuField{0, 256, 255, 0}, CuField{8, 8, 7, 0}], [u64(0), 16], 24, 7, 16, false, initialize)
	fixtures << cu_case(entry, probe, native, [CuField{1, 1, 0, 0}, CuField{8, 8, 0x110007, 0x7fffffff}], [u64(48), 56], 64, 7, 48, false, initialize)
	mut many := []CuField{}; mut positions := []u64{}
	for i in 0 .. 64 { many << CuField{1, 1, 0, 0}; positions << u64(16 + i) }
	fixtures << cu_case(entry, probe, native, many, positions, 80, 7, 16, false, initialize)
	// A copied table preserves the encoding and alignment of unchanged entries.
	mixed := cu_input([CuField{8, 8, 7, 0}, CuField{1, 1, 0, 0}], native, 16, false)
	write32(mixed.list + 8 + 28, 8)
	if !native { ios_runtime.classes[mixed.metadata].ivars['field0'].size = 8 }
	cu_call(mixed, entry, probe)
	updated := read64(mixed.ro + 48)
	assert updated != mixed.list
	assert read64(updated + 8 + 16) == mixed.base + mixed.page + 11200 && read32(updated + 8 + 24) == 3
	assert read64(updated + 40 + 16) == 0 && read32(updated + 40 + 24) == 0 && read32(updated + 40 + 28) == 1
	assert read64(mixed.metadata + 80) == 16 && read64(mixed.metadata + 88) == 24 && read32(mixed.metadata + 48) == 25
	assert read32(mixed.list + 40 + 28) == 99 && read64(mixed.list + 40 + 16) == mixed.base + mixed.page + 11200
	if !native { assert ios_runtime.classes[mixed.metadata].ivars['field0'].types == '@' && ios_runtime.classes[mixed.metadata].ivars['field1'].types == '' }
	fixtures << mixed
	unsafe { many.free(); positions.free() }
	return fixtures
}
fn cu_reject(metadata u64, flags u64, count u64, types u64, offsets u64) {
	if _ := swift_class_update_checked(metadata, flags, count, types, offsets) { assert false, 'unsupported class update accepted' }
}
fn ci_reject(metadata u64, flags u64, count u64, types u64, offsets u64) {
	if _ := swift_class_initialize_checked(metadata, flags, count, types, offsets) { assert false, 'unsupported class initialization accepted' }
}
fn cu_bad_kind(input CuInput, initialize bool) {
	copy := C.malloc(usize(input.page * 4)); assert copy != unsafe { nil }
	C.memcpy(copy, voidptr(input.base + input.page), usize(input.page * 4))
	if initialize { ci_reject(input.metadata, 0x100, u64(input.count), input.types, input.metadata + 80) }
	else { cu_reject(input.metadata, 0x100, u64(input.count), input.types, input.metadata + 80) }
	assert C.memcmp(copy, voidptr(input.base + input.page), usize(input.page * 4)) == 0
	C.free(copy)
}
fn cu_bad(input CuInput) { cu_bad_kind(input, false) }
fn ci_invalid(guard u64) CuInput {
	for flags in [u64(0), 1, 0x101, 0x200, ~u64(0)]! { ci_reject(guard, flags, 1, guard, guard) }
	ci_reject(guard, 0x100, 65, guard, guard)
	for pointer in [u64(0), 1, ~u64(7), guard]! { ci_reject(pointer, 0x100, 0, guard, guard) }
	input := cu_input([CuField{8, 8, 7, 0}], false, 16, false)
	m := input.metadata; d := input.descriptor; layout := read64(input.types)
	parent := read64(m + 8)
	cu_write(m + 8, 0); cu_write(m + 32, input.ro | 1)
	// A late invalid field must not partially normalize either class header.
	for field in [CuField{8, 0, 7, 0}, CuField{8, 8, 2, 0}, CuField{8, 8, 0x400007, 0}, CuField{8, 8, 7, 0x80000000}]! {
		cu_write(layout + 8, field.stride); write32(layout + 16, field.flags); write32(layout + 20, field.extra); cu_bad_kind(input, true)
	}
	cu_write(layout + 8, 8); write32(layout + 16, 7); write32(layout + 20, 0)
	for pair in [[d, u64(0x10090)]!, [d, u64(0x20010010)]!, [d + 20, u64(4)]!, [d + 24, u64(3)]!, [d + 28, u64(12)]!, [d + 36, u64(2)]!, [d + 40, u64(11)]!, [input.ro, u64(0x180)]!, [input.list, u64(24)]!, [input.list + 4, u64(2)]!]! {
		old := read32(pair[0]); write32(pair[0], u32(pair[1])); cu_bad_kind(input, true); write32(pair[0], old)
	}
	for bits in [u64(0), 3, 6]! { cu_write(m + 32, input.ro | bits); cu_bad_kind(input, true) }; cu_write(m + 32, input.ro | 1)
	cu_write(m + 8, guard); cu_bad_kind(input, true); cu_write(m + 8, 0)
	mut info := ios_runtime.classes[m]
	info.initialized = true; cu_bad_kind(input, true); info.initialized = false
	info.instances = 1; cu_bad_kind(input, true); info.instances = 0
	info.initializing = true; cu_bad_kind(input, true); info.initializing = false
	info.dynamic = true; cu_bad_kind(input, true); info.dynamic = false
	info.meta = true; cu_bad_kind(input, true); info.meta = false
	info.parent = guard; cu_bad_kind(input, true); info.parent = parent
	ios_runtime.swift_concurrency_retired = true; ci_reject(guard, 0x100, 0, guard, guard); ios_runtime.swift_concurrency_retired = false
	ios_runtime.swift_generic_metadata_retired = true; ci_reject(guard, 0x100, 0, guard, guard); ios_runtime.swift_generic_metadata_retired = false
	ios_runtime.swift_generic_value_retired = true; ci_reject(guard, 0x100, 0, guard, guard); ios_runtime.swift_generic_value_retired = false
	assert info.swift_ivar_list == 0 && !info.swift_layout_complete && info.size == 16
	assert info.ivars['field0'].offset == 1 && info.ivars['field0'].size == 99 && info.ivars['field0'].types == '@'
	return input
}
fn cu_invalid(guard u64) CuInput {
	input := cu_input([CuField{8, 8, 7, 0}], false, 16, false)
	m := input.metadata; d := input.descriptor; layout := read64(input.types)
	for flags in [u64(0), 1, 0x101, 0x200, ~u64(0)]! { cu_reject(guard, flags, 1, guard, guard) }
	cu_reject(guard, 0x100, 65, guard, guard)
	for pointer in [u64(0), 1, ~u64(7), guard]! { cu_reject(pointer, 0x100, 0, guard, guard) }
	for pointer in [u64(0), 1, ~u64(7)]! {
		cu_reject(m, 0x100, 1, pointer, m + 80)
		cu_reject(m, 0x100, 1, input.types, pointer)
		cu_write(input.types, pointer); cu_bad(input); cu_write(input.types, layout)
	}
	for pair in [[d, u64(0x10090)]!, [d, u64(0x20010010)]!, [d, u64(0x10030)]!, [d + 20, u64(4)]!, [d + 24, u64(3)]!, [d + 28, u64(12)]!, [d + 36, u64(2)]!, [d + 40, u64(11)]!, [m + 44, u64(8)]!, [m + 56, u64(96)]!, [m + 60, u64(24)]!, [m + 60, u64(32)]!, [input.ro, u64(0x40)]!, [input.ro, u64(0x180)]!, [input.list, u64(24)]!, [input.list + 4, u64(2)]!]! {
		old := read32(pair[0]); write32(pair[0], u32(pair[1])); cu_bad(input); write32(pair[0], old)
	}
	for bits in [u64(0), 1, 3, 6]! { cu_write(m + 32, input.ro | bits); cu_bad(input) }; cu_write(m + 32, input.ro | 2)
	// The extra negative word must agree with both the total class size and
	// descriptor extent, even when all observed FileStorage flags are present.
	write32(d, 0x80010050); write32(d + 24, 3); write32(m + 60, 24); write32(input.ro, 0xc0)
	cu_bad(input)
	write32(m + 56, 120); cu_bad(input)
	write32(m + 56, 104); write32(m + 60, 16); write32(d, 0x10010); write32(d + 24, 2); write32(input.ro, 0x80)
	for field in [CuField{1048577, 1048584, 7, 0}, CuField{8, 0, 7, 0}, CuField{8, 7, 7, 0}, CuField{8, 9, 7, 0}, CuField{8, 8, 2, 0}, CuField{8, 8, 0x400007, 0}, CuField{8, 8, 7, 0x80000000}, CuField{1048576, 1048576, 7, 0}]! {
		cu_write(layout, field.size); cu_write(layout + 8, field.stride); write32(layout + 16, field.flags); write32(layout + 20, field.extra); cu_bad(input)
	}
	cu_write(layout, 8); cu_write(layout + 8, 8); write32(layout + 16, 7); write32(layout + 20, 0)
	mut info := ios_runtime.classes[m]
	info.initialized = true; cu_bad(input); info.initialized = false
	info.instances = 1; cu_bad(input); info.instances = 0
	info.dynamic = true; cu_bad(input); info.dynamic = false
	info.meta = true; cu_bad(input); info.meta = false
	parent := info.parent; info.parent = guard; cu_bad(input); info.parent = parent
	ios_runtime.swift_concurrency_retired = true; cu_reject(guard, 0x100, 0, guard, guard); ios_runtime.swift_concurrency_retired = false
	ios_runtime.swift_generic_metadata_retired = true; cu_reject(guard, 0x100, 0, guard, guard); ios_runtime.swift_generic_metadata_retired = false
	ios_runtime.swift_generic_value_retired = true; cu_reject(guard, 0x100, 0, guard, guard); ios_runtime.swift_generic_value_retired = false
	assert info.swift_ivar_list == 0 && !info.swift_layout_complete && info.size == 16
	return input
}
fn cu_worker(input CuInput, entry u64) {
	for _ in 0 .. 64 { result := unsafe { CuEntry(voidptr(entry))(input.metadata, 0x100, u64(input.count), input.types, input.metadata + 80) }; assert result.metadata == 0 && result.state == 0 }
}
fn cu_repeat(entry u64, probe CuProbe, initialize bool) CuInput {
	input := cu_input([CuField{8, 8, 7, 0}], false, 16, false)
	if initialize { cu_write(input.metadata + 8, 0); cu_write(input.metadata + 32, input.ro | 1) }
	cu_call(input, entry, probe)
	list := read64(input.ro + 48)
	// Changing an already-published layout must fail without writing or replacing
	// its owned ivar table. Identical calls need no allocations or image writes.
	layout := read64(input.types); cu_write(layout, 16); cu_write(layout + 8, 16); cu_bad_kind(input, initialize); cu_write(layout, 8); cu_write(layout + 8, 8)
	assert C.mprotect(voidptr(input.base + input.page), usize(input.page * 4), C.PROT_READ) == 0
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn cu_worker(input, entry) }; workers.wait(); unsafe { workers.free() }
	assert read64(input.ro + 48) == list && ios_runtime.classes[input.metadata].swift_ivar_list == list
	return input
}
fn ci_matrix(entry u64, probe CuProbe, native bool) []CuInput {
	mut fixtures := []CuInput{}
	fields := [CuField{8, 8, 0x10007, 0}, CuField{8, 8, 7, 0}]
	for bits in [u64(1), 2]! {
		for implicit_superclass in [false, true]! {
			input := cu_input(fields, native, 16, false)
			m := input.metadata; d := input.descriptor
			// FileStorage's unique descriptor, extra negative word and static
			// vtable coexist with an Objective-C metadata initializer callback.
			write32(d, 0x80010050); write32(d + 24, 3); write32(d + 28, 13)
			write32(m + 56, 128); write32(m + 60, 24); write32(input.ro, 0xc0)
			cu_write(input.ro + 72, u64(unsafe { voidptr(cu_metadata_initialize) }))
			parent := read64(m + 8)
			if implicit_superclass { cu_write(m + 8, 0) }
			cu_write(m + 32, input.ro | bits)
			for i in 1 .. 4 { cu_write(m - u64(i * 8), 0x12340000 + u64(i)) }
			cu_call(input, entry, probe)
			assert read64(m + 8) == parent && read64(m + 32) & 7 == 2
			cu_check(input, [u64(16), 24], 32, 7, fields, native, false, true)
			assert read64(m + 8) == parent && read64(m + 32) & 7 == 2
			assert read32(d) == 0x80010050 && read32(m + 60) == 24
			assert read64(input.ro + 72) == u64(unsafe { voidptr(cu_metadata_initialize) })
			for i in 1 .. 4 { assert read64(m - u64(i * 8)) == 0x12340000 + u64(i) }
			fixtures << input
		}
	}
	fixtures << cu_matrix(entry, probe, native, true)
	fixtures << cu_headers(entry, probe, native, true)
	return fixtures
}
// Singleton records follow the 44-byte class descriptor, before its vtable.
// These fixtures share the observed FileStorage header and two pointer fields.
fn cs_trace(input CuInput) u64 { return input.base + input.page + 11776 }
fn cs_cache(input CuInput) u64 { return input.base + input.page + 1792 }
fn cs_lookup() u64 { return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_getSingletonMetadata') or { panic(err) } }
fn cs_complete(m u64, context u64, pattern u64) SwiftAssociatedMetadata {
	assert pattern == 0
	for i in 0 .. 4 { assert read64(context + u64(i * 8)) == 0; cu_write(context + u64(i * 8), u64(0x3100 + i)) }
	d := read64(m + 64) & 0x0000ffffffffffff
	t := u64(i64(d + 16) + i64(i32(read32(d + 16))))
	assert C.ios_ref_change(unsafe { &i64(t) }, 1) == 0
	assert read64(m + 32) & 7 == 2 && read64(m - 8) == read64(t + 8)
	assert C.ios_load_pointer(unsafe { &u64(read64(t + 32)) }) == 0
	if read64(t + 64) != 0 { C.pthread_mutex_lock(voidptr(t + 128)); C.pthread_mutex_unlock(voidptr(t + 128)) }
	if read64(t + 40) == 0 {
		// Completion runs without the registry lock, can resolve runtime symbols,
		// inspect partial metadata and initialize a different singleton.
		worker := spawn cs_lookup(); assert worker.wait() == read64(t + 48)
		partial := unsafe { CsGet(voidptr(read64(t + 48)))(0x1ff, d) }
		assert partial.metadata == m && partial.state == 0x3f
		if _ := swift_singleton_metadata_checked(0, d) { assert false }
		if read64(t + 80) != 0 {
			nested := unsafe { CsGet(voidptr(read64(t + 48)))(0, read64(t + 80)) }; assert nested.metadata != 0 && nested.state == 0
		}
	}
	if read64(t + 56) != 1 {
		result := unsafe { CuEntry(voidptr(read64(t + 16)))(m, 0x100, 2, read64(t + 24), m + 80) }; assert result.metadata == 0
	}
	match read64(t + 56) {
		2 { cu_write(m - 8, 0) }
		3 { cu_write(m + 80, 999) }
		4 { write32(m + 48, 999) }
		else {}
	}
	return SwiftAssociatedMetadata{read64(t + 72), ~u64(0)}
}
fn cs_input(native bool, get u64, initialize u64, code u64) CuInput {
	return cs_input_kind(native, get, initialize, code, true)
}
fn cs_input_kind(native bool, get u64, initialize u64, code u64, registered bool) CuInput {
	input := cu_input_kind([CuField{8, 8, 0x10007, 0}, CuField{8, 8, 7, 0}], native, 16, false, registered)
	m := input.metadata; d := input.descriptor; t := cs_trace(input)
	write32(d, 0x80010050); write32(d + 24, 3); write32(d + 28, 13)
	write32(m + 56, 128); write32(m + 60, 24); write32(input.ro, 0xc0)
	cu_write(input.ro + 72, u64(unsafe { voidptr(cu_metadata_initialize) }))
	cu_write(m + 32, input.ro | 1); cu_write(m + 8, 0)
	for i in 1 .. 4 { cu_write(m - u64(i * 8), 0x12340000 + u64(i)) }
	swift_protocol_relative(d + 16, t)
	swift_protocol_relative(d + 44, cs_cache(input)); swift_protocol_relative(d + 48, m); swift_protocol_relative(d + 52, code + 256)
	write32(d + 56, 12); write32(d + 60, 0) // Empty trailing vtable.
	mut witness := u64(0)
	$if macos { if native { core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2); witness = u64(C.dlsym(core, c'$sBoWV')) } }
	if !native { witness = swift_native_value_witnesses() }
	assert witness != 0
	cu_write(t + 8, witness); cu_write(t + 16, initialize); cu_write(t + 24, input.types); cu_write(t + 32, cs_cache(input)); cu_write(t + 40, u64(native)); cu_write(t + 48, get)
	assert C.ios_mutex_create(voidptr(t + 128), 0) == 0
	return input
}
fn cs_call(input CuInput, get u64, probe CuProbe, request u64) {
	mut words := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	probe(request, input.descriptor, 0, 0, 0, get, unsafe { &words[1] })
	assert words[0] == 0xcafe && words[5] == 0xbeef && words[1] == input.metadata && words[2] == 0 && words[3] == 0x5020 && words[4] == 0x5021
	assert C.ios_load_pointer(unsafe { &u64(cs_cache(input)) }) == input.metadata && read64(cs_trace(input)) == 1
}
fn cs_worker(input CuInput, get u64) u64 {
	result := unsafe { CsGet(voidptr(get))(0, input.descriptor) }; assert result.metadata == input.metadata && result.state == 0; return result.metadata
}
fn cs_bad(input CuInput) { if _ := swift_singleton_metadata_checked(0, input.descriptor) { assert false, 'unsupported class singleton accepted' } }
fn cs_matrix(native bool, get u64, initialize u64, code u64, probe CuProbe) []CuInput {
	mut fixtures := []CuInput{}
	for request in [u64(0), 1, 0x3f, 0xff, 0x100, 0x101, 0x13f, 0x1ff]! {
		input := cs_input(native, get, initialize, code); fixtures << input
		cs_call(input, get, probe, request)
		cu_check(input, [u64(16), 24], 32, 7, [CuField{8, 8, 0x10007, 0}, CuField{8, 8, 7, 0}], native, false, true)
		for i in 2 .. 4 { assert read64(input.metadata - u64(i * 8)) == 0x12340000 + u64(i) }
		assert C.mprotect(voidptr(input.base + input.page), usize(input.page * 4), C.PROT_READ) == 0
		for next in [u64(0), 1, 0x3f, 0xff, 0x100, 0x101, 0x13f, 0x1ff]! { cs_call(input, get, probe, next) }
		if !native { checked := swift_metadata_state_checked(0, input.metadata) or { panic(err) }; assert checked.metadata == input.metadata && checked.state == 0 }
	}
	busy := cs_input(native, get, initialize, code); fixtures << busy
	t := cs_trace(busy); cu_write(t + 64, 1); C.pthread_mutex_lock(voidptr(t + 128))
	worker := spawn cs_worker(busy, get)
	for C.ios_load_pointer(unsafe { &u64(t) }) == 0 { C.usleep(1000) }
	for request in [u64(0x100), 0x101, 0x13f, 0x1ff, 0x3f, 0xff]! {
		partial := unsafe { CsGet(voidptr(get))(request, busy.descriptor) }; assert partial.metadata == busy.metadata && partial.state == 0x3f
	}
	assert read64(cs_cache(busy)) == 0
	C.pthread_mutex_unlock(voidptr(t + 128)); assert worker.wait() == busy.metadata; cs_call(busy, get, probe, 0)
	concurrent := cs_input(native, get, initialize, code); fixtures << concurrent
	if !native { nested := cs_input(false, get, initialize, code); fixtures << nested; cu_write(cs_trace(concurrent) + 80, nested.descriptor) }
	mut workers := []thread u64{}
	for _ in 0 .. 8 { workers << spawn cs_worker(concurrent, get) }; results := workers.wait()
	for result in results { assert result == concurrent.metadata }; assert read64(cs_trace(concurrent)) == 1
	unsafe { workers.free(); results.free() }
	if !native {
		invalid := cs_input(false, get, initialize, code); fixtures << invalid
		// Preflight failures leave both borrowed headers and cache untouched.
		for pair in [[invalid.descriptor + 20, u64(4)]!, [invalid.descriptor + 36, u64(65)]!, [invalid.metadata + 44, u64(1)]!, [invalid.ro, u64(0x180)]!]! {
			old := read32(pair[0]); write32(pair[0], u32(pair[1])); copy := C.malloc(usize(invalid.page * 4)); assert copy != unsafe { nil }; C.memcpy(copy, voidptr(invalid.base + invalid.page), usize(invalid.page * 4))
			cs_bad(invalid); assert C.memcmp(copy, voidptr(invalid.base + invalid.page), usize(invalid.page * 4)) == 0; C.free(copy); write32(pair[0], old)
		}
		for offset in [u64(44), 48, 52]! { old := read32(invalid.descriptor + offset); write32(invalid.descriptor + offset, 0); cs_bad(invalid); write32(invalid.descriptor + offset, old) }
		cu_write(cs_cache(invalid) + 8, 1); cs_bad(invalid); cu_write(cs_cache(invalid) + 8, 0)
		// A cache cannot be shared by different descriptors.
		swift_protocol_relative(invalid.descriptor + 44, cs_cache(concurrent)); cs_bad(invalid); swift_protocol_relative(invalid.descriptor + 44, cs_cache(invalid))
		assert read64(cs_trace(invalid)) == 0
		for mode in [u64(1), 2, 3, 4, 5]! {
			bad := cs_input(false, get, initialize, code); fixtures << bad; cu_write(cs_trace(bad) + 56, mode)
			if mode == 5 { cu_write(cs_trace(bad) + 72, code) }
			cs_bad(bad); cs_bad(bad); assert read64(cs_trace(bad)) == 1 && read64(cs_cache(bad)) == 0
		}
	}
	return fixtures
}
// Image registration has a separate lifecycle: borrowed metadata is checked
// while non-executable, then callbacks run after binding and selector repair.
fn cx_initialize(cls u64, argument u64) u64 {
	d := read64(cls + 64); t := u64(i64(d + 16) + i64(i32(read32(d + 16))))
	assert argument == 0 && C.ios_ref_change(unsafe { &i64(t + 88) }, 1) == 0
	assert ios_runtime.classes[cls].swift_image_phase == 1
	assert ios_runtime.classes[read64(cls)].meta
	assert read64(t + 192) == objc_selector(c'initialize')
	// A different thread must acquire the registry lock during this callback.
	worker := spawn objc_get_class(unsafe { &char(read64((read64(cls + 32) & ~u64(7)) + 24)) })
	assert worker.wait() == cls
	if _ := objc_complete_swift_class(cls) { assert false, 'recursive image initializer accepted' }
	if read64(t + 96) != 1 {
		result := unsafe { CsGet(voidptr(read64(t + 48)))(0, d) }
		assert result.metadata == cls && result.state == 0
	}
	return if read64(t + 96) == 2 { cls + 8 } else { cls }
}
fn cx_load(cls u64, _selector &char) {
	d := read64(cls + 64); t := u64(i64(d + 16) + i64(i32(read32(d + 16))))
	assert ios_runtime.classes[cls].swift_image_phase == 2 && read64(t + 88) == 1
	assert read64(read64(t + 32)) == cls && read64(t) == 1
	assert C.ios_ref_change(unsafe { &i64(t + 112) }, 1) == 0
}
fn cx_input(get u64, initialize u64, code u64) CuInput {
	input := cs_input_kind(false, get, initialize, code, false)
	b := input.base + input.page; m := input.metadata; d := input.descriptor; t := cs_trace(input)
	cu_write(m + 8, b + 12288); write32(m + 48, 32); write32(input.ro + 8, 32)
	cu_write(input.ro + 72, code + 512)
	for i in 0 .. 2 {
		cu_write(m + 80 + u64(i * 8), u64(16 + i * 8)); cu_write(input.cells + u64(i * 8), u64(16 + i * 8))
		write32(input.list + 8 + u64(i * 32) + 28, 8)
	}
	write32(d + 60, 1); write32(d + 64, 1); write32(d + 68, 0)
	cu_write(m + 96, u64(unsafe { voidptr(swift_deleted_method_failure) }))
	methods := b + 11520; write32(methods + 4, 2); cu_write(methods + 24, code + 768)
	C.memcpy(voidptr(b + 11400), c'load', 5)
	cu_write(methods + 32, b + 11400); cu_write(methods + 40, b + 11360); cu_write(methods + 48, code + 1024)
	// Keep image tables beyond the host's pthread mutex at trace + 128..192.
	cu_write(b + 12032, m); cu_write(b + 12040, m); cu_write(t + 192, b + 11328)
	return input
}
fn cx_image(input CuInput, code u64, data_flags u32, file_size u64) ObjMetadata {
	b := input.base + input.page
	return ObjMetadata{
		image: macho.Image{segments: [
			macho.Segment{name: '__TEXT', address: code, size: input.page, filesize: input.page, prot: 5},
			macho.Segment{name: '__DATA', address: b, size: input.page * 4, filesize: file_size, prot: 3, flags: data_flags, sections: [
				macho.Section{name: '__objc_classlist', address: b + 12032, size: 8},
				macho.Section{name: '__objc_nlclslist', address: b + 12040, size: 8},
				macho.Section{name: '__objc_selrefs', address: cs_trace(input) + 192, size: 8},
			]},
		]}
		layout: macho.Layout{size: input.page * 5}
	}
}
fn cx_reject(input CuInput, image ObjMetadata) {
	copy := C.malloc(usize(input.page * 4)); assert copy != unsafe { nil }
	C.memcpy(copy, voidptr(input.base + input.page), usize(input.page * 4))
	if _ := image.register(input.metadata, 0) { assert false, 'malformed Swift image accepted' }
	assert input.metadata !in ios_runtime.classes && read64(cs_trace(input)) == 0 && read64(cs_trace(input) + 88) == 0
	assert C.memcmp(copy, voidptr(input.base + input.page), usize(input.page * 4)) == 0; C.free(copy)
}
fn cx_matrix(get u64, initialize u64, code u64, guard u64) []CuInput {
	mut fixtures := []CuInput{}
	bad := cx_input(get, initialize, code); fixtures << bad
	image := cx_image(bad, code, 0, bad.page * 4)
	for pair in [[bad.metadata + 64, guard]!, [bad.metadata, guard]!, [bad.ro + 72, guard]!,
		[bad.metadata + 32, guard | 1]!, [bad.cells, u64(33)]!, [bad.list + 8, guard]!,
		[bad.list + 16, guard]!, [bad.list + 24, guard]!, [bad.metadata + 96, code]!]! {
		old := read64(pair[0]); cu_write(pair[0], pair[1]); cx_reject(bad, image); cu_write(pair[0], old)
	}
	for pair in [[bad.descriptor, u32(0x800100d0)]!, [bad.descriptor + 20, u32(1)]!,
		[bad.descriptor + 36, u32(65)]!, [bad.descriptor + 40, u32(9)]!, [bad.descriptor + 60, u32(2)]!,
		[bad.descriptor + 64, u32(2)]!, [bad.descriptor + 68, u32(1)]!, [bad.ro, u32(0x1c0)]!,
		[bad.metadata + 44, u32(1)]!, [bad.list + 8 + 24, u32(9)]!]! {
		old := read32(u64(pair[0])); write32(u64(pair[0]), u32(pair[1])); cx_reject(bad, image); write32(u64(pair[0]), old)
	}
	for offset in [u64(44), 48, 52]! {
		old := read32(bad.descriptor + offset); write32(bad.descriptor + offset, 0); cx_reject(bad, image); write32(bad.descriptor + offset, old)
	}
	cu_write(cs_cache(bad) + 8, 1); cx_reject(bad, image); cu_write(cs_cache(bad) + 8, 0)
	old_cell := read64(bad.list + 40); cu_write(bad.list + 40, bad.cells); cx_reject(bad, image); cu_write(bad.list + 40, old_cell)
	cx_reject(bad, cx_image(bad, code, 0x10, bad.page * 4)) // Final SG_READ_ONLY removes write permission.
	cx_reject(bad, cx_image(bad, code, 0, 4096)) // Reservation without file-backed ivars.
	for local_method in [false, true]! {
		input := cx_input(get, initialize, code); fixtures << input
		if local_method { swift_protocol_relative(input.descriptor + 68, code + 768); cu_write(input.metadata + 96, code + 768) }
		m := cx_image(input, code, 0, input.page * 4)
		objc_register_image(m.image, m.layout, m.base) or { panic(err) }
		assert read64(cs_trace(input)) == 0 && read64(cs_trace(input) + 88) == 0 && read64(cs_trace(input) + 112) == 0
		assert ios_runtime.classes[input.metadata].swift_image_phase == 0 && !ios_runtime.classes[input.metadata].initialized
		objc_complete_swift_images() or { panic(err) }; objc_complete_swift_images() or { panic(err) }
		assert read64(cs_trace(input)) == 1 && read64(cs_trace(input) + 88) == 1
		assert ios_runtime.classes[input.metadata].swift_image_phase == 2 && ios_runtime.classes[input.metadata].swift_layout_complete
		assert read64(input.ro + 48) == input.list && read64(input.cells) == 16 && read64(input.cells + 8) == 24
	}
	objc_load_image()
	for input in fixtures[1..] { assert read64(cs_trace(input) + 112) == 1 && !ios_runtime.classes[input.metadata].initialized }
	assert cu_initializations == 0 && cu_metadata_initializations == 0
	for mode in [u64(1), 2]! {
		input := cx_input(get, initialize, code); fixtures << input
		m := cx_image(input, code, 0, input.page * 4); cu_write(cs_trace(input) + 96, mode)
		objc_register_image(m.image, m.layout, m.base) or { panic(err) }
		for _ in 0 .. 2 { if _ := objc_complete_swift_class(input.metadata) { assert false, 'incomplete or relocated Swift image accepted' } }
		assert ios_runtime.classes[input.metadata].swift_image_phase == 3 && read64(cs_trace(input) + 88) == 1
		assert read64(cs_trace(input) + 112) == 0
	}
	return fixtures
}
fn test_swift_class_update() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != ~u64(0) && guard != ~u64(0)
	defer { assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0 }
	// x0..x4 arguments; x0/x1 dependency result; preserved Swift context x20/x21.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0603f3, 0xaa0503f0, u32(0xd2800000 | (0x5020 << 5) | 20), u32(0xd2800000 | (0x5021 << 5) | 21), 0xd63f0200, 0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	write32(code + 256, 0x58000050); write32(code + 260, 0xd61f0200); cu_write(code + 264, u64(unsafe { voidptr(cs_complete) }))
	for pair in [[u64(512), u64(unsafe { voidptr(cx_initialize) })]!, [u64(768), u64(unsafe { voidptr(cu_initialize) })]!, [u64(1024), u64(unsafe { voidptr(cx_load) })]!]! {
		write32(code + pair[0], 0x58000050); write32(code + pair[0] + 4, 0xd61f0200); cu_write(code + pair[0] + 8, pair[1])
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 1040)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { CuProbe(voidptr(code)) }
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2); entry := u64(C.dlsym(core, c'swift_updateClassMetadata2')); assert entry != 0
		// Native Objective-C realizes these class identities permanently; their
		// synthetic image storage remains mapped until this process exits.
		mut fixtures := cu_matrix(entry, probe, true, false); fixtures << cu_headers(entry, probe, true, false); unsafe { fixtures.free() }
		println('IOS-CLASS-UPDATE-NATIVE: five-argument C ABI, nil dependency in x0/x1, preserved x20/x21; root header, field size/tail padding/alignment, UInt64 vectors and exported cells, copy-on-size-change ivars, unchanged encodings, zero/64 fields, existing instance start; 16 header variants, unchanged negative words, no metadata initializer or +initialize')
		initialize := u64(C.dlsym(core, c'swift_initClassMetadata2')); assert initialize != 0
		mut initialized := ci_matrix(initialize, probe, true); unsafe { initialized.free() }
		println('IOS-CLASS-INIT-NATIVE: static-vtable root initialization, implicit SwiftObject superclass, normalized Swift bit, FileStorage-shaped headers, field layout and nil dependency ABI; no metadata callback or +initialize')
		get := u64(C.dlsym(core, c'swift_getSingletonMetadata')); assert get != 0
		mut singletons := cs_matrix(true, get, initialize, code, probe); unsafe { singletons.free() }
		println('IOS-CLASS-SINGLETON-NATIVE: FileStorage-shaped root completion, native object witnesses before callback, four-word context and null pattern, eight cold/warm requests, LayoutComplete busy responses, one completion across eight readers and preserved x20/x21')
	}
	cu_reject(guard, 0x100, 0, guard, guard); ci_reject(guard, 0x100, 0, guard, guard)
	for _ in 0 .. 2 {
		objc_start()
		entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_updateClassMetadata2') or { panic(err) }
		mut fixtures := cu_matrix(entry, probe, false, false)
		fixtures << cu_headers(entry, probe, false, false)
		fixtures << cu_invalid(guard); fixtures << cu_repeat(entry, probe, false)
		initialize := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_initClassMetadata2') or { panic(err) }
		fixtures << ci_matrix(initialize, probe, false)
		fixtures << ci_invalid(guard); fixtures << cu_repeat(initialize, probe, true)
		singletons := cs_matrix(false, cs_lookup(), initialize, code, probe); fixtures << singletons
		images := cx_matrix(cs_lookup(), initialize, code, guard); fixtures << images
		if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_swift_initClassMetadata2') { assert false }
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '__swift_initClassMetadata2') { assert false }
		if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_swift_updateClassMetadata2') { assert false }
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '__swift_updateClassMetadata2') { assert false }
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.live == 0
		for input in singletons {
			assert C.mprotect(voidptr(input.base + input.page), usize(input.page * 4), C.PROT_READ | C.PROT_WRITE) == 0
			assert C.pthread_mutex_destroy(voidptr(cs_trace(input) + 128)) == 0
		}; unsafe { singletons.free() }
		for input in images { assert C.pthread_mutex_destroy(voidptr(cs_trace(input) + 128)) == 0 }; unsafe { images.free() }
		for input in fixtures { assert C.mprotect(voidptr(input.base + input.page), usize(input.page * 4), C.PROT_NONE) == 0 }
		objc_stop(); cu_reject(guard, 0x100, 0, guard, guard); ci_reject(guard, 0x100, 0, guard, guard)
		if _ := swift_singleton_metadata_checked(0, guard) { assert false }
		if _ := objc_complete_swift_class(guard) { assert false }
		for input in fixtures { cu_free(input) }; unsafe { fixtures.free() }
	}
	println('IOS-CLASS-UPDATE: bounded registered nongeneric Swift root layout, UInt64 offsets, ivar encoding/alignment and registry publication; 16 header variants, unchanged negative words, no metadata initializer or +initialize; fail-before-write validation, live-layout rejection, readonly unchanged storage, 512 concurrent repeats, owned-copy drain with inaccessible image pages and two runtime lifetimes')
	println('IOS-CLASS-INIT: bounded registered static-vtable Swift root initialization, implicit superclass and normalized Swift bit; FileStorage-shaped headers, field layout and nil dependency ABI; no metadata callback or +initialize; fail-before-write rejection, readonly 512 concurrent repeats, inaccessible-image teardown and two lifetimes')
	println('IOS-CLASS-SINGLETON: bounded registered root completion, reference witness setup, release publication and complete-state recognition; eight cold/warm requests, LayoutComplete busy responses, eight concurrent readers, unlocked nested completion and recursive rejection; preflight validation, cache alias rejection, malformed/dependency poisoning and inaccessible-image teardown across two lifetimes')
	println('IOS-CLASS-IMAGE: bounded file-backed Swift root registration, final segment protections, deleted/local vtable entries and fail-before-write malformed metadata rejection; deferred C-ABI initializer after metaclass and selector registration, unlocked registry reentry, recursive rejection, exact-once completion across duplicate lists before +load without +initialize; incomplete/relocated result poisoning and inaccessible-image teardown across two lifetimes')
}
