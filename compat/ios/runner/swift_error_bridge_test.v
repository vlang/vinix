// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFDictionary.h>
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFErrorCreate(voidptr, voidptr, i64, voidptr) voidptr
fn C.CFErrorGetCode(voidptr) i64
fn C.CFErrorGetDomain(voidptr) voidptr
fn C.CFErrorCopyUserInfo(voidptr) voidptr
fn C.CFDictionaryCreateMutable(voidptr, i64, voidptr, voidptr) voidptr
fn C.CFDictionarySetValue(voidptr, voidptr, voidptr)
fn C.CFDictionaryGetCount(voidptr) i64
fn C.CFDictionaryGetValue(voidptr, voidptr) voidptr
fn C.CFEqual(voidptr, voidptr) bool
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.objc_disposeClassPair(voidptr)
fn C.sel_registerName(&char) voidptr

type ErrorBridgeCall = fn (u64) u64
type ErrorBridgeProbe = fn (u64, u64, &u64)
type ErrorBridgeSend = fn (u64, u64) u64
type ErrorBridgeInit = fn (u64, u64, u64, i64, u64) u64
type ErrorBridgePoolPush = fn () u64
type ErrorBridgePoolPop = fn (u64)
struct ErrorBridgeApi {
	native bool
	entry u64
	probe ErrorBridgeProbe
	send u64
	subclass u64
	pool_push u64
	pool_pop u64
}
fn (api ErrorBridgeApi) text(text string) u64 {
	$if macos { if api.native { return u64(C.CFStringCreateWithBytes(unsafe { nil },text.str,i64(text.len),0x08000100,false)) } }
	return owned_string(text)
}
fn (api ErrorBridgeApi) keep(owner u64) u64 {
	$if macos { if api.native { return u64(C.CFRetain(unsafe { voidptr(owner) })) } }
	return objc_retain(owner)
}
fn (api ErrorBridgeApi) drop(owner u64) {
	$if macos { if api.native { if owner != 0 { C.CFRelease(unsafe { voidptr(owner) }) };return } }
	objc_release(owner)
}
fn (api ErrorBridgeApi) refs(owner u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(unsafe { voidptr(owner) }) } }
	return obj_header(owner).refs
}
fn (api ErrorBridgeApi) domain(owner u64) u64 {
	$if macos { if api.native {
		// NSError's property getter may retain/autorelease its borrowed result.
		// Drain that temporary before measuring the error's field ownership.
		push := unsafe { ErrorBridgePoolPush(voidptr(api.pool_push)) }; pop := unsafe { ErrorBridgePoolPop(voidptr(api.pool_pop)) }
		pool := push(); result := u64(C.CFErrorGetDomain(unsafe { voidptr(owner) })); pop(pool); return result
	} }
	return if read64(owner) == cf_error_type_id() { cf_error_domain(owner) } else { unsafe { (&AbiNSError(owner)).domain } }
}
fn (api ErrorBridgeApi) code(owner u64) i64 {
	$if macos { if api.native { return C.CFErrorGetCode(unsafe { voidptr(owner) }) } }
	return if read64(owner) == cf_error_type_id() { cf_error_code(owner) } else { unsafe { (&AbiNSError(owner)).code } }
}
fn (api ErrorBridgeApi) info(owner u64) u64 {
	$if macos { if api.native {
		push := unsafe { ErrorBridgePoolPush(voidptr(api.pool_push)) }; pop := unsafe { ErrorBridgePoolPop(voidptr(api.pool_pop)) }
		pool := push(); result := u64(C.CFErrorCopyUserInfo(unsafe { voidptr(owner) })); pop(pool); return result
	} }
	if read64(owner) == cf_error_type_id() { return swift_cf_error_info(owner) }
	return objc_retain(unsafe { (&AbiNSError(owner)).user_info })
}
fn (api ErrorBridgeApi) make(kind int, code i64, with_info bool) u64 {
	domain := api.text('Fortnite error bridge ownership domain é 🎮'); mut info := u64(0)
	if with_info {
		key := api.text('VinixErrorBridgeKey'); item := api.text('retained bridge userInfo value')
		$if macos { if api.native {
			info = u64(C.CFDictionaryCreateMutable(unsafe { nil },0,unsafe { &C.kCFTypeDictionaryKeyCallBacks },unsafe { &C.kCFTypeDictionaryValueCallBacks }))
			C.CFDictionarySetValue(unsafe { voidptr(info) },unsafe { voidptr(key) },unsafe { voidptr(item) })
		} }
		if !api.native {
			info = cf_dictionary_mutable(0,0,cf_callbacks_constant('_kCFTypeDictionaryKeyCallBacks'),cf_callbacks_constant('_kCFTypeDictionaryValueCallBacks'))
			cf_dictionary_set(info,key,item); objc_set_class(info,ios_runtime.names['NSDictionary'])
		}
		api.drop(key); api.drop(item)
	}
	mut owner := u64(0)
	$if macos { if api.native {
		if kind == 0 { owner = u64(C.CFErrorCreate(unsafe { nil },unsafe { voidptr(domain) },code,unsafe { voidptr(info) })) }
		else {
			cls := if kind == 2 { api.subclass } else { u64(C.objc_getClass(c'NSError')) }
			send := unsafe { ErrorBridgeSend(voidptr(api.send)) }; initialize := unsafe { ErrorBridgeInit(voidptr(api.send)) }
			owner = initialize(send(cls,u64(C.sel_registerName(c'alloc'))),u64(C.sel_registerName(c'initWithDomain:code:userInfo:')),domain,code,info)
		}
	} }
	if !api.native {
		if kind == 0 { owner = objc_allocate(cf_error_type_id()); mut header := obj_header(owner); header.fields[0] = objc_retain(domain); header.fields[1] = objc_retain(info); header.number = code }
		else { owner = ns_error_create(domain,code,info); if kind == 2 { objc_set_class(owner,api.subclass) } }
	}
	api.drop(domain); api.drop(info); assert owner != 0; return owner
}
fn error_bridge_fields(api ErrorBridgeApi, owner u64, code i64, with_info bool) {
	assert api.code(owner) == code
	info := api.info(owner)
	$if macos { if api.native { assert C.CFDictionaryGetCount(unsafe { voidptr(info) }) == if with_info { i64(1) } else { i64(0) } } }
	if !api.native { assert obj_header(info).keys.len == if with_info { 1 } else { 0 } }
	if with_info {
		key := api.text('VinixErrorBridgeKey'); expected := api.text('retained bridge userInfo value')
		$if macos { if api.native {
			item := C.CFDictionaryGetValue(unsafe { voidptr(info) },unsafe { voidptr(key) })
			assert item != unsafe { nil } && C.CFEqual(item,unsafe { voidptr(expected) })
		} }
		if !api.native { assert string_text(cf_dictionary_value(info,key)) == string_text(expected) }
		api.drop(key); api.drop(expected)
	}
	api.drop(info)
}
fn error_bridge_case(api ErrorBridgeApi, kind int, code i64, with_info bool) {
	owner := api.make(kind,code,with_info); domain := api.domain(owner); api.keep(domain)
	before := api.refs(owner); domain_before := api.refs(domain)
	cls := read64(owner)
	mut registers := [3]u64{}
	api.probe(owner,api.entry,unsafe { &registers[0] })
	assert registers[0] == owner && registers[1] == 0x5020 && registers[2] == 0x5021
	assert api.refs(owner) == before && api.refs(domain) == domain_before && read64(owner) == cls
	assert api.domain(owner) == domain
	error_bridge_fields(api,owner,code,with_info)
	// The first call transferred the incoming reference to its result. Every
	// subsequent call consumes a separate retain, released through ObjC ARC.
	entry := unsafe { ErrorBridgeCall(voidptr(api.entry)) }
	for _ in 0 .. 16 { assert entry(api.keep(owner)) == owner; api.drop(owner) }
	assert api.refs(owner) == before
	api.drop(registers[0])
	assert api.refs(domain) == domain_before - 1
	api.drop(domain)
}
fn error_bridge_worker(api ErrorBridgeApi, owner u64) {
	entry := unsafe { ErrorBridgeCall(voidptr(api.entry)) }
	for _ in 0 .. 256 { assert entry(api.keep(owner)) == owner; api.drop(owner) }
}
fn error_bridge_run(api ErrorBridgeApi) {
	for kind in 0 .. 3 { for code in [i64(0),-7,0x7fffffff,i64(9223372036854775807),-i64(9223372036854775807)-1]! {
		for with_info in [false,true]! { error_bridge_case(api,kind,code,with_info) }
	} }
	owner := api.make(2,-7,true); before := api.refs(owner)
	mut workers := []thread{cap: 8}; for _ in 0 .. 8 { workers << spawn error_bridge_worker(api,owner) }; workers.wait()
	assert api.refs(owner) == before; error_bridge_fields(api,owner,-7,true); api.drop(owner)
}
fn error_bridge_unreachable_heap_destroy(_owner u64, _metadata u64) {
	assert false, 'uninitialized private heap test owner must bypass destruction'
}
fn error_bridge_rejections(guard u64) {
	for owner in [u64(0),1,guard,guard+8,0x8000000000000010]! { if _ := swift_error_bridge_checked(owner) { assert false } }
	owner := objc_allocate(ios_runtime.names['NSObject'])
	if _ := swift_error_bridge_checked(owner) { assert false }
	objc_release(owner)
	if _ := swift_error_bridge_checked(owner) { assert false }
	owner2 := objc_allocate(cf_error_type_id()); header := obj_header(owner2)
	for phase in 0 .. 4 {
		unsafe { mut state := header; state.releasing = phase == 0; state.destroying = phase == 1; state.destroyed = phase == 2; state.refs = if phase == 3 { i64(0) } else { i64(1) } }
		if _ := swift_error_bridge_checked(owner2) { assert false }
	}
	unsafe { mut state := header; state.releasing = false; state.destroying = false; state.destroyed = false; state.refs = 1 }
	original := read64(owner2); unsafe { *(&u64(owner2)) = 0 }
	if _ := swift_error_bridge_checked(owner2) { assert false }
	unsafe { *(&u64(owner2)) = original }; objc_release(owner2)
	mut metadata := [u64(unsafe { voidptr(error_bridge_unreachable_heap_destroy) }),u64(0),u64(0x400),u64(0)]!
	heap := swift_heap_allocate(u64(unsafe { &metadata[2] }),16,7)
	if _ := swift_error_bridge_checked(heap) { assert false }
	assert read64(heap + 8) == 3 && heap in ios_runtime.swift_heap
	swift_heap_deallocate_uninitialized(heap,16,7)
	ios_runtime.swift_concurrency_retired = true
	if _ := swift_error_bridge_checked(guard) { assert false }
	ios_runtime.swift_concurrency_retired = false
}
struct ErrorBridgeDeinit {
	weak &u64
mut:
	calls int
}
fn error_bridge_dealloc(owner u64, _selector &char) {
	header := obj_header(owner); mut state := unsafe { &ErrorBridgeDeinit(header.tag) }
	assert state.calls == 0 && unsafe { *state.weak } == 0
	if _ := swift_error_bridge_checked(owner) { assert false }
	state.calls++
	api := ErrorBridgeApi{entry: u64(unsafe { voidptr(swift_error_bridge) })}
	worker := spawn error_bridge_worker(api,header.fields[0]); worker.wait()
}
fn error_bridge_reentrant(api ErrorBridgeApi) {
	objc_replace_method(api.subclass,objc_selector(c'dealloc'),u64(unsafe { voidptr(error_bridge_dealloc) }),c'v16@0:8')
	owner := api.make(2,42,true); child := api.make(0,13,false)
	mut weak := u64(0); mut state := ErrorBridgeDeinit{weak: unsafe { &weak }}
	mut header := obj_header(owner); header.tag = i64(unsafe { &state }); header.fields[0] = objc_retain(child)
	objc_store_weak(unsafe { &weak },owner)
	assert swift_error_bridge(owner) == owner && weak == owner && state.calls == 0
	api.drop(owner)
	assert state.calls == 1 && weak == 0 && api.refs(child) == 1
	objc_destroy_weak(unsafe { &weak }); api.drop(child)
}
fn test_swift_error_bridge() {
	page := usize(C.getpagesize()); code := u64(C.mmap(unsafe { nil },page * 2,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert code != u64(-1); guard := code + u64(page)
	for i, word in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0203f3,0xaa0103f0,0xd28a0414,0xd28a0435,0xd63f0200,0xa9005260,0xf9000a75,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]! { write32(code+u64(i)*4,word) }
	C.__builtin___clear_cache(unsafe { voidptr(code) },unsafe { voidptr(code+56) })
	assert C.mprotect(unsafe { voidptr(code) },page,C.PROT_READ | C.PROT_EXEC) == 0
	assert C.mprotect(unsafe { voidptr(guard) },page,C.PROT_NONE) == 0
	probe := unsafe { ErrorBridgeProbe(voidptr(code)) }
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW); lib := C.dlopen(c'/usr/lib/libobjc.A.dylib',C.RTLD_NOW)
		subclass := u64(C.objc_allocateClassPair(C.objc_getClass(c'NSError'),c'VinixNativeErrorBridgeSubclass',0)); assert subclass != 0; C.objc_registerClassPair(unsafe { voidptr(subclass) })
		api := ErrorBridgeApi{native: true,entry: u64(C.dlsym(core,c'_swift_stdlib_bridgeErrorToNSError')),probe: probe,send: u64(C.dlsym(lib,c'objc_msgSend')),subclass: subclass,
			pool_push: u64(C.dlsym(lib,c'objc_autoreleasePoolPush')),pool_pop: u64(C.dlsym(lib,c'objc_autoreleasePoolPop'))}
		assert api.entry != 0 && api.send != 0 && api.pool_push != 0 && api.pool_pop != 0; error_bridge_run(api); C.objc_disposeClassPair(unsafe { voidptr(subclass) })
		println('IOS-ERROR-BRIDGE-NATIVE: consuming identity transfer for CFError/NSError/ObjC subclass, 30 field/ownership cases, INT64 extrema, exact final domain disposal, x20/x21 and eight shared-owner workers')
	}
	for _ in 0 .. 2 {
		if _ := swift_error_bridge_checked(guard) { assert false }
		objc_start(); library := '/usr/lib/swift/libswiftCore.dylib'
		for name in ['_swift_stdlib_bridgeErrorToNSError','___swift_stdlib_bridgeErrorToNSError']! { if _ := runtime_symbol(library,name) { assert false } }
		if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib','__swift_stdlib_bridgeErrorToNSError') { assert false }
		subclass := objc_allocate_class(ios_runtime.names['NSError'],c'VinixErrorBridgeSubclass',0); objc_register_class(subclass)
		api := ErrorBridgeApi{entry: runtime_symbol(library,'__swift_stdlib_bridgeErrorToNSError') or { panic(err) },probe: probe,subclass: subclass}
		error_bridge_run(api); error_bridge_rejections(guard); error_bridge_reentrant(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_error_arena == 0
		objc_stop(); assert ios_runtime.live == 0
		if _ := swift_error_bridge_checked(guard) { assert false }
	}
	assert C.munmap(unsafe { voidptr(code) },page * 2) == 0
	println('IOS-ERROR-BRIDGE: exact Core-only ordinary C export, consuming CFError/NSError/subclass identity, intact fields and ownership, protected unknown/stale/tearing-down/mismatched/private heap owners reject before reads, eight workers, weak zeroing and unlocked reentrant destruction, two drained lifetimes without Swift arena allocation')
}
