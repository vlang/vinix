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
type PointerAllocate = fn (i64, u64) u64
type PointerDestroy = fn (i64, u64, u64) u64
type PointerFree = fn (u64, u64)
type PointerType = fn (u64) u64
type PointerSign = fn (u64, u64) u64
struct PointerAllocApi {
	native bool
	allocate PointerAllocate
	destroy PointerDestroy
	integer u64
	string_type u64
	objc_type u64
	frees [4]PointerFree
}
fn pointer_alloc_api(native bool, core voidptr) PointerAllocApi {
	mut frees := [4]PointerFree{}
	for i, symbol in [c'$sSp10deallocateyyF', c'$sSP10deallocateyyF', c'$sSv10deallocateyyF', c'$sSV10deallocateyyF']! {
		$if macos { if native { frees[i] = unsafe { PointerFree(C.dlsym(core, symbol)) }; continue } }
		address := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_' + unsafe { symbol.vstring() }) or { panic(err) }
		frees[i] = unsafe { PointerFree(voidptr(address)) }
	}
	$if macos { if native {
		wrapper := unsafe { PointerType(C.dlsym(core, c'swift_getObjCClassMetadata')) }
		return PointerAllocApi{native: true, frees: frees,
			allocate: unsafe { PointerAllocate(C.dlsym(core, c'$sSp8allocate8capacitySpyxGSi_tFZ')) },
			destroy: unsafe { PointerDestroy(C.dlsym(core, c'$sSp12deinitialize5countSvSi_tF')) },
			integer: u64(C.dlsym(core, c'$sSiN')), string_type: u64(C.dlsym(core, c'$sSSN')),
			objc_type: wrapper(u64(C.objc_getClass(c'NSString')))}
	} }
	address := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSp8allocate8capacitySpyxGSi_tFZ') or { panic(err) }
	assert address == u64(unsafe { voidptr(swift_pointer_allocate) })
	return PointerAllocApi{allocate: unsafe { PointerAllocate(voidptr(address)) }, destroy: swift_pointer_deinitialize,
		integer: swift_integer_metadata(), string_type: swift_string_metadata(),
		objc_type: swift_objc_metadata(ios_runtime.names['NSString']), frees: frees}
}
fn pointer_alloc_refs(api PointerAllocApi, object u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(voidptr(object)) } }
	return obj_header(object).refs
}
fn pointer_alloc_typed(api PointerAllocApi, kind int, count i64, release int) {
	metadata := if kind == 0 { api.integer } else if kind == 1 { api.string_type } else { api.objc_type }
	stride := if kind == 1 { u64(16) } else { u64(8) }
	mut object := u64(0)
	$if macos { if api.native { object = u64(C.CFStringCreateMutable(unsafe { nil }, 0)) } }
	if !api.native { object = owned_string('Typed allocation ownership') }
	assert pointer_alloc_refs(api, object) == 1
	pointer := api.allocate(count, metadata)
	assert pointer != 0 && pointer & 15 == 0 && pointer_alloc_refs(api, object) == 1
	C.memset(voidptr(pointer), 0xa5, usize(if count == 0 { u64(1) } else { u64(count) * stride }))
	for i in i64(0) .. count {
		value := pointer + u64(i) * stride
		if kind == 0 { unsafe { *(&u64(value)) = u64(i + 37) }; continue }
		$if macos { if api.native { C.CFRetain(voidptr(object)) } }
		if !api.native { objc_retain(object) }
		if kind == 1 { unsafe { *(&u64(value)) = 0; *(&u64(value + 8)) = object | 0x5000000000000000 } }
		else { unsafe { *(&u64(value)) = object } }
	}
	assert pointer_alloc_refs(api, object) == 1 + if kind == 0 { i64(0) } else { count }
	assert api.destroy(count, pointer, metadata) == pointer
	assert pointer_alloc_refs(api, object) == 1
	if kind == 0 { for i in i64(0) .. count { assert read64(pointer + u64(i) * stride) == u64(i + 37) } }
	C.memset(voidptr(pointer), 0x67, usize(if count == 0 { u64(1) } else { u64(count) * stride }))
	if release == 4 { C.free(voidptr(pointer)) } else { api.frees[release](pointer, metadata) }
	$if macos { if api.native { C.CFRelease(voidptr(object)); return } }
	objc_release(object)
}
fn pointer_alloc_custom(api PointerAllocApi, sign u64, guard u64, size u64, stride u64, alignment u64, count i64) {
	mut table := [11]u64{}; for i in 0 .. 11 { table[i] = guard }
	table[8] = size; table[9] = stride; table[10] = alignment - 1 | 0x10000
	mut words := [u64(unsafe { &table[0] }), 0x301]!
	$if macos { if api.native {
		signer := unsafe { PointerSign(voidptr(sign)) }
		words[0] = signer(words[0], u64(unsafe { &words[0] }) | (u64(11839) << 48))
	} }
	pointer := api.allocate(count, u64(unsafe { &words[1] }))
	assert pointer != 0 && pointer & (if alignment < 16 { u64(16) } else { alignment } - 1) == 0
	bytes := if count == 0 { u64(1) } else { u64(count) * stride }
	C.memset(voidptr(pointer), 0x79, usize(bytes))
	assert unsafe { *(&u8(pointer)) } == 0x79 && unsafe { *(&u8(pointer + bytes - 1)) } == 0x79
	C.free(voidptr(pointer))
}
fn pointer_alloc_suite(api PointerAllocApi, sign u64, guard u64) {
	for kind in 0 .. 3 { for count in [i64(0), 1, 5, 33]! { for release in 0 .. 5 { pointer_alloc_typed(api, kind, count, release) } } }
	for layout in [[u64(0), 1, 1]!, [u64(8), 16, 8]!, [u64(40), 64, 64]!, [u64(0), 32, 32]!, [u64(128), 256, 256]!]! {
		for count in [i64(0), 1, 5, 257]! { pointer_alloc_custom(api, sign, guard, layout[0], layout[1], layout[2], count) }
	}
}
fn pointer_alloc_rejected(guard u64) {
	if _ := swift_pointer_allocate_checked(-1, guard) { assert false }
	for metadata in [u64(0), 1, guard | 1]! { if _ := swift_pointer_allocate_checked(0, metadata) { assert false } }
	mut table := [11]u64{}; mut words := [u64(unsafe { &table[0] }), 0x301]!
	metadata := u64(unsafe { &words[1] })
	for bad in 0 .. 9 {
		words[0] = u64(unsafe { &table[0] }); table[8] = 8; table[9] = 16; table[10] = 7
		mut count := i64(0)
		match bad {
			0 { words[0] = 0 } 1 { words[0] = guard | 1 } 2 { table[9] = 0 }
			3 { table[8] = 17 } 4 { table[9] = 17 } 5 { table[10] = 2 }
			6 { table[10] = 0x400007 } 7 { table[9] = 0x8000000000000000 }
			else { count = 0x7fffffffffffffff / 16 + 1 }
		}
		if _ := swift_pointer_allocate_checked(count, metadata) { assert false }
	}
}
fn pointer_alloc_worker(api PointerAllocApi, guard u64) {
	for _ in 0 .. 300 { pointer_alloc_custom(api, 0, guard, 40, 64, 64, 5) }
}
fn test_swift_pointer_alloc() {
	page := usize(C.getpagesize()); sign := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert sign != u64(-1) && guard != u64(-1)
	write32(sign, 0xdac10820); write32(sign + 4, 0xd65f03c0)
	C.__builtin___clear_cache(voidptr(sign), voidptr(sign + 8)); assert C.mprotect(voidptr(sign), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW); assert core != unsafe { nil }
		pointer_alloc_suite(pointer_alloc_api(true, core), sign, guard); assert C.dlclose(core) == 0
		println('IOS-POINTER-ALLOC-NATIVE: count/metadata ABI, 60 Int/String/ObjC lifecycles, four pointer frees and libSystem free, 20 guarded padded/over-aligned/zero-size layouts, zero capacity and writable stride extent')
	}
	for _ in 0 .. 2 {
		objc_start(); api := pointer_alloc_api(false, unsafe { nil }); pointer_alloc_suite(api, sign, guard); pointer_alloc_rejected(guard)
		mut workers := []thread{}; for _ in 0 .. 8 { workers << spawn pointer_alloc_worker(api, guard) }; workers.wait()
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		objc_stop()
	}
	assert C.munmap(voidptr(guard), page) == 0 && C.munmap(voidptr(sign), page) == 0
	println('IOS-POINTER-ALLOC: native layout agreement, uninitialized storage, separate owned-value destruction and free, guarded unused witnesses, rejected metadata/negative count/overflow, eight concurrent workers and two drained lifetimes')
}
