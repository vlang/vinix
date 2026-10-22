// SPDX-License-Identifier: GPL-2.0-or-later
module main

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
struct CuField { size u64 stride u64 flags u32 extra u32 }
struct CuInput { base u64 page u64 metadata u64 ro u64 descriptor u64 types u64 list u64 cells u64 count int }
__global cu_sequence = u64(0)
__global cu_initializations = i64(0)
fn cu_initialize(_cls u64, _selector &char) { C.ios_ref_change(unsafe { &cu_initializations }, 1) }
fn cu_write(address u64, value u64) { unsafe { *(&u64(address)) = value } }

fn cu_input(fields []CuField, native bool, start u32, matching_sizes bool) CuInput {
	page := u64(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, usize(page * 6), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != ~u64(0)
	b := base + page
	assert C.mprotect(voidptr(b), usize(page * 4), C.PROT_READ | C.PROT_WRITE) == 0
	m := b + 16; meta := b + 1024; ro := b + 1280; mr := b + 1408; d := b + 1536
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
		if !native { ios_runtime.classes[m].ivars[field_name] = &ObjIvar{name: field_name.clone(), types: '@'.clone(), offset: 1, size: if matching_sizes { f.size } else { u64(99) }} }
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
fn cu_check(input CuInput, positions []u64, size u32, mask u32, fields []CuField, native bool, matching_sizes bool) {
	m := input.metadata; list := read64(input.ro + 48)
	assert read32(m + 44) == 0 && read32(m + 48) == size && read32(m + 52) == mask
	assert read32(input.ro + 8) == size && read32(m + 56) == u32(96 + fields.len * 8) && read64(m + 64) == input.descriptor
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
	$if macos { if native { assert C.class_getInstanceSize(voidptr(m)) == usize((size + 7) & ~u32(7)) } }
	if !native { assert ios_runtime.classes[m].size == size && ios_runtime.classes[m].swift_layout_complete && !ios_runtime.classes[m].initialized }
	assert cu_initializations == 0
}
fn cu_case(entry u64, probe CuProbe, native bool, fields []CuField, positions []u64, size u32, mask u32, start u32, matching bool) CuInput {
	input := cu_input(fields, native, start, matching)
	cu_call(input, entry, probe)
	cu_check(input, positions, size, mask, fields, native, matching)
	return input
}
fn cu_matrix(entry u64, probe CuProbe, native bool) []CuInput {
	mut fixtures := []CuInput{}
	fixtures << cu_case(entry, probe, native, []CuField{}, []u64{}, 16, 7, 16, true)
	for matching in [false, true]! {
		// Same two-field pointer-layout shape as the observed URL/NativeObject call.
		fixtures << cu_case(entry, probe, native, [CuField{8, 8, 0x10007, 0}, CuField{8, 8, 7, 0}], [u64(16), 24], 32, 7, 16, matching)
	}
	fixtures << cu_case(entry, probe, native, [CuField{1, 1, 0, 0}, CuField{8, 8, 7, 0}, CuField{2, 2, 1, 0}], [u64(16), 24, 32], 34, 7, 16, false)
	fixtures << cu_case(entry, probe, native, [CuField{3, 4, 3, 0}, CuField{1, 1, 0, 0}], [u64(16), 19], 20, 7, 16, false)
	fixtures << cu_case(entry, probe, native, [CuField{8, 32, 31, 0}], [u64(32)], 40, 31, 16, false)
	fixtures << cu_case(entry, probe, native, [CuField{0, 256, 255, 0}, CuField{8, 8, 7, 0}], [u64(0), 16], 24, 7, 16, false)
	fixtures << cu_case(entry, probe, native, [CuField{1, 1, 0, 0}, CuField{8, 8, 0x110007, 0x7fffffff}], [u64(48), 56], 64, 7, 48, false)
	mut many := []CuField{}; mut positions := []u64{}
	for i in 0 .. 64 { many << CuField{1, 1, 0, 0}; positions << u64(16 + i) }
	fixtures << cu_case(entry, probe, native, many, positions, 80, 7, 16, false)
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
fn cu_bad(input CuInput) {
	copy := C.malloc(usize(input.page * 4)); assert copy != unsafe { nil }
	C.memcpy(copy, voidptr(input.base + input.page), usize(input.page * 4))
	cu_reject(input.metadata, 0x100, u64(input.count), input.types, input.metadata + 80)
	assert C.memcmp(copy, voidptr(input.base + input.page), usize(input.page * 4)) == 0
	C.free(copy)
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
	for pair in [[d, u64(0x10090)]!, [d, u64(0x20010010)]!, [d + 20, u64(4)]!, [d + 36, u64(2)]!, [d + 40, u64(11)]!, [m + 44, u64(8)]!, [m + 56, u64(96)]!, [input.ro, u64(0x40)]!, [input.list, u64(24)]!, [input.list + 4, u64(2)]!]! {
		old := read32(pair[0]); write32(pair[0], u32(pair[1])); cu_bad(input); write32(pair[0], old)
	}
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
fn cu_repeat(entry u64, probe CuProbe) CuInput {
	input := cu_input([CuField{8, 8, 7, 0}], false, 16, false)
	cu_call(input, entry, probe)
	list := read64(input.ro + 48)
	// Changing an already-published layout must fail without writing or replacing
	// its owned ivar table. Identical calls need no allocations or image writes.
	layout := read64(input.types); cu_write(layout, 16); cu_write(layout + 8, 16); cu_bad(input); cu_write(layout, 8); cu_write(layout + 8, 8)
	assert C.mprotect(voidptr(input.base + input.page), usize(input.page * 4), C.PROT_READ) == 0
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn cu_worker(input, entry) }; workers.wait(); unsafe { workers.free() }
	assert read64(input.ro + 48) == list && ios_runtime.classes[input.metadata].swift_ivar_list == list
	return input
}
fn test_swift_class_update() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != ~u64(0) && guard != ~u64(0)
	defer { assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0 }
	// x0..x4 arguments; x0/x1 dependency result; preserved Swift context x20/x21.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0603f3, 0xaa0503f0, u32(0xd2800000 | (0x5020 << 5) | 20), u32(0xd2800000 | (0x5021 << 5) | 21), 0xd63f0200, 0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 56)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { CuProbe(voidptr(code)) }
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2); entry := u64(C.dlsym(core, c'swift_updateClassMetadata2')); assert entry != 0
		// Native Objective-C realizes these class identities permanently; their
		// synthetic image storage remains mapped until this process exits.
		fixtures := cu_matrix(entry, probe, true); unsafe { fixtures.free() }
		println('IOS-CLASS-UPDATE-NATIVE: five-argument C ABI, nil dependency in x0/x1, preserved x20/x21; root header, field size/tail padding/alignment, UInt64 vectors and exported cells, copy-on-size-change ivars, unchanged encodings, zero/64 fields, existing instance start and no +initialize')
	}
	cu_reject(guard, 0x100, 0, guard, guard)
	for _ in 0 .. 2 {
		objc_start()
		entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_updateClassMetadata2') or { panic(err) }
		mut fixtures := cu_matrix(entry, probe, false)
		fixtures << cu_invalid(guard); fixtures << cu_repeat(entry, probe)
		if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_swift_updateClassMetadata2') { assert false }
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '__swift_updateClassMetadata2') { assert false }
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.live == 0
		for input in fixtures { assert C.mprotect(voidptr(input.base + input.page), usize(input.page * 4), C.PROT_NONE) == 0 }
		objc_stop(); cu_reject(guard, 0x100, 0, guard, guard)
		for input in fixtures { cu_free(input) }; unsafe { fixtures.free() }
	}
	println('IOS-CLASS-UPDATE: bounded registered nongeneric Swift root layout, UInt64 offsets, ivar encoding/alignment and registry publication; fail-before-write validation, live-layout rejection, readonly unchanged storage, 512 concurrent repeats, owned-copy drain with inaccessible image pages and two runtime lifetimes')
}
