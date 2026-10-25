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

type BridgeValueSend = fn (u64, u64) u64
type BridgeValueCopy = fn (u64, u64, u64) u64
type BridgeValueDestroy = fn (u64, u64)
type BridgeValueGet = fn (u64, u32, u64) u32
type BridgeValueStore = fn (u64, u32, u32, u64)
type BridgeValueRetain = fn (u64) u64
type BridgeValueRelease = fn (u64)
type BridgeValueAllocate = fn (i64, u64) SwiftArrayAllocation

struct BridgeValueApi {
	native   bool
	table    u64
	integer  u64
	retain   BridgeValueRetain @[required]
	release  BridgeValueRelease @[required]
	allocate BridgeValueAllocate @[required]
}

fn bridge_value_api(native bool) BridgeValueApi {
	mut entries := [5]u64{}
	for i, name in ['_$sBbWV', '_swift_bridgeObjectRetain', '_swift_bridgeObjectRelease',
		'_$ss27_allocateUninitializedArrayySayxG_BptBwlF', '_$sSiN']! {
		if native {
			library := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			assert library != unsafe { nil }
			entries[i] = u64(C.dlsym(library, name[1..].str))
		} else {
			entries[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) }
		}
		assert entries[i] != 0
	}
	return BridgeValueApi{
		native:   native
		table:    entries[0]
		integer:  entries[4]
		retain:   unsafe { BridgeValueRetain(voidptr(entries[1])) }
		release:  unsafe { BridgeValueRelease(voidptr(entries[2])) }
		allocate: unsafe { BridgeValueAllocate(voidptr(entries[3])) }
	}
}

fn bridge_value_send(owner u64, selector &char) u64 {
	return unsafe { BridgeValueSend(C.dlsym(voidptr(-2), c'objc_msgSend'))(owner, u64(C.sel_registerName(selector))) }
}

fn (api BridgeValueApi) owner(native_heap bool) u64 {
	if native_heap {
		value := api.allocate(1, api.integer)
		unsafe { *(&u64(value.bytes)) = 42 }
		return value.owner | u64(0x3000000000000000)
	}
	$if macos {
		if api.native {
			return bridge_value_send(u64(C.objc_getClass(c'NSObject')), c'new') | u64(0x4000000000000000)
		}
	}
	return objc_allocate(ios_runtime.names['NSObject']) | u64(0x4000000000000000)
}

fn (api BridgeValueApi) refs(owner u64, native_heap bool) u64 {
	raw := owner & swift_address_mask
	if native_heap { return (read64(raw + 8) >> 33) + 1 }
	$if macos {
		if api.native { return bridge_value_send(raw, c'retainCount') }
	}
	return u64(obj_header(raw).refs)
}

fn bridge_value_copy(table u64, slot int) BridgeValueCopy {
	return unsafe { BridgeValueCopy(voidptr(read64(table + u64(slot * 8)) & 0x0000ffffffffffff)) }
}

fn bridge_value_destroy(table u64) BridgeValueDestroy {
	return unsafe { BridgeValueDestroy(voidptr(read64(table + 8) & 0x0000ffffffffffff)) }
}

fn bridge_value_ownership(api BridgeValueApi, native_heap bool) {
	owner := api.owner(native_heap)
	assert api.refs(owner, native_heap) == 1
	mut source := [u64(0x1234), owner, 0x5678]!
	mut destination := [u64(0x1234), 0, 0x5678]!
	src := u64(unsafe { &source[1] })
	dst := u64(unsafe { &destination[1] })
	for slot in [0, 2]! {
		initialize := bridge_value_copy(api.table, slot)
		assert initialize(dst, src, 0) == dst
		assert source[1] == owner && destination[1] == owner && api.refs(owner, native_heap) == 2
		destroy := bridge_value_destroy(api.table)
		destroy(dst, 0)
		assert destination[1] == owner && api.refs(owner, native_heap) == 1
	}
	assign_copy := bridge_value_copy(api.table, 3)
	assert assign_copy(src, src, 0) == src && api.refs(owner, native_heap) == 1
	for slot in [3, 5]! {
		destination[1] = api.owner(!native_heap) // Replacement crosses ARC domains.
		if slot == 5 { api.retain(owner) }
		assign := bridge_value_copy(api.table, slot)
		assert assign(dst, src, 0) == dst
		assert source[1] == owner && destination[1] == owner && api.refs(owner, native_heap) == 2
		api.release(destination[1])
		assert api.refs(owner, native_heap) == 1
	}
	take := bridge_value_copy(api.table, 4)
	assert take(dst, src, 0) == dst
	assert destination[1] == owner && source[1] == owner && api.refs(owner, native_heap) == 1
	// A take of aliased storage consumes the distinct source ownership.
	api.retain(owner)
	assign_take := bridge_value_copy(api.table, 5)
	assert assign_take(dst, dst, 0) == dst && api.refs(owner, native_heap) == 1
	assert source[0] == 0x1234 && source[2] == 0x5678 && destination[0] == 0x1234 && destination[2] == 0x5678
	api.release(destination[1])
}

fn bridge_value_immortal(api BridgeValueApi) {
	for owner in [u64(0), 0x8000000000000000, 0xffffffffffffffff]! {
		mut source := owner
		mut destination := u64(0)
		for slot in [0, 2, 3, 4, 5]! {
			operation := bridge_value_copy(api.table, slot)
			assert operation(u64(unsafe { &destination }), u64(unsafe { &source }), 0) == u64(unsafe { &destination })
			assert destination == owner && source == owner
		}
		destroy := bridge_value_destroy(api.table)
		destroy(u64(unsafe { &destination }), 0)
	}
}

fn bridge_value_enums(api BridgeValueApi) {
	get := unsafe { BridgeValueGet(voidptr(read64(api.table + 48) & 0x0000ffffffffffff)) }
	store := unsafe { BridgeValueStore(voidptr(read64(api.table + 56) & 0x0000ffffffffffff)) }
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(unsafe { voidptr(region) }, page, C.PROT_NONE) == 0
	assert C.mprotect(unsafe { voidptr(region + u64(page * 2)) }, page, C.PROT_NONE) == 0
	for count in [u32(0), 1, 2, 255, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff]! {
		length := if count > 0x7fffffff { 9 } else { 8 }
		for tag in [u32(0), 1, 2, 255, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff]! {
			if tag > count { continue }
			mut bytes := [24]u8{}
			for i in 0 .. bytes.len { bytes[i] = 0xa5 }
			address := u64(unsafe { &bytes[7] })
			store(address, tag, count, 0)
			wanted := if tag == 0 {
				u64(0xa5a5a5a5a5a5a5a5)
			} else if tag <= 0x7fffffff {
				u64(tag - 1)
			} else {
				u64(tag - 0x80000000)
			}
			mut actual := u64(0)
			for i in 0 .. 8 { actual |= u64(bytes[7 + i]) << u32(i * 8) }
			assert actual == wanted && get(address, count, 0) == tag
			if length == 9 {
				assert bytes[15] == if tag > 0x7fffffff { u8(1) } else { u8(0) }
			}
			for i in 0 .. bytes.len {
				if i < 7 || i >= 7 + length {
					assert bytes[i] == 0xa5
				}
			}
			boundary := region + u64(page * 2) - u64(length)
			C.memset(unsafe { voidptr(boundary) }, 0xa5, usize(length))
			store(boundary, tag, count, 0)
			assert C.mprotect(unsafe { voidptr(region + u64(page)) }, page, C.PROT_READ) == 0
			assert get(boundary, count, 0) == tag
			assert C.mprotect(unsafe { voidptr(region + u64(page)) }, page, C.PROT_READ | C.PROT_WRITE) == 0
		}
		for bits in [u64(0), 1, 0xfff, 0x1000, 0x7fffffff, 0x80000000, 0xffffffff, 0x100000000,
			0x8000000000000000]! {
			mut value := [bits, u64(0)]!
			assert get(u64(unsafe { &value[0] }), count, 0) == if bits >> 32 == 0 {
				u32(bits) + 1
			} else {
				u32(0)
			}
		}
	}
	assert C.munmap(unsafe { voidptr(region) }, page * 3) == 0
}

struct BridgeValueReentry {
	destination u64
	expected    u64
	table       u64
mut:
	calls int
}

fn bridge_value_reader(state &BridgeValueReentry) {
	assert read64(state.destination) == state.expected
	mut temporary := u64(0)
	initialize := bridge_value_copy(state.table, 2)
	assert initialize(u64(unsafe { &temporary }), state.destination, 0) == u64(unsafe { &temporary })
	assert temporary == state.expected && swift_bridge_value_witnesses() == state.table
	destroy := bridge_value_destroy(state.table)
	destroy(u64(unsafe { &temporary }), 0)
}

fn bridge_value_reentry_dealloc(owner u64, _selector &char) {
	mut state := unsafe { &BridgeValueReentry(obj_header(owner).tag) }
	assert state.calls == 0
	worker := spawn bridge_value_reader(state)
	worker.wait()
	state.calls++
}

fn bridge_value_reentry(api BridgeValueApi) {
	cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixBridgeValueValueReentry', 0)
	assert cls != 0
	objc_register_class(cls)
	objc_replace_method(cls, objc_selector(c'dealloc'), u64(unsafe { voidptr(bridge_value_reentry_dealloc) }), c'v16@0:8')
	for native_heap in [false, true]! {
		for slot in [3, 5]! {
			mut source := api.owner(native_heap)
			mut destination := objc_allocate(cls) | u64(0x4000000000000000)
			state := unsafe { &BridgeValueReentry(C.__builtin_alloca(sizeof(BridgeValueReentry))) }
			unsafe { *state = BridgeValueReentry{ destination: u64(&destination), expected: source, table: api.table } }
			mut header := obj_header(destination & swift_address_mask)
			header.tag = i64(state)
			if slot == 5 { api.retain(source) }
			assign := bridge_value_copy(api.table, slot)
			assert assign(u64(unsafe { &destination }), u64(unsafe { &source }), 0) == u64(unsafe { &destination })
			assert state.calls == 1 && destination == source && api.refs(source, native_heap) == 2
			api.release(destination)
			api.release(source)
		}
	}
}

fn bridge_value_worker(api BridgeValueApi, owner u64) {
	initialize := bridge_value_copy(api.table, 0)
	destroy := bridge_value_destroy(api.table)
	for _ in 0 .. 1000 {
		mut source := owner
		mut destination := u64(0)
		assert initialize(u64(unsafe { &destination }), u64(unsafe { &source }), 0) == u64(unsafe { &destination })
		assert destination == owner
		destroy(u64(unsafe { &destination }), 0)
	}
}

fn bridge_value_resolve() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sBbWV') or { panic(err) }
}

fn bridge_value_read_only(address u64) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object) == 0
		assert start <= address && address + 88 <= start + size && info[0] == C.PROT_READ
		if object != 0 {
			assert C.mach_port_deallocate(task, object) == 0
		}
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields()
			if fields.len < 2 { continue }
			range := fields[0].split('-')
			if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end {
				assert address + 88 <= end && fields[1] == 'r--p'
				found = true
				break
			}
		}
		assert found
	}
}

fn bridge_value_suite(api BridgeValueApi) {
	assert read64(api.table + 64) == 8 && read64(api.table + 72) == 8
	assert read32(api.table + 80) == 0x10007 && read32(api.table + 84) == 0x7fffffff
	bridge_value_immortal(api)
	bridge_value_enums(api)
	bridge_value_raw(api)
	for native_heap in [false, true]! {
		for _ in 0 .. 100 { bridge_value_ownership(api, native_heap) }
		owner := api.owner(native_heap)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn bridge_value_worker(api, owner) }
		workers.wait()
		assert api.refs(owner, native_heap) == 1
		api.release(owner)
	}
	if !api.native {
		bridge_value_reentry(api)
		bridge_value_read_only(api.table)
	}
}

type BridgeValueProbe = fn (&u64, u64, &u64)

fn bridge_value_raw(api BridgeValueApi) {
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
	probe := unsafe { BridgeValueProbe(voidptr(code)) }
	guard := code + u64(page)
	for slot in 0 .. 8 {
		mut source := [u64(0x1234), u64(0xa123456789abcdef), u64(0x5678)]!
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
		assert source[1] == if slot == 7 { u64(0) } else { u64(0xa123456789abcdef) }
	}
	assert C.munmap(voidptr(code), page * 2) == 0
}

fn test_swift_bridge_value() {
	$if macos {
		bridge_value_suite(bridge_value_api(true))
		println('IOS-SWIFT-BRIDGE-VALUE-NATIVE: installed Builtin.BridgeObject layout, all eight witnesses, ObjC/native reference ownership with spare bridge bits, nil/tagged values, guarded enum boundaries and concurrent copies')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn bridge_value_resolve() }
		tables := publishers.wait()
		api := bridge_value_api(false)
		for table in tables {
			assert table == api.table
		}
		bridge_value_suite(api)
		assert (swift_core_symbol('_$sBoWV') or { panic('missing NativeObject witnesses') }) == swift_native_value_witnesses()
		assert swift_core_symbol('_$sBON') == none
		assert ios_runtime.live == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_buffers.len == 0
		assert api.table == swift_unknown_value_witnesses() + 128
		arena := api.table - 128
		objc_stop()
		assert ios_runtime.swift_unknown_value_arena == 0 && ios_runtime.live == 0
		$if macos {
			assert C.mprotect(unsafe { voidptr(arena) }, usize(C.getpagesize()), C.PROT_READ) == -1
		} $else {
			mut residency := u8(0)
			assert C.mincore(unsafe { voidptr(arena) }, usize(C.getpagesize()), &residency) == -1
		}
	}
	println('IOS-SWIFT-BRIDGE-VALUE: differential eight-slot witnesses, encoded cross-domain assignments, self copy/take, unchanged moved bytes, guarded eight/nine-byte enums, eight publishers/workers, unlocked destructor reentry and two drained/sealed/unmapped lifetimes')
}
