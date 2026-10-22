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
type VoidCopy = fn (u64, u64, u64) u64
type VoidDestroy = fn (u64, u64)
type VoidGet = fn (u64, u32, u64) u32
type VoidStore = fn (u64, u32, u32, u64)
type VoidAllocate = fn (i64, u64) SwiftArrayAllocation
type VoidRetain = fn (u64) u64
type VoidRelease = fn (u64)
type VoidArray = fn (u64, u64) SwiftAssociatedMetadata

struct VoidApi {
	full u64
	witness u64
	@[required]
	allocate VoidAllocate
	@[required]
	retain VoidRetain
	@[required]
	release VoidRelease
	@[required]
	array VoidArray
}
fn void_witness(metadata u64) u64 { return read64(metadata - 8) & 0x0000ffffffffffff }
fn void_export() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sytWV') or { panic(err) }
}
fn void_resolve(witness_first bool) u64 {
	mut full := u64(0)
	for _ in 0 .. 64 {
		mut witness := u64(0)
		if witness_first { witness = void_export() }
		full = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sytN') or { panic(err) }
		if !witness_first { witness = void_export() }
		assert witness == void_witness(full + 8)
	}
	return full
}
fn void_readonly(full u64, bytes u64) {
	$if macos {
		mut address := full; mut size := u64(0); mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64); mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, &address, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object) == 0
		assert address <= full && full + bytes <= address + size && info[0] == C.PROT_READ
		if object != 0 { assert C.mach_port_deallocate(task, object) == 0 }
	} $else {
		maps := os.read_file('/proc/self/maps') or { panic(err) }
		mut found := false
		for line in maps.split_into_lines() {
			fields := line.fields(); if fields.len < 2 { continue }
			range := fields[0].split('-'); if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if full >= start && full < end {
				assert full + bytes <= end && fields[1] == 'r--p'
				found = true; break
			}
		}
		assert found
	}
}
fn void_values(api VoidApi, inaccessible u64) {
	void_readonly(api.full, 32)
	void_readonly(api.witness, 88)
	metadata := api.full + 8
	assert read64(metadata) == 0x301 && read64(metadata + 8) == 0 && read64(metadata + 16) == 0
	// The exported data symbol is the table itself, not a pointer cell or
	// metadata address point. Exercise every entry through that direct export.
	witness := api.witness
	assert witness != 0 && witness == void_witness(metadata)
	assert read64(witness + 64) == 0 && read64(witness + 72) == 1 && read64(witness + 80) == 0
	mut source := [u8(0xa5)].repeat(16)
	mut destination := [u8(0x5a)].repeat(16)
	for slot in [0, 2, 3, 4, 5]! {
		copy_value := unsafe { VoidCopy(voidptr(read64(witness + u64(slot * 8)))) }
		assert copy_value(u64(destination.data), u64(source.data), metadata) == u64(destination.data)
		assert source == [u8(0xa5)].repeat(16) && destination == [u8(0x5a)].repeat(16)
		assert copy_value(inaccessible, inaccessible, metadata) == inaccessible
		assert copy_value(0, 0, metadata) == 0
	}
	destroy := unsafe { VoidDestroy(voidptr(read64(witness + 8))) }
	destroy(u64(source.data), metadata); destroy(inaccessible, metadata); destroy(0, metadata)
	assert source == [u8(0xa5)].repeat(16)
	get := unsafe { VoidGet(voidptr(read64(witness + 48))) }
	store := unsafe { VoidStore(voidptr(read64(witness + 56))) }
	for count in [u32(0), 1, 2, 254, 255, 256, 65534, 65535, 65536, 0xfffffffe, 0xffffffff]! {
		width := if count == 0 || count == 0xffffffff { 0 } else if count < 255 { 1 } else if count < 65535 { 2 } else { 4 }
		for tag in [u32(0), 1, 2, 254, 255, 256, 65534, 65535, 65536, 0xfffffffe, 0xffffffff]! {
			if tag > count { continue }
			// Unaligned addresses and guards on both sides expose excessive stores.
			mut bytes := [u8(0xa5)].repeat(16)
			address := u64(bytes.data) + 1
			store(address, tag, count, metadata)
			assert get(address, count, metadata) == if count == 0xffffffff { u32(0) } else { tag }
			for i in 0 .. 16 {
				expected := if i > 0 && i <= width { u8(tag >> u32((i - 1) * 8)) } else { u8(0xa5) }
				assert bytes[i] == expected
			}
		}
		if width == 0 {
			store(inaccessible, 1, count, metadata)
			assert get(inaccessible, count, metadata) == 0
			store(0, 0, count, metadata); assert get(0, count, metadata) == 0
		}
	}
	// Place exactly the tag width before a protected page. Both witnesses
	// must stay inside that width, including two-byte unaligned accesses.
	page := u64(C.getpagesize())
	for count in [u32(1), 254, 255, 65534, 65535, 0xfffffffe]! {
		width := if count < 255 { u64(1) } else if count < 65535 { u64(2) } else { u64(4) }
		address := inaccessible - width
		store(address, count, count, metadata)
		assert C.mprotect(unsafe { voidptr(inaccessible - page) }, usize(page), C.PROT_READ) == 0
		assert get(address, count, metadata) == count
		assert C.mprotect(unsafe { voidptr(inaccessible - page) }, usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	}
}
fn void_arrays(api VoidApi) {
	metadata := api.full + 8
	array := api.array(0, metadata)
	assert array.state == 0 && read64(array.metadata + 16) & swift_address_mask == metadata
	assert api.array(0xff, metadata).metadata == array.metadata
	for count in [i64(0), 1, 5, 257]! {
		value := api.allocate(count, metadata)
		assert value.owner != 0 && value.bytes == value.owner + 32 && read64(value.owner + 16) == u64(count)
		assert read64(value.owner + 24) >> 1 >= u64(count)
		assert api.retain(value.owner) == value.owner
		api.release(value.owner); api.release(value.owner)
	}
	inner := api.allocate(5, metadata)
	outer := api.allocate(3, array.metadata)
	for i in 0 .. 3 { unsafe { *(&u64(outer.bytes + u64(i * 8))) = api.retain(inner.owner) } }
	witness := void_witness(api.array(0, array.metadata).metadata)
	copy_value := unsafe { VoidCopy(voidptr(read64(witness + 16))) }
	destroy := unsafe { VoidDestroy(voidptr(read64(witness + 8))) }
	mut value := outer.owner; mut alias := u64(0)
	assert copy_value(u64(unsafe { &alias }), u64(unsafe { &value }), api.array(0, array.metadata).metadata) == u64(unsafe { &alias })
	destroy(u64(unsafe { &value }), api.array(0, array.metadata).metadata)
	assert read64(inner.owner + 8) == 0x600000003
	destroy(u64(unsafe { &alias }), api.array(0, array.metadata).metadata)
	assert read64(inner.owner + 8) == 3
	api.release(inner.owner)
}
fn void_worker(api VoidApi) { for _ in 0 .. 64 { void_arrays(api) } }
fn void_run(api VoidApi, inaccessible u64) {
	void_values(api, inaccessible); void_arrays(api)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn void_worker(api) }
	workers.wait()
}
fn test_swift_void() {
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	inaccessible := region + u64(page)
	assert C.mprotect(unsafe { voidptr(inaccessible) }, page, C.PROT_NONE) == 0
	defer { assert C.munmap(unsafe { voidptr(region) }, page * 2) == 0 }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		assert C.dlsym(lib, c'swift_getTupleTypeMetadata') != unsafe { nil }
		full := u64(C.dlsym(lib, c'$sytN')); assert full != 0
		witness := u64(C.dlsym(lib, c'$sytWV')); assert witness != 0
		void_run(VoidApi{ full: full, witness: witness, allocate: unsafe { VoidAllocate(C.dlsym(lib, c'$ss27_allocateUninitializedArrayySayxG_BptBwlF')) },
			retain: unsafe { VoidRetain(C.dlsym(lib, c'swift_bridgeObjectRetain')) },
			release: unsafe { VoidRelease(C.dlsym(lib, c'swift_bridgeObjectRelease')) },
			array: unsafe { VoidArray(C.dlsym(lib, c'$sSaMa')) } }, inaccessible)
		println('IOS-SWIFT-VOID-NATIVE: direct exported VWT aliases full metadata, both read-only extents, no-touch zero-size witnesses, exact tag widths with protected boundaries, Array<Void> and nested ownership, eight workers')
	}
	for cycle in 0 .. 2 {
		objc_start()
		assert swift_core_symbol('_$sytWVunknown') == none && ios_runtime.swift_void_arena == 0
		assert runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib', '_$sytWV') == none
		assert ios_runtime.swift_void_arena == 0
		mut resolvers := []thread u64{}
		for _ in 0 .. 8 { resolvers << spawn void_resolve(cycle == 0) }
		resolved := resolvers.wait()
		for full in resolved { assert full == resolved[0] && full != 0 }
		assert void_export() == ios_runtime.swift_void_arena + 32
		void_run(VoidApi{ full: resolved[0], witness: void_export(), allocate: swift_array_allocate,
			retain: swift_bridge_retain, release: swift_bridge_release, array: swift_array_access }, inaccessible)
		assert ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.objects.len == 0
		arena := ios_runtime.swift_void_arena
		objc_stop()
		assert ios_runtime.swift_void_arena == 0 && ios_runtime.swift_array_arena == 0 && ios_runtime.live == 0
		$if macos { assert C.mprotect(unsafe { voidptr(arena) }, page, C.PROT_READ) == -1 }
		$else { mut residency := u8(0); assert C.mincore(unsafe { voidptr(arena) }, page, &residency) == -1 }
	}
	println('IOS-SWIFT-VOID: canonical direct VWT export/full metadata alias, read-only extents, table-first and metadata-first concurrent publication, no-touch POD witnesses, exact enum tags including UInt32 wrap, protected/unaligned storage, nested Array ownership, eight workers and two drained/unmapped teardowns')
}
