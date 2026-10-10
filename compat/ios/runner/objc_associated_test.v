// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <CoreFoundation/CFArray.h>
	#include <CoreFoundation/CFData.h>
	#include <CoreFoundation/CFDictionary.h>
}
#include <dlfcn.h>

fn C.objc_getClass(&char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_createInstance(voidptr, usize) voidptr
fn C.class_addIvar(voidptr, &char, usize, u8, &char) bool
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.class_replaceMethod(voidptr, voidptr, voidptr, &char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.objc_storeWeak(&voidptr, voidptr) voidptr
fn C.objc_destructInstance(voidptr) voidptr
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFArrayCreateMutable(voidptr, i64, voidptr) voidptr
fn C.CFArrayAppendValue(voidptr, voidptr)
fn C.CFArrayGetCount(voidptr) i64
fn C.CFDictionaryCreateMutable(voidptr, i64, voidptr, voidptr) voidptr
fn C.CFDictionarySetValue(voidptr, voidptr, voidptr)
fn C.CFDictionaryGetValue(voidptr, voidptr) voidptr
fn C.CFDataCreateMutable(voidptr, i64) voidptr
fn C.CFDataSetLength(voidptr, i64)
fn C.CFDataGetMutableBytePtr(voidptr) &u8
fn C.CFDataGetBytePtr(voidptr) &u8
fn C.CFDataGetLength(voidptr) i64

type AssociationSet = fn (u64, u64, u64, u64)
type AssociationGet = fn (u64, u64) u64
type AssociationRemove = fn (u64)
type AssociationRelease = fn (u64)
type AssociationPush = fn () u64
type AssociationPop = fn (u64)
type AssociationSend = fn (u64, u64) u64
type AssociationBlockCopy = fn (u64) u64

struct AssociationApi {
	native bool
	root u64
	probe u64
	@[required]
	set AssociationSet
	@[required]
	get AssociationGet
	@[required]
	remove AssociationRemove
	@[required]
	release AssociationRelease
	@[required]
	push AssociationPush
	@[required]
	pop AssociationPop
}

__global association_api = &AssociationApi(unsafe { nil })
__global association_copy_calls = i64(0)
__global association_reentry_owner = u64(0)
__global association_reentry_value = u64(0)
__global association_reentry_seen = bool(false)
__global association_cpp_value = u64(0)
__global association_cpp_seen = i64(0)
__global association_shutdown_seen = int(0)

fn (api AssociationApi) create(cls u64) u64 {
	$if macos { if api.native { return u64(C.class_createInstance(voidptr(cls), 0)) } }
	return objc_allocate(cls)
}
fn (api AssociationApi) refs(object u64) i64 {
	$if macos {
		if api.native {
			lib := C.dlopen('/usr/lib/libobjc.A.dylib'.str, C.RTLD_NOW)
			send := unsafe { AssociationSend(C.dlsym(lib, c'objc_msgSend')) }
			return i64(send(object, u64(C.sel_registerName(c'retainCount'))))
		}
	}
	return C.ios_ref_change(unsafe { &obj_header(object).refs }, 0)
}
fn (api AssociationApi) weak(location &u64, value u64) {
	$if macos { if api.native { C.objc_storeWeak(unsafe { &voidptr(location) }, voidptr(value)); return } }
	objc_store_weak(location, value)
}
fn (api AssociationApi) weak_clear(location &u64) {
	$if macos { if api.native { C.objc_storeWeak(unsafe { &voidptr(location) }, unsafe { nil }); return } }
	objc_destroy_weak(location)
}
fn (api AssociationApi) destruct(object u64) {
	$if macos { if api.native { assert u64(C.objc_destructInstance(voidptr(object))) == object; return } }
	assert objc_destruct_instance(object) == object
}
fn association_copy_probe(object u64, selector &char, zone u64) u64 {
	_ = selector
	assert zone == 0
	C.ios_ref_change(unsafe { &association_copy_calls }, 1)
	result := association_api.create(association_api.probe)
	unsafe { *(&u64(result + 8)) = read64(object + 8) }
	return result
}
fn association_dealloc_probe(object u64, selector &char) {
	_ = selector
	if read64(object + 8) == 77 {
		assert association_api.get(association_reentry_owner, 19) == 0
		association_reentry_seen = true
		association_reentry_value = association_api.create(association_api.root)
		association_api.set(association_reentry_owner, 23, association_reentry_value, 1)
		association_api.release(association_reentry_value)
	}
	if read64(object + 8) == 88 {
		assert !association_api.native
		association_shutdown_seen++
		payload := objc_autorelease(association_api.create(association_api.root))
		association_api.set(association_api.root, 99, payload, 1)
	}
	$if macos {
		if association_api.native { C.objc_destructInstance(voidptr(object)); C.free(voidptr(object)); return }
	}
	assert objc_destruct_instance(object) == object
	C.free(unsafe { voidptr(object) })
}

fn association_test_policies(api AssociationApi) {
	for policy in [u64(0), 1, 3, 0x301, 0x303]! {
		for _ in 0 .. 100 {
			pool := api.push()
			owner := api.create(api.root)
			value := api.create(api.probe)
			unsafe { *(&u64(value + 8)) = 41 }
			assert api.get(owner, 7) == 0 && api.get(0, 7) == 0
			api.remove(0); api.set(0, 7, 0, policy)
			api.set(owner, 7, value, policy)
			assert api.refs(value) == if policy in [u64(1), 0x301]! { 2 } else { 1 }
			got := api.get(owner, 7)
			assert (got == value) == (policy !in [u64(3), 0x303]!)
			assert read64(got + 8) == 41
			assert api.refs(got) == if policy == 0x301 { 3 } else if policy in [u64(1), 0x303]! { 2 } else { 1 }
			mut weak := u64(0)
			api.weak(unsafe { &weak }, got)
			api.release(value)
			api.set(owner, 7, 0, policy)
			assert api.get(owner, 7) == 0
			assert (weak != 0) == (policy in [u64(0x301), 0x303]!)
			api.pop(pool)
			assert weak == 0
			api.weak_clear(unsafe { &weak })
			api.release(owner)
		}
	}
	for _ in 0 .. 200 {
		owner := api.create(api.root)
		value := api.create(api.root)
		mut key1 := [u8(1), 2, 3]!
		mut key2 := [u8(1), 2, 3]!
		first := u64(unsafe { &key1[0] })
		second := u64(unsafe { &key2[0] })
		assert first != second
		api.set(owner, first, value, 1)
		api.set(owner, second, value, 1)
		api.set(owner, 0, value, 1)
		assert api.refs(value) == 4
		assert api.get(owner, first) == value && api.get(owner, second) == value && api.get(owner, 0) == value
		api.set(owner, first, value, 1) // Retain before retiring the same value.
		assert api.refs(value) == 4
		api.set(owner, second, 0, 0)
		assert api.get(owner, second) == 0 && api.refs(value) == 3
		api.remove(owner)
		assert api.refs(value) == 1 && api.get(owner, first) == 0 && api.get(owner, 0) == 0
		api.set(owner, first, 0x1234, 0) // ASSIGN never inspects, retains or releases the value.
		assert api.get(owner, first) == 0x1234
		api.remove(owner)
		api.release(value); api.release(owner)
	}
}

fn association_test_lifecycle(api AssociationApi) {
	for _ in 0 .. 200 {
		owner := api.create(api.root)
		value := api.create(api.root)
		mut weak := u64(0)
		api.weak(unsafe { &weak }, value)
		api.set(owner, 5, value, 1)
		api.release(value)
		assert weak == value
		api.release(owner)
		assert weak == 0
		api.weak_clear(unsafe { &weak })
		assert api.get(owner, 5) == 0 // Cleared table, without reading freed object bytes.
		buffer := api.create(api.root)
		payload := api.create(api.root)
		api.weak(unsafe { &weak }, payload)
		api.set(buffer, 5, payload, 1)
		api.release(payload)
		api.destruct(buffer)
		assert weak == 0 && api.get(buffer, 5) == 0
		api.weak_clear(unsafe { &weak })
		C.free(unsafe { voidptr(buffer) })
	}
	owner := api.create(api.root)
	value := api.create(api.probe)
	unsafe { *(&u64(value + 8)) = 77 }
	association_reentry_owner = owner
	association_reentry_seen = false
	api.set(owner, 19, value, 1)
	api.release(value)
	api.remove(owner)
	assert association_reentry_seen && api.get(owner, 23) == association_reentry_value
	api.remove(owner)
	api.release(owner)
	// Classes can own associations, without acquiring instance metadata.
	value2 := api.create(api.root)
	api.set(api.probe, 1, value2, 1)
	assert api.get(api.probe, 1) == value2 && api.refs(value2) == 2
	api.remove(api.probe)
	api.release(value2)
}

fn association_cpp_ctor(object u64, selector &char) u64 { _ = selector; return object }
fn association_cpp_dtor(object u64, selector &char) {
	_ = selector
	assert association_api.get(object, 41) == association_cpp_value
	C.ios_ref_change(unsafe { &association_cpp_seen }, 1)
}

fn association_test_cpp(api AssociationApi) {
	mut base := u64(0)
	mut child := u64(0)
	$if macos {
		if api.native {
			assert C.dlopen('build/ios/fortnite/objc-storage-checks/native-startup.dylib'.str, C.RTLD_NOW) != unsafe { nil }
			base = u64(C.objc_getClass(c'StartupBase'))
			child = u64(C.objc_getClass(c'StartupChild'))
			for cls in [base, child]! {
				C.class_replaceMethod(voidptr(cls), C.sel_registerName(c'.cxx_construct'), unsafe { voidptr(association_cpp_ctor) }, c'@16@0:8')
				C.class_replaceMethod(voidptr(cls), C.sel_registerName(c'.cxx_destruct'), unsafe { voidptr(association_cpp_dtor) }, c'v16@0:8')
			}
		}
	}
	if !api.native {
		base = objc_allocate_class(api.root, c'AssociationCppBase', 0)
		objc_register_class(base)
		child = objc_allocate_class(base, c'AssociationCppChild', 0)
		objc_register_class(child)
		for cls in [base, child]! {
			assert objc_add_method(cls, objc_selector(c'.cxx_destruct'), u64(unsafe { voidptr(association_cpp_dtor) }), c'v16@0:8')
		}
	}
	assert base != 0 && child != 0
	association_cpp_seen = 0
	for _ in 0 .. 100 {
		owner := api.create(child)
		payload := api.create(api.root)
		association_cpp_value = payload
		mut weak := u64(0)
		api.weak(unsafe { &weak }, payload)
		api.set(owner, 41, payload, 1)
		api.release(payload)
		api.release(owner)
		assert weak == 0
		api.weak_clear(unsafe { &weak })
	}
	assert association_cpp_seen == 200 // Each destructor sees associations before removal.
	if !api.native { objc_dispose_class(child); objc_dispose_class(base) }
}

fn association_test_mutable_copies(api AssociationApi) {
	$if macos {
		if api.native {
			lib := C.dlopen('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'.str, C.RTLD_NOW)
			for _ in 0 .. 100 {
				owner := api.create(api.root)
				value := C.CFDataCreateMutable(unsafe { nil }, 0)
				C.CFDataSetLength(value, 3)
				bytes := C.CFDataGetMutableBytePtr(value)
				unsafe { *bytes = 42 }
				api.set(owner, 1, u64(value), 3)
				got := api.get(owner, 1)
				unsafe { *bytes = 9 }
				assert got != u64(value) && C.CFDataGetLength(voidptr(got)) == 3 && unsafe { *C.CFDataGetBytePtr(voidptr(got)) == 42 }
				key := api.create(api.root)
				first := api.create(api.root)
				second := api.create(api.root)
				array := C.CFArrayCreateMutable(unsafe { nil }, 0, C.dlsym(lib, c'kCFTypeArrayCallBacks'))
				C.CFArrayAppendValue(array, voidptr(first))
				api.set(owner, 2, u64(array), 3)
				C.CFArrayAppendValue(array, voidptr(second))
				assert C.CFArrayGetCount(voidptr(api.get(owner, 2))) == 1
				dictionary := C.CFDictionaryCreateMutable(unsafe { nil }, 0,
					C.dlsym(lib, c'kCFTypeDictionaryKeyCallBacks'), C.dlsym(lib, c'kCFTypeDictionaryValueCallBacks'))
				C.CFDictionarySetValue(dictionary, voidptr(key), voidptr(first))
				api.set(owner, 3, u64(dictionary), 3)
				C.CFDictionarySetValue(dictionary, voidptr(key), voidptr(second))
				assert u64(C.CFDictionaryGetValue(voidptr(api.get(owner, 3)), voidptr(key))) == first
				for object in [u64(value), u64(array), u64(dictionary), key, first, second, owner]! { api.release(object) }
			}
			return
		}
	}
	for _ in 0 .. 100 {
		owner := api.create(api.root)
		value := cf_data_mutable(0, 3)
		cf_data_set_length(value, 3)
		unsafe { *(&u8(data_pointer(value))) = 42 }
		api.set(owner, 1, value, 3)
		got := api.get(owner, 1)
		unsafe { *(&u8(data_pointer(value))) = 9 }
		assert got != value && data_length(got) == 3 && unsafe { *(&u8(data_pointer(got))) == 42 }
		key := api.create(api.root)
		first := api.create(api.root)
		second := api.create(api.root)
		array := objc_allocate(ios_runtime.names['NSMutableArray'])
		mut header := obj_header(array)
		array_append(mut header, first)
		api.set(owner, 2, array, 3)
		array_append(mut header, second)
		assert cf_array_count(api.get(owner, 2)) == 1 && read64(api.get(owner, 2)) == ios_runtime.names['NSArray']
		dictionary := cf_dictionary_mutable(0, 0, cf_callbacks_constant('_kCFTypeDictionaryKeyCallBacks'), cf_callbacks_constant('_kCFTypeDictionaryValueCallBacks'))
		cf_dictionary_set(dictionary, key, first)
		api.set(owner, 3, dictionary, 3)
		cf_dictionary_set(dictionary, key, second)
		assert cf_dictionary_value(api.get(owner, 3), key) == first && read64(api.get(owner, 3)) == ios_runtime.names['NSDictionary']
		for object in [value, array, dictionary, key, first, second, owner]! { api.release(object) }
	}
}

fn association_block_noop(block u64) { _ = block }

fn association_test_blocks(api AssociationApi) {
	mut isa := u64(0)
	mut copy_block := AssociationBlockCopy(block_copy)
	mut release_block := AssociationRelease(block_release)
	$if macos {
		if api.native {
			lib := C.dlopen('/usr/lib/libSystem.B.dylib'.str, C.RTLD_NOW)
			isa = u64(C.dlsym(lib, c'_NSConcreteStackBlock'))
			copy_block = unsafe { AssociationBlockCopy(C.dlsym(lib, c'_Block_copy')) }
			release_block = unsafe { AssociationRelease(C.dlsym(lib, c'_Block_release')) }
		}
	}
	if !api.native { isa = block_isa(0) }
	assert isa != 0
	mut descriptor := [u64(0), 32]!
	mut stack := [isa, u64(0), u64(unsafe { voidptr(association_block_noop) }), u64(unsafe { &descriptor[0] })]!
	for _ in 0 .. 200 {
		owner := copy_block(u64(unsafe { &stack[0] }))
		value := api.create(api.root)
		mut weak := u64(0)
		api.weak(unsafe { &weak }, value)
		api.set(owner, 7, value, 1)
		api.release(value)
		release_block(owner)
		assert weak == 0 && api.get(owner, 7) == 0
		api.weak_clear(unsafe { &weak })
		container := api.create(api.root)
		api.set(container, 7, u64(unsafe { &stack[0] }), 3)
		assert api.get(container, 7) != u64(unsafe { &stack[0] })
		api.release(container)
	}
}

fn association_test_worker(api AssociationApi, owner u64) {
	for _ in 0 .. 200 {
		pool := api.push()
		value := api.create(api.root)
		api.set(owner, 9, value, 0x301)
		api.release(value)
		got := api.get(owner, 9)
		if got != 0 { assert api.refs(got) >= 1 }
		api.remove(owner)
		if got != 0 { assert api.refs(got) >= 1 }
		api.pop(pool)
	}
}

fn association_native_api() AssociationApi {
	$if macos {
		lib := C.dlopen('/usr/lib/libobjc.A.dylib'.str, C.RTLD_NOW)
		root := u64(C.objc_getClass(c'NSObject'))
		probe := u64(C.objc_allocateClassPair(voidptr(root), c'VinixAssociationProbe', 0))
		assert probe != 0
		assert C.class_addIvar(voidptr(probe), c'kind', 8, 3, c'Q')
		assert C.class_addMethod(voidptr(probe), C.sel_registerName(c'copyWithZone:'), unsafe { voidptr(association_copy_probe) }, c'@24@0:8^v16')
		assert C.class_addMethod(voidptr(probe), C.sel_registerName(c'dealloc'), unsafe { voidptr(association_dealloc_probe) }, c'v16@0:8')
		C.objc_registerClassPair(voidptr(probe))
		return AssociationApi{
			native: true, root: root, probe: probe
			set: unsafe { AssociationSet(C.dlsym(lib, c'objc_setAssociatedObject')) }
			get: unsafe { AssociationGet(C.dlsym(lib, c'objc_getAssociatedObject')) }
			remove: unsafe { AssociationRemove(C.dlsym(lib, c'objc_removeAssociatedObjects')) }
			release: unsafe { AssociationRelease(C.dlsym(lib, c'objc_release')) }
			push: unsafe { AssociationPush(C.dlsym(lib, c'objc_autoreleasePoolPush')) }
			pop: unsafe { AssociationPop(C.dlsym(lib, c'objc_autoreleasePoolPop')) }
		}
	}
	panic('native Objective-C is unavailable')
}

fn association_test_suite(api AssociationApi) {
	if association_api != unsafe { nil } { C.free(association_api) }
	association_api = &AssociationApi{...api}
	association_copy_calls = 0
	association_test_policies(api)
	assert association_copy_calls == 200
	association_test_lifecycle(api)
	association_test_cpp(api)
	association_test_mutable_copies(api)
	association_test_blocks(api)
	owner := api.create(api.root)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn association_test_worker(api, owner) }
	workers.wait()
	api.remove(owner)
	api.release(owner)
}

fn test_associated_objects_match_native_ownership() {
	$if macos {
		association_test_suite(association_native_api())
		println('IOS-ASSOCIATED-NATIVE: five policies, copyWithZone and mutable snapshots, raw keys, atomic getter lifetime, explicit destruction, C++ destructor ordering, blocks, reentrant removal, classes and eight shared-owner workers')
	}
	for _ in 0 .. 2 {
		objc_start()
		probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixAssociationProbe', 0)
		assert objc_add_ivar(probe, c'kind', 8, 3, c'Q')
		assert objc_add_method(probe, objc_selector(c'copyWithZone:'), u64(unsafe { voidptr(association_copy_probe) }), c'@24@0:8^v16')
		assert objc_add_method(probe, objc_selector(c'dealloc'), u64(unsafe { voidptr(association_dealloc_probe) }), c'v16@0:8')
		objc_register_class(probe)
		api := AssociationApi{
			root: ios_runtime.names['NSObject'], probe: probe
			set: unsafe { AssociationSet(voidptr(runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_setAssociatedObject') or { panic(err) })) }
			get: unsafe { AssociationGet(voidptr(runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_getAssociatedObject') or { panic(err) })) }
			remove: unsafe { AssociationRemove(voidptr(runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_removeAssociatedObjects') or { panic(err) })) }
			release: objc_release, push: objc_pool_push, pop: objc_pool_pop
		}
		association_test_suite(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.associations.len == 0
		// Immortal classes and literal strings are cleared while their metadata
		// and the root pool remain usable. Dealloc can attach and autorelease
		// another value during association cleanup or during pool draining.
		association_shutdown_seen = 0
		payload := api.create(probe)
		unsafe { *(&u64(payload + 8)) = 88 }
		api.set(api.root, 1, payload, 1)
		api.release(payload)
		pooled := objc_autorelease(api.create(probe))
		unsafe { *(&u64(pooled + 8)) = 88 }
		mut literal := [ios_runtime.names['NSString'], u64(0), u64(c'literal'), u64(7)]!
		constant := u64(unsafe { &literal[0] })
		ios_runtime.constants[constant] = true
		child := api.create(api.root)
		api.set(constant, 1, child, 1)
		api.release(child)
		objc_stop()
		assert association_shutdown_seen == 2
		assert ios_runtime.live == 0 && ios_runtime.associations.len == 0 && ios_runtime.objects.len == 0
	}
	C.free(association_api)
	association_api = unsafe { nil }
	println('IOS-ASSOCIATED: native ownership/copy/destructor contract, eight shared-owner workers, literal and class associations, reentrant root-pool cleanup, empty tables and two clean runtime teardowns')
}
