// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFDictionary.h>
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFStringAppendCString(voidptr, &char, u32)
fn C.CFErrorCreate(voidptr, voidptr, i64, voidptr) voidptr
fn C.CFDictionaryCreateMutable(voidptr, i64, voidptr, voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
fn C.object_getClass(voidptr) voidptr

type ObjectTypeGet = fn (u64) u64
type ObjectTypeProbe = fn (u64, u64, &u64)
type ObjectTypeAllocate = fn (i64, u64) SwiftArrayAllocation
type ObjectTypeRelease = fn (u64)

fn object_type_case(get ObjectTypeGet, metadata ObjectTypeGet, probe ObjectTypeProbe, owner u64, cls u64) {
	expected := metadata(cls)
	assert read64(expected) == 0x305 && read64(expected + 8) == cls
	for _ in 0 .. 256 {
		mut output := [u64(0x1234), 0, 0, 0, 0x5678]!
		probe(owner, u64(unsafe { voidptr(get) }), unsafe { &output[1] })
		assert output[0] == 0x1234 && output[4] == 0x5678
		assert output[1] == expected && output[2] == 0x5020 && output[3] == 0x5021
		assert get(owner) == expected && metadata(cls) == expected
	}
}

fn object_type_native(probe ObjectTypeProbe) {
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		get := unsafe { ObjectTypeGet(C.dlsym(lib, c'swift_getObjectType')) }
		metadata := unsafe { ObjectTypeGet(C.dlsym(lib, c'swift_getObjCClassMetadata')) }
		text := C.CFStringCreateMutable(unsafe { nil }, 0)
		C.CFStringAppendCString(text, c'Vinix long owned object type string é 🎮', 0x08000100)
		error_owner := C.CFErrorCreate(unsafe { nil }, text, -26275, unsafe { nil })
		dictionary := C.CFDictionaryCreateMutable(unsafe { nil }, 0, unsafe { nil }, unsafe { nil })
		for owner in [u64(text), u64(error_owner), u64(dictionary)]! {
			refs := C.CFGetRetainCount(unsafe { voidptr(owner) })
			object_type_case(get, metadata, probe, owner, u64(C.object_getClass(unsafe { voidptr(owner) })))
			assert C.CFGetRetainCount(unsafe { voidptr(owner) }) == refs
		}
		C.CFRelease(error_owner); C.CFRelease(text); C.CFRelease(dictionary)
		allocate := unsafe { ObjectTypeAllocate(C.dlsym(lib, c'$ss27_allocateUninitializedArrayySayxG_BptBwlF')) }
		release := unsafe { ObjectTypeRelease(C.dlsym(lib, c'swift_release')) }
		int_metadata := u64(C.dlsym(lib, c'$sSiN'))
		array := allocate(5, int_metadata)
		assert array.owner != 0 && array.bytes != 0
		for i in 0 .. 5 { unsafe { *(&u64(array.bytes + u64(i * 8))) = u64(i) } }
		cls := get(array.owner); bits := read64(array.owner + 8)
		assert cls == read64(array.owner) & 0x0000ffffffffffff
		assert read64(cls + 32) & 2 != 0 && read64(cls + 64) != 0
		for _ in 0 .. 256 {
			mut output := [3]u64{}
			probe(array.owner, u64(unsafe { voidptr(get) }), unsafe { &output[0] })
			assert output[0] == cls && output[1] == 0x5020 && output[2] == 0x5021
		}
		assert read64(array.owner + 8) == bits
		// Vinix can allocate against this genuine native class metadata without
		// calling its authenticated destructor: deallocate uninitialized storage.
		objc_start()
		size := u64(unsafe { *(&u32(cls + 48)) }); mask := u64(unsafe { *(&u16(cls + 52)) })
		owner := swift_heap_allocate(cls, size, mask)
		assert swift_object_type(owner) == cls && read64(owner + 8) == 3
		swift_heap_deallocate_uninitialized(owner, size, mask)
		objc_stop(); release(array.owner)
		println('IOS-SWIFT-OBJECT-TYPE-NATIVE: ordinary C borrowed CFError/string/dictionary type lookup, canonical class wrappers, guarded raw calls preserving x20/x21, genuine Swift ContiguousArrayStorage<Int> metadata and Vinix heap allocation against that native class')
	}
}

fn object_type_worker(owner u64) u64 {
	metadata := swift_object_type(owner)
	for _ in 0 .. 1000 { assert swift_object_type(owner) == metadata }
	return metadata
}

struct ObjectTypeState {
	metadata u64
mut:
	calls int
}
fn object_type_dealloc(owner u64, _selector &char) {
	mut state := unsafe { &ObjectTypeState(obj_header(owner).tag) }
	assert obj_header(owner).refs == 0 && swift_object_type(owner) == state.metadata
	worker := spawn object_type_worker(owner)
	assert worker.wait() == state.metadata
	state.calls++
	// Caller destruction can leave metadata until this callback returns. Type
	// lookup must reject it before reading bytes the caller may already free.
	assert objc_destruct_instance(owner) == owner
	if _ := swift_object_type_checked(owner) { assert false }
	C.free(unsafe { voidptr(owner) })
}
fn object_type_heap_dealloc(owner u64) {
	mut state := unsafe { &ObjectTypeState(read64(owner + 16)) }
	assert read64(owner + 8) == 0x100000003 && swift_object_type(owner) == state.metadata
	worker := spawn object_type_worker(owner)
	assert worker.wait() == state.metadata
	state.calls++
	swift_heap_deallocate(owner, 32, 15)
}

fn object_type_rejected(owner u64) {
	if _ := swift_object_type_checked(owner) { assert false, 'unsupported owner accepted' }
}

fn object_type_class_worker(cls u64) u64 { return swift_objc_metadata(cls) }
fn object_type_formal_class(owner u64, selector &char) u64 {
	assert u64(selector) == objc_selector(c'class')
	cls := u64(obj_header(owner).tag)
	if cls == ios_runtime.names['NSObject'] {
		worker := spawn object_type_class_worker(cls)
		assert worker.wait() == swift_objc_metadata(cls)
	}
	return cls
}
fn object_type_initialize(cls u64, _selector &char) {
	objc_replace_method(cls, objc_selector(c'class'), u64(unsafe { voidptr(object_type_formal_class) }), c'#16@0:8')
}

fn object_type_suite(probe ObjectTypeProbe, fixture u64) {
	get := unsafe { ObjectTypeGet(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_getObjectType') or { panic(err) })) }
	for cls in [ios_runtime.names['NSString'], cf_error_type_id(), ios_runtime.names['NSDictionary']]! {
		owner := objc_allocate(cls)
		object_type_case(get, swift_objc_metadata, probe, owner, cls)
		assert obj_header(owner).refs == 1
		objc_release(owner)
	}
	first := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixObjectTypeFirst', 0)
	second := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixObjectTypeSecond', 0)
	objc_register_class(first); objc_register_class(second)
	owner := objc_allocate(first)
	mut workers := []thread u64{}
	for _ in 0 .. 8 { workers << spawn object_type_worker(owner) }
	values := workers.wait()
	for metadata in values { assert metadata == values[0] && read64(metadata + 8) == first }
	assert obj_header(owner).refs == 1
	assert objc_set_class(owner, second) == first
	assert get(owner) == swift_objc_metadata(second) && get(owner) != values[0]
	assert objc_set_class(owner, first) == second && get(owner) == values[0]
	mut state := ObjectTypeState{ metadata: values[0] }
	mut header := obj_header(owner); header.tag = i64(unsafe { &state })
	objc_replace_method(first, objc_selector(c'dealloc'), u64(unsafe { voidptr(object_type_dealloc) }), c'v16@0:8')
	objc_release(owner); assert state.calls == 1
	formal := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixObjectTypeFormalClass', 0)
	objc_register_class(formal)
	objc_replace_method(formal, objc_selector(c'class'), u64(unsafe { voidptr(object_type_formal_class) }), c'#16@0:8')
	formal_owner := objc_allocate(formal)
	mut formal_header := obj_header(formal_owner); formal_header.tag = i64(ios_runtime.names['NSObject'])
	assert get(formal_owner) == swift_objc_metadata(ios_runtime.names['NSObject'])
	assert get(formal_owner) != swift_objc_metadata(formal) && formal_header.refs == 1
	// Invalid formal classes must fail metadata validation after the callback.
	formal_header.tag = i64(read64(formal)); object_type_rejected(formal_owner)
	formal_header.tag = i64(ios_runtime.names['NSObject'])
	objc_release(formal_owner)
	constructed := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixObjectTypeCallerConstructed', 0)
	objc_register_class(constructed)
	objc_replace_method(read64(constructed), objc_selector(c'initialize'), u64(unsafe { voidptr(object_type_initialize) }), c'v16@0:8')
	bytes := u64(C.calloc(1, usize(ios_runtime.classes[constructed].size)))
	assert bytes != 0 && objc_construct_instance(constructed, bytes) == bytes
	mut constructed_header := obj_header(bytes); constructed_header.tag = i64(ios_runtime.names['NSObject'])
	assert !ios_runtime.classes[constructed].initialized
	assert get(bytes) == swift_objc_metadata(ios_runtime.names['NSObject']) && ios_runtime.classes[constructed].initialized
	assert objc_destruct_instance(bytes) == bytes
	C.free(unsafe { voidptr(bytes) }); object_type_rejected(bytes)
	// A Swift class prefix takes the nominal metadata fast path, ignoring
	// ObjC class overrides. Extra class bytes hold the full metadata fixture.
	swift_cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixObjectTypeSwiftClassPrefix', 40)
	objc_register_class(swift_cls)
	objc_replace_method(swift_cls, objc_selector(c'class'), u64(unsafe { voidptr(object_type_formal_class) }), c'#16@0:8')
	unsafe { *(&u64(swift_cls + 32)) = 2; *(&u64(swift_cls + 64)) = fixture + 128 }
	swift_owner := objc_allocate(swift_cls)
	assert get(swift_owner) == swift_cls && obj_header(swift_owner).refs == 1
	unsafe { *(&u64(swift_cls + 64)) = 0 }; object_type_rejected(swift_owner)
	objc_release(swift_owner); objc_dispose_class(swift_cls)
	// A Mach-O constant's registered storage borrows the same class wrapper.
	mut constant := [ios_runtime.names['NSString'], u64(0), 0, 0]!
	address := u64(unsafe { &constant[0] })
	ios_runtime.constants[address] = true
	assert get(address) == swift_objc_metadata(constant[0])
	ios_runtime.constants.delete(address)
	object_type_rejected(address)
	for invalid in [u64(0), 1, 0xdeadbeef, 0x8000000000000001, first, read64(first)]! { object_type_rejected(invalid) }
	page := usize(C.getpagesize())
	protected := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert protected != u64(-1); object_type_rejected(protected)
	assert C.munmap(unsafe { voidptr(protected) }, page) == 0
	// This is a full class-layout fixture, not a native class allocation. A
	// nonzero nominal descriptor distinguishes it from an artificial subclass.
	metadata := fixture + 16
	unsafe { *(&u64(metadata)) = 0; *(&u64(metadata + 32)) = 2; *(&u64(metadata + 64)) = fixture + 128 }
	write32(metadata + 40, 2); write32(metadata + 44, 0); write32(metadata + 48, 32)
	write32(metadata + 52, 15); write32(fixture + 128, 0x10)
	class_owner := swift_heap_allocate(metadata, 32, 15)
	mut heap_state := ObjectTypeState{ metadata: metadata }
	unsafe { *(&u64(class_owner + 16)) = u64(&heap_state) }
	assert get(class_owner) == metadata && read64(class_owner + 8) == 3
	unsafe { *(&u64(class_owner)) = metadata + 8 }; object_type_rejected(class_owner)
	unsafe { *(&u64(class_owner)) = metadata; *(&u64(metadata + 64)) = 0 }; object_type_rejected(class_owner)
	unsafe { *(&u64(metadata + 64)) = fixture + 128 }
	swift_release(class_owner); assert heap_state.calls == 1
	object_type_rejected(class_owner)
	for kind in [u64(0x400), 0x500]! {
		unsafe { *(&u64(metadata)) = kind }
		context := swift_heap_allocate(metadata, 32, 15)
		object_type_rejected(context); swift_heap_deallocate_uninitialized(context, 32, 15)
	}
	private_array := swift_array_allocate(1, swift_string_metadata())
	unsafe { *(&u64(private_array.bytes)) = 0; *(&u64(private_array.bytes + 8)) = 0 }
	object_type_rejected(private_array.owner); swift_release(private_array.owner)
	object_type_rejected(swift_array_allocate(0, swift_string_metadata()).owner)
	mut words := swift_interpolation_init(64, 0)
	text := 'long private Swift String allocation'
	swift_string_append_bytes(u64(unsafe { &words }), u64(text.str), u64(text.len))
	object_type_rejected(words.second & swift_address_mask)
	utf8 := swift_string_utf8(words.first, words.second) or { panic(err) }
	object_type_rejected(utf8); swift_release(utf8); swift_bridge_release(words.second)
	assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0
}

fn test_swift_object_type() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0203f3, 0xaa0103f0,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	// Deallocating destructor receives self in x20; tail-call the V callback.
	for i, op in [u32(0xaa1403e0), 0x58000070, 0xd61f0200, 0xd503201f]! { write32(code + 64 + u64(i * 4), op) }
	unsafe { *(&u64(code + 80)) = u64(voidptr(object_type_heap_dealloc)) }
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 88) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { ObjectTypeProbe(voidptr(code)) }
	object_type_native(probe)
	fixture := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert fixture != u64(-1)
	unsafe { *(&u64(fixture)) = code + 64 }
	for _ in 0 .. 2 {
		objc_start(); object_type_suite(probe, fixture)
		arena := ios_runtime.swift_error_arena; wrapper := swift_objc_metadata(ios_runtime.names['NSObject'])
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_arrays.len == 0
		objc_stop()
		assert ios_runtime.swift_objc_metadata.len == 0 && ios_runtime.swift_error_arena == 0
		assert C.mprotect(unsafe { voidptr(arena) }, page, C.PROT_READ) == -1
		assert C.mprotect(unsafe { voidptr(wrapper - 8) }, page, C.PROT_READ) == -1
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0 && C.munmap(unsafe { voidptr(fixture) }, page) == 0
	println('IOS-SWIFT-OBJECT-TYPE: borrowed class metadata, guarded raw C calls preserving x20/x21, eight first-publication readers, object_setClass canonicality, unlocked reentrant formal class override, registered constants, live type lookup during unlocked ObjC/Swift deallocation, rejection before unknown/freed storage reads, private storage/context/artificial-class rejection and two drained/unmapped cycles')
}
