// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFArray.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFArrayCreateMutable(voidptr, i64, voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.mincore(voidptr, usize, &u8) i32

type ArrayAccess = fn (u64, u64) SwiftAssociatedMetadata
type ArrayInstantiate = fn (u64, u64, u64) u64
type ArrayCopy = fn (u64, u64, u64) u64
type ArrayDestroy = fn (u64, u64)
type ArrayGetTag = fn (u64, u32, u64) u32
type ArrayStoreTag = fn (u64, u32, u32, u64)
type ArrayUTF8 = fn (u64, u64) u64
struct ArrayApi {
	native bool
	metadata u64
	element u64
	descriptor u64
	@[required]
	access ArrayAccess
	@[required]
	utf8 ArrayUTF8
}
fn array_relative(address u64) u64 {
	offset := unsafe { *(&i32(address)) }
	return if offset == 0 { u64(0) } else { u64(i64(address) + i64(offset)) }
}
fn (api ArrayApi) copy(slot int, destination u64, source u64) u64 {
	function := unsafe { ArrayCopy(voidptr(read64(read64(api.metadata - 8) + u64(slot * 8)))) }
	return function(destination, source, api.metadata)
}
fn (api ArrayApi) destroy(value u64) {
	function := unsafe { ArrayDestroy(voidptr(read64(read64(api.metadata - 8) + 8))) }
	function(value, api.metadata)
}
fn (api ArrayApi) get_tag(value u64, cases u32) u32 {
	function := unsafe { ArrayGetTag(voidptr(read64(read64(api.metadata - 8) + 48))) }
	return function(value, cases, api.metadata)
}
fn (api ArrayApi) store_tag(value u64, tag u32, cases u32) {
	function := unsafe { ArrayStoreTag(voidptr(read64(read64(api.metadata - 8) + 56))) }
	function(value, tag, cases, api.metadata)
}
fn array_layout(api ArrayApi, metadata u64, element u64) {
	assert read64(metadata) == 0x200 && read64(metadata + 8) == api.descriptor
	assert read64(metadata + 16) == element && read64(metadata + 24) == 0
	witness := read64(metadata - 8)
	for i in 0 .. 8 { assert read64(witness + u64(i * 8)) != 0 }
	assert read64(witness + 64) == 8 && read64(witness + 72) == 8
	assert read64(witness + 80) == 0x7fffffff00010007
}
fn array_descriptor(api ArrayApi) {
	d := api.descriptor
	assert unsafe { *(&u32(d)) } & 0xffff == 0xd1
	assert unsafe { (&u8(array_relative(d + 8))).vstring() } == 'Array'
	parent := array_relative(d + 4)
	assert unsafe { *(&u32(parent)) } == 0
	assert unsafe { (&u8(array_relative(parent + 8))).vstring() } == 'Swift'
	assert unsafe { *(&u32(d + 20)) } == 1 && unsafe { *(&u32(d + 24)) } == 3
	assert unsafe { *(&u32(d + 36)) } == 1 && unsafe { *(&u32(d + 40)) } == 1
	assert unsafe { *(&u8(d + 44)) } == 0x80
	from_descriptor := unsafe { ArrayAccess(voidptr(array_relative(d + 12))) }
	for request in [u64(0), 0x3f, 0xff, 0x100, 0x1ff]! {
		for access in [api.access, from_descriptor]! {
			response := access(request, api.element)
			assert response.metadata == api.metadata && response.state == 0
		}
	}
	if !api.native {
		assert array_relative(d + 16) == 0
		cache := array_relative(d + 28)
		for i in 0 .. 16 { assert read64(cache + u64(i * 8)) == 0 }
		pattern := array_relative(d + 32)
		assert unsafe { *(&u32(pattern + 4)) } == 0
		assert unsafe { *(&u32(pattern + 8)) } == 0x40000000
		assert array_relative(pattern + 12) == read64(api.metadata - 8)
		instantiate := unsafe { ArrayInstantiate(voidptr(array_relative(pattern))) }
		mut arguments := [api.element, u64(0xbad), u64(0xbad)]!
		assert instantiate(d, u64(unsafe { &arguments[0] }), pattern) == api.metadata
	}
}
fn array_enums(api ArrayApi) {
	for cases in [u32(0), 1, 2, 17, 0x7fffffff, 0x80000000, 0xffffffff]! {
		length := if cases > 0x7fffffff { usize(9) } else { usize(8) }
		value := u64(C.malloc(length))
		defer { C.free(unsafe { voidptr(value) }) }
		for tag in [u32(0), 1, 2, 17, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff]! {
			if tag > cases { continue }
			C.memset(unsafe { voidptr(value) }, 0x5a, length)
			api.store_tag(value, tag, cases)
			assert api.get_tag(value, cases) == tag
			assert read64(value) == if tag == 0 { u64(0x5a5a5a5a5a5a5a5a) } else if tag <= 0x7fffffff { u64(tag - 1) } else { u64(tag - 0x80000000) }
			if length == 9 { assert unsafe { *(&u8(value + 8)) } == if tag > 0x7fffffff { u8(1) } else { u8(0) } }
		}
	}
	mut owner := u64(0)
	for value in [u64(0), 1, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xffffffff, 0x100000000, 0xe800000000000000]! {
		owner = value
		for cases in [u32(0), 1, 17]! {
			assert api.get_tag(u64(unsafe { &owner }), cases) == if value >> 32 == 0 { u32(value + 1) } else { u32(0) }
		}
	}
}
fn array_refs(api ArrayApi, object u64, native_heap bool) u64 {
	if native_heap { return (read64(object + 8) >> 33) + 1 }
	$if macos { if api.native { return u64(C.CFGetRetainCount(unsafe { voidptr(object) })) } }
	return u64(obj_header(object).refs)
}
fn array_foreign(api ArrayApi) u64 {
	$if macos {
		if api.native {
			object := u64(C.CFArrayCreateMutable(unsafe { nil }, 0, unsafe { nil }))
			assert object != 0
			return object | (u64(1) << 62)
		}
	}
	return objc_allocate(ios_runtime.names['NSMutableArray']) | (u64(1) << 62)
}
fn array_ownership(api ArrayApi, owner u64, object u64, native_heap bool) {
	mut source := owner
	mut destination := u64(0)
	mut buffer := [u64(0), u64(0xcafebabe), u64(0xdeadbeef)]!
	sp := u64(unsafe { &source }); dp := u64(unsafe { &destination }); bp := u64(unsafe { &buffer[0] })
	assert api.copy(2, dp, sp) == dp && destination == owner
	assert api.copy(0, bp, dp) == bp && buffer[0] == owner && buffer[1] == 0xcafebabe && buffer[2] == 0xdeadbeef
	if object != 0 { assert array_refs(api, object, native_heap) == 3 }
	assert api.copy(3, dp, dp) == dp
	assert api.copy(3, bp, dp) == bp
	if object != 0 { assert array_refs(api, object, native_heap) == 3 }
	api.destroy(dp)
	mut moved := u64(0)
	mp := u64(unsafe { &moved })
	assert api.copy(4, mp, bp) == mp && moved == owner
	assert api.copy(5, sp, mp) == sp && source == owner
	if object != 0 { assert array_refs(api, object, native_heap) == 1 }
	api.destroy(sp)
}
fn array_worker(api ArrayApi, source u64) {
	for _ in 0 .. 200 {
		mut copy := u64(0)
		address := u64(unsafe { &copy })
		assert api.copy(2, address, source) == address
		api.destroy(address)
		mut element := api.element
		for _ in 0 .. 16 {
			response := api.access(0x1ff, element)
			// A native nonblocking Abstract request may observe instantiation
			// in progress. Complete the same canonical entry before using it.
			assert response.state <= 0xff
			if !api.native { assert response.state == 0 }
			complete := api.access(0, element)
			assert complete.metadata == response.metadata && complete.state == 0
			array_layout(api, response.metadata, element)
			element = response.metadata
		}
	}
}
__global array_reentry_api = unsafe { &ArrayApi(nil) }
__global array_reentry_destination = u64(0)
__global array_reentry_expected = u64(0)
__global array_reentry_seen = false
fn array_reentry_reader() {
	assert read64(array_reentry_destination) == array_reentry_expected
	assert array_reentry_api.access(0, array_reentry_api.element).metadata == array_reentry_api.metadata
	mut copy := u64(0)
	address := u64(unsafe { &copy })
	assert array_reentry_api.copy(2, address, array_reentry_destination) == address
	array_reentry_api.destroy(address)
}
fn array_reentry_dealloc(_object u64, _selector &char) {
	worker := spawn array_reentry_reader()
	worker.wait()
	array_reentry_seen = true
}
fn array_reentry(api ArrayApi) {
	cls := objc_allocate_class(ios_runtime.names['NSMutableArray'], c'SwiftArrayWitnessReentry', 0)
	assert cls != 0 && objc_add_method(cls, objc_selector(c'dealloc'), u64(unsafe { voidptr(array_reentry_dealloc) }), c'v16@0:8')
	objc_register_class(cls)
	array_reentry_api = unsafe { &api }
	for slot in [3, 5]! {
		mut previous := array_foreign(api)
		mut next := array_foreign(api)
		assert objc_set_class(previous & swift_address_mask, cls) != 0
		array_reentry_destination = u64(unsafe { &previous })
		array_reentry_expected = next
		array_reentry_seen = false
		assert api.copy(slot, array_reentry_destination, u64(unsafe { &next })) == array_reentry_destination
		assert array_reentry_seen && previous == next
		if slot == 3 { api.destroy(u64(unsafe { &next })) }
		assert array_refs(api, previous & swift_address_mask, false) == 1
		api.destroy(array_reentry_destination)
	}
	array_reentry_api = unsafe { nil }
	array_reentry_destination = 0
	array_reentry_expected = 0
}
fn array_run(api ArrayApi) {
	array_layout(api, api.metadata, api.element); array_descriptor(api); array_enums(api)
	array_ownership(api, u64(0x8000000000001000), 0, false)
	owner := array_foreign(api)
	array_ownership(api, owner, owner & swift_address_mask, false)
	for text in ['', 'Fortnite', 'é 🎮 a UTF-8 owner longer than fifteen bytes']! {
		words := swift_string_literal(text.str, i64(text.len), text.is_ascii())
		buffer := api.utf8(words.first, words.second)
		array_ownership(api, buffer, buffer, true)
	}
	// Different owners exercise retirement rather than only self-assignment.
	mut a := array_foreign(api); mut b := array_foreign(api); mut keeper := u64(0)
	ap := u64(unsafe { &a }); bp := u64(unsafe { &b }); kp := u64(unsafe { &keeper })
	old := a & swift_address_mask; new := b & swift_address_mask
	assert api.copy(2, kp, ap) == kp && api.copy(3, ap, bp) == ap
	assert array_refs(api, old, false) == 1 && array_refs(api, new, false) == 2
	api.destroy(kp)
	assert api.copy(5, ap, bp) == ap && array_refs(api, new, false) == 1
	api.destroy(ap)
	mut source := array_foreign(api)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn array_worker(api, u64(unsafe { &source })) }
	workers.wait()
	assert array_refs(api, source & swift_address_mask, false) == 1
	api.destroy(u64(unsafe { &source }))
}
fn array_retired(address u64) {
	$if macos {
		// macOS redacts mincore's mapping information. mprotect on a hole
		// fails; a surviving read-only metadata page would succeed here.
		assert C.mprotect(unsafe { voidptr(address) }, usize(C.getpagesize()), C.PROT_READ) == -1
	} $else {
		mut resident := u8(0)
		assert C.mincore(unsafe { voidptr(address) }, usize(C.getpagesize()), &resident) == -1
	}
}
fn test_swift_array_metadata_and_witnesses() {
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		access := unsafe { ArrayAccess(C.dlsym(lib, c'$sSaMa')) }
		for name in [c'$sSSN', c'$ss4Int8VN']! {
			element := u64(C.dlsym(lib, name))
			response := access(0, element)
			api := ArrayApi{ native: true, metadata: response.metadata, element: element,
				descriptor: u64(C.dlsym(lib, c'$sSaMn')), access: access,
				utf8: unsafe { ArrayUTF8(C.dlsym(lib, c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg')) } }
			array_run(api)
		}
		println('IOS-SWIFT-ARRAY-NATIVE: generic descriptor/layout, complete canonical responses, eight value witnesses, exact-size enums through UINT32_MAX, native/ObjC ownership and concurrent nested specialization')
	}
	for _ in 0 .. 2 {
		objc_start()
		library := '/usr/lib/swift/libswiftCore.dylib'
		access := unsafe { ArrayAccess(voidptr(runtime_symbol(library, '_$sSaMa') or { panic(err) })) }
		element := swift_string_metadata()
		response := access(0, element)
		api := ArrayApi{ metadata: response.metadata, element: element,
			descriptor: runtime_symbol(library, '_$sSaMn') or { panic(err) }, access: access,
			utf8: unsafe { ArrayUTF8(voidptr(runtime_symbol(library, '_$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg') or { panic(err) })) } }
		array_run(api); array_reentry(api)
		assert ios_runtime.swift_array_metadata.len == 16
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		mut retired := [16]u64{}
		mut index := 0
		for _, metadata in ios_runtime.swift_array_metadata { retired[index] = metadata - 8; index++ }
		arena := ios_runtime.swift_array_arena
		objc_stop()
		assert ios_runtime.swift_array_arena == 0 && ios_runtime.swift_metadata_arena == 0 && ios_runtime.live == 0
		for address in retired { array_retired(address) }
		for offset in 0 .. 3 { array_retired(arena + u64(offset * C.getpagesize())) }
	}
	println('IOS-SWIFT-ARRAY: canonical sealed metadata per Element, genuine generic descriptor/accessor/pattern, eight ownership and enum witnesses, reentrant assignment destruction, concurrent publication, unsupported arbitrary heap-class allocation and two empty teardowns')
}
