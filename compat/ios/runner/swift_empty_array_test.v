// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

$if macos {
	#include <mach/mach.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mincore(voidptr, usize, &u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type EmptyArrayAllocate = fn (i64, u64) SwiftArrayAllocation
type EmptyArrayBuffer = fn (i64, u64) u64
type EmptyArrayAccess = fn (u64, u64) SwiftAssociatedMetadata
type EmptyArrayKeep = fn (u64) u64
type EmptyArrayDrop = fn (u64)
type EmptyArrayDropN = fn (u64, u32)
type EmptyArrayUnique = fn (u64) bool
type EmptyArrayCopy = fn (u64, u64, u64) u64
type EmptyArrayDestroy = fn (u64, u64)

struct EmptyArrayApi {
	native bool
	owner u64
	int_type u64
	string_type u64
	any_type u64
	byte_type u64
	allocate EmptyArrayAllocate = swift_array_allocate
	buffer EmptyArrayBuffer = swift_array_buffer_allocate
	access EmptyArrayAccess = swift_array_access
	keep EmptyArrayKeep = swift_retain
	drop EmptyArrayDrop = swift_release
	drop_n EmptyArrayDropN = swift_release_n
	bridge_keep EmptyArrayKeep = swift_bridge_retain
	bridge_drop EmptyArrayDrop = swift_bridge_release
	unknown_keep EmptyArrayKeep = swift_unknown_retain
	unknown_drop EmptyArrayDrop = swift_unknown_release
	unique EmptyArrayUnique = swift_is_unique_native
}

fn empty_array_header(owner u64) {
	assert owner != 0 && owner & 7 == 0 && read64(owner) != 0
	assert read64(owner + 8) == 0x80000004ffffffff
	assert read64(owner + 16) == 0 && read64(owner + 24) == 1
}

fn empty_array_resolve() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '__swiftEmptyArrayStorage') or { panic(err) }
}

fn empty_array_readonly(owner u64) {
	$if macos {
		mut address := owner; mut size := u64(0); mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64); mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, &address, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object) == 0
		assert address <= owner && owner + 32 <= address + size && info[0] == C.PROT_READ
		if object != 0 { assert C.mach_port_deallocate(task, object) == 0 }
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields(); if fields.len < 2 { continue }; range := fields[0].split('-'); if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }; end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if owner >= start && owner < end { assert owner + 32 <= end && fields[1] == 'r--p'; found = true; break }
		}
		assert found
	}
}

fn empty_array_payload(api EmptyArrayApi, element u64) {
	metadata := api.access(0, element).metadata
	witness := read64(metadata - 8)
	destroy := unsafe { EmptyArrayDestroy(voidptr(read64(witness + 8))) }
	mut source := [api.owner, u64(0x9182736455463728)]!
	for slot in [u64(16), 24, 32, 40]! {
		// Both initialized and uninitialized destinations carry a sentinel
		// beyond Array's single-word payload. Takes preserve the source bytes.
		mut destination := [api.owner, u64(0x123456789abcdef0)]!
		operation := unsafe { EmptyArrayCopy(voidptr(read64(witness + slot))) }
		dst := u64(unsafe { &destination[0] }); src := u64(unsafe { &source[0] })
		assert operation(dst, src, metadata) == dst
		assert destination[0] == api.owner && destination[1] == 0x123456789abcdef0
		assert source[0] == api.owner && source[1] == 0x9182736455463728
		destroy(dst, metadata)
		empty_array_header(api.owner)
	}
	destroy(u64(unsafe { &source[0] }), metadata)
	if !api.native {
		view := swift_array_sequence_view_checked(metadata, u64(unsafe { &source[0] }), false) or { panic(err) }
		assert view.owner == api.owner && view.count == 0
		assert swift_array_sequence_count(metadata, 0, u64(unsafe { &source[0] })) == 0
	}
}

fn empty_array_worker(api EmptyArrayApi) {
	for _ in 0 .. 64 {
		if !api.native {
			assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '__swiftEmptyArrayStorage') or { panic(err) } == api.owner
		}
		empty_array_header(api.owner)
		assert api.keep(api.owner) == api.owner
		assert api.bridge_keep(api.owner) == api.owner
		assert api.unknown_keep(api.owner) == api.owner
		assert !api.unique(api.owner)
		api.drop(api.owner); api.bridge_drop(api.owner); api.unknown_drop(api.owner)
		api.drop_n(api.owner, 0); api.drop_n(api.owner, 0xffffffff)
		assert !api.unique(api.owner)
	}
}

fn empty_array_run(api EmptyArrayApi) {
	empty_array_header(api.owner)
	nested := api.access(0, api.int_type).metadata
	for element in [api.int_type, api.string_type, api.any_type, api.byte_type, nested]! {
		value := api.allocate(0, element)
		assert value.owner == api.owner && value.bytes == api.owner + 32
		assert api.buffer(0, element) == api.owner
		empty_array_payload(api, element)
	}
	mut workers := []thread{cap: 8}
	for _ in 0 .. 8 { workers << spawn empty_array_worker(api) }
	workers.wait()
	empty_array_header(api.owner)
}

fn empty_array_retired(address u64) {
	$if macos { assert C.mprotect(unsafe { voidptr(address) }, usize(C.getpagesize()), C.PROT_READ) == -1 }
	$else { mut resident := u8(0); assert C.mincore(unsafe { voidptr(address) }, usize(C.getpagesize()), &resident) == -1 }
}

fn test_swift_empty_array() {
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert core != unsafe { nil }
		api := EmptyArrayApi{native: true, owner: u64(C.dlsym(core, c'_swiftEmptyArrayStorage')),
			int_type: u64(C.dlsym(core, c'$sSiN')), string_type: u64(C.dlsym(core, c'$sSSN')),
			any_type: u64(C.dlsym(core, c'$sypN')) + 8, byte_type: u64(C.dlsym(core, c'$ss5UInt8VN')),
			allocate: unsafe { EmptyArrayAllocate(C.dlsym(core, c'$ss27_allocateUninitializedArrayySayxG_BptBwlF')) },
			buffer: unsafe { EmptyArrayBuffer(C.dlsym(core, c'$sSa28_allocateBufferUninitialized15minimumCapacitys06_ArrayB0VyxGSi_tFZ')) },
			access: unsafe { EmptyArrayAccess(C.dlsym(core, c'$sSaMa')) },
			keep: unsafe { EmptyArrayKeep(C.dlsym(core, c'swift_retain')) }, drop: unsafe { EmptyArrayDrop(C.dlsym(core, c'swift_release')) },
			drop_n: unsafe { EmptyArrayDropN(C.dlsym(core, c'swift_release_n')) },
			bridge_keep: unsafe { EmptyArrayKeep(C.dlsym(core, c'swift_bridgeObjectRetain')) }, bridge_drop: unsafe { EmptyArrayDrop(C.dlsym(core, c'swift_bridgeObjectRelease')) },
			unknown_keep: unsafe { EmptyArrayKeep(C.dlsym(core, c'swift_unknownObjectRetain')) }, unknown_drop: unsafe { EmptyArrayDrop(C.dlsym(core, c'swift_unknownObjectRelease')) },
			unique: unsafe { EmptyArrayUnique(C.dlsym(core, c'swift_isUniquelyReferenced_nonNull_native')) }}
		empty_array_run(api)
		println('IOS-EMPTY-ARRAY-NATIVE: direct singleton address, zero-capacity Int/String/Any/UInt8/nested factories, 20 Array witness operations, immortal native/bridge/unknown ARC, UInt32 release counts and eight workers')
	}
	for _ in 0 .. 2 {
		objc_start(); library := '/usr/lib/swift/libswiftCore.dylib'
		assert ios_runtime.swift_empty_array == 0
		for name in ['_swiftEmptyArrayStorage', '___swiftEmptyArrayStorage']! {
			if _ := runtime_symbol(library, name) { assert false }
		}
		if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '__swiftEmptyArrayStorage') { assert false }
		assert ios_runtime.swift_empty_array == 0
		mut resolvers := []thread u64{cap: 8}
		for _ in 0 .. 8 { resolvers << spawn empty_array_resolve() }
		owners := resolvers.wait(); owner := owners[0]
		for candidate in owners { assert candidate == owner }
		assert owner == ios_runtime.swift_empty_array && owner == swift_array_empty()
		empty_array_readonly(owner)
		assert owner !in ios_runtime.swift_arrays && owner !in ios_runtime.swift_heap && owner !in ios_runtime.swift_buffers
		// Private typed storage is deliberately not exposed as class metadata.
		if _ := swift_object_type_checked(owner) { assert false }
		api := EmptyArrayApi{owner: owner, int_type: swift_integer_metadata(), string_type: swift_string_metadata(),
			any_type: swift_any_full_metadata() + 8, byte_type: runtime_symbol(library, '_$ss5UInt8VN') or { panic(err) }}
		empty_array_run(api)
		assert ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0
		allocation := owner - 8
		objc_stop()
		assert ios_runtime.swift_empty_array == 0 && ios_runtime.live == 0
		empty_array_retired(allocation)
	}
	println('IOS-EMPTY-ARRAY: exact Core-only data export aliases canonical sealed storage; five element types, padded Array witnesses, zero counts, immortal ARC, concurrent import resolution and two drained/unmapped runtime lifetimes')
}
