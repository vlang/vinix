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
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type DataUnbridgeProbe = fn (u64, u64, &u64, u64)
type DataUnbridgeAccess = fn (u64) SwiftAssociatedMetadata
type DataUnbridgeDestroy = fn (u64, u64)
type DataUnbridgeRetain = fn (u64) u64
type DataUnbridgeSend = fn (u64, u64) u64
type DataUnbridgeCreate = fn (u64, u64, i64) u64
type DataUnbridgeMutable = fn (u64, i64) u64
type DataUnbridgeAppend = fn (u64, u64, i64)
type DataUnbridgeExternal = fn (u64, u64, i64, u64) u64
type DataUnbridgeCount = fn (u64, u64) u64
type DataUnbridgeBridge = fn (u64, u64) u64

struct DataUnbridgeApi {
	native   bool
	entry    u64
	metadata u64
	probe    DataUnbridgeProbe
	destroy  DataUnbridgeDestroy
	retain   DataUnbridgeRetain
}

fn data_unbridge_send(object u64, selector &char) u64 {
	$if macos {
		return unsafe { DataUnbridgeSend(C.dlsym(voidptr(-2), c'objc_msgSend'))(object, u64(C.sel_registerName(selector))) }
	} $else {
		panic('native NSData messaging requires macOS')
	}
}

fn data_unbridge_entry(native bool, overlay bool) u64 {
	library := if overlay {
		'/usr/lib/swift/libswiftFoundation.dylib'
	} else {
		'/System/Library/Frameworks/Foundation.framework/Foundation'
	}
	name := '_$s10Foundation4DataV36_unconditionallyBridgeFromObjectiveCyACSo6NSDataCSgFZ'
	return if native {
		u64(C.dlsym(C.dlopen(library.str, 2), name[1..].str))
	} else {
		runtime_symbol(library, name) or { panic(err) }
	}
}

fn data_unbridge_api(native bool, code u64) DataUnbridgeApi {
	entry := data_unbridge_entry(native, false)
	assert entry != 0 && data_unbridge_entry(native, true) == entry
	if native {
		lib := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		response := unsafe { DataUnbridgeAccess(C.dlsym(lib, c'$s10Foundation4DataVMa'))(0) }
		metadata := response.metadata
		assert response.state == 0
		table := read64(metadata - 8) & u64(0x0000ffffffffffff)
		assert read64(table + 64) == 16 && read64(table + 72) == 16
		return DataUnbridgeApi{ native: true, entry: entry, metadata: metadata, probe: unsafe { DataUnbridgeProbe(voidptr(code)) }, destroy: unsafe { DataUnbridgeDestroy(voidptr(read64(table + 8) & u64(0x0000ffffffffffff))) }, retain: unsafe { DataUnbridgeRetain(C.dlsym(C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2), c'swift_retain')) } }
	}
	return DataUnbridgeApi{ entry: entry, probe: unsafe { DataUnbridgeProbe(voidptr(code)) }, destroy: swift_data_reference_destroy, retain: swift_retain }
}

fn (api DataUnbridgeApi) construct(object u64, guard u64) SwiftDataWords {
	mut output := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	api.probe(api.entry, object, unsafe { &output[1] }, guard)
	assert output[0] == 0xcafe && output[3] == 0x5020 && output[4] == 0x5021 && output[5] == 0xbeef
	return SwiftDataWords{ first: output[1], second: output[2] }
}

fn (api DataUnbridgeApi) source(bytes u64, count int, mutable_data bool, external bool) u64 {
	if api.native {
		if external {
			no_free := read64(u64(C.dlsym(voidptr(-2), c'kCFAllocatorNull')))
			return unsafe { DataUnbridgeExternal(C.dlsym(voidptr(-2), c'CFDataCreateWithBytesNoCopy'))(0, bytes, i64(count), no_free) }
		}
		if mutable_data {
			object := unsafe { DataUnbridgeMutable(C.dlsym(voidptr(-2), c'CFDataCreateMutable'))(0, i64(count)) }
			unsafe { DataUnbridgeAppend(C.dlsym(voidptr(-2), c'CFDataAppendBytes'))(object, bytes, i64(count)) }
			return object
		}
		return unsafe { DataUnbridgeCreate(C.dlsym(voidptr(-2), c'CFDataCreate'))(0, bytes, i64(count)) }
	}
	if external {
		object := objc_allocate(ios_runtime.names['NSData'])
		mut header := obj_header(object)
		header.external_data = bytes
		header.external_size = u64(count)
		return object
	}
	if mutable_data {
		object := cf_data_mutable(0, i64(count))
		cf_data_set_length(object, i64(count))
		if count != 0 { C.memcpy(voidptr(data_pointer(object)), voidptr(bytes), usize(count)) }
		return object
	}
	return cf_data_create(0, bytes, i64(count))
}

fn (api DataUnbridgeApi) refs(object u64) u64 {
	return if api.native {
		data_unbridge_send(object, c'retainCount')
	} else {
		u64(obj_header(object).refs)
	}
}

fn (api DataUnbridgeApi) release(object u64) {
	if api.native { data_unbridge_send(object, c'release') } else { objc_release(object) }
}

fn (api DataUnbridgeApi) drop(value SwiftDataWords) {
	mut words := [value.first, value.second]!
	api.destroy(u64(unsafe { &words[0] }), api.metadata)
	assert words == [value.first, value.second]!
}

fn data_unbridge_verify(api DataUnbridgeApi, value SwiftDataWords, expected []u8, native_compact bool) {
	if api.native {
		counter := unsafe { DataUnbridgeCount(C.dlsym(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2), c'$s10Foundation4DataV5countSivg')) }
		assert counter(value.first, value.second) == u64(expected.len)
	}
	if expected.len == 0 {
		assert value.first == 0 && value.second == u64(0xc000000000000000)
	} else if expected.len <= 14 {
		mut words := [2]u64{}
		C.memcpy(unsafe { &words[0] }, expected.data, usize(expected.len))
		assert value == SwiftDataWords{ first: words[0], second: words[1] | (u64(expected.len) << 48) }
	} else {
		assert value.first == u64(expected.len) << 32 && value.second >> 62 == 1
		owner := value.second & u64(0x3fffffffffffffff)
		assert read64(owner + 8) == 3 && read64(owner + 24) == u64(expected.len)
		assert read64(owner + 40) == 0 && read64(owner + 56) == 0
		if native_compact {
			assert api.native && read64(owner + 32) == u64(expected.len) && read64(owner + 48) == 0
		} else {
			assert read64(owner + 32) == 0 && read64(owner + 48) != 0
		}
		assert unsafe { *(&u8(owner + 64)) } == if native_compact { u8(1) } else { u8(0) }
		assert C.memcmp(voidptr(read64(owner + 16)), expected.data, usize(expected.len)) == 0
		if !api.native {
			C.ios_objc_initialize_lock()
			registered := owner in ios_runtime.swift_heap && read64(owner) == ios_runtime.swift_foundation_arena + u64(C.getpagesize()) + 400
			C.ios_objc_initialize_unlock()
			assert registered
		}
	}
}

fn data_unbridge_case(api DataUnbridgeApi, guard u64, count int, mutable_data bool) {
	mut expected := []u8{len: count}
	defer { unsafe { expected.free() } }
	for i in 0 .. count { expected[i] = u8(i * 37 + 5) }
	object := api.source(u64(expected.data), count, mutable_data, false)
	assert object != 0 && api.refs(object) == 1
	value := api.construct(object, guard)
	assert api.refs(object) == 1
	if mutable_data && count != 0 {
		bytes := if api.native {
			data_unbridge_send(object, c'mutableBytes')
		} else {
			data_pointer(object)
		}
		unsafe {
			*(&u8(bytes)) = 0xee
			*(&u8(bytes + u64(count - 1))) = 0xdd
		}
	}
	api.release(object)
	data_unbridge_verify(api, value, expected, false)
	// The constructor returns one owned storage reference. Shared value copies
	// retain that storage, and either ownership can be destroyed first.
	if count > 14 {
		owner := value.second & u64(0x3fffffffffffffff)
		assert api.retain(owner) == owner && read64(owner + 8) == 0x200000003
		api.drop(value)
		data_unbridge_verify(api, value, expected, false)
	}
	api.drop(value)
}

fn data_unbridge_worker(api DataUnbridgeApi, guard u64) {
	for _ in 0 .. 4 {
		assert data_unbridge_entry(api.native, true) == api.entry
		api.drop(api.construct(0, guard))
		for count in [0, 1, 14, 15, 31, 4096]! {
			for mutable_data in [false, true]! {
				data_unbridge_case(api, guard, count, mutable_data)
			}
		}
	}
}

fn data_unbridge_guarded(api DataUnbridgeApi) {
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	input := region + u64(page)
	output := region + u64(page * 4) - 16
	for count in [0, 1, 13, 14, 15, 16, int(page)]! {
		for at_start in [false, true]! {
			assert C.mprotect(voidptr(input), page, C.PROT_READ | C.PROT_WRITE) == 0
			mut expected := []u8{len: count}
			for i in 0 .. count { expected[i] = u8(i * 37 + 5) }
			bytes := if at_start { input } else { input + u64(page) - u64(count) }
			if count != 0 { C.memcpy(voidptr(bytes), expected.data, usize(count)) }
			assert C.mprotect(voidptr(input), page, C.PROT_READ) == 0
			object := api.source(bytes, count, false, true)
			value := api.construct(object, region)
			assert api.refs(object) == 1
			api.release(object)
			assert C.mprotect(voidptr(input), page, C.PROT_NONE) == 0
			data_unbridge_verify(api, value, expected, false)
			assert C.mprotect(voidptr(region + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
			unsafe { *(&SwiftDataWords(output)) = value }
			assert C.mprotect(voidptr(region + u64(page * 3)), page, C.PROT_READ) == 0
			api.destroy(output, api.metadata)
			assert unsafe { *(&SwiftDataWords(output)) } == value
			unsafe { expected.free() }
		}
	}
	assert C.munmap(voidptr(region), page * 5) == 0
}

fn data_unbridge_reject(object u64, reason string) {
	if _ := swift_data_unbridge_checked(object) {
		assert false
	} else {
		assert err.msg().contains(reason)
	}
}

fn data_unbridge_failures(guard u64) {
	for value in [u64(1), guard]! { data_unbridge_reject(value, 'registered NSData') }
	object := objc_allocate(ios_runtime.names['NSObject'])
	data_unbridge_reject(object, 'built-in NSData')
	objc_release(object)
	cls := objc_allocate_class(ios_runtime.names['NSData'], c'VinixDataUnbridgeerenceSubclass', 0)
	objc_register_class(cls)
	instance := objc_allocate(cls)
	data_unbridge_reject(instance, 'built-in NSData')
	objc_release(instance)
	oversized := objc_allocate(ios_runtime.names['NSData'])
	mut header := obj_header(oversized)
	header.external_data = guard
	header.external_size = 16777217
	data_unbridge_reject(oversized, 'supported NSData length')
	objc_release(oversized)
}

fn data_unbridge_mapping(address u64, mapped bool, executable bool) {
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

fn data_unbridge_roundtrip(api DataUnbridgeApi, guard u64, count int) {
	mut expected := []u8{len: count}
	defer { unsafe { expected.free() } }
	for i in 0 .. count { expected[i] = u8(i * 37 + 5) }
	source := api.source(u64(expected.data), count, false, false)
	value := api.construct(source, guard)
	api.release(source)
	object := if api.native {
		unsafe { DataUnbridgeBridge(C.dlsym(C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2), c'$s10Foundation4DataV19_bridgeToObjectiveCSo6NSDataCyF'))(value.first, value.second) }
	} else {
		swift_data_bridge(value.first, value.second)
	}
	refs := api.refs(object)
	roundtrip := api.construct(object, guard)
	assert api.refs(object) == refs
	if count > 14 {
		assert value.second != roundtrip.second
		assert read64((value.second & u64(0x3fffffffffffffff)) + 8) == 0x200000003
	}
	api.drop(value)
	api.release(object)
	data_unbridge_verify(api, roundtrip, expected, api.native)
	api.drop(roundtrip)
}

fn data_unbridge_suite(api DataUnbridgeApi, guard u64) {
	for _ in 0 .. 16 {
		value := api.construct(0, guard)
		assert value == SwiftDataWords{ second: u64(0xc000000000000000) }
		api.drop(value)
	}
	if !api.native {
		assert ios_runtime.swift_foundation_arena == 0
	}
	for count in [0, 1, 7, 8, 13, 14, 15, 16, 31, 4096, 65536, 16777216]! {
		for mutable_data in [false, true]! { data_unbridge_case(api, guard, count, mutable_data) }
	}
	data_unbridge_guarded(api)
	for count in [0, 1, 14, 15, 31, 4096]! { data_unbridge_roundtrip(api, guard, count) }
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn data_unbridge_worker(api, guard) }
	workers.wait()
}

fn test_swift_data_unbridge() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && C.mprotect(voidptr(code + u64(page)), page, C.PROT_NONE) == 0
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0203f3, 0xaa0303e8,
		0xaa0103e0, 0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3,
		0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 64))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page)
	$if macos {
		data_unbridge_suite(data_unbridge_api(true, code), guard)
		println('IOS-SWIFT-DATA-UNBRIDGE-NATIVE: nil-to-empty, borrowed NSData/NSMutableData and no-copy inputs, empty/inline/slice words, bridge roundtrip snapshots and native storage variants, independent bytes after mutation/release, exact Swift ownership, direct x0/x1 result and context, guarded spans and concurrent snapshots measured')
	}
	data_unbridge_reject(guard, 'outside runtime lifetime')
	data_unbridge_reject(0, 'outside runtime lifetime')
	for _ in 0 .. 2 {
		objc_start()
		api := data_unbridge_api(false, code)
		data_unbridge_suite(api, guard)
		data_unbridge_failures(guard)
		arena := ios_runtime.swift_foundation_arena
		assert arena != 0 && ios_runtime.live == 1 && ios_runtime.swift_data_zero != 0 && ios_runtime.swift_heap.len == 0
		data_unbridge_mapping(arena + 960, true, true)
		data_unbridge_mapping(arena + u64(page) + 400, true, false)
		for library in ['/usr/lib/swift/libswiftCore.dylib',
			'/System/Library/Frameworks/UIKit.framework/UIKit']! {
			if _ := runtime_symbol(library, '_$s10Foundation4DataV36_unconditionallyBridgeFromObjectiveCyACSo6NSDataCSgFZ') {
				assert false
			}
		}
		for name in ['_$s10Foundation4DataVMa', '_$s10Foundation4DataVMn']! {
			if _ := swift_foundation_symbol(name) {
				assert false
			}
		}
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.swift_data_zero == 0 && ios_runtime.swift_foundation_arena == 0
		data_unbridge_mapping(arena + 960, false, false)
		data_unbridge_mapping(arena + u64(page) + 400, false, false)
		data_unbridge_reject(guard, 'outside runtime lifetime')
		data_unbridge_reject(0, 'outside runtime lifetime')
	}
	assert C.munmap(voidptr(code), page * 2) == 0
	println('IOS-SWIFT-DATA-UNBRIDGE: nil without snapshot allocation, optional built-in NSData snapshots and bridge roundtrips, native empty/14-byte-inline/small-slice layout, owned Swift storage and exact release, mutation/input-release isolation, guarded buffers/result ABI, concurrent nil/aliases/calls and two drained/unmapped lifetimes; general Data metadata, witnesses, large ranges and custom NSData subclasses remain unsupported')
}
