// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <mach/mach.h>
}

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.class_getName(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.class_createInstance(voidptr, usize) voidptr
fn C.objc_destructInstance(voidptr) voidptr
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type DataBridgeProbe = fn (u64, u64, u64, &u64, u64)
type DataBridgeConstruct = fn (u64) SwiftDataWords
type DataBridgeAccess = fn (u64) SwiftAssociatedMetadata
type DataBridgeDestroy = fn (u64, u64)
type DataBridgeCreate = fn (u64, u64, i64) u64
type DataBridgeMessage = fn (u64, u64, u64, u64) u64
type DataBridgeSet = fn (u64, u64, u64, u64)
type DataBridgeWeak = fn (u64, u64) u64
type DataBridgeWeakDrop = fn (u64)
type DataBridgeWeakLoad = fn (u64) u64

struct DataBridgeApi {
	native    bool
	entry     u64
	construct DataBridgeConstruct
	destroy   DataBridgeDestroy
	metadata  u64
	probe     DataBridgeProbe
	set       DataBridgeSet
	weak      DataBridgeWeak
	weak_drop DataBridgeWeakDrop
}

struct DataBridgeObserver {
	api   DataBridgeApi
	owner u64
	weak  u64
mut:
	calls int
}

fn data_bridge_entry(native bool, overlay bool) u64 {
	library := if overlay {
		'/usr/lib/swift/libswiftFoundation.dylib'
	} else {
		'/System/Library/Frameworks/Foundation.framework/Foundation'
	}
	name := '_$s10Foundation4DataV19_bridgeToObjectiveCSo6NSDataCyF'
	return if native {
		u64(C.dlsym(C.dlopen(library.str, 2), name[1..].str))
	} else {
		runtime_symbol(library, name) or { panic(err) }
	}
}

fn data_bridge_api(native bool, code u64) DataBridgeApi {
	entry := data_bridge_entry(native, false)
	assert entry != 0 && data_bridge_entry(native, true) == entry
	if native {
		lib := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		response := unsafe { DataBridgeAccess(C.dlsym(lib, c'$s10Foundation4DataVMa'))(0) }
		metadata := response.metadata
		return DataBridgeApi{ native: true, entry: entry, construct: unsafe { DataBridgeConstruct(C.dlsym(lib, c'$s10Foundation4DataV11referencingACSo6NSDataCh_tcfC')) }, destroy: unsafe { DataBridgeDestroy(voidptr(read64((read64(metadata - 8) & 0x0000ffffffffffff) + 8) & 0x0000ffffffffffff)) }, metadata: metadata, probe: unsafe { DataBridgeProbe(voidptr(code)) }, set: unsafe { DataBridgeSet(C.dlsym(objc, c'objc_setAssociatedObject')) }, weak: unsafe { DataBridgeWeak(C.dlsym(objc, c'objc_initWeak')) }, weak_drop: unsafe { DataBridgeWeakDrop(C.dlsym(objc, c'objc_destroyWeak')) } }
	}
	return DataBridgeApi{ entry: entry, construct: swift_data_reference, destroy: swift_data_reference_destroy, probe: unsafe { DataBridgeProbe(voidptr(code)) }, set: objc_set_associated, weak: unsafe { DataBridgeWeak(voidptr(objc_store_weak)) }, weak_drop: unsafe { DataBridgeWeakDrop(voidptr(objc_destroy_weak)) } }
}

fn (api DataBridgeApi) message(object u64, name &char, argument u64) u64 {
	$if macos {
		if api.native {
			return unsafe { DataBridgeMessage(C.dlsym(voidptr(-2), c'objc_msgSend'))(object, u64(C.sel_registerName(name)), argument, 0) }
		}
	}
	return unsafe { DataBridgeMessage(voidptr(C.ios_objc_builtin))(object, u64(name), argument, 0) }
}

fn (api DataBridgeApi) release(object u64) {
	if api.native { api.message(object, c'release', 0) } else { objc_release(object) }
}

fn (api DataBridgeApi) weak_retained(location u64) u64 {
	if api.native {
		return unsafe { DataBridgeWeakLoad(C.dlsym(voidptr(-2), c'objc_loadWeakRetained'))(location) }
	}
	return objc_load_weak(unsafe { &u64(location) })
}

fn (api DataBridgeApi) drop(value SwiftDataWords) {
	mut words := [value.first, value.second]!
	api.destroy(u64(unsafe { &words[0] }), api.metadata)
	assert words == [value.first, value.second]!
}

fn (api DataBridgeApi) source(bytes []u8) SwiftDataWords {
	object := if api.native {
		unsafe { DataBridgeCreate(C.dlsym(voidptr(-2), c'CFDataCreate'))(0, u64(bytes.data), i64(bytes.len)) }
	} else {
		cf_data_create(0, u64(bytes.data), i64(bytes.len))
	}
	value := api.construct(object)
	api.release(object)
	return value
}

fn (api DataBridgeApi) bridge(value SwiftDataWords, guard u64) u64 {
	mut output := [u64(0xcafe), 0, 0, 0, 0xbeef]!
	api.probe(api.entry, value.first, value.second, unsafe { &output[1] }, guard)
	assert output[0] == 0xcafe && output[2] == 0x5020 && output[3] == 0x5021 && output[4] == 0xbeef && output[1] != 0
	return output[1]
}

fn (api DataBridgeApi) identity(object u64, name string, size u64) {
	$if macos {
		if api.native {
			cls := C.object_getClass(voidptr(object))
			assert unsafe { C.class_getName(cls).vstring() } == name && C.class_getInstanceSize(cls) == usize(size)
			return
		}
	}
	assert ctext(u64(objc_class_name(read64(object)))) == name && objc_class_size(read64(object)) == size
}

fn (api DataBridgeApi) verify(object u64, bytes []u8) {
	assert api.message(object, c'length', 0) == u64(bytes.len)
	pointer := api.message(object, c'bytes', 0)
	if bytes.len != 0 {
		assert pointer != 0 && C.memcmp(voidptr(pointer), bytes.data, usize(bytes.len)) == 0
	}
}

fn data_bridge_case(api DataBridgeApi, guard u64, count int, start int, end int, release_value_first bool) {
	mut bytes := []u8{len: count}
	defer { unsafe { bytes.free() } }
	for i in 0 .. count { bytes[i] = u8(i * 37 + 5) }
	value := api.source(bytes)
	slice := if count > 14 {
		SwiftDataWords{ first: (u64(end) << 32) | u64(start), second: value.second }
	} else {
		value
	}
	empty := end == start
	first := api.bridge(slice, guard)
	second := api.bridge(slice, guard)
	expected := bytes[start..end]
	api.verify(first, expected)
	api.verify(second, expected)
	if empty {
		assert first == second && api.message(first, c'retainCount', 0) == u64(-1)
		assert api.message(first, c'bytes', 0) == 0
		api.identity(first, '_NSZeroData', 8)
	} else {
		assert first != second && api.message(first, c'retainCount', 0) == 1
		api.identity(first, if count <= 14 { '_NSInlineData' } else { 'Foundation.__NSSwiftData' }, if count <= 14 {
			u64(16)
		} else {
			u64(40)
		})
	}
	owner := if count > 14 { value.second & 0x3fffffffffffffff } else { u64(0) }
	if owner != 0 {
		assert read64(owner + 8) == if empty { u64(3) } else { u64(0x400000003) }
		if !empty {
			assert api.message(first, c'bytes', 0) == read64(owner + 16) + u64(start)
		}
	}
	for selector in [c'copy', c'copyWithZone:']! {
		// Re-referencing a bridged NSData snapshots its bytes, including slices.
		roundtrip := api.construct(first)
		if expected.len > 14 {
			round_owner := roundtrip.second & u64(0x3fffffffffffffff)
			assert round_owner != owner && read64(round_owner + 24) == u64(expected.len)
			assert C.memcmp(voidptr(read64(round_owner + 16)), expected.data, usize(expected.len)) == 0
		}
		api.drop(roundtrip)
		copied := api.message(first, selector, 0)
		assert copied == first
		api.release(copied)
	}
	for selector in [c'mutableCopy', c'mutableCopyWithZone:']! {
		mutable_copy := api.message(first, selector, 0)
		assert mutable_copy != first
		api.verify(mutable_copy, expected)
		if !empty {
			pointer := api.message(mutable_copy, c'mutableBytes', 0)
			unsafe { *(&u8(pointer)) = 0xee }
			api.verify(first, expected)
		}
		api.release(mutable_copy)
	}
	if release_value_first {
		api.drop(value)
		api.verify(first, expected)
		api.verify(second, expected)
	}
	api.release(first)
	api.verify(second, expected)
	if owner != 0 && !release_value_first {
		assert read64(owner + 8) == if empty { u64(3) } else { u64(0x200000003) }
	}
	if !release_value_first {
		api.drop(value)
		api.verify(second, expected)
	}
	api.release(second)
}

fn data_bridge_reenter(api DataBridgeApi) {
	assert data_bridge_entry(api.native, true) == api.entry
}

fn data_bridge_observer_destroy(object u64, _selector &char) {
	mut state := unsafe { &DataBridgeObserver(read64(object + 8)) }
	assert state.calls == 0 && read64(state.owner + 8) == 3
	assert state.api.weak_retained(state.weak) == 0
	if !state.api.native { assert read64(state.weak) == 0 }
	state.calls++
	worker := spawn data_bridge_reenter(state.api)
	worker.wait()
	$if macos {
		if state.api.native {
			C.objc_destructInstance(voidptr(object))
			C.free(voidptr(object))
			return
		}
	}
	objc_destruct_instance(object)
	C.free(voidptr(object))
}

fn data_bridge_observer_case(api DataBridgeApi, guard u64) {
	mut bytes := []u8{len: 31}
	defer { unsafe { bytes.free() } }
	value := api.source(bytes)
	owner := value.second & 0x3fffffffffffffff
	object := api.bridge(value, guard)
	mut weak := u64(0)
	assert api.weak(u64(unsafe { &weak }), object) == object
	mut state := DataBridgeObserver{ api: api, owner: owner, weak: u64(unsafe { &weak }) }
	mut cls := u64(0)
	mut observer := u64(0)
	$if macos {
		if api.native {
			cls = u64(C.objc_allocateClassPair(C.objc_getClass(c'NSObject'), c'VinixNativeDataBridgeObserver', 0))
			assert cls != 0 && C.class_addMethod(voidptr(cls), C.sel_registerName(c'dealloc'), unsafe { voidptr(data_bridge_observer_destroy) }, c'v16@0:8')
			C.objc_registerClassPair(voidptr(cls))
			observer = u64(C.class_createInstance(voidptr(cls), 8))
		}
	}
	if !api.native {
		cls = objc_allocate_class(ios_runtime.names['NSObject'], c'VinixPrivateDataBridgeObserver', 0)
		assert objc_add_ivar(cls, c'context', 8, 3, c'Q') && objc_add_method(cls, objc_selector(c'dealloc'), u64(unsafe { voidptr(data_bridge_observer_destroy) }), c'v16@0:8')
		objc_register_class(cls)
		observer = objc_allocate(cls)
	}
	unsafe { *(&u64(observer + 8)) = u64(&state) }
	api.set(object, 1, observer, 1)
	api.release(observer)
	api.release(object)
	assert state.calls == 1 && weak == 0
	api.weak_drop(u64(unsafe { &weak }))
	api.drop(value)
}

fn data_bridge_worker(api DataBridgeApi, guard u64) {
	for _ in 0 .. 4 {
		for count in [0, 1, 14, 15, 31, 4096]! {
			data_bridge_case(api, guard, count, 0, count, true)
		}
	}
}

fn data_bridge_suite(api DataBridgeApi, guard u64) {
	// Race the first empty singleton publication before any other bridge calls.
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn data_bridge_worker(api, guard) }
	workers.wait()
	for count in [0, 1, 7, 13, 14, 15, 16, 31, 4096, 65536, 16777216]! {
		for first in [false, true]! { data_bridge_case(api, guard, count, 0, count, first) }
	}
	for first in [false, true]! {
		data_bridge_case(api, guard, 31, 3, 12, first)
		data_bridge_case(api, guard, 31, 3, 3, first)
	}
	empty := api.bridge(SwiftDataWords{}, guard)
	mut empty_weak := u64(0)
	location := u64(unsafe { &empty_weak })
	assert api.weak(location, empty) == empty && api.weak_retained(location) == empty
	api.release(empty)
	assert api.message(empty, c'autorelease', 0) == empty && api.message(empty, c'retainCount', 0) == u64(-1)
	api.weak_drop(location)
	if !api.native {
		assert obj_header(empty).refs == 1
	}
	assert api.bridge(SwiftDataWords{ first: 0xfeedface, second: 0xc000000000001234 }, guard) == empty
	if !api.native {
		assert api.bridge(SwiftDataWords{ first: (u64(3) << 32) | 3, second: guard | u64(0x4000000000000000) }, guard) == empty
	}
	data_bridge_observer_case(api, guard)
}

fn data_bridge_reject(first u64, second u64, reason string) {
	if _ := swift_data_bridge_checked(first, second) {
		assert false
	} else {
		assert err.msg().contains(reason)
	}
}

fn data_bridge_failures(guard u64) {
	data_bridge_reject(0, u64(15) << 48, 'inline Swift Data length')
	data_bridge_reject(guard, u64(0x8000000000000000) | guard, 'large-range')
	for owner in [u64(0), 1, guard]! {
		data_bridge_reject(u64(1) << 32, u64(0x4000000000000000) | owner, 'registered snapshot')
	}
	data_bridge_reject((u64(1) << 32) | 2, u64(0x4000000000000000) | guard, 'slice range')
	mut bytes := [31]u8{}
	source := cf_data_create(0, u64(unsafe { &bytes[0] }), 31)
	value := swift_data_reference(source)
	objc_release(source)
	data_bridge_reject(u64(32) << 32, value.second, 'layout or range')
	swift_data_reference_destroy(u64(unsafe { &value }), 0)
}

fn data_bridge_mapping(address u64, mapped bool, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped {
			assert status == 0 && start <= address && address + 8 <= start + size && info[0] == (C.PROT_READ | if executable {
				C.PROT_EXEC
			} else {
				0
			})
		} else {
			assert status != 0 || start > address
		}
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
				assert mapped && fields[1] == if executable { 'r-xp' } else { 'r--p' }
				found = true
				break
			}
		}
		assert found == mapped
	}
}

fn test_swift_data_bridge() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && C.mprotect(voidptr(code + u64(page)), page, C.PROT_NONE) == 0
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0303f3, 0xaa0403e8,
		0xaa0103e0, 0xaa0203e1, 0xd28a0414, 0xd28a0435, 0xd63f0200, 0xf9000260, 0xa900d674, 0xa9425bf5,
		0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 68))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page)
	$if macos {
		data_bridge_suite(data_bridge_api(true, code), guard)
		println('IOS-SWIFT-DATA-BRIDGE-NATIVE: immortal empty singleton, inline NSData copies and retained Swift slice wrappers, class sizes, borrowed register ABI, copied/mutable results, exact storage lifetime, empty-range normalization, weak zeroing before unlocked association reentry and concurrent bridges measured')
	}
	data_bridge_reject(0, 0, 'outside runtime lifetime')
	for _ in 0 .. 2 {
		objc_start()
		api := data_bridge_api(false, code)
		data_bridge_suite(api, guard)
		data_bridge_failures(guard)
		arena := ios_runtime.swift_foundation_arena
		assert ios_runtime.live == 1 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_data_zero != 0
		data_bridge_mapping(arena + 960, true, true)
		data_bridge_mapping(arena + u64(page) + 400, true, false)
		for library in ['/usr/lib/swift/libswiftCore.dylib',
			'/System/Library/Frameworks/UIKit.framework/UIKit']! {
			if _ := runtime_symbol(library, '_$s10Foundation4DataV19_bridgeToObjectiveCSo6NSDataCyF') {
				assert false
			}
		}
		if _ := swift_foundation_symbol('_$s10Foundation4DataV5write2to7optionsyAA3URLV_So20NSDataWritingOptionsVtKF') {
			assert false
		}
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.swift_data_zero == 0 && ios_runtime.swift_foundation_arena == 0
		data_bridge_mapping(arena + 960, false, false)
		data_bridge_mapping(arena + u64(page) + 400, false, false)
		data_bridge_reject(0, 0, 'outside runtime lifetime')
	}
	assert C.munmap(voidptr(code), page * 2) == 0
	println('IOS-SWIFT-DATA-BRIDGE: native empty/inline/slice NSData bridging, borrowed input and owned result/storage, shared bytes and independent mutable copies, weak-zeroed unlocked association teardown, safe invalid storage rejection, concurrent singleton publication/bridges and two drained/unmapped lifetimes; arbitrary external Data storage, metadata and large-range cases remain unsupported')
}
