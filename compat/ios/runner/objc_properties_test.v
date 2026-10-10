// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <CoreFoundation/CFData.h>
	#include <CoreFoundation/CFArray.h>
	#include <CoreFoundation/CFDictionary.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addIvar(voidptr, &char, usize, u8, &char) bool
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.sel_registerName(&char) voidptr
fn C.class_createInstance(voidptr, usize) voidptr
fn C.objc_destructInstance(voidptr) voidptr
fn C.objc_storeWeak(&voidptr, voidptr) voidptr
fn C.CFDataCreate(voidptr, &u8, i64) voidptr
fn C.CFDataGetBytePtr(voidptr) &u8
fn C.CFDataGetMutableBytePtr(voidptr) &u8
fn C.CFArrayCreateMutable(voidptr, i64, voidptr) voidptr
fn C.CFArrayAppendValue(voidptr, voidptr)
fn C.CFArrayGetCount(voidptr) i64
fn C.CFDictionaryCreateMutable(voidptr, i64, voidptr, voidptr) voidptr
fn C.CFDictionarySetValue(voidptr, voidptr, voidptr)
fn C.CFDictionaryGetValue(voidptr, voidptr) voidptr

type PropertyGet = fn (u64, u64, i64, bool) u64
type PropertySet = fn (u64, u64, i64, u64, bool, i8)
type PropertySpecialized = fn (u64, u64, u64, i64)
type PropertyRelease = fn (u64)
type PropertyPush = fn () u64
type PropertyPop = fn (u64)
type PropertySend = fn (u64, u64) u64

struct PropertyApi {
	native bool
	root u64
	owner u64
	probe u64
	@[required]
	get PropertyGet
	@[required]
	set PropertySet
	setters [4]PropertySpecialized
	@[required]
	release PropertyRelease
	@[required]
	push PropertyPush
	@[required]
	pop PropertyPop
}
__global property_api = &PropertyApi(unsafe { nil })
__global property_reentry_owner = u64(0)
__global property_reentry_value = u64(0)
__global property_reentry_seen = bool(false)
__global property_direct_calls = i64(0)
__global property_block_calls = i64(0)

fn (api PropertyApi) create(cls u64) u64 {
	$if macos { if api.native { return u64(C.class_createInstance(voidptr(cls), 0)) } }
	return objc_allocate(cls)
}
fn (api PropertyApi) refs(value u64) i64 {
	$if macos {
		if api.native {
			lib := C.dlopen('/usr/lib/libobjc.A.dylib'.str, C.RTLD_NOW)
			send := unsafe { PropertySend(C.dlsym(lib, c'objc_msgSend')) }
			return i64(send(value, u64(C.sel_registerName(c'retainCount'))))
		}
	}
	return C.ios_ref_change(unsafe { &obj_header(value).refs }, 0)
}
fn (api PropertyApi) weak(slot &u64, value u64) {
	$if macos { if api.native { C.objc_storeWeak(unsafe { &voidptr(slot) }, voidptr(value)); return } }
	objc_store_weak(slot, value)
}
fn (api PropertyApi) clear_weak(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(unsafe { &voidptr(slot) }, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn property_copy(object u64, selector u64, zone u64) u64 {
	_ = selector
	assert zone == 0
	if read64(object + 8) == 99 { return 0 }
	result := property_api.create(property_api.probe)
	unsafe { *(&u64(result + 8)) = read64(object + 8) + 1 }
	return result
}
fn property_mutable_copy(object u64, selector u64, zone u64) u64 {
	result := property_copy(object, selector, zone)
	if result != 0 { unsafe { *(&u64(result + 8)) = read64(object + 8) + 2 } }
	return result
}
fn property_direct_copy(object u64, selector u64) u64 {
	_ = selector
	C.ios_ref_change(unsafe { &property_direct_calls }, 1)
	return property_copy(object, 0, 0)
}
fn property_destroy(object u64) {
	$if macos { if property_api.native { C.objc_destructInstance(voidptr(object)); C.free(voidptr(object)); return } }
	assert objc_destruct_instance(object) == object
	C.free(unsafe { voidptr(object) })
}
fn property_owner_dealloc(object u64, selector u64) {
	_ = selector
	property_api.set(object, 0, 16, 0, false, 0)
	property_destroy(object)
}
fn property_reentry_reader(owner u64, expected u64) {
	pool := property_api.push()
	assert property_api.get(owner, 0, 16, true) == expected
	property_api.pop(pool)
}
fn property_probe_dealloc(object u64, selector u64) {
	_ = selector
	if read64(object + 8) == 77 {
		assert property_api.get(property_reentry_owner, 0, 16, true) == property_reentry_value
		// A different thread must be able to read while this callback waits.
		reader := spawn property_reentry_reader(property_reentry_owner, property_reentry_value)
		reader.wait()
		property_reentry_seen = true
		value := property_api.create(property_api.root)
		property_api.set(property_reentry_owner, 0, 16, value, true, 0)
		property_api.release(value)
	}
	property_destroy(object)
}
fn property_owner(api PropertyApi) u64 {
	owner := api.create(api.owner)
	unsafe { *(&u64(owner + 8)) = 0x123456789abcdef0; *(&u64(owner + 24)) = 0xfedcba9876543210 }
	return owner
}
fn property_guards(owner u64) {
	assert read64(owner + 8) == 0x123456789abcdef0 && read64(owner + 24) == 0xfedcba9876543210
}

fn property_test_ownership(api PropertyApi) {
	for is_atomic in [false, true]! {
		for mode in [i8(0), 1, 2]! {
			for _ in 0 .. 200 {
				pool := api.push()
				owner := property_owner(api)
				value := api.create(api.probe)
				unsafe { *(&u64(value + 8)) = 40 }
				api.set(owner, 0, 16, value, is_atomic, mode)
				assert api.refs(value) == if mode == 0 { 2 } else { 1 }
				got := api.get(owner, 0, 16, is_atomic)
				assert (got == value) == (mode == 0) && read64(got + 8) == u64(40 + mode)
				assert api.refs(got) == i64(if mode == 0 { 2 } else { 1 }) + if is_atomic { 1 } else { 0 }
				mut weak := u64(0)
				api.weak(unsafe { &weak }, got)
				api.release(value)
				api.set(owner, 0, 16, 0, is_atomic, mode)
				assert api.get(owner, 0, 16, is_atomic) == 0 && (weak != 0) == is_atomic
				api.pop(pool)
				assert weak == 0
				api.clear_weak(unsafe { &weak })
				property_guards(owner); api.release(owner)
			}
		}
	}
	for index, setter in api.setters {
		for _ in 0 .. 200 {
			owner := property_owner(api)
			value := api.create(api.probe)
			unsafe { *(&u64(value + 8)) = 40 }
			setter(owner, 0, value, 16)
			got := api.get(owner, 0, 16, false)
			assert (got == value) == (index < 2) && read64(got + 8) == if index < 2 { u64(40) } else { u64(41) }
			if index < 2 { setter(owner, 0, value, 16); assert api.refs(value) == 2 }
			if index == 0 { setter(owner + 24, 0, value, -8); assert api.refs(value) == 2 }
			assert api.get(owner + 24, 0, -8, false) == got // Signed pointer-sized offset.
			setter(owner, 0, 0, 16)
			property_guards(owner); api.release(value); api.release(owner)
		}
	}
	owner := property_owner(api)
	value := api.create(api.probe)
	api.set(owner, 0, 16, value, false, 0)
	unsafe { *(&u64(value + 8)) = 99 }
	api.set(owner, 0, 16, value, true, 1) // A nil copy clears the previous value.
	assert api.get(owner, 0, 16, false) == 0 && api.refs(value) == 1
	api.release(value)
	for is_atomic in [false, true]! {
		assert api.get(owner, 0, 0, is_atomic) == api.owner && api.get(0, 0, 0, is_atomic) == 0
		api.set(owner, 0, 0, api.probe, is_atomic, 2)
		assert api.get(owner, 0, 0, is_atomic) == api.probe
		api.set(owner, 0, 0, api.owner, is_atomic, 1)
	}
	property_guards(owner); api.release(owner)
	pool := api.push()
	reentrant_owner := property_owner(api)
	old := api.create(api.probe)
	unsafe { *(&u64(old + 8)) = 77 }
	property_reentry_owner = reentrant_owner
	property_reentry_seen = false
	api.set(reentrant_owner, 0, 16, old, true, 0); api.release(old)
	replacement := api.create(api.root)
	property_reentry_value = replacement
	api.set(reentrant_owner, 0, 16, replacement, true, 0)
	assert property_reentry_seen && api.get(reentrant_owner, 0, 16, false) != replacement
	api.release(replacement); api.release(reentrant_owner); api.pop(pool)
}

fn property_test_mutable(api PropertyApi) {
	$if macos {
		if api.native {
			lib := C.dlopen('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'.str, C.RTLD_NOW)
			for _ in 0 .. 100 {
				owner := property_owner(api)
				mut bytes := [u8(42), 43, 44]!
				data := C.CFDataCreate(unsafe { nil }, unsafe { &bytes[0] }, 3)
				api.set(owner, 0, 16, u64(data), true, 2)
				got := api.get(owner, 0, 16, false)
				mutable := C.CFDataGetMutableBytePtr(voidptr(got))
				unsafe { *mutable = 9 }
				assert got != u64(data) && unsafe { *C.CFDataGetBytePtr(data) == 42 }
				first := api.create(api.root)
				second := api.create(api.root)
				array := C.CFArrayCreateMutable(unsafe { nil }, 0, C.dlsym(lib, c'kCFTypeArrayCallBacks'))
				C.CFArrayAppendValue(array, voidptr(first))
				api.set(owner, 0, 16, u64(array), true, 2)
				C.CFArrayAppendValue(voidptr(api.get(owner, 0, 16, false)), voidptr(second))
				assert C.CFArrayGetCount(array) == 1
				dictionary := C.CFDictionaryCreateMutable(unsafe { nil }, 0, C.dlsym(lib, c'kCFTypeDictionaryKeyCallBacks'), C.dlsym(lib, c'kCFTypeDictionaryValueCallBacks'))
				C.CFDictionarySetValue(dictionary, voidptr(first), voidptr(first))
				api.set(owner, 0, 16, u64(dictionary), true, 2)
				C.CFDictionarySetValue(voidptr(api.get(owner, 0, 16, false)), voidptr(first), voidptr(second))
				assert u64(C.CFDictionaryGetValue(dictionary, voidptr(first))) == first
				for item in [u64(data), u64(array), u64(dictionary), first, second, owner]! { api.release(item) }
			}
			return
		}
	}
	for _ in 0 .. 100 {
		owner := property_owner(api)
		mut bytes := [u8(42), 43, 44]!
		data := cf_data_create(0, u64(unsafe { &bytes[0] }), 3)
		api.set(owner, 0, 16, data, true, 2)
		got := api.get(owner, 0, 16, false)
		assert read64(got) == ios_runtime.names['NSMutableData']
		unsafe { *(&u8(data_pointer(got))) = 9 }
		assert got != data && unsafe { *(&u8(data_pointer(data))) == 42 }
		first := api.create(api.root)
		second := api.create(api.root)
		array := objc_allocate(ios_runtime.names['NSMutableArray'])
		mut header := obj_header(array)
		array_append(mut header, first)
		api.set(owner, 0, 16, array, true, 2)
		mut copy_header := obj_header(api.get(owner, 0, 16, false))
		array_append(mut copy_header, second)
		assert cf_array_count(array) == 1 && read64(api.get(owner, 0, 16, false)) == ios_runtime.names['NSMutableArray']
		dictionary := cf_dictionary_mutable(0, 0, cf_callbacks_constant('_kCFTypeDictionaryKeyCallBacks'), cf_callbacks_constant('_kCFTypeDictionaryValueCallBacks'))
		cf_dictionary_set(dictionary, first, first)
		api.set(owner, 0, 16, dictionary, true, 2)
		cf_dictionary_set(api.get(owner, 0, 16, false), first, second)
		assert cf_dictionary_value(dictionary, first) == first
		for item in [data, array, dictionary, first, second, owner]! { api.release(item) }
	}
}

fn property_worker(api PropertyApi, owner u64) {
	for _ in 0 .. 500 {
		pool := api.push()
		value := api.create(api.root)
		api.setters[1](owner, 0, value, 16)
		api.release(value)
		got := api.get(owner, 0, 16, true)
		api.set(owner, 0, 16, 0, true, 0)
		if got != 0 { assert api.refs(got) >= 1 }
		api.pop(pool)
	}
}

fn property_block_invoke(block u64) {
	assert block != 0
	C.ios_ref_change(unsafe { &property_block_calls }, 1)
}
fn property_test_blocks(api PropertyApi) {
	mut isa := u64(0)
	$if macos {
		if api.native {
			lib := C.dlopen('/usr/lib/libSystem.B.dylib'.str, C.RTLD_NOW)
			isa = u64(C.dlsym(lib, c'_NSConcreteStackBlock'))
		}
	}
	if !api.native { isa = block_isa(0) }
	mut descriptor := [u64(0), 32]!
	mut stack := [isa, u64(0), u64(unsafe { voidptr(property_block_invoke) }), u64(unsafe { &descriptor[0] })]!
	property_block_calls = 0
	for index in [2, 3]! {
		for _ in 0 .. 100 {
			pool := api.push()
			owner := property_owner(api)
			api.setters[index](owner, 0, u64(unsafe { &stack[0] }), 16)
			got := api.get(owner, 0, 16, index == 3)
			assert got != u64(unsafe { &stack[0] })
			if index == 3 { api.setters[index](owner, 0, 0, 16) }
			unsafe { BlockVoid(voidptr(read64(got + 16)))(got) }
			api.release(owner); api.pop(pool)
		}
	}
	assert property_block_calls == 200
}

fn property_classes(native bool) (u64, u64, u64) {
	mut root := u64(0)
	mut owner := u64(0)
	mut probe := u64(0)
	$if macos {
		if native {
			root = u64(C.objc_getClass(c'NSObject'))
			owner = u64(C.objc_allocateClassPair(voidptr(root), c'VinixPropertyOwner', 0))
			probe = u64(C.objc_allocateClassPair(voidptr(root), c'VinixPropertyProbe', 0))
			for name in ['guard', 'value', 'tail']! { assert C.class_addIvar(voidptr(owner), name.str, 8, 3, c'Q') }
			assert C.class_addIvar(voidptr(probe), c'kind', 8, 3, c'Q')
			assert C.class_addMethod(voidptr(owner), C.sel_registerName(c'dealloc'), unsafe { voidptr(property_owner_dealloc) }, c'v16@0:8')
			assert C.class_addMethod(voidptr(probe), C.sel_registerName(c'dealloc'), unsafe { voidptr(property_probe_dealloc) }, c'v16@0:8')
			assert C.class_addMethod(voidptr(probe), C.sel_registerName(c'copyWithZone:'), unsafe { voidptr(property_copy) }, c'@24@0:8^v16')
			assert C.class_addMethod(voidptr(probe), C.sel_registerName(c'mutableCopyWithZone:'), unsafe { voidptr(property_mutable_copy) }, c'@24@0:8^v16')
			for name in ['copy', 'mutableCopy']! { assert C.class_addMethod(voidptr(probe), C.sel_registerName(name.str), unsafe { voidptr(property_direct_copy) }, c'@16@0:8') }
			C.objc_registerClassPair(voidptr(owner)); C.objc_registerClassPair(voidptr(probe))
			return root, owner, probe
		}
	}
	root = ios_runtime.names['NSObject']
	owner = objc_allocate_class(root, c'VinixPropertyOwner', 0)
	probe = objc_allocate_class(root, c'VinixPropertyProbe', 0)
	for name in ['guard', 'value', 'tail']! { assert objc_add_ivar(owner, name.str, 8, 3, c'Q') }
	assert objc_add_ivar(probe, c'kind', 8, 3, c'Q')
	assert objc_add_method(owner, objc_selector(c'dealloc'), u64(unsafe { voidptr(property_owner_dealloc) }), c'v16@0:8')
	assert objc_add_method(probe, objc_selector(c'dealloc'), u64(unsafe { voidptr(property_probe_dealloc) }), c'v16@0:8')
	assert objc_add_method(probe, objc_selector(c'copyWithZone:'), u64(unsafe { voidptr(property_copy) }), c'@24@0:8^v16')
	assert objc_add_method(probe, objc_selector(c'mutableCopyWithZone:'), u64(unsafe { voidptr(property_mutable_copy) }), c'@24@0:8^v16')
	for name in ['copy', 'mutableCopy']! { assert objc_add_method(probe, objc_selector(name.str), u64(unsafe { voidptr(property_direct_copy) }), c'@16@0:8') }
	objc_register_class(owner); objc_register_class(probe)
	return root, owner, probe
}
fn property_run(api PropertyApi) {
	if property_api != unsafe { nil } { C.free(property_api) }
	property_api = &PropertyApi{...api}
	property_direct_calls = 0
	property_test_ownership(api)
	property_test_mutable(api)
	property_test_blocks(api)
	owner := property_owner(api)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn property_worker(api, owner) }
	workers.wait()
	property_guards(owner); api.release(owner)
	assert property_direct_calls == 0 // Runtime setters send the zone methods directly.
}
fn test_properties_match_native_runtime() {
	$if macos {
		root, owner, probe := property_classes(true)
		lib := C.dlopen('/usr/lib/libobjc.A.dylib'.str, C.RTLD_NOW)
		mut setters := [4]PropertySpecialized{}
		for i, name in ['objc_setProperty_nonatomic', 'objc_setProperty_atomic', 'objc_setProperty_nonatomic_copy', 'objc_setProperty_atomic_copy']! { setters[i] = unsafe { PropertySpecialized(C.dlsym(lib, name.str)) } }
		property_run(PropertyApi{
			native: true, root: root, owner: owner, probe: probe, setters: setters
			get: unsafe { PropertyGet(C.dlsym(lib, c'objc_getProperty')) }
			set: unsafe { PropertySet(C.dlsym(lib, c'objc_setProperty')) }
			release: unsafe { PropertyRelease(C.dlsym(lib, c'objc_release')) }
			push: unsafe { PropertyPush(C.dlsym(lib, c'objc_autoreleasePoolPush')) }
			pop: unsafe { PropertyPop(C.dlsym(lib, c'objc_autoreleasePoolPop')) }
		})
		println('IOS-PROPERTY-NATIVE: legacy and specialized setters, guarded/signed offsets, isa, copyWithZone/mutableCopyWithZone, nil copies, autoreleased getters, reentrant dealloc and eight shared-slot workers')
	}
	for _ in 0 .. 2 {
		objc_start()
		root, owner, probe := property_classes(false)
		mut setters := [4]PropertySpecialized{}
		for i, name in ['_objc_setProperty_nonatomic', '_objc_setProperty_atomic', '_objc_setProperty_nonatomic_copy', '_objc_setProperty_atomic_copy']! { setters[i] = unsafe { PropertySpecialized(voidptr(runtime_symbol('/usr/lib/libobjc.A.dylib', name) or { panic(err) })) } }
		property_run(PropertyApi{
			root: root, owner: owner, probe: probe, setters: setters
			get: unsafe { PropertyGet(voidptr(runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_getProperty') or { panic(err) })) }
			set: unsafe { PropertySet(voidptr(runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_setProperty') or { panic(err) })) }
			release: objc_release, push: objc_pool_push, pop: objc_pool_pop
		})
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.associations.len == 0
		owner_info := ios_runtime.classes[owner] or { panic('missing property owner class') }
		probe_info := ios_runtime.classes[probe] or { panic('missing property probe class') }
		assert owner_info.instances == 0 && probe_info.instances == 0 && ios_runtime.block_refs.len == 0
		objc_dispose_class(owner); objc_dispose_class(probe)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	C.free(property_api); property_api = unsafe { nil }
	println('IOS-PROPERTY: native ownership and zone-copy contract, real mutable snapshots, reentrant dealloc without locked callbacks, eight shared-slot workers and two empty runtime teardowns')
}
