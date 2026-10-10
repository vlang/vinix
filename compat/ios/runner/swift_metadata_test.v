// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFStringAppendCString(voidptr, &char, u32)
fn C.CFGetRetainCount(voidptr) i64

struct SwiftMetadataResponse { metadata u64 state u64 }
type SwiftMetadataAccess = fn (u64) SwiftMetadataResponse
type SwiftWitnessCopy = fn (u64, u64, u64) u64
type SwiftWitnessDestroy = fn (u64, u64)
type SwiftWitnessGetTag = fn (u64, u32, u64) u32
type SwiftWitnessStoreTag = fn (u64, u32, u32, u64)
type SwiftMetadataCString = fn (&u8) SwiftStringWords

struct SwiftMetadataApi {
	native bool
	metadata u64
	@[required]
	access SwiftMetadataAccess
}

__global swift_metadata_reentry_destination = u64(0)
__global swift_metadata_reentry_expected = u64(0)
__global swift_metadata_reentry_metadata = u64(0)
__global swift_metadata_reentry_seen = false

fn swift_metadata_reentry_reader() {
	assert read64(swift_metadata_reentry_destination + 8) == swift_metadata_reentry_expected
	mut copy := SwiftStringWords{}
	address := u64(unsafe { &copy })
	assert swift_string_copy(address, swift_metadata_reentry_destination, swift_metadata_reentry_metadata) == address
	swift_string_destroy(address, swift_metadata_reentry_metadata)
}
fn swift_metadata_reentry_dealloc(object u64, selector &char) {
	assert read64(swift_metadata_reentry_destination + 8) == swift_metadata_reentry_expected
	// Another thread must be able to acquire the newly published owner while
	// the previous owner's deallocator waits. Witness callbacks hold no lock.
	worker := spawn swift_metadata_reentry_reader()
	worker.wait()
	swift_metadata_reentry_seen = true
}
fn swift_metadata_reentry(api SwiftMetadataApi) {
	cls := objc_allocate_class(ios_runtime.names['NSString'], c'SwiftWitnessReentryString', 0)
	assert cls != 0
	assert objc_add_method(cls, objc_selector(c'dealloc'), u64(unsafe { voidptr(swift_metadata_reentry_dealloc) }), c'v16@0:8')
	objc_register_class(cls)
	for slot in [3, 5]! {
		mut previous := swift_metadata_foreign(api, 'previous owner with a deallocator')
		mut next := swift_metadata_foreign(api, 'owner published before deallocation')
		assert objc_set_class(previous.second & swift_address_mask, cls) != 0
		destination := u64(unsafe { &previous })
		swift_metadata_reentry_destination = destination
		swift_metadata_reentry_expected = next.second
		swift_metadata_reentry_metadata = api.metadata
		swift_metadata_reentry_seen = false
		assert api.copy(slot, destination, u64(unsafe { &next })) == destination
		assert swift_metadata_reentry_seen
		if slot == 3 { api.destroy(u64(unsafe { &next })) }
		assert swift_metadata_refs(api, previous.second & swift_address_mask, false) == 1
		api.destroy(destination)
	}
	swift_metadata_reentry_destination = 0
	swift_metadata_reentry_expected = 0
	swift_metadata_reentry_metadata = 0
}

fn (api SwiftMetadataApi) copy(slot int, destination u64, source u64) u64 {
	function := unsafe { SwiftWitnessCopy(voidptr(read64(read64(api.metadata - 8) + u64(slot * 8)))) }
	return function(destination, source, api.metadata)
}
fn (api SwiftMetadataApi) destroy(value u64) {
	function := unsafe { SwiftWitnessDestroy(voidptr(read64(read64(api.metadata - 8) + 8))) }
	function(value, api.metadata)
}
fn (api SwiftMetadataApi) get_tag(value u64, cases u32) u32 {
	function := unsafe { SwiftWitnessGetTag(voidptr(read64(read64(api.metadata - 8) + 48))) }
	return function(value, cases, api.metadata)
}
fn (api SwiftMetadataApi) store_tag(value u64, tag u32, cases u32) {
	function := unsafe { SwiftWitnessStoreTag(voidptr(read64(read64(api.metadata - 8) + 56))) }
	function(value, tag, cases, api.metadata)
}
fn swift_metadata_relative(address u64) u64 {
	offset := unsafe { *(&i32(address)) }
	return if offset == 0 { u64(0) } else { u64(i64(address) + i64(offset)) }
}
fn swift_metadata_name(address u64) string { return unsafe { (&u8(address)).vstring() } }
fn swift_metadata_layout(api SwiftMetadataApi) {
	m := api.metadata
	assert read64(m) == 0x200 && read64(m + 16) == 0
	w := read64(m - 8)
	for i in 0 .. 8 { assert read64(w + u64(i * 8)) != 0 }
	assert read64(w + 64) == 16 && read64(w + 72) == 16
	assert read64(w + 80) == 0x7fffffff02010007
	d := read64(m + 8)
	assert unsafe { *(&u32(d)) } == 0x51
	assert swift_metadata_name(swift_metadata_relative(d + 8)) == 'String'
	parent := swift_metadata_relative(d + 4)
	assert unsafe { *(&u32(parent)) } == 0 && unsafe { *(&u32(parent + 4)) } == 0
	assert swift_metadata_name(swift_metadata_relative(parent + 8)) == 'Swift'
	assert unsafe { *(&u32(d + 20)) } == 1 && unsafe { *(&u32(d + 24)) } == 2
	if !api.native { assert swift_metadata_relative(d + 16) == 0 }
	from_descriptor := unsafe { SwiftMetadataAccess(voidptr(swift_metadata_relative(d + 12))) }
	for request in [u64(0), 0x3f, 0xff, 0x100, 0x1ff]! {
		for accessor in [api.access, from_descriptor]! {
			response := accessor(request)
			assert response.metadata == m && response.state == 0
		}
	}
}
fn swift_metadata_enums(api SwiftMetadataApi) {
	for cases in [u32(0), 1, 2, 17, 0x7fffffff, 0x80000000, 0xffffffff]! {
		length := if cases > 0x7fffffff { usize(17) } else { usize(16) }
		value := u64(C.malloc(length))
		defer { C.free(unsafe { voidptr(value) }) }
		for tag in [u32(0), 1, 2, 17, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff]! {
			if tag > cases { continue }
			C.memset(unsafe { voidptr(value) }, 0x5a, length)
			api.store_tag(value, tag, cases)
			assert api.get_tag(value, cases) == tag
			assert read64(value) == if tag > 0x7fffffff { u64(tag - 0x80000000) } else { u64(0x5a5a5a5a5a5a5a5a) }
			assert read64(value + 8) == if tag == 0 { u64(0x5a5a5a5a5a5a5a5a) } else if tag <= 0x7fffffff { u64(tag - 1) } else { u64(0) }
			if length == 17 { assert unsafe { *(&u8(value + 16)) } == if tag > 0x7fffffff { u8(1) } else { u8(0) } }
		}
	}
	// Empty-case count zero must not interpret the payload or touch byte 16.
	mut words := SwiftStringWords{}
	address := u64(unsafe { &words })
	assert api.get_tag(address, 0) == 0
	for object in [u64(0), 1, 0x7ffffffe, 0x7fffffff, 0x80000000, 0xffffffff, 0x100000000, 0xe800000000000000]! {
		words.second = object
		assert api.get_tag(address, 1) == if object >> 32 == 0 { u32(object + 1) } else { u32(0) }
	}
	for text in ['', 'Fortnite', 'a literal longer than fifteen bytes', 'é 🎮']! {
		mut payload := swift_string_literal(text.str, i64(text.len), text.is_ascii())
		before := payload
		api.store_tag(u64(unsafe { &payload }), 0, 1)
		assert payload.first == before.first && payload.second == before.second
		assert api.get_tag(u64(unsafe { &payload }), 1) == 0
	}
}
fn swift_metadata_ownership(api SwiftMetadataApi, words SwiftStringWords, object u64, native_heap bool) {
	mut source := words
	mut destination := SwiftStringWords{}
	mut buffer := [u64(0), u64(0), u64(0xdeadbeefcafebabe)]!
	sp := u64(unsafe { &source }); dp := u64(unsafe { &destination }); bp := u64(unsafe { &buffer[0] })
	assert api.copy(2, dp, sp) == dp
	assert destination.first == words.first && destination.second == words.second
	assert api.copy(0, bp, dp) == bp && buffer[2] == 0xdeadbeefcafebabe
	if object != 0 { assert swift_metadata_refs(api, object, native_heap) == 3 }
	assert api.copy(3, dp, dp) == dp // Copy self-assignment owns exactly one reference.
	assert api.copy(3, bp, dp) == bp
	if object != 0 { assert swift_metadata_refs(api, object, native_heap) == 3 }
	api.destroy(dp)
	if object != 0 { assert swift_metadata_refs(api, object, native_heap) == 2 }
	mut moved := SwiftStringWords{}
	mp := u64(unsafe { &moved })
	assert api.copy(4, mp, bp) == mp && moved.first == words.first && moved.second == words.second
	assert api.copy(5, sp, mp) == sp
	if object != 0 { assert swift_metadata_refs(api, object, native_heap) == 1 }
	api.destroy(sp)
}
fn swift_metadata_refs(api SwiftMetadataApi, object u64, native_heap bool) u64 {
	if native_heap { return (read64(object + 8) >> 33) + 1 }
	$if macos { if api.native { return u64(C.CFGetRetainCount(unsafe { voidptr(object) })) } }
	return u64(obj_header(object).refs)
}
fn swift_metadata_foreign(api SwiftMetadataApi, text string) SwiftStringWords {
	mut object := u64(0)
	$if macos {
		if api.native {
			object = u64(C.CFStringCreateMutable(unsafe { nil }, 0))
			C.CFStringAppendCString(unsafe { voidptr(object) }, text.str, 0x08000100)
		}
	}
	if !api.native { object = owned_string(text) }
	// Foreign Cocoa String form. The witnesses manipulate its bridge owner;
	// this test does not ask the currently unsupported foreign UTF-8 getter.
	return SwiftStringWords{ first: u64(text.len), second: object | u64(0x5000000000000000) }
}
fn swift_metadata_worker(api SwiftMetadataApi, source u64) {
	for _ in 0 .. 2000 {
		mut copy := SwiftStringWords{}
		cp := u64(unsafe { &copy })
		assert api.copy(2, cp, source) == cp
		api.destroy(cp)
		if !api.native { assert swift_string_metadata() == api.metadata }
	}
}
fn swift_metadata_run(api SwiftMetadataApi) {
	swift_metadata_layout(api); swift_metadata_enums(api)
	for text in ['', 'Fortnite', '123456789012345', '1234567890123456', 'é 🎮', 'a\x00b']! {
		words := swift_string_literal(text.str, i64(text.len), text.is_ascii())
		swift_metadata_ownership(api, words, 0, false)
	}
	for text in ['owned Cocoa string for String witnesses', 'é 🎮 another owned Cocoa value']! {
		words := swift_metadata_foreign(api, text)
		swift_metadata_ownership(api, words, words.second & swift_address_mask, false)
	}
	// Assignment from a different owner must release the previous one.
	mut a := swift_metadata_foreign(api, 'first String owner')
	mut b := swift_metadata_foreign(api, 'second String owner')
	mut keeper := SwiftStringWords{}
	ap := u64(unsafe { &a }); bp := u64(unsafe { &b }); kp := u64(unsafe { &keeper })
	old := a.second & swift_address_mask; new := b.second & swift_address_mask
	assert api.copy(2, kp, ap) == kp
	assert api.copy(3, ap, bp) == ap
	assert swift_metadata_refs(api, old, false) == 1 && swift_metadata_refs(api, new, false) == 2
	api.destroy(kp)
	assert api.copy(5, ap, bp) == ap
	assert swift_metadata_refs(api, new, false) == 1
	api.destroy(ap)
	mut source := swift_metadata_foreign(api, 'concurrent String copies')
	object := source.second & swift_address_mask
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn swift_metadata_worker(api, u64(unsafe { &source })) }
	workers.wait()
	assert swift_metadata_refs(api, object, false) == 1
	api.destroy(u64(unsafe { &source }))
}
fn test_swift_string_metadata_and_witnesses() {
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		native := SwiftMetadataApi{ native: true, metadata: u64(C.dlsym(lib, c'$sSSN')),
			access: unsafe { SwiftMetadataAccess(C.dlsym(lib, c'$sSSMa')) } }
		swift_metadata_run(native)
		ctor := unsafe { SwiftMetadataCString(C.dlsym(lib, c'$sSS7cStringSSSPys4Int8VG_tcfC')) }
		for text in ['a native owned String longer than fifteen bytes', 'é 🎮 another native owned String']! {
			words := ctor(text.str)
			swift_metadata_ownership(native, words, words.second, true)
		}
		println('IOS-SWIFT-METADATA-NATIVE: String metadata and descriptor, complete accessor responses, eight witnesses, exact-size enum payloads through UINT32_MAX, native/ObjC ownership, assignments and eight concurrent workers')
	}
	for _ in 0 .. 2 {
		objc_start()
		library := '/usr/lib/swift/libswiftCore.dylib'
		api := SwiftMetadataApi{ metadata: runtime_symbol(library, '_$sSSN') or { panic(err) },
			access: unsafe { SwiftMetadataAccess(voidptr(runtime_symbol(library, '_$sSSMa') or { panic(err) })) } }
		assert runtime_symbol(library, '_$sSSMn') or { panic(err) } == read64(api.metadata + 8)
		swift_metadata_run(api)
		swift_metadata_reentry(api)
		if _ := runtime_symbol(library, '_swift_allocObject') { assert false }
		if _ := runtime_symbol(library, '_swift_getTypeByMangledNameInContext') { assert false }
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_arc_code == 0 && ios_runtime.live == 0
	}
	println('IOS-SWIFT-METADATA: immutable String metadata, relative nominal descriptor and accessor, all eight witnesses, Optional/enum tags, acquire-before-publish and retire-after-publish ownership, copy/take assignments, reentrant deallocation without locked callbacks, concurrent copies, unsupported reflection/allocation and two empty teardowns')
}
