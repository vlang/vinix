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
fn C.dlclose(voidptr) i32
fn C.objc_getClass(&char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
type DeinitMethod = fn (i64, u64, u64) u64
type DeinitArray = fn (u64, u64, u64)
type DeinitAllocate = fn (u64, u64) u64
type DeinitSign = fn (u64, u64) u64
type DeinitObjCType = fn (u64) u64
struct DeinitApi {
	native bool
	method DeinitMethod
	array DeinitArray
	allocate DeinitAllocate
	integer u64
	string_type u64
	objc_type u64
}
fn deinit_api(native bool, core voidptr) DeinitApi {
	$if macos { if native {
		wrapper := unsafe { DeinitObjCType(C.dlsym(core, c'swift_getObjCClassMetadata')) }
		return DeinitApi{native: true,
			method: unsafe { DeinitMethod(C.dlsym(core, c'$sSp12deinitialize5countSvSi_tF')) },
			array: unsafe { DeinitArray(C.dlsym(core, c'swift_arrayDestroy')) },
			allocate: unsafe { DeinitAllocate(C.dlsym(core, c'swift_slowAlloc')) },
			integer: u64(C.dlsym(core, c'$sSiN')), string_type: u64(C.dlsym(core, c'$sSSN')),
			objc_type: wrapper(u64(C.objc_getClass(c'NSString')))}
	} }
	method := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSp12deinitialize5countSvSi_tF') or { panic(err) }
	array := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_arrayDestroy') or { panic(err) }
	assert method == u64(unsafe { voidptr(swift_pointer_deinitialize) })
	assert array == u64(unsafe { voidptr(swift_array_destroy_elements) })
	return DeinitApi{method: unsafe { DeinitMethod(voidptr(method)) }, array: unsafe { DeinitArray(voidptr(array)) },
		allocate: swift_raw_allocate, integer: swift_integer_metadata(), string_type: swift_string_metadata(),
		objc_type: swift_objc_metadata(ios_runtime.names['NSString'])}
}
fn deinit_object(api DeinitApi) u64 {
	$if macos { if api.native { return u64(C.CFStringCreateMutable(unsafe { nil }, 0)) } }
	return owned_string('Pointer initialized Element owner')
}
fn deinit_keep(api DeinitApi, object u64) {
	$if macos { if api.native { C.CFRetain(voidptr(object)); return } }
	objc_retain(object)
}
fn deinit_drop(api DeinitApi, object u64) {
	$if macos { if api.native { C.CFRelease(voidptr(object)); return } }
	objc_release(object)
}
fn deinit_refs(api DeinitApi, object u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(voidptr(object)) } }
	return obj_header(object).refs
}
fn deinit_typed(api DeinitApi, kind int, count i64, direct bool) {
	metadata := if kind == 0 { api.integer } else if kind == 1 { api.string_type } else { api.objc_type }
	stride := if kind == 1 { u64(16) } else { u64(8) }
	base := api.allocate((u64(count) + 2) * stride, u64(-1)); pointer := base + stride
	C.memset(voidptr(base), 0xa5, usize((u64(count) + 2) * stride))
	object := deinit_object(api)
	for i in i64(0) .. count {
		value := pointer + u64(i) * stride
		if kind == 0 { unsafe { *(&u64(value)) = u64(i + 73) } }
		else {
			deinit_keep(api, object)
			if kind == 1 { unsafe { *(&u64(value)) = 0; *(&u64(value + 8)) = object | 0x5000000000000000 } }
			else { unsafe { *(&u64(value)) = object } }
		}
	}
	assert deinit_refs(api, object) == 1 + if kind == 0 { i64(0) } else { count }
	if direct { api.array(pointer, u64(count), metadata) }
	else { assert api.method(count, pointer, metadata) == pointer }
	assert deinit_refs(api, object) == 1
	assert read64(base) == 0xa5a5a5a5a5a5a5a5 && read64(pointer + u64(count) * stride) == 0xa5a5a5a5a5a5a5a5
	if kind == 0 { for i in i64(0) .. count { assert read64(pointer + u64(i) * stride) == u64(i + 73) } }
	// This succeeds only if destruction kept the caller's allocation alive.
	C.memset(voidptr(base), 0x67, usize((u64(count) + 2) * stride)); C.free(voidptr(base))
	deinit_drop(api, object)
}
struct DeinitScenario {
	api DeinitApi
	metadata u64
	base u64
	stride u64
	size u64
	count u64
mut:
	visited u64
}
fn deinit_lookup_worker() u64 { return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_arrayDestroy') or { panic(err) } }
fn deinit_custom_destroy(value u64, metadata u64) {
	mut scenario := unsafe { &DeinitScenario(read64(metadata + 24)) }
	assert metadata == scenario.metadata && scenario.visited < scenario.count
	assert value == scenario.base + scenario.visited * scenario.stride
	if scenario.size >= 8 { assert read64(value) == scenario.visited + 17; unsafe { *(&u64(value)) = 0 } }
	scenario.visited++
	if !scenario.api.native { worker := spawn deinit_lookup_worker(); assert worker.wait() == u64(unsafe { voidptr(swift_array_destroy_elements) }) }
}
fn deinit_custom(api DeinitApi, probe u64, guard u64, size u64, stride u64, alignment u64, count u64, pod bool, direct bool) {
	base := api.allocate(stride * (count + 2), alignment - 1)
	mut table := [11]u64{}; for i in 0 .. 11 { table[i] = guard }
	table[1] = if pod { guard } else { u64(unsafe { voidptr(deinit_custom_destroy) }) }
	table[8] = size; table[9] = stride; table[10] = alignment - 1 | if pod { u64(0) } else { u64(0x10000) }
	mut words := [u64(unsafe { &table[0] }), 0x301, 0, 0, 0]!
	metadata := u64(unsafe { &words[1] })
	mut scenario := DeinitScenario{api: api, metadata: metadata, base: base + stride, stride: stride, size: size, count: count}
	words[4] = u64(unsafe { &scenario })
	$if macos { if api.native {
		sign_code := unsafe { DeinitSign(voidptr(probe)) }; sign_data := unsafe { DeinitSign(voidptr(probe + 16)) }
		if !pod { table[1] = sign_code(table[1], u64(unsafe { &table[1] }) | (u64(1272) << 48)) }
		words[0] = sign_data(words[0], u64(unsafe { &words[0] }) | (u64(11839) << 48))
	} }
	C.memset(voidptr(base), 0xa5, usize(stride * (count + 2)))
	if size >= 8 { for i in u64(0) .. count { unsafe { *(&u64(scenario.base + i * stride)) = i + 17 } } }
	if direct { api.array(scenario.base, count, metadata) }
	else { assert api.method(i64(count), scenario.base, metadata) == scenario.base }
	assert scenario.visited == if pod { u64(0) } else { count }
	assert unsafe { *(&u8(base)) } == 0xa5 && unsafe { *(&u8(scenario.base + count * stride)) } == 0xa5
	if !pod && size >= 8 { for i in u64(0) .. count { assert read64(scenario.base + i * stride) == 0 } }
	if pod {
		api.array(guard, u64(-1), metadata)
		assert api.method(37, guard, metadata) == guard
	}
	C.memset(voidptr(base), 0x67, usize(stride * (count + 2))); C.free(voidptr(base))
}
fn deinit_suite(api DeinitApi, probe u64, guard u64) {
	api.array(guard, 0, guard); api.array(0, 0, 0)
	assert api.method(0, guard, guard) == guard && api.method(0, 0, 0) == 0
	for direct in [false, true]! {
		for kind in 0 .. 3 { for count in [i64(0), 1, 5, 33]! { deinit_typed(api, kind, count, direct) } }
		for layout in [[u64(8), 16, 8]!, [u64(40), 64, 64]!, [u64(0), 1, 1]!, [u64(0), 32, 32]!]! {
			for count in [u64(0), 1, 5]! { deinit_custom(api, probe, guard, layout[0], layout[1], layout[2], count, false, direct) }
		}
		deinit_custom(api, probe, guard, 0, 1, 1, 5, true, direct)
	}
}
fn deinit_rejected(guard u64) {
	if _ := swift_pointer_deinitialize_checked(-1, guard, guard) { assert false }
	for metadata in [u64(0), 1, guard | 1]! { if _ := swift_array_destroy_elements_checked(guard, 1, metadata) { assert false } }
	mut table := [11]u64{}; mut words := [u64(unsafe { &table[0] }), 0x301, 0, 0, 0]!
	metadata := u64(unsafe { &words[1] })
	for bad in 0 .. 11 {
		words[0] = u64(unsafe { &table[0] }); table[1] = u64(unsafe { voidptr(deinit_custom_destroy) }); table[8] = 8; table[9] = 16; table[10] = 0x10007
		mut pointer := guard; mut count := u64(1)
		match bad {
			0 { words[0] = 0 } 1 { words[0] = guard | 1 } 2 { table[9] = 0 }
			3 { table[8] = 17 } 4 { table[9] = 17 } 5 { table[10] = 0x10002 }
			6 { table[10] = 0x410007 } 7 { table[1] = 0 } 8 { table[1] = guard | 1 }
			9 { pointer = guard + 1 } else { pointer = 0xfffffffffffffff8; count = 2 }
		}
		if _ := swift_array_destroy_elements_checked(pointer, count, metadata) { assert false }
	}
}
fn test_swift_pointer_deinit() {
	page := usize(C.getpagesize()); probe := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert probe != u64(-1) && guard != u64(-1)
	write32(probe, 0xdac10020); write32(probe + 4, 0xd65f03c0)
	write32(probe + 16, 0xdac10820); write32(probe + 20, 0xd65f03c0)
	C.__builtin___clear_cache(voidptr(probe), voidptr(probe + 24)); assert C.mprotect(voidptr(probe), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW); assert core != unsafe { nil }
		deinit_suite(deinit_api(true, core), probe, guard); assert C.dlclose(core) == 0
		println('IOS-POINTER-DEINIT-NATIVE: count/Self/metadata ABI, 24 typed ranges, 26 minimal witness ranges, ascending padded/over-aligned/zero-size destruction, zero/POD guard paths and retained allocation')
	}
	for _ in 0 .. 2 {
		objc_start(); deinit_suite(deinit_api(false, unsafe { nil }), probe, guard); deinit_rejected(guard)
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		objc_stop()
	}
	assert C.munmap(voidptr(guard), page) == 0 && C.munmap(voidptr(probe), page) == 0
	println('IOS-POINTER-DEINIT: owned String/ObjC cleanup, untouched neighbours and caller allocation, required witnesses only, ascending padded/over-aligned/zero-size callbacks, unlocked cross-thread lookup, guarded zero/POD paths, rejected layouts/range overflow and two drained lifetimes')
}
