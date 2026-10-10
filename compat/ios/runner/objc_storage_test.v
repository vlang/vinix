// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>

fn C.objc_getClass(&char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.object_getClass(voidptr) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_replaceMethod(voidptr, voidptr, voidptr, &char) voidptr
fn C.objc_constructInstance(voidptr, voidptr) voidptr
fn C.objc_destructInstance(voidptr) voidptr
fn C.objc_storeWeak(&voidptr, voidptr) voidptr
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type StorageConstruct = fn (u64, u64) u64
type StorageDestruct = fn (u64) u64
type StorageRelease = fn (u64)

__global storage_destruct_callback = StorageDestruct(unsafe { nil })
__global storage_initialize_count = i64(0)

struct StorageTestApi {
	native bool
	cls u64
	base u64
	size u64
	@[required]
	construct StorageConstruct
	@[required]
	destruct StorageDestruct
	@[required]
	release StorageRelease
}

fn storage_test_event(object u64, event u64) {
	count := read64(object + 8)
	assert count < 8
	unsafe { *(&u64(object + 16 + count * 8)) = event; *(&u64(object + 8)) = count + 1 }
}
fn storage_test_initialize(object u64, selector &char) { _ = object; _ = selector; storage_initialize_count++ }
fn storage_test_base_ctor(object u64, selector &char) u64 { _ = selector; storage_test_event(object, 1); return object }
fn storage_test_child_ctor(object u64, selector &char) u64 { _ = selector; storage_test_event(object, 2); return object }
fn storage_test_fail_ctor(object u64, selector &char) u64 { _ = selector; storage_test_event(object, 9); return 0 }
fn storage_test_base_dtor(object u64, selector &char) { _ = selector; storage_test_event(object, 5) }
fn storage_test_child_dtor(object u64, selector &char) { _ = selector; storage_test_event(object, 4) }
fn storage_test_dealloc(object u64, selector &char) {
	_ = selector
	storage_test_event(object, 3)
	assert storage_destruct_callback(object) == object
}
fn storage_test_freeing_dealloc(object u64, selector &char) {
	storage_test_dealloc(object, selector)
	C.free(unsafe { voidptr(object) })
}

fn storage_test_native_construct(cls u64, bytes u64) u64 {
	$if macos { return u64(C.objc_constructInstance(voidptr(cls), voidptr(bytes))) }
	panic('native Objective-C is unavailable')
}
fn storage_test_native_destruct(object u64) u64 {
	$if macos { return u64(C.objc_destructInstance(voidptr(object))) }
	panic('native Objective-C is unavailable')
}
fn (api StorageTestApi) method(cls u64, name string, imp u64, types string) {
	$if macos {
		if api.native { C.class_replaceMethod(voidptr(cls), C.sel_registerName(name.str), voidptr(imp), types.str); return }
	}
	objc_replace_method(cls, objc_selector(unsafe { &char(name.str) }), imp, unsafe { &char(types.str) })
}
fn (api StorageTestApi) weak(location &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(unsafe { &voidptr(location) }, voidptr(object)); return } }
	objc_store_weak(location, object)
}
fn (api StorageTestApi) destroy_weak(location &u64) {
	$if macos { if api.native { C.objc_storeWeak(unsafe { &voidptr(location) }, unsafe { nil }); return } }
	objc_destroy_weak(location)
}

fn storage_test_guards(memory u64, size u64) {
	for i := u64(0); i < 16; i++ { assert unsafe { *(&u8(memory + i)) == 0xaa && *(&u8(memory + 16 + size + i)) == 0xaa } }
}
fn storage_test_buffer(size u64) u64 {
	memory := u64(C.calloc(1, usize(size + 32)))
	assert memory != 0
	for i := u64(0); i < 16; i++ { unsafe { *(&u8(memory + i)) = 0xaa; *(&u8(memory + 16 + size + i)) = 0xaa } }
	return memory
}
fn storage_test_events(object u64, events []u64) {
	assert read64(object + 8) == u64(events.len)
	for i, event in events { assert read64(object + 16 + u64(i) * 8) == event }
}

fn storage_test_lifetimes(api StorageTestApi, iterations int) {
	for _ in 0 .. iterations {
		memory := storage_test_buffer(api.size)
		object := memory + 16
		assert api.construct(0, object) == 0 && api.construct(api.cls, 0) == 0 && api.destruct(0) == 0
		assert read64(object) == 0
		assert api.construct(api.cls, object) == object
		storage_test_events(object, [u64(1), 2])
		mut weak := u64(0)
		api.weak(unsafe { &weak }, object)
		assert weak == object
		assert api.destruct(object) == object && weak == 0
		storage_test_events(object, [u64(1), 2, 4, 5]) // Explicit destruction does not send dealloc.
		api.destroy_weak(unsafe { &weak })
		storage_test_guards(memory, api.size)
		unsafe { C.memset(voidptr(object), 0, usize(api.size)) }
		// The same caller-owned bytes can be reused with fresh metadata.
		assert api.construct(api.cls, object) == object
		api.weak(unsafe { &weak }, object)
		api.release(object) // Custom dealloc explicitly destroys and preserves storage.
		assert weak == 0
		api.destroy_weak(unsafe { &weak })
		storage_test_events(object, [u64(1), 2, 3, 4, 5])
		storage_test_guards(memory, api.size)
		C.free(unsafe { voidptr(memory) })
	}
}

fn storage_test_suite(api StorageTestApi) {
	storage_destruct_callback = api.destruct
	mut meta := read64(api.base)
	$if macos { if api.native { meta = u64(C.object_getClass(voidptr(api.base))) } }
	api.method(meta, 'initialize', u64(unsafe { voidptr(storage_test_initialize) }), 'v16@0:8')
	api.method(api.base, '.cxx_construct', u64(unsafe { voidptr(storage_test_base_ctor) }), '@16@0:8')
	api.method(api.base, '.cxx_destruct', u64(unsafe { voidptr(storage_test_base_dtor) }), 'v16@0:8')
	api.method(api.cls, '.cxx_construct', u64(unsafe { voidptr(storage_test_child_ctor) }), '@16@0:8')
	api.method(api.cls, '.cxx_destruct', u64(unsafe { voidptr(storage_test_child_dtor) }), 'v16@0:8')
	api.method(api.cls, 'dealloc', u64(unsafe { voidptr(storage_test_dealloc) }), 'v16@0:8')
	storage_initialize_count = 0
	// Construction itself must not send +initialize.
	memory := storage_test_buffer(api.size)
	assert api.construct(api.cls, memory + 16) == memory + 16 && storage_initialize_count == 0
	api.destruct(memory + 16)
	C.free(unsafe { voidptr(memory) })
	storage_test_lifetimes(api, 200)
	api.method(api.cls, '.cxx_construct', u64(unsafe { voidptr(storage_test_fail_ctor) }), '@16@0:8')
	for _ in 0 .. 200 {
		failed := storage_test_buffer(api.size)
		assert api.construct(api.cls, failed + 16) == 0
		storage_test_events(failed + 16, [u64(1), 9, 5]) // Failed child has no destructor.
		storage_test_guards(failed, api.size)
		C.free(unsafe { voidptr(failed) })
	}
	api.method(api.cls, '.cxx_construct', u64(unsafe { voidptr(storage_test_child_ctor) }), '@16@0:8')
	api.method(api.cls, 'dealloc', u64(unsafe { voidptr(storage_test_freeing_dealloc) }), 'v16@0:8')
	for _ in 0 .. 200 {
		object := u64(C.calloc(1, usize(api.size)))
		assert api.construct(api.cls, object) == object
		api.release(object) // Callback frees its bytes; outer release must not read or free them again.
	}
	api.method(api.cls, 'dealloc', u64(unsafe { voidptr(storage_test_dealloc) }), 'v16@0:8')
}

fn test_objc_supplied_storage_matches_native_lifetimes() {
	$if macos {
		library := C.dlopen('build/ios/fortnite/objc-storage-checks/native-startup.dylib'.str, C.RTLD_NOW)
		assert library != unsafe { nil }
		base := u64(C.objc_getClass('StartupBase'.str))
		cls := u64(C.objc_getClass('StartupChild'.str))
		assert base != 0 && cls != 0
		api := StorageTestApi{
			native: true, base: base, cls: cls, size: u64(C.class_getInstanceSize(voidptr(cls)))
			construct: storage_test_native_construct, destruct: storage_test_native_destruct
			release: unsafe { StorageRelease(C.dlsym(C.dlopen('/usr/lib/libobjc.A.dylib'.str, C.RTLD_NOW), 'objc_release'.str)) }
		}
		storage_test_suite(api)
		println('IOS-OBJC-STORAGE-NATIVE: real compiled C++ class flags; supplied addresses, no initialize, ctor/dtor order, failure unwind, zeroing weak slots, reusable guarded bytes and custom dealloc that preserves or frees storage')
	}
	for _ in 0 .. 2 {
		objc_start()
		// Mach-O literal NSStrings have no allocated metadata. Dispatch must
		// reach their Foundation handlers without probing another framework's
		// instance storage first.
		text := c'literal storage fixture'
		mut literal := [ios_runtime.names['NSString'], u64(0), u64(text), u64(23)]!
		constant := u64(unsafe { &literal[0] })
		ios_runtime.constants[constant] = true
		mut frame := RegisterFrame{}
		assert framework_dispatch(constant, 'UTF8String', mut frame)
		assert frame.x[0] == u64(text)
		assert framework_dispatch(constant, 'length', mut frame) && frame.x[0] == 23
		assert framework_dispatch(constant, 'copy', mut frame) && frame.x[0] == constant
		objc_release(frame.x[0])
		assert constant !in ios_runtime.objects
		ios_runtime.constants.delete(constant)
		base := objc_allocate_class(ios_runtime.names['NSObject'], c'StorageBase', 0)
		assert objc_add_ivar(base, c'state', 80, 3, c'[10Q]')
		objc_register_class(base)
		cls := objc_allocate_class(base, c'StorageChild', 0)
		objc_register_class(cls)
		api := StorageTestApi{
			base: base, cls: cls, size: objc_class_size(cls)
			construct: unsafe { StorageConstruct(voidptr(runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_constructInstance') or { panic(err) })) }
			destruct: unsafe { StorageDestruct(voidptr(runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_destructInstance') or { panic(err) })) }
			release: objc_release
		}
		storage_test_suite(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn storage_test_lifetimes(api, 100) }
		workers.wait()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		// Ordinary allocated objects also support explicit destruction, followed
		// by the caller freeing the returned allocation address.
		for _ in 0 .. 200 {
			object := objc_allocate(ios_runtime.names['NSObject'])
			payload := owned_string('owned metadata payload')
			mut header := obj_header(object)
			objc_store_strong(unsafe { &header.fields[0] }, payload)
			objc_release(payload)
			assert api.destruct(object) == object
			C.free(unsafe { voidptr(object) })
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		}
		assert (ios_runtime.classes[cls] or { panic('class') }).instances == 0
		objc_dispose_class(cls)
		objc_dispose_class(base)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-OBJC-STORAGE: native construction/destruction contract, failure cleanup, released private members, eight independent workers, class instance counts, empty metadata registry and two clean teardowns')
}
