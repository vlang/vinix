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
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.mincore(voidptr, usize, &u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32
type UnknownSend = fn (u64, u64) u64
type UnknownCopy = fn (u64, u64, u64) u64
type UnknownDestroy = fn (u64, u64)
type UnknownGet = fn (u64, u32, u64) u32
type UnknownStore = fn (u64, u32, u32, u64)
type UnknownRetain = fn (u64) u64
type UnknownRelease = fn (u64)
type UnknownAllocate = fn (i64, u64) SwiftArrayAllocation
struct UnknownApi {
	native bool
	table u64
	integer u64
	@[required]
	retain UnknownRetain
	@[required]
	release UnknownRelease
	@[required]
	allocate UnknownAllocate
}
fn unknown_api(native bool) UnknownApi {
	mut entries := [5]u64{}
	for i, name in ['_$sBOWV', '_swift_unknownObjectRetain', '_swift_unknownObjectRelease',
		'_$ss27_allocateUninitializedArrayySayxG_BptBwlF', '_$sSiN']! {
		if native {
			library := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			assert library != unsafe { nil }
			entries[i] = u64(C.dlsym(library, name[1..].str))
		} else { entries[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) } }
		assert entries[i] != 0
	}
	return UnknownApi{ native: native, table: entries[0], integer: entries[4],
		retain: unsafe { UnknownRetain(voidptr(entries[1])) }, release: unsafe { UnknownRelease(voidptr(entries[2])) },
		allocate: unsafe { UnknownAllocate(voidptr(entries[3])) } }
}
fn unknown_send(owner u64, selector &char) u64 {
	return unsafe { UnknownSend(C.dlsym(voidptr(-2), c'objc_msgSend'))(owner, u64(C.sel_registerName(selector))) }
}
fn (api UnknownApi) owner(native_heap bool) u64 {
	if native_heap {
		value := api.allocate(1, api.integer)
		unsafe { *(&u64(value.bytes)) = 42 }
		return value.owner
	}
	$if macos { if api.native { return unknown_send(u64(C.objc_getClass(c'NSObject')), c'new') } }
	return objc_allocate(ios_runtime.names['NSObject'])
}
fn (api UnknownApi) refs(owner u64, native_heap bool) u64 {
	if native_heap { return (read64(owner + 8) >> 33) + 1 }
	$if macos { if api.native { return unknown_send(owner, c'retainCount') } }
	return u64(obj_header(owner).refs)
}
fn unknown_copy(table u64, slot int) UnknownCopy {
	return unsafe { UnknownCopy(voidptr(read64(table + u64(slot * 8)) & 0x0000ffffffffffff)) }
}
fn unknown_destroy(table u64) UnknownDestroy {
	return unsafe { UnknownDestroy(voidptr(read64(table + 8) & 0x0000ffffffffffff)) }
}
fn unknown_ownership(api UnknownApi, native_heap bool) {
	owner := api.owner(native_heap)
	assert api.refs(owner, native_heap) == 1
	mut source := [u64(0x1234), owner, 0x5678]!
	mut destination := [u64(0x1234), 0, 0x5678]!
	src := u64(unsafe { &source[1] }); dst := u64(unsafe { &destination[1] })
	for slot in [0, 2]! {
		initialize := unknown_copy(api.table, slot)
		assert initialize(dst, src, 0) == dst
		assert source[1] == owner && destination[1] == owner && api.refs(owner, native_heap) == 2
		destroy := unknown_destroy(api.table); destroy(dst, 0)
		assert destination[1] == owner && api.refs(owner, native_heap) == 1
	}
	assign_copy := unknown_copy(api.table, 3)
	assert assign_copy(src, src, 0) == src && api.refs(owner, native_heap) == 1
	for slot in [3, 5]! {
		destination[1] = api.owner(!native_heap) // Replacement crosses ARC domains.
		if slot == 5 { api.retain(owner) }
		assign := unknown_copy(api.table, slot)
		assert assign(dst, src, 0) == dst
		assert source[1] == owner && destination[1] == owner && api.refs(owner, native_heap) == 2
		api.release(destination[1]); assert api.refs(owner, native_heap) == 1
	}
	take := unknown_copy(api.table, 4)
	assert take(dst, src, 0) == dst
	assert destination[1] == owner && source[1] == owner && api.refs(owner, native_heap) == 1
	// A take of aliased storage consumes the distinct source ownership.
	api.retain(owner)
	assign_take := unknown_copy(api.table, 5)
	assert assign_take(dst, dst, 0) == dst && api.refs(owner, native_heap) == 1
	assert source[0] == 0x1234 && source[2] == 0x5678 && destination[0] == 0x1234 && destination[2] == 0x5678
	api.release(destination[1])
}
fn unknown_immortal(api UnknownApi) {
	for owner in [u64(0), 0x8000000000000000, 0xffffffffffffffff]! {
		mut source := owner; mut destination := u64(0)
		for slot in [0, 2, 3, 4, 5]! {
			operation := unknown_copy(api.table, slot)
			assert operation(u64(unsafe { &destination }), u64(unsafe { &source }), 0) == u64(unsafe { &destination })
			assert destination == owner && source == owner
		}
		destroy := unknown_destroy(api.table); destroy(u64(unsafe { &destination }), 0)
	}
}
fn unknown_enums(api UnknownApi) {
	get := unsafe { UnknownGet(voidptr(read64(api.table + 48) & 0x0000ffffffffffff)) }
	store := unsafe { UnknownStore(voidptr(read64(api.table + 56) & 0x0000ffffffffffff)) }
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
struct UnknownReentry {
	destination u64
	expected u64
	table u64
mut:
	calls int
}
fn unknown_reader(state &UnknownReentry) {
	assert read64(state.destination) == state.expected
	mut temporary := u64(0)
	initialize := unknown_copy(state.table, 2)
	assert initialize(u64(unsafe { &temporary }), state.destination, 0) == u64(unsafe { &temporary })
	assert temporary == state.expected && swift_unknown_value_witnesses() == state.table
	destroy := unknown_destroy(state.table); destroy(u64(unsafe { &temporary }), 0)
}
fn unknown_reentry_dealloc(owner u64, _selector &char) {
	mut state := unsafe { &UnknownReentry(obj_header(owner).tag) }
	assert state.calls == 0
	worker := spawn unknown_reader(state); worker.wait(); state.calls++
}
fn unknown_reentry(api UnknownApi) {
	cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixUnknownValueReentry', 0)
	assert cls != 0; objc_register_class(cls)
	objc_replace_method(cls, objc_selector(c'dealloc'), u64(unsafe { voidptr(unknown_reentry_dealloc) }), c'v16@0:8')
	for native_heap in [false, true]! { for slot in [3, 5]! {
		mut source := api.owner(native_heap); mut destination := objc_allocate(cls)
		state := unsafe { &UnknownReentry(C.__builtin_alloca(sizeof(UnknownReentry))) }
		unsafe { *state = UnknownReentry{ destination: u64(&destination), expected: source, table: api.table } }
		mut header := obj_header(destination); header.tag = i64(state)
		if slot == 5 { api.retain(source) }
		assign := unknown_copy(api.table, slot)
		assert assign(u64(unsafe { &destination }), u64(unsafe { &source }), 0) == u64(unsafe { &destination })
		assert state.calls == 1 && destination == source && api.refs(source, native_heap) == 2
		api.release(destination); api.release(source)
	} }
}
fn unknown_worker(api UnknownApi, owner u64) {
	initialize := unknown_copy(api.table, 0); destroy := unknown_destroy(api.table)
	for _ in 0 .. 1000 {
		mut source := owner; mut destination := u64(0)
		assert initialize(u64(unsafe { &destination }), u64(unsafe { &source }), 0) == u64(unsafe { &destination })
		assert destination == owner; destroy(u64(unsafe { &destination }), 0)
	}
}
fn unknown_resolve() u64 { return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sBOWV') or { panic(err) } }
fn unknown_read_only(address u64) {
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
fn unknown_suite(api UnknownApi) {
	assert read64(api.table + 64) == 8 && read64(api.table + 72) == 8
	assert read32(api.table + 80) == 0x10007 && read32(api.table + 84) == 0x7fffffff
	unknown_immortal(api); unknown_enums(api)
	for native_heap in [false, true]! {
		for _ in 0 .. 100 { unknown_ownership(api, native_heap) }
		owner := api.owner(native_heap)
		mut workers := []thread{}; for _ in 0 .. 8 { workers << spawn unknown_worker(api, owner) }; workers.wait()
		assert api.refs(owner, native_heap) == 1; api.release(owner)
	}
	if !api.native { unknown_reentry(api); unknown_read_only(api.table) }
}
fn test_swift_unknown_value() {
	$if macos {
		unknown_suite(unknown_api(true))
		println('IOS-SWIFT-UNKNOWN-NATIVE: installed Builtin.UnknownObject layout, all eight witnesses, ObjC/native reference ownership, nil/tagged values, guarded enum boundaries and concurrent copies')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}; for _ in 0 .. 8 { publishers << spawn unknown_resolve() }; tables := publishers.wait()
		api := unknown_api(false); for table in tables { assert table == api.table }
		unknown_suite(api)
		assert swift_core_symbol('_$sBoWV') == none && swift_core_symbol('_$sBON') == none
		assert ios_runtime.live == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_buffers.len == 0
		arena := api.table; objc_stop()
		assert ios_runtime.swift_unknown_value_arena == 0 && ios_runtime.live == 0
		$if macos { assert C.mprotect(unsafe { voidptr(arena) }, usize(C.getpagesize()), C.PROT_READ) == -1 }
		$else { mut residency := u8(0); assert C.mincore(unsafe { voidptr(arena) }, usize(C.getpagesize()), &residency) == -1 }
	}
	println('IOS-SWIFT-UNKNOWN: differential eight-slot witnesses, cross-domain assignments, self copy/take, unchanged moved bytes, guarded eight/nine-byte enums, eight publishers/workers, unlocked destructor reentry and two drained/sealed/unmapped lifetimes')
}
