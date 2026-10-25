// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv
$if macos {
	#include <objc/runtime.h>
	#include <mach/mach.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mincore(voidptr, usize, &u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32
type NativeValueCopy = fn (u64, u64, u64) u64
type NativeValueDestroy = fn (u64, u64)
type NativeValueGet = fn (u64, u32, u64) u32
type NativeValueStore = fn (u64, u32, u32, u64)
type NativeValueRetain = fn (u64) u64
type NativeValueRelease = fn (u64)
type NativeValueAllocate = fn (i64, u64) SwiftArrayAllocation
type NativeValueHeapAllocate = fn (u64, u64, u64) u64
type NativeValueHeapDeallocate = fn (u64, u64, u64)
type NativeValueSign = fn (u64, u64) u64
struct NativeValueApi {
	native bool
	table u64
	integer u64
	empty u64
	@[required]
	heap_allocate NativeValueHeapAllocate
	@[required]
	heap_deallocate NativeValueHeapDeallocate
	@[required]
	retain NativeValueRetain
	@[required]
	release NativeValueRelease
	@[required]
	allocate NativeValueAllocate
}
fn native_value_api(native bool) NativeValueApi {
	mut entries := [8]u64{}
	for i, name in ['_$sBoWV', '_swift_retain', '_swift_release',
		'_$ss27_allocateUninitializedArrayySayxG_BptBwlF', '_$sSiN', '__swiftEmptyArrayStorage', '_swift_allocObject', '_swift_deallocObject']! {
		if native {
			library := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			assert library != unsafe { nil }
			entries[i] = u64(C.dlsym(library, name[1..].str))
		} else { entries[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) } }
		assert entries[i] != 0
	}
	return NativeValueApi{ native: native, table: entries[0], integer: entries[4], empty: entries[5],
		heap_allocate: unsafe { NativeValueHeapAllocate(voidptr(entries[6])) },
		heap_deallocate: unsafe { NativeValueHeapDeallocate(voidptr(entries[7])) },
		retain: unsafe { NativeValueRetain(voidptr(entries[1])) }, release: unsafe { NativeValueRelease(voidptr(entries[2])) },
		allocate: unsafe { NativeValueAllocate(voidptr(entries[3])) } }
}
fn (api NativeValueApi) owner() u64 {
	value := api.allocate(1, api.integer)
	unsafe { *(&u64(value.bytes)) = 42 }
	return value.owner
}
fn (api NativeValueApi) refs(owner u64) u64 {
	return (read64(owner + 8) >> 33) + 1
}
fn native_value_copy(table u64, slot int) NativeValueCopy {
	return unsafe { NativeValueCopy(voidptr(read64(table + u64(slot * 8)) & 0x0000ffffffffffff)) }
}
fn native_value_destroy(table u64) NativeValueDestroy {
	return unsafe { NativeValueDestroy(voidptr(read64(table + 8) & 0x0000ffffffffffff)) }
}
fn native_value_ownership(api NativeValueApi) {
	owner := api.owner()
	assert api.refs(owner) == 1
	mut source := [u64(0x1234), owner, 0x5678]!
	mut destination := [u64(0x1234), 0, 0x5678]!
	src := u64(unsafe { &source[1] }); dst := u64(unsafe { &destination[1] })
	for slot in [0, 2]! {
		initialize := native_value_copy(api.table, slot)
		assert initialize(dst, src, 0) == dst
		assert source[1] == owner && destination[1] == owner && api.refs(owner) == 2
		destroy := native_value_destroy(api.table); destroy(dst, 0)
		assert destination[1] == owner && api.refs(owner) == 1
	}
	assign_copy := native_value_copy(api.table, 3)
	assert assign_copy(src, src, 0) == src && api.refs(owner) == 1
	for slot in [3, 5]! {
		destination[1] = api.owner()
		if slot == 5 { api.retain(owner) }
		assign := native_value_copy(api.table, slot)
		assert assign(dst, src, 0) == dst
		assert source[1] == owner && destination[1] == owner && api.refs(owner) == 2
		api.release(destination[1]); assert api.refs(owner) == 1
	}
	take := native_value_copy(api.table, 4)
	assert take(dst, src, 0) == dst
	assert destination[1] == owner && source[1] == owner && api.refs(owner) == 1
	// A take of aliased storage consumes the distinct source ownership.
	api.retain(owner)
	assign_take := native_value_copy(api.table, 5)
	assert assign_take(dst, dst, 0) == dst && api.refs(owner) == 1
	assert source[0] == 0x1234 && source[2] == 0x5678 && destination[0] == 0x1234 && destination[2] == 0x5678
	api.release(destination[1])
}
fn native_value_immortal(api NativeValueApi) {
	for owner in [u64(0), api.empty]! {
		mut source := owner; mut destination := u64(0)
		for slot in [0, 2, 3, 4, 5]! {
			operation := native_value_copy(api.table, slot)
			assert operation(u64(unsafe { &destination }), u64(unsafe { &source }), 0) == u64(unsafe { &destination })
			assert destination == owner && source == owner
		}
		destroy := native_value_destroy(api.table); destroy(u64(unsafe { &destination }), 0)
	}
}
fn native_value_enums(api NativeValueApi) {
	get := unsafe { NativeValueGet(voidptr(read64(api.table + 48) & 0x0000ffffffffffff)) }
	store := unsafe { NativeValueStore(voidptr(read64(api.table + 56) & 0x0000ffffffffffff)) }
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert region != u64(-1)
	assert C.mprotect(unsafe { voidptr(region) }, page, C.PROT_NONE) == 0
	assert C.mprotect(unsafe { voidptr(region + u64(page * 2)) }, page, C.PROT_NONE) == 0
	for count in [u32(0), 1, 2, 255, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff]! {
		length := if count > 0x7fffffff { 9 } else { 8 }
		for tag in [u32(0), 1, 2, 255, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff]! {
			if tag > count { continue }
			mut bytes := [24]u8{}
			for i in 0 .. bytes.len { bytes[i] = 0xa5 }
			address := u64(unsafe { &bytes[7] }); store(address, tag, count, 0)
			wanted := if tag == 0 { u64(0xa5a5a5a5a5a5a5a5) } else if tag <= 0x7fffffff { u64(tag - 1) } else { u64(tag - 0x80000000) }
			mut actual := u64(0)
			for i in 0 .. 8 { actual |= u64(bytes[7 + i]) << u32(i * 8) }
			assert actual == wanted && get(address, count, 0) == tag
			if length == 9 { assert bytes[15] == if tag > 0x7fffffff { u8(1) } else { u8(0) } }
			for i in 0 .. bytes.len { if i < 7 || i >= 7 + length { assert bytes[i] == 0xa5 } }
			boundary := region + u64(page * 2) - u64(length)
			C.memset(unsafe { voidptr(boundary) }, 0xa5, usize(length)); store(boundary, tag, count, 0)
			assert C.mprotect(unsafe { voidptr(region + u64(page)) }, page, C.PROT_READ) == 0
			assert get(boundary, count, 0) == tag
			assert C.mprotect(unsafe { voidptr(region + u64(page)) }, page, C.PROT_READ | C.PROT_WRITE) == 0
		}
		for bits in [u64(0), 1, 0xfff, 0x1000, 0x7fffffff, 0x80000000, 0xffffffff, 0x100000000, 0x8000000000000000]! {
			mut value := [bits, u64(0)]!
			assert get(u64(unsafe { &value[0] }), count, 0) == if bits >> 32 == 0 { u32(bits) + 1 } else { u32(0) }
		}
	}
	assert C.munmap(unsafe { voidptr(region) }, page * 3) == 0
}

struct NativeValueReentry {
	api NativeValueApi
	destination u64
	expected u64
mut:
	calls int
}
fn native_value_reader(state &NativeValueReentry) {
	assert read64(state.destination) == state.expected
	mut temporary := u64(0)
	initialize := native_value_copy(state.api.table, 2)
	assert initialize(u64(unsafe { &temporary }), state.destination, 0) == u64(unsafe { &temporary })
	assert temporary == state.expected
	if !state.api.native { assert native_value_resolve() == state.api.table }
	destroy := native_value_destroy(state.api.table); destroy(u64(unsafe { &temporary }), 0)
}
fn native_value_reentry_dealloc(owner u64) {
	mut state := unsafe { &NativeValueReentry(read64(owner + 16)) }
	assert state.calls == 0 && read64(owner + 8) == 0x100000003
	worker := spawn native_value_reader(state); worker.wait(); state.calls++
	state.api.heap_deallocate(owner, 24, 7)
}
fn native_value_reentry(api NativeValueApi) {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	words := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && words != u64(-1)
	// Swift deallocating destructors receive self in x20. The second entry
	// signs the destructor pointer for the installed arm64e runtime.
	for i, op in [u32(0xaa1403e0), 0x58000070, 0xd61f0200, 0xd503201f, 0, 0, 0, 0, 0xdac10020, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	unsafe { *(&u64(voidptr(code + 16))) = u64(voidptr(native_value_reentry_dealloc)) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 40))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	metadata := words + 24
	unsafe { *(&u64(voidptr(metadata))) = 0x400; *(&u64(voidptr(metadata - 16))) = code }
	$if macos { if api.native {
		sign := unsafe { NativeValueSign(voidptr(code + 32)) }
		unsafe { *(&u64(voidptr(metadata - 16))) = sign(code, (metadata - 16) | (u64(0xbbbf) << 48)) }
	} }
	assert C.mprotect(voidptr(words), page, C.PROT_READ) == 0
	for slot in [3, 5]! {
		mut source := api.owner(); mut destination := api.heap_allocate(metadata, 24, 7)
		state := unsafe { &NativeValueReentry(C.__builtin_alloca(sizeof(NativeValueReentry))) }
		unsafe { *state = NativeValueReentry{ api: api, destination: u64(&destination), expected: source }
			*(&u64(voidptr(destination + 16))) = u64(state) }
		if slot == 5 { api.retain(source) }
		assign := native_value_copy(api.table, slot)
		assert assign(u64(unsafe { &destination }), u64(unsafe { &source }), 0) == u64(unsafe { &destination })
		assert state.calls == 1 && destination == source && api.refs(source) == 2
		api.release(destination); api.release(source)
	}
	assert C.munmap(voidptr(words), page) == 0 && C.munmap(voidptr(code), page) == 0
}
fn native_value_worker(api NativeValueApi, owner u64) {
	initialize := native_value_copy(api.table, 0); destroy := native_value_destroy(api.table)
	for _ in 0 .. 1000 {
		mut source := owner; mut destination := u64(0)
		assert initialize(u64(unsafe { &destination }), u64(unsafe { &source }), 0) == u64(unsafe { &destination })
		assert destination == owner; destroy(u64(unsafe { &destination }), 0)
	}
}
fn native_value_resolve() u64 { return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sBoWV') or { panic(err) } }
fn native_value_read_only(address u64) {
	$if macos {
		mut start := address; mut size := u64(0); mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64); mut object := u32(0); task := C.mach_task_self()
		assert C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object) == 0
		assert start <= address && address + 88 <= start + size && info[0] == C.PROT_READ
		if object != 0 { assert C.mach_port_deallocate(task, object) == 0 }
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields(); if fields.len < 2 { continue }; range := fields[0].split('-'); if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }; end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end { assert address + 88 <= end && fields[1] == 'r--p'; found = true; break }
		}
		assert found
	}
}
type NativeValueProbe = fn (&u64, u64, &u64)

fn native_value_raw(api NativeValueApi) {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f1, 0xaa0103f0, 0xaa0203f3,
		0xd10043ff, 0xa9400620, 0xa9410e22, 0xa9421624, 0xa9431e26, 0xa9442a29, 0xa9002be9, 0xf9402a28,
		0xf9402e34, 0xf9403235, 0xd63f0200, 0xa9000660, 0xa9010e62, 0xa9025674, 0x910043ff, 0xa9425bf5,
		0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 100))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0 && C.mprotect(voidptr(code + u64(page)), page, C.PROT_NONE) == 0
	probe := unsafe { NativeValueProbe(voidptr(code)) }
	guard := code + u64(page)
	for slot in 0 .. 8 {
		mut source := [u64(0x1234), api.empty, u64(0x5678)]!
		mut destination := [u64(0x1234), u64(0), u64(0x5678)]!
		src := u64(unsafe { &source[1] })
		dst := u64(unsafe { &destination[1] })
		mut input := [dst, src, guard, guard, guard, guard, guard, guard, guard, guard, guard,
			guard, guard]!
		if slot == 1 {
			destination[1] = source[1]
			input[1] = guard
		}
		if slot == 6 {
			input[0] = src
			input[1] = 1
		}
		if slot == 7 {
			input[0] = src
			input[1] = 1
			input[2] = 1
		}
		mut output := [6]u64{}
		entry := read64(api.table + u64(slot * 8)) & 0x0000ffffffffffff
		probe(unsafe { &input[0] }, entry, unsafe { &output[0] })
		assert output[4] == guard && output[5] == guard
		if slot in [0, 2, 3, 4, 5]! {
			assert output[0] == dst && destination[1] == source[1]
		}
		if slot == 6 {
			assert u32(output[0]) == 0
		}
		assert source[0] == 0x1234 && source[2] == 0x5678 && destination[0] == 0x1234 && destination[2] == 0x5678
		assert source[1] == if slot == 7 { u64(0) } else { api.empty }
	}
	assert C.munmap(voidptr(code), page * 2) == 0
}

fn native_value_suite(api NativeValueApi) {
	assert read64(api.table + 64) == 8 && read64(api.table + 72) == 8
	assert read32(api.table + 80) == 0x10007 && read32(api.table + 84) == 0x7fffffff
	native_value_immortal(api); native_value_enums(api); native_value_raw(api); native_value_reentry(api)
	for _ in 0 .. 100 { native_value_ownership(api) }
	owner := api.owner()
	mut workers := []thread{}; for _ in 0 .. 8 { workers << spawn native_value_worker(api, owner) }; workers.wait()
	assert api.refs(owner) == 1; api.release(owner)
	if !api.native { native_value_read_only(api.table) }
}
fn test_swift_native_value() {
	$if macos {
		native_value_suite(native_value_api(true))
		println('IOS-SWIFT-NATIVE-VALUE-NATIVE: installed Builtin.NativeObject layout, eight witnesses, native ownership, nil/immortal values, guarded enum boundaries, ARM64 registers, destructor reentry and concurrent copies')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}; for _ in 0 .. 8 { publishers << spawn native_value_resolve() }; tables := publishers.wait()
		api := native_value_api(false); for table in tables { assert table == api.table }
		native_value_suite(api)
		assert (swift_core_symbol('_$sBoWV') or { panic('missing NativeObject witnesses') }) == api.table
		assert swift_core_symbol('_$sBoN') == none && swift_core_symbol('_$sBON') == none
		assert ios_runtime.live == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_heap.len == 0
		arena := ios_runtime.swift_unknown_value_arena; objc_stop()
		assert ios_runtime.swift_unknown_value_arena == 0 && ios_runtime.live == 0
		$if macos { assert C.mprotect(unsafe { voidptr(arena) }, usize(C.getpagesize()), C.PROT_READ) == -1 }
		$else { mut residency := u8(0); assert C.mincore(unsafe { voidptr(arena) }, usize(C.getpagesize()), &residency) == -1 }
	}
	println('IOS-SWIFT-NATIVE-VALUE: differential eight-slot witnesses, native assignments, self copy/take, unchanged moved bytes, guarded eight/nine-byte enums, ARM64 registers, eight publishers/workers, unlocked destructor reentry and two drained/sealed/unmapped lifetimes')
}
