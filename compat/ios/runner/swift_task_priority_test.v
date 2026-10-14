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
struct PriorityResponse { metadata u64 state u64 }
type PriorityAccess = fn (u64) PriorityResponse
type PriorityProbe = fn (u64, u64, u64, u64, u64, &u64)
type PriorityCopy = fn (u64, u64, u64) u64
type PriorityDestroy = fn (u64, u64)
type PriorityGet = fn (u64, u32, u64) u32
type PriorityStore = fn (u64, u32, u32, u64)
type PriorityLookup = fn (u64, u64, u64, u64) u64
type PriorityAllocate = fn (i64, u64) SwiftArrayAllocation
type PriorityRetain = fn (u64) u64
type PriorityRelease = fn (u64)
type PriorityArray = fn (u64, u64) SwiftAssociatedMetadata
struct PriorityApi {
	native bool
	metadata u64
	entry u64
	@[required]
	lookup PriorityLookup
	@[required]
	allocate PriorityAllocate
	@[required]
	retain PriorityRetain
	@[required]
	release PriorityRelease
	@[required]
	array PriorityArray
}
fn priority_relative(address u64) u64 {
	delta := i32(read32(address))
	return if delta == 0 { u64(0) } else { u64(i64(address) + delta) }
}
fn priority_protection(address u64, length u64, executable bool) {
	$if macos {
		mut start := address; mut size := u64(0); mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64); mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object) == 0
		assert start <= address && address + length <= start + size
		assert info[0] == (C.PROT_READ | if executable { C.PROT_EXEC } else { 0 })
		if object != 0 { assert C.mach_port_deallocate(task, object) == 0 }
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields(); if fields.len < 2 { continue }
			range := fields[0].split('-'); if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end {
				assert address + length <= end && fields[1] == if executable { 'r-xp' } else { 'r--p' }
				found = true; break
			}
		}
		assert found
	}
}
fn priority_layout(api PriorityApi, probe PriorityProbe) {
	metadata := api.metadata; witness := read64(metadata - 8); descriptor := read64(metadata + 8)
	assert read64(metadata) == 0x200 && read32(metadata + 16) == 0
	assert read64(witness + 64) == 1 && read64(witness + 72) == 1
	assert read32(witness + 80) == 0x02000000 && read32(witness + 84) == 0
	assert read32(descriptor) == 0x51 && read32(descriptor + 20) == 1 && read32(descriptor + 24) == 2
	assert ctext(priority_relative(descriptor + 8)) == 'TaskPriority'
	parent := priority_relative(descriptor + 4)
	assert read64(parent) == 0 && ctext(priority_relative(parent + 8)) == 'Swift'
	if !api.native {
		assert priority_relative(descriptor + 16) == 0 // Reflection remains unsupported.
		priority_protection(metadata - 8, 224, false); priority_protection(api.entry, 24, true)
	}
	for entry in [api.entry, priority_relative(descriptor + 12)]! {
		for request in [u64(0), 63, 255, 256, 319, 511]! { for _ in 0 .. 128 {
			mut output := [u64(0x1234), 0, 0, 0, 0, 0x5678]!
			probe(request, 0xdeadbeef, 0x5020, 0x5021, entry, unsafe { &output[1] })
			assert output[0] == 0x1234 && output[5] == 0x5678
			assert output[1] == metadata && output[2] == 0 && output[3] == 0x5020 && output[4] == 0x5021
		} }
	}
}
fn priority_expected_width(count u32) u32 {
	if count == 0 { return 0 }
	// Independent boundary table from the installed witness's measurements.
	return if count <= 65024 || count >= 0xffffff01 { u32(1) } else if count <= 0x00fffe00 { u32(2) } else { u32(4) }
}
fn priority_values(api PriorityApi) {
	metadata := api.metadata; table := read64(metadata - 8)
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 4, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(unsafe { voidptr(region) }, page, C.PROT_NONE) == 0
	assert C.mprotect(unsafe { voidptr(region + u64(page * 3)) }, page, C.PROT_NONE) == 0
	source := region + u64(page * 2) - 1; destination := region + u64(page * 3) - 1
	for value in 0 .. 256 {
		unsafe { *(&u8(source)) = u8(value) }
		assert C.mprotect(unsafe { voidptr(region + u64(page)) }, page, C.PROT_READ) == 0
		for slot in [0, 2, 3, 4, 5]! {
			copy_value := unsafe { PriorityCopy(voidptr(read64(table + u64(slot * 8)))) }
			assert copy_value(destination, source, metadata) == destination
			assert unsafe { *(&u8(destination)) } == u8(value) && unsafe { *(&u8(source)) } == u8(value)
			assert copy_value(destination, destination, metadata) == destination
		}
		assert C.mprotect(unsafe { voidptr(region + u64(page)) }, page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	destroy := unsafe { PriorityDestroy(voidptr(read64(table + 8))) }; destroy(region, metadata); destroy(0, metadata)
	get := unsafe { PriorityGet(voidptr(read64(table + 48))) }; store := unsafe { PriorityStore(voidptr(read64(table + 56))) }
	assert get(region, 0, metadata) == 0; store(region, 0, 0, metadata)
	for count in [u32(1), 2, 254, 255, 256, 65024, 65025, 65026, 65279, 65280, 65281,
		0x00fffe00, 0x00fffe01, 0xffffff00, 0xffffff01, 0xffffffff]! {
		length := priority_expected_width(count)
		for tag in [u32(0), 1, 2, 254, 255, 256, 257, 65279, 65280, 65281,
			0x00fffe00, 0x00fffe01, 0xffffff00, 0xffffff01, 0xfffffffe, 0xffffffff]! {
			if tag > count { continue }
			mut bytes := [u8(0xa5), 0xa5, 0xa5, 0xa5, 0xa5, 0xa5, 0xa5, 0xa5, 0xa5, 0xa5, 0xa5, 0xa5]!
			address := u64(unsafe { &bytes[3] }); store(address, tag, count, metadata)
			marker := if tag == 0 { u32(0) } else { ((tag - 1) >> 8) + 1 }; mut stored := u32(0)
			for index in u32(0) .. length {
				expected := u8(marker >> (index * 8)); assert bytes[4 + index] == expected
				stored |= u32(expected) << (index * 8)
			}
			wanted := if stored == 0 { u32(0) } else { ((stored << 8) | u32(bytes[3])) - u32(255) }
			assert get(address, count, metadata) == wanted
			assert bytes[3] == if tag == 0 { u8(0xa5) } else { u8(tag - 1) }
			for index in 0 .. bytes.len { if index != 3 && (index < 4 || index >= int(4 + length)) { assert bytes[index] == 0xa5 } }
			boundary := region + u64(page * 3) - u64(1 + length); store(boundary, tag, count, metadata)
			assert C.mprotect(unsafe { voidptr(region + u64(page * 2)) }, page, C.PROT_READ) == 0
			assert get(boundary, count, metadata) == wanted
			assert C.mprotect(unsafe { voidptr(region + u64(page * 2)) }, page, C.PROT_READ | C.PROT_WRITE) == 0
		}
	}
	assert C.munmap(unsafe { voidptr(region) }, page * 4) == 0
}
fn priority_arrays(api PriorityApi) {
	assert api.lookup(u64('ScP'.str), 3, 0, 0) == api.metadata
	array := api.array(0, api.metadata); assert array.state == 0 && read64(array.metadata + 16) == api.metadata
	assert api.lookup(u64('SayScPG'.str), 7, 0, 0) == array.metadata
	outer_metadata := api.array(0, array.metadata).metadata
	assert api.lookup(u64('SaySayScPGG'.str), 11, 0, 0) == outer_metadata
	for count in [i64(0), 1, 5, 257]! {
		value := api.allocate(count, api.metadata)
		assert value.owner != 0 && read64(value.owner + 16) == u64(count)
		assert value.bytes == value.owner + 32 && read64(value.owner + 24) >> 1 >= u64(count)
		for index in 0 .. count { unsafe { *(&u8(value.bytes + u64(index))) = u8(index) } }
		assert api.retain(value.owner) == value.owner; api.release(value.owner); api.release(value.owner)
	}
	inner := api.allocate(5, api.metadata); outer := api.allocate(3, array.metadata)
	for index in 0 .. 3 { unsafe { *(&u64(outer.bytes + u64(index * 8))) = api.retain(inner.owner) } }
	witness := read64(outer_metadata - 8)
	copy_value := unsafe { PriorityCopy(voidptr(read64(witness + 16))) }
	destroy := unsafe { PriorityDestroy(voidptr(read64(witness + 8))) }
	mut value := outer.owner; mut alias := u64(0)
	assert copy_value(u64(unsafe { &alias }), u64(unsafe { &value }), outer_metadata) == u64(unsafe { &alias })
	destroy(u64(unsafe { &value }), outer_metadata); destroy(u64(unsafe { &alias }), outer_metadata)
	api.release(inner.owner)
}
fn priority_worker(api PriorityApi) { for _ in 0 .. 32 { priority_arrays(api) } }
fn priority_bounded_lookup(api PriorityApi) {
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert region != u64(-1)
	name := region + u64(page) - 3
	unsafe { *(&u8(name)) = `S`; *(&u8(name + 1)) = `c`; *(&u8(name + 2)) = `P` }
	assert C.mprotect(unsafe { voidptr(region + u64(page)) }, page, C.PROT_NONE) == 0
	assert C.mprotect(unsafe { voidptr(region) }, page, C.PROT_READ) == 0
	assert api.lookup(name, 3, 0, 0) == api.metadata
	if !api.native {
		if result := swift_mangled_lookup_checked(name, 2, 0, 0) { assert result == 0 }
	}
	assert C.munmap(unsafe { voidptr(region) }, page * 2) == 0
}
fn priority_resolve() u64 {
	library := '/usr/lib/swift/libswift_Concurrency.dylib'
	entry := runtime_symbol(library, '_$sScPMa') or { panic(err) }
	access := unsafe { PriorityAccess(voidptr(entry)) }; response := access(0)
	assert response.state == 0 && response.metadata == (runtime_symbol(library, '_$sScPN') or { panic(err) })
	assert read64(response.metadata + 8) == (runtime_symbol(library, '_$sScPMn') or { panic(err) })
	return response.metadata
}
fn priority_run(api PriorityApi, probe PriorityProbe) {
	priority_layout(api, probe); priority_bounded_lookup(api); priority_values(api); priority_arrays(api)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn priority_worker(api) }; workers.wait()
}
fn test_swift_task_priority() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert code != u64(-1)
	for index, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0203f4, 0xaa0303f5, 0xaa0403f0,
		0xd63f0200, 0xa9000660, 0xa9015674, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(index * 4), op) }
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 56) }); assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { PriorityProbe(voidptr(code)) }
	$if macos {
		concurrency := C.dlopen(c'/usr/lib/swift/libswift_Concurrency.dylib', C.RTLD_NOW)
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW); assert concurrency != unsafe { nil } && core != unsafe { nil }
		metadata := u64(C.dlsym(concurrency, c'$sScPN')); assert metadata != 0
		assert u64(C.dlsym(concurrency, c'$sScPMn')) == read64(metadata + 8)
		priority_run(PriorityApi{native: true, metadata: metadata, entry: u64(C.dlsym(concurrency, c'$sScPMa')),
			lookup: unsafe { PriorityLookup(C.dlsym(core, c'swift_getTypeByMangledNameInContext')) },
			allocate: unsafe { PriorityAllocate(C.dlsym(core, c'$ss27_allocateUninitializedArrayySayxG_BptBwlF')) },
			retain: unsafe { PriorityRetain(C.dlsym(core, c'swift_bridgeObjectRetain')) },
			release: unsafe { PriorityRelease(C.dlsym(core, c'swift_bridgeObjectRelease')) },
			array: unsafe { PriorityArray(C.dlsym(core, c'$sSaMa')) }}, probe)
		println('IOS-SWIFT-TASK-PRIORITY-NATIVE: canonical byte metadata, nominal descriptor and guarded complete accessor responses; exact byte witnesses and enum width/wrap boundaries; ScP and nested Array lookup/ownership with eight workers')
	}
	if _ := swift_task_priority_arena() { assert false }
	for _ in 0 .. 2 {
		objc_start()
		assert ios_runtime.swift_task_priority_arena == 0
		for text in ['ScPSg', 'SayScPSgG', 'ScPjunk', 'Sc']! {
			if result := swift_mangled_lookup_checked(u64(text.str), u64(text.len), 0, 0) { assert result == 0, text }
		}
		for name in ['_$sScPSgMa', '_$sScPSQsMc', '_$sScMs11GlobalActorsMc']! {
			if _ := runtime_symbol('/usr/lib/swift/libswift_Concurrency.dylib', name) { assert false }
		}
		assert ios_runtime.swift_task_priority_arena == 0 && ios_runtime.swift_array_arena == 0
		mut resolvers := []thread u64{}; for _ in 0 .. 8 { resolvers << spawn priority_resolve() }
		resolved := resolvers.wait(); for address in resolved { assert address == resolved[0] }
		api := PriorityApi{metadata: resolved[0], entry: runtime_symbol('/usr/lib/swift/libswift_Concurrency.dylib', '_$sScPMa') or { panic(err) },
			lookup: swift_mangled_lookup, allocate: swift_array_allocate, retain: swift_bridge_retain, release: swift_bridge_release, array: swift_array_access}
		priority_run(api, probe)
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sScPMa') { assert false }
		assert ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.live == 0
		arena := ios_runtime.swift_task_priority_arena; objc_stop()
		assert ios_runtime.swift_task_priority_arena == 0 && ios_runtime.swift_array_arena == 0 && ios_runtime.swift_concurrency_retired
		if _ := swift_task_priority_arena() { assert false }
		$if macos { assert C.mprotect(unsafe { voidptr(arena) }, page * 2, C.PROT_READ) == -1 }
		$else { mut residency := u8(0); assert C.mincore(unsafe { voidptr(arena) }, page * 2, &residency) == -1 }
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0
	println('IOS-SWIFT-TASK-PRIORITY: canonical sealed accessor/read-only byte metadata, descriptor and eight value witnesses; guarded UInt8/unaligned enum width/wrap boundaries; ScP and nested Array ownership, eight resolvers/workers, unsupported Optional/conformances before allocation, wrong-library rejection, two drained/unmapped runtime lifetimes')
}
