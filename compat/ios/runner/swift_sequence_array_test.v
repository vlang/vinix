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
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.CFGetRetainCount(voidptr) i64
type SaRun = fn (u64, u64, u64) u64
type SaProbe = fn (u64, u64, u64, u64, u64, &u64) u64
type SaAccess = fn (u64, u64) SwiftAssociatedMetadata
type SaLookup = fn (u64, u64, u64) u64
type SaAllocate = fn (i64, u64) SwiftArrayAllocation
type SaKeep = fn (u64) u64
type SaDrop = fn (u64)
type SaObject = fn () u64
type SaObjectKeep = fn (u64)
type SaRefs = fn (u64) i64
type SaObjCType = fn (u64) u64
struct SaApi {
	native bool
	zero_hint bool
	code u64
	guard u64
	descriptor u64
	integer u64
	string_type u64
	object_type u64
	entry SaRun @[required]
	access SaAccess @[required]
	lookup SaLookup @[required]
	allocate SaAllocate @[required]
	keep SaKeep @[required]
	drop SaDrop @[required]
	object SaObject @[required]
	object_keep SaObjectKeep @[required]
	object_drop SaObjectKeep @[required]
	refs SaRefs @[required]
}
fn sa_native_object() u64 { $if macos { return u64(C.CFStringCreateMutable(unsafe { nil }, 0)) } $else { panic('native reference requires macOS') } }
fn sa_native_keep(owner u64) { $if macos { C.CFRetain(voidptr(owner)) } }
fn sa_native_drop(owner u64) { $if macos { C.CFRelease(voidptr(owner)) } }
fn sa_native_refs(owner u64) i64 { $if macos { return C.CFGetRetainCount(voidptr(owner)) } $else { panic('native reference requires macOS') } }
fn sa_native_api(code u64, guard u64) SaApi {
	$if macos {
	core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2);assert core != unsafe { nil }
	objc_type := unsafe { SaObjCType(C.dlsym(core, c'swift_getObjCClassMetadata')) }
	return SaApi{native: true, code: code, guard: guard, descriptor: u64(C.dlsym(core, c'$sSayxGSTsMc')),
		integer: u64(C.dlsym(core, c'$sSiN')), string_type: u64(C.dlsym(core, c'$sSSN')), object_type: objc_type(u64(C.objc_getClass(c'NSString'))),
		entry: unsafe { SaRun(C.dlsym(core, c'$ss30_copySequenceToContiguousArrayys0dE0Vy7ElementQzGxSTRzlF')) },
		access: unsafe { SaAccess(C.dlsym(core, c'$sSaMa')) }, lookup: unsafe { SaLookup(C.dlsym(core, c'swift_getWitnessTable')) },
		allocate: unsafe { SaAllocate(C.dlsym(core, c'$ss27_allocateUninitializedArrayySayxG_BptBwlF')) },
		keep: unsafe { SaKeep(C.dlsym(core, c'swift_bridgeObjectRetain')) }, drop: unsafe { SaDrop(C.dlsym(core, c'swift_bridgeObjectRelease')) },
		object: sa_native_object, object_keep: sa_native_keep, object_drop: sa_native_drop, refs: sa_native_refs}
	} $else { panic('native reference requires macOS') }
}
fn sa_emit(code u64) {
	// C source/metadata/table/entry/guard/capture -> Swift x0/x1/x2.
	// Inaccessible x3...x8 and preserved opaque x20/x21/x22.
	for i, op in [u32(0xa9bc7bfd), 0xa90157f4, 0xa9024ff6, 0xf9001bf7,
		0xaa0303f3, 0xaa0503f7, 0xaa0403f4, 0x91002095, 0x91004096,
		0xaa0403e8, 0xaa0403e3, 0xaa0403e5, 0xaa0403e6, 0xaa0403e7,
		0xd63f0260, 0xa90056f4, 0xf9000af6, 0xa9424ff6, 0xa94157f4,
		0xf9401bf7, 0xa8c47bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	write32(code + 128, 0xd2800000);write32(code + 132, 0xd65f03c0) // Underestimate 0.
	write32(code + 144, 0x92800000);write32(code + 148, 0xd65f03c0) // Invalid -1.
	write32(code + 160, 0xd2a00200);write32(code + 164, 0xd65f03c0) // Oversized 1 MiB elements.
	write32(code + 176, 0xd2800020);write32(code + 180, 0xd65f03c0) // Invalid underestimate 1 for empty.
}
fn sa_value(address u64, kind int, index u64, object u64) {
	if kind == 0 { assert read64(address) == index * 17 + 3 }
	else if kind == 1 { assert read64(address) == 0 && read64(address + 8) == object | 0x5000000000000000 }
	else { assert read64(address) == object }
}
fn sa_case(api SaApi, kind int, count u64, tail bool) {
	element := if kind == 0 { api.integer } else if kind == 1 { api.string_type } else { api.object_type }
	metadata := api.access(0, element).metadata;mut table := api.lookup(api.descriptor, metadata, api.guard)
	assert table != 0
	mut adjusted := [6]u64{}
	if api.zero_hint {
		assert !api.native
		for i in 0 .. 6 { adjusted[i] = read64(table + u64(i * 8)) };adjusted[5] = api.code + 128
		table = u64(unsafe { &adjusted[0] })
	}
	object := api.object();allocation := api.allocate(i64(count), element);owner := allocation.owner
	stride := if kind == 1 { u64(16) } else { u64(8) }
	for i in u64(0) .. count {
		address := allocation.bytes + i * stride
		if kind == 0 { unsafe { *(&u64(address)) = i * 17 + 3 } }
		else {
			api.object_keep(object)
			if kind == 1 { unsafe { *(&u64(address)) = 0;*(&u64(address + 8)) = object | 0x5000000000000000 } }
			else { unsafe { *(&u64(address)) = object } }
		}
	}
	api.keep(owner) // A retained source alias must survive the entire copy.
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert region != u64(-1)
	assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	source := region + u64(page) + if tail { u64(page) - 8 } else { u64(0) }
	unsafe { *(&u64(source)) = owner }
	assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ) == 0
	before := read64(owner + 8);refs := api.refs(object)
	mut capture := [u64(0xCAFE), 0, 0, 0, 0xBEEF]!
	result := unsafe { SaProbe(voidptr(api.code))(source, metadata, table, u64(voidptr(api.entry)), api.guard, &capture[1]) }
	assert capture == [u64(0xCAFE), api.guard, api.guard + 8, api.guard + 16, 0xBEEF]!
	assert read64(source) == owner && result != 0 && read64(result + 16) == count
	for i in u64(0) .. count { sa_value(result + 32 + i * stride, kind, i, object);sa_value(allocation.bytes + i * stride, kind, i, object) }
	assert api.refs(object) == refs + if kind == 0 || result == owner { i64(0) } else { i64(count) }
	api.drop(result)
	assert read64(owner + 8) == before && api.refs(object) == refs
	api.drop(owner);api.drop(owner)
	assert api.refs(object) == 1;api.object_drop(object)
	assert C.munmap(voidptr(region), page * 3) == 0
}
fn sa_cases(api SaApi) {
	for kind in 0 .. 3 { for count in [u64(0), 1, 5, 33, 257]! { for tail in [false, true]! { sa_case(api, kind, count, tail) } } }
}
fn sa_worker(api SaApi) { for _ in 0 .. 4 { sa_case(api, 2, 5, true) } }

fn sa_compat_object() u64 { return owned_string('') }
fn sa_compat_keep(owner u64) { objc_retain(owner) }
fn sa_compat_drop(owner u64) { objc_release(owner) }
fn sa_compat_refs(owner u64) i64 { return obj_header(owner).refs }
fn sa_callback_metadata(metadata u64) u64 { return swift_array_sequence_table_checked(metadata) or { panic(err) } }
fn sa_reentrant_hint(metadata u64, _table u64, receiver u64) u64 {
	worker := spawn sa_callback_metadata(metadata);assert worker.wait() != 0
	return read64(read64(receiver) + 16)
}
fn sa_reentrant_case(api SaApi) {
	metadata := api.access(0, api.integer).metadata;table := api.lookup(api.descriptor, metadata, api.guard)
	mut adjusted := [6]u64{};for i in 0 .. 6 { adjusted[i] = read64(table + u64(i * 8)) };adjusted[5] = api.code + 192
	allocation := api.allocate(5, api.integer);mut source := allocation.owner
	for i in 0 .. 5 { unsafe { *(&u64(allocation.bytes + u64(i * 8))) = u64(i) } }
	result := api.entry(u64(unsafe { &source }), metadata, u64(unsafe { &adjusted[0] }))
	assert read64(result + 16) == 5;api.drop(result);api.drop(source)
}
fn sa_publish() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss30_copySequenceToContiguousArrayys0dE0Vy7ElementQzGxSTRzlF') or { panic(err) }
}
fn sa_compat_api(code u64, guard u64, entry u64) SaApi {
	return SaApi{code: code, guard: guard, descriptor: runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSayxGSTsMc') or { panic(err) },
		integer: swift_integer_metadata(), string_type: swift_string_metadata(), object_type: swift_objc_metadata(ios_runtime.names['NSString']),
		entry: unsafe { SaRun(voidptr(entry)) }, access: swift_array_access, lookup: swift_witness_table, allocate: swift_array_allocate,
		keep: swift_bridge_retain, drop: swift_bridge_release, object: sa_compat_object, object_keep: sa_compat_keep, object_drop: sa_compat_drop, refs: sa_compat_refs}
}
fn sa_invalid(api SaApi) {
	for args in [[u64(0), api.guard, api.guard]!, [u64(1), 0, 0]!, [api.guard, u64(1), 0]!, [api.guard, api.guard, ~u64(0) - 7]!]! {
		if _ := swift_sequence_array_checked(args[0], args[1], args[2]) { assert false }
	}
	metadata := api.access(0, api.integer).metadata;table := api.lookup(api.descriptor, metadata, api.guard)
	mut broken := [8]u64{};for i in 0 .. 6 { broken[i] = read64(table + u64(i * 8)) }
	for slot in [1, 2, 3, 4, 5]! {
		saved := broken[slot];broken[slot] = 1
		if _ := swift_sequence_array_checked(api.guard, metadata, u64(unsafe { &broken[0] })) { assert false };broken[slot] = saved
	}
	if _ := swift_sequence_array_checked(api.guard + 1, metadata, table) { assert false }
	// Invalid hints fail before dereferencing the protected source.
	for entry in [api.code + 144, api.code + 160]! {
		broken[5] = entry
		if _ := swift_sequence_array_checked(api.guard, metadata, u64(unsafe { &broken[0] })) { assert false }
	}
	// A violated lower bound cleans an already-created Iterator and result.
	owner := api.allocate(0, api.integer).owner;mut source := owner;before := read64(owner + 8)
	broken[5] = api.code + 176
	if _ := swift_sequence_array_checked(u64(unsafe { &source }), metadata, u64(unsafe { &broken[0] })) { assert false }
	assert source == owner && read64(owner + 8) == before;api.drop(owner)
}
fn sa_growth_failure(api SaApi) {
	count := u64(65537);object := api.object()
	allocation := api.allocate(i64(count), api.object_type)
	for i in u64(0) .. count { api.object_keep(object);unsafe { *(&u64(allocation.bytes + i * 8)) = object } }
	metadata := api.access(0, api.object_type).metadata;table := api.lookup(api.descriptor, metadata, api.guard)
	mut adjusted := [6]u64{};for i in 0 .. 6 { adjusted[i] = read64(table + u64(i * 8)) };adjusted[5] = api.code + 128
	mut source := allocation.owner;before := read64(source + 8);refs := api.refs(object)
	// Doubling from 65536 exceeds the bounded 1 MiB result extent. One owned
	// Optional payload is pending, with 65536 already-initialized result slots.
	if _ := swift_sequence_array_checked(u64(unsafe { &source }), metadata, u64(unsafe { &adjusted[0] })) { assert false }
	assert source == allocation.owner && read64(source + 8) == before && api.refs(object) == refs
	api.drop(source);assert api.refs(object) == 1;api.object_drop(object)
}
fn sa_pod_copy(destination u64, source u64, metadata u64) u64 {
	C.memcpy(voidptr(destination), voidptr(source), usize(read64(read64(metadata - 8) + 64)));return destination
}
fn sa_pod_destroy(_value u64, _metadata u64) {}
fn sa_pod_tag(value u64, _cases u32, metadata u64) u32 { return u32(unsafe { *(&u8(value + read64(read64(metadata - 8) + 64))) }) }
fn sa_pod_store(value u64, tag u32, _cases u32, metadata u64) { unsafe { *(&u8(value + read64(read64(metadata - 8) + 64))) = u8(tag) } }
fn sa_pod_case(api SaApi, base u64, size u64, stride u64, alignment u64) {
	metadata := base + 136
	for i in 0 .. 8 { unsafe { *(&u64(base + u64(i * 8))) = u64(voidptr(sa_pod_copy)) } }
	unsafe { *(&u64(base + 8)) = u64(voidptr(sa_pod_destroy));*(&u64(base + 48)) = u64(voidptr(sa_pod_tag));*(&u64(base + 56)) = u64(voidptr(sa_pod_store))
		*(&u64(base + 64)) = size;*(&u64(base + 72)) = stride;*(&u64(base + 80)) = alignment - 1
		*(&u64(metadata - 8)) = base;*(&u64(metadata)) = 0x200 }
	array_type := api.access(0, metadata).metadata;table := api.lookup(api.descriptor, array_type, api.guard)
	mut adjusted := [6]u64{};for i in 0 .. 6 { adjusted[i] = read64(table + u64(i * 8)) };adjusted[5] = api.code + 128
	allocation := api.allocate(9, metadata);mut source := allocation.owner;before := read64(source + 8)
	for i in u64(0) .. 9 { for j in u64(0) .. size { unsafe { *(&u8(allocation.bytes + i * stride + j)) = u8(i * 7 + j) } } }
	result := api.entry(u64(unsafe { &source }), array_type, u64(unsafe { &adjusted[0] }))
	tail := (u64(32) + alignment - 1) & ~(alignment - 1)
	assert (result + tail) & (alignment - 1) == 0 && read64(result + 16) == 9
	for i in u64(0) .. 9 { for j in u64(0) .. size { assert unsafe { *(&u8(result + tail + i * stride + j)) } == u8(i * 7 + j) } }
	assert source == allocation.owner && read64(source + 8) == before
	api.drop(result);api.drop(source)
}
fn test_swift_sequence_array() {
	page := usize(C.getpagesize());code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert code != u64(-1)
	sa_emit(code)
	write32(code + 192, 0xaa1403e2);write32(code + 196, 0x58000070);write32(code + 200, 0xd61f0200)
	unsafe { *(&u64(code + 208)) = u64(voidptr(sa_reentrant_hint)) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 216));assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page);assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	pod := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert pod != u64(-1)
	$if macos { sa_cases(sa_native_api(code, guard));println('NATIVE-SEQUENCE-ARRAY: borrowed source and owned result, Int/String/ObjC arrays, exact source/element ownership, retained aliases, protected source boundaries/x8 and preserved x20/x21/x22') }
	assert swift_sequence_array_symbol('_$ss30_copySequenceToContiguousArrayys0dE0Vy7ElementQzGxSTRzlF') == none
	for _ in 0 .. 2 {
		objc_start();mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn sa_publish() };entries := publishers.wait();for entry in entries { assert entry == entries[0] }
		api := sa_compat_api(code, guard, entries[0]);sa_cases(api);sa_invalid(api)
		sa_cases(SaApi{...api, zero_hint: true})
		sa_growth_failure(api)
		sa_reentrant_case(api)
		for i, layout in [[u64(0), 1, 1]!, [u64(3), 4, 4]!, [u64(64), 64, 32]!]! { sa_pod_case(api, pod + u64(i * 256), layout[0], layout[1], layout[2]) }
		mut workers := []thread{};for _ in 0 .. 8 { workers << spawn sa_worker(api) };workers.wait()
		unsafe { publishers.free();entries.free();workers.free() }
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library, '_$ss30_copySequenceToContiguousArrayys0dE0Vy7ElementQzGxSTRzlF') == none }
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$ss30_copySequenceToContiguousArrayys0dE0Vy7ElementQzGxSTRzlF') == none
		ios_runtime.swift_concurrency_retired = true;assert swift_sequence_array_symbol('_$ss30_copySequenceToContiguousArrayys0dE0Vy7ElementQzGxSTRzlF') == none
		if _ := swift_sequence_array_checked(guard, guard, guard) { assert false };ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		arena := ios_runtime.swift_sequence_arena;objc_stop();assert ios_runtime.swift_sequence_arena == 0
		assert C.mprotect(voidptr(arena), page, C.PROT_READ) == -1
		if _ := swift_sequence_array_checked(guard, guard, guard) { assert false }
	}
	assert C.munmap(voidptr(code), page * 2) == 0 && C.munmap(voidptr(pod), page) == 0
	println('IOS-SEQUENCE-ARRAY: borrowed checked Sequence to owned contiguous storage, source aliases/element ownership and protected contexts, zero hints and bounded partial-growth cleanup, empty/padded/32-byte-aligned elements, reentrant count callback, rejected invalid/retired inputs, eight cold publishers/workers and two drained/unmapped lifetimes')
}
