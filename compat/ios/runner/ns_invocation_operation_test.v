// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.objc_storeWeak(&u64, voidptr) voidptr

type InvocationOperationSend = fn (u64, u64, u64, u64, u64) u64
struct InvocationOperationApi { native bool send u64 cls u64 base u64 root u64 strings u64 mutable_strings u64 }
__global invocation_operation_api = InvocationOperationApi{}
__global invocation_operation_receiver = u64(0)
__global invocation_operation_calls = 0
__global invocation_operation_executing = false
fn (api InvocationOperationApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api InvocationOperationApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { InvocationOperationSend(voidptr(api.send))(object, api.selector(name), a, b, c) }
}
fn (api InvocationOperationApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api InvocationOperationApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api InvocationOperationApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api InvocationOperationApi) destroy_weak(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api InvocationOperationApi) new_target_class() u64 {
	mut cls := u64(0)
	$if macos { if api.native { cls = u64(C.objc_allocateClassPair(unsafe { voidptr(api.root) }, c'VinixInvocationOperationTarget', 0)) } }
	if !api.native { cls = objc_allocate_class(api.root, c'VinixInvocationOperationTarget', 0) }
	assert cls != 0
	for entry in [
		[u64(c'objectZero'), u64(unsafe { voidptr(invocation_operation_object_zero) }), u64(c'@16@0:8')]!,
		[u64(c'objectOne:'), u64(unsafe { voidptr(invocation_operation_object_one) }), u64(c'@24@0:8@16')]!,
		[u64(c'voidZero'), u64(unsafe { voidptr(invocation_operation_void_zero) }), u64(c'v16@0:8')]!,
		[u64(c'voidOne:'), u64(unsafe { voidptr(invocation_operation_void_one) }), u64(c'v24@0:8@16')]!,
	]! {
		$if macos { if api.native { assert C.class_addMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.selector(&char(entry[0]))) }, unsafe { voidptr(entry[1]) }, unsafe { &char(entry[2]) }) } }
		if !api.native { assert objc_add_method(cls, entry[0], entry[1], unsafe { &char(entry[2]) }) }
	}
	$if macos { if api.native { C.objc_registerClassPair(unsafe { voidptr(cls) }) } }
	if !api.native { objc_register_class(cls) }
	return cls
}
fn invocation_operation_observe() {
	api := invocation_operation_api
	invocation_operation_calls++
	assert api.message(invocation_operation_receiver, c'isExecuting', 0, 0, 0) == u64(invocation_operation_executing)
	assert api.message(invocation_operation_receiver, c'isFinished', 0, 0, 0) == 0
}
fn invocation_operation_object_zero(object u64, selector &char) u64 { invocation_operation_observe(); return object }
fn invocation_operation_object_one(object u64, selector &char, argument u64) u64 { invocation_operation_observe(); return argument }
fn invocation_operation_void_zero(object u64, selector &char) { invocation_operation_observe() }
fn invocation_operation_void_one(object u64, selector &char, argument u64) { invocation_operation_observe() }
fn invocation_operation_record_zero(object u64, size int) {
	for offset in 8 .. size { assert unsafe { *(&u8(voidptr(object + u64(offset)))) } == 0 }
}
fn invocation_operation_defaults(api InvocationOperationApi, object u64) {
	for name in [c'isCancelled', c'isExecuting', c'isFinished', c'isConcurrent', c'isAsynchronous']! { assert api.message(object, name, 0, 0, 0) == 0 }
	assert api.message(object, c'isReady', 0, 0, 0) == 1 && api.message(object, c'name', 0, 0, 0) == 0
}
fn invocation_operation_initialize(api InvocationOperationApi, target u64, name &char, argument u64) u64 {
	return api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithTarget:selector:object:', target, api.selector(name), argument)
}
fn invocation_operation_shared(api InvocationOperationApi) {
	invocation_operation_api = api
	mut pool := api.pool()
	assert api.message(api.cls, c'new', 0, 0, 0) == 0
	raw := api.message(api.cls, c'alloc', 0, 0, 0); invocation_operation_record_zero(raw, 264); invocation_operation_defaults(api, raw)
	mut raw_weak := u64(0); api.weak(unsafe { &raw_weak }, raw)
	assert api.message(raw, c'init', 0, 0, 0) == 0 && raw_weak == 0; api.destroy_weak(unsafe { &raw_weak })
	base := api.message(api.base, c'alloc', 0, 0, 0); invocation_operation_record_zero(base, 248); invocation_operation_defaults(api, base)
	mutable_name := api.message(api.message(api.mutable_strings, c'alloc', 0, 0, 0), c'initWithUTF8String:', u64(c'copied synchronous operation name 😀'), 0, 0)
	api.message(base, c'setName:', mutable_name, 0, 0)
	stored := api.message(base, c'name', 0, 0, 0); assert stored != 0 && stored != mutable_name
	changed := api.message(api.strings, c'stringWithUTF8String:', u64(c'changed name'), 0, 0)
	api.message(mutable_name, c'setString:', changed, 0, 0); api.message(mutable_name, c'release', 0, 0, 0)
	assert unsafe { (&char(voidptr(api.message(stored, c'UTF8String', 0, 0, 0)))).vstring() } == 'copied synchronous operation name 😀'
	api.message(base, c'cancel', 0, 0, 0); assert api.message(base, c'init', 0, 0, 0) == base
	assert api.message(base, c'isCancelled', 0, 0, 0) == 1 && api.message(base, c'name', 0, 0, 0) == 0
	api.message(base, c'main', 0, 0, 0); assert api.message(base, c'isFinished', 0, 0, 0) == 0
	api.message(base, c'start', 0, 0, 0); api.message(base, c'start', 0, 0, 0)
	assert api.message(base, c'isFinished', 0, 0, 0) == 1 && api.message(base, c'isExecuting', 0, 0, 0) == 0
	api.message(base, c'release', 0, 0, 0)
	target_class := api.new_target_class()
	for name in [c'objectZero', c'objectOne:', c'voidZero', c'voidOne:']! {
		for direct_main in [false, true]! {
			target := api.message(target_class, c'new', 0, 0, 0)
			argument := api.message(api.message(api.strings, c'stringWithUTF8String:', u64(c'invocation retains its owned argument'), 0, 0), c'retain', 0, 0, 0)
			object := invocation_operation_initialize(api, target, name, argument); assert object != 0
			invocation_operation_receiver = object; invocation_operation_calls = 0; invocation_operation_executing = false
			invocation_operation_defaults(api, object); assert api.message(object, c'result', 0, 0, 0) == 0
			mut target_weak := u64(0); mut argument_weak := u64(0)
			api.weak(unsafe { &target_weak }, target); api.weak(unsafe { &argument_weak }, argument)
			api.message(target, c'release', 0, 0, 0); api.message(argument, c'release', 0, 0, 0)
			api.drain(pool); pool = api.pool()
			method_name := unsafe { name.vstring() }
			one := method_name == 'objectOne:' || method_name == 'voidOne:'
			assert target_weak != 0 && (argument_weak != 0) == one
			if direct_main {
				api.message(object, c'cancel', 0, 0, 0)
				api.message(object, c'main', 0, 0, 0); api.message(object, c'main', 0, 0, 0)
				assert invocation_operation_calls == 2 && api.message(object, c'isFinished', 0, 0, 0) == 0 && api.message(object, c'result', 0, 0, 0) == 0
				api.message(object, c'start', 0, 0, 0); assert invocation_operation_calls == 2
			} else {
				invocation_operation_executing = true; api.message(object, c'start', 0, 0, 0)
				assert invocation_operation_calls == 1
				if method_name == 'objectZero' || method_name == 'objectOne:' { assert api.message(object, c'result', 0, 0, 0) == if one { argument } else { target } }
			}
			api.message(object, c'start', 0, 0, 0)
			assert api.message(object, c'isFinished', 0, 0, 0) == 1 && api.message(object, c'isExecuting', 0, 0, 0) == 0
			api.message(object, c'release', 0, 0, 0); api.drain(pool); pool = api.pool()
			assert target_weak == 0 && argument_weak == 0
			api.destroy_weak(unsafe { &target_weak }); api.destroy_weak(unsafe { &argument_weak })
		}
	}
	// The inherited NSObject builtin must execute through the same message path.
	target := api.message(api.root, c'new', 0, 0, 0)
	object := invocation_operation_initialize(api, target, c'self', 0); api.message(object, c'start', 0, 0, 0)
	assert api.message(object, c'result', 0, 0, 0) == target
	api.message(target, c'release', 0, 0, 0); api.message(object, c'release', 0, 0, 0)
	for mode in 0 .. 3 {
		other := api.message(api.root, c'new', 0, 0, 0)
		allocated := api.message(api.cls, c'alloc', 0, 0, 0); mut weak := u64(0); api.weak(unsafe { &weak }, allocated)
		assert api.message(allocated, c'initWithTarget:selector:object:', if mode == 0 { u64(0) } else { other }, if mode == 1 { u64(0) } else { api.selector(c'missingInvocationMethod') }, 0) == 0 && weak == 0
		api.destroy_weak(unsafe { &weak }); api.message(other, c'release', 0, 0, 0)
	}
	// A failed initializer consumes one owner and clears preinitialization name.
	survivor := api.message(api.cls, c'alloc', 0, 0, 0); api.message(survivor, c'retain', 0, 0, 0)
	preinit_name := api.message(api.strings, c'stringWithUTF8String:', u64(c'failed initializer clears name'), 0, 0)
	api.message(survivor, c'setName:', preinit_name, 0, 0); api.message(survivor, c'cancel', 0, 0, 0)
	assert api.message(survivor, c'initWithTarget:selector:object:', 0, api.selector(c'self'), 0) == 0
	assert api.message(survivor, c'name', 0, 0, 0) == 0 && api.message(survivor, c'isCancelled', 0, 0, 0) == 1
	api.message(survivor, c'release', 0, 0, 0)
	nil_target := api.message(target_class, c'new', 0, 0, 0)
	nil_argument := invocation_operation_initialize(api, nil_target, c'objectOne:', 0)
	invocation_operation_receiver = nil_argument; invocation_operation_executing = true
	api.message(nil_argument, c'start', 0, 0, 0); assert api.message(nil_argument, c'result', 0, 0, 0) == 0
	api.message(nil_target, c'release', 0, 0, 0); api.message(nil_argument, c'release', 0, 0, 0)
	api.drain(pool); invocation_operation_receiver = 0
}
fn invocation_operation_encodings(api InvocationOperationApi) {
	for cls in [api.base, api.cls]! {
		for name, expected in {'init': '@16@0:8', 'main': 'v16@0:8', 'start': 'v16@0:8', 'cancel': 'v16@0:8', 'name': '@16@0:8', 'setName:': 'v24@0:8@16', 'isCancelled': 'B16@0:8', 'isExecuting': 'B16@0:8', 'isFinished': 'B16@0:8', 'isReady': 'B16@0:8', 'isConcurrent': 'B16@0:8', 'isAsynchronous': 'B16@0:8'} {
			mut actual := ''
			$if macos { if api.native { method := C.class_getInstanceMethod(unsafe { voidptr(cls) }, C.sel_registerName(name.str)); assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() } } }
			if !api.native { method := objc_instance_method(cls, u64(name.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
			assert actual == expected, name + ': ' + actual
		}
	}
	for name, expected in {'initWithTarget:selector:object:': '@40@0:8@16:24@32', 'result': '@16@0:8'} {
		mut actual := ''
		$if macos { if api.native { method := C.class_getInstanceMethod(unsafe { voidptr(api.cls) }, C.sel_registerName(name.str)); actual = unsafe { C.method_getTypeEncoding(method).vstring() } } }
		if !api.native { actual = ctext(u64(objc_method_types(objc_instance_method(api.cls, u64(name.str))))) }
		assert actual == expected
	}
}
fn test_invocation_operation_native() {
	$if macos {
		api := InvocationOperationApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSInvocationOperation')), base: u64(C.objc_getClass(c'NSOperation')), root: u64(C.objc_getClass(c'NSObject')), strings: u64(C.objc_getClass(c'NSString')), mutable_strings: u64(C.objc_getClass(c'NSMutableString'))}
		assert C.class_getInstanceSize(unsafe { voidptr(api.cls) }) == 264 && C.class_getSuperclass(unsafe { voidptr(api.cls) }) == unsafe { voidptr(api.base) }
		assert C.class_getInstanceSize(unsafe { voidptr(api.base) }) == 248 && C.class_getSuperclass(unsafe { voidptr(api.base) }) == unsafe { voidptr(api.root) }
		invocation_operation_encodings(api); invocation_operation_shared(api)
		println('IOS-INVOCATION-OPERATION-NATIVE:248/264-byte records, nil default construction, typed native/builtin calls, zero/one object args, repeated main, synchronous start, cancellation, borrowed result and copied names')
	}
}

// Runtime-only ownership and invalid-input fixtures.
__global invocation_operation_callback_weak = u64(0)
__global invocation_operation_constructor_fail = false
__global invocation_operation_callback_mode = ''
fn invocation_operation_runtime_api() InvocationOperationApi {
	return InvocationOperationApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), cls: ios_runtime.names['NSInvocationOperation'], base: ios_runtime.names['NSOperation'], root: ios_runtime.names['NSObject'], strings: ios_runtime.names['NSString'], mutable_strings: ios_runtime.names['NSMutableString']}
}
fn invocation_operation_drop_owner() {
	api := invocation_operation_api; pool := api.pool()
	assert api.message(invocation_operation_receiver, c'isReady', 0, 0, 0) == 1
	other := objc_new(api.root); objc_release(other)
	objc_release(invocation_operation_receiver); api.drain(pool)
}
fn invocation_operation_releasing_target(object u64, selector &char, argument u64) u64 {
	invocation_operation_observe()
	worker := spawn invocation_operation_drop_owner(); worker.wait()
	return argument
}
fn invocation_operation_property_copy(object u64, selector &char) u64 {
	worker := spawn invocation_operation_drop_owner(); worker.wait()
	result := owned_string(string_text(object))
	objc_store_weak(unsafe { &invocation_operation_callback_weak }, result)
	return result
}
fn invocation_operation_constructor(object u64, selector &char) u64 {
	if !invocation_operation_constructor_fail { return object }
	api := invocation_operation_api
	target := objc_new(api.root)
	assert api.message(object, c'initWithTarget:selector:object:', target, u64(c'self'), 0) == object
	objc_store_weak(unsafe { &invocation_operation_callback_weak }, target); objc_release(target)
	return 0
}
fn invocation_operation_runtime_callbacks(api InvocationOperationApi) {
	invocation_operation_api = api; pool := api.pool()
	cls := objc_allocate_class(api.root, c'VinixReleasingInvocationTarget', 0)
	assert objc_add_method(cls, u64(c'run:'), u64(unsafe { voidptr(invocation_operation_releasing_target) }), c'@24@0:8@16'); objc_register_class(cls)
	target := objc_new(cls); argument := owned_string('argument survives releasing operation callback')
	invocation_operation_receiver = invocation_operation_initialize(api, target, c'run:', argument)
	mut receiver_weak := u64(0); mut target_weak := u64(0); mut argument_weak := u64(0)
	api.weak(unsafe { &receiver_weak }, invocation_operation_receiver); api.weak(unsafe { &target_weak }, target); api.weak(unsafe { &argument_weak }, argument)
	objc_release(target); objc_release(argument)
	invocation_operation_calls = 0; invocation_operation_executing = true
	// The joined worker drops the caller's final owner during the application IMP.
	api.message(invocation_operation_receiver, c'start', 0, 0, 0)
	assert invocation_operation_calls == 1 && receiver_weak == 0 && target_weak == 0 && argument_weak == 0
	api.destroy_weak(unsafe { &receiver_weak }); api.destroy_weak(unsafe { &target_weak }); api.destroy_weak(unsafe { &argument_weak })
	property_class := objc_allocate_class(api.strings, c'VinixInvocationCopiedName', 0)
	assert objc_add_method(property_class, u64(c'copy'), u64(unsafe { voidptr(invocation_operation_property_copy) }), c'@16@0:8'); objc_register_class(property_class)
	property := owned_string('copied name drops the last operation owner'); assert objc_set_class(property, property_class) == api.strings
	invocation_operation_receiver = objc_new(api.base); api.weak(unsafe { &receiver_weak }, invocation_operation_receiver)
	api.message(invocation_operation_receiver, c'setName:', property, 0, 0)
	assert receiver_weak == 0 && invocation_operation_callback_weak == 0
	api.destroy_weak(unsafe { &receiver_weak }); api.destroy_weak(unsafe { &invocation_operation_callback_weak }); objc_release(property)
	assert objc_add_method(api.cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(invocation_operation_constructor) }), c'@16@0:8')
	invocation_operation_constructor_fail = true
	assert objc_allocate(api.cls) == 0 && invocation_operation_callback_weak == 0
	api.destroy_weak(unsafe { &invocation_operation_callback_weak })
	mut storage := [33]u64{}
	assert objc_construct_instance(api.cls, u64(unsafe { &storage[0] })) == 0 && invocation_operation_callback_weak == 0
	api.destroy_weak(unsafe { &invocation_operation_callback_weak })
	assert storage[0] == api.cls; invocation_operation_record_zero(u64(unsafe { &storage[0] }), 264)
	invocation_operation_constructor_fail = false; invocation_operation_receiver = 0; api.drain(pool)
}
fn test_invocation_operation_runtime() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!; api := invocation_operation_runtime_api()
		library := '/System/Library/Frameworks/Foundation.framework/Foundation'
		for cls in [api.base, api.cls]! {
			name := if cls == api.base { 'NSOperation' } else { 'NSInvocationOperation' }
			assert runtime_symbol(library, '_OBJC_CLASS_$_' + name)! == cls && runtime_symbol(library, '_OBJC_METACLASS_$_' + name)! == read64(cls)
		}
		assert objc_class_size(api.base) == 248 && objc_class_parent(api.base) == api.root && ios_runtime.classes[api.base].ivars.len == 1
		assert objc_class_size(api.cls) == 264 && objc_class_parent(api.cls) == api.base && ios_runtime.classes[api.cls].ivars.len == 2
		for entry in [[api.base, u64(c'_iop'), u64(8)]!, [api.cls, u64(c'_inv'), u64(248)]!, [api.cls, u64(c'_exception'), u64(256)]!]! {
			ivar := objc_find_ivar(entry[0], unsafe { &char(entry[1]) }); assert ivar != 0 && objc_ivar_offset(ivar) == entry[2]
		}
		assert ctext(u64(objc_ivar_types(objc_find_ivar(api.cls, c'_inv')))) == '@"NSInvocation"'
		assert ctext(u64(objc_ivar_types(objc_find_ivar(api.cls, c'_exception')))) == '@"NSException"'
		invocation_operation_encodings(api); invocation_operation_shared(api)
		assert ios_runtime.live == 0
		invocation_operation_runtime_callbacks(api); assert ios_runtime.live == 0
		pool := api.pool()
		for cls in [api.base, api.cls]! {
			mut guarded := [35]u64{}; size := if cls == api.base { 248 } else { 264 }; end := size / 8 + 1
			guarded[0] = 0x1122334455667788; guarded[end] = 0x8877665544332211
			object := objc_construct_instance(cls, u64(unsafe { &guarded[1] })); assert object != 0
			if cls == api.base { assert api.message(object, c'init', 0, 0, 0) == object }
			else { target := objc_new(api.root); assert api.message(object, c'initWithTarget:selector:object:', target, u64(c'self'), 0) == object; objc_release(target) }
			name := owned_string('caller-owned synchronous operation storage'); api.message(object, c'setName:', name, 0, 0); objc_release(name)
			mut weak := u64(0); api.weak(unsafe { &weak }, obj_header(object).operation.name)
			assert objc_destruct_instance(object) == object && weak == 0; api.destroy_weak(unsafe { &weak })
			invocation_operation_record_zero(object, size)
			assert read64(object) == cls && guarded[0] == 0x1122334455667788 && guarded[end] == 0x8877665544332211
			for _ in 0 .. 32 {
				target := objc_new(api.root)
				replaced := if cls == api.base { objc_new(cls) } else { invocation_operation_initialize(api, target, c'self', 0) }
				objc_release(target)
				owned := owned_string('operation isa replacement retains construction cleanup'); api.message(replaced, c'setName:', owned, 0, 0); objc_release(owned)
				assert objc_set_class(replaced, api.root) == cls; objc_release(replaced)
			}
		}
		api.drain(pool); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		last := objc_autorelease(objc_new(api.base)); name := owned_string('operation shutdown cleanup'); api.message(last, c'setName:', name, 0, 0); objc_release(name)
		target := objc_new(api.root); objc_autorelease(invocation_operation_initialize(api, target, c'self', 0)); objc_release(target)
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0; system_data_stop()
	}
	println('IOS-INVOCATION-OPERATION: measured metadata and nil constructors, native/builtin calls, callback receiver pins, failed construction, guarded caller storage,64 isa replacements and two drained runtimes')
}
fn invocation_operation_invalid_target(object u64, selector &char) u64 {
	api := invocation_operation_api
	match invocation_operation_callback_mode {
		'nested-main' { api.message(invocation_operation_receiver, c'main', 0, 0, 0) }
		'nested-start' { api.message(invocation_operation_receiver, c'start', 0, 0, 0) }
		'destruct-active' { objc_destruct_instance(invocation_operation_receiver) }
		else {}
	}
	return object
}
fn invocation_operation_invalid_copy(object u64, selector &char) u64 {
	return if invocation_operation_callback_mode == 'nil-name-copy' { u64(0) } else { objc_new(ios_runtime.names['NSObject']) }
}
fn test_invocation_operation_rejections() {
	objc_start(); system_data_start()!; api := invocation_operation_runtime_api(); invocation_operation_api = api
	modes := ['invocation', 'initWithInvocation:', 'dependencies', 'addDependency:', 'removeDependency:', 'completionBlock', 'setCompletionBlock:', 'waitUntilFinished', 'queuePriority', 'setQueuePriority:', 'qualityOfService', 'setQualityOfService:', 'threadPriority', 'setThreadPriority:', 'copy', 'mutableCopy', 'initWithCoder:', 'encodeWithCoder:', 'description', 'base-reinit', 'target-reinit', 'name-type', 'bad-name-copy', 'nil-name-copy', 'subclass', 'caller-subclass', 'spoof', 'base-to-invocation', 'invocation-to-base', 'scalar', 'two-args', 'owned-family', 'signature-change', 'nested-main', 'nested-start', 'destruct-active', 'void-result', 'cancelled-result', 'raw-result']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			invocation_operation_callback_mode = mode
			object := objc_new(api.base)
			match mode {
				'raw-result' { raw := objc_allocate(api.cls); api.message(raw, c'start', 0, 0, 0); api.message(raw, c'result', 0, 0, 0) }
				'base-reinit' { api.message(object, c'init', 0, 0, 0) }
				'name-type' { api.message(object, c'setName:', objc_new(api.root), 0, 0) }
				'bad-name-copy', 'nil-name-copy' {
					custom := objc_allocate_class(api.strings, c'VinixInvalidOperationName', 0)
					assert objc_add_method(custom, u64(c'copy'), u64(unsafe { voidptr(invocation_operation_invalid_copy) }), c'@16@0:8'); objc_register_class(custom)
					api.message(object, c'setName:', objc_new(custom), 0, 0)
				}
				'subclass', 'caller-subclass' {
					sub := objc_allocate_class(api.cls, c'VinixUnsupportedOperationSubclass', 0); objc_register_class(sub)
					if mode == 'subclass' { objc_allocate(sub) } else { mut storage := [33]u64{}; objc_construct_instance(sub, u64(unsafe { &storage[0] })) }
				}
				'spoof' { spoof := objc_new(api.root); objc_set_class(spoof, api.cls); api.message(spoof, c'start', 0, 0, 0) }
				'base-to-invocation' { objc_set_class(object, api.cls); api.message(object, c'start', 0, 0, 0) }
				'invocation-to-base' { raw := objc_allocate(api.cls); objc_set_class(raw, api.base); api.message(raw, c'start', 0, 0, 0) }
				'scalar', 'two-args', 'owned-family', 'signature-change', 'nested-main', 'nested-start', 'destruct-active', 'target-reinit', 'void-result', 'cancelled-result' {
					cls := objc_allocate_class(api.root, c'VinixInvalidOperationTarget', 0)
					selector := if mode == 'owned-family' { c'newResult' } else { c'run' }
					types := match mode { 'scalar' { c'q16@0:8' } 'two-args' { c'@32@0:8@16@24' } 'void-result' { c'v16@0:8' } else { c'@16@0:8' } }
					implementation := if mode == 'void-result' { u64(unsafe { voidptr(invocation_operation_void_zero) }) } else { u64(unsafe { voidptr(invocation_operation_invalid_target) }) }
					assert objc_add_method(cls, u64(selector), implementation, types); objc_register_class(cls)
					target := objc_new(cls); operation := invocation_operation_initialize(api, target, selector, 0)
					invocation_operation_receiver = operation; invocation_operation_executing = true
					if mode == 'signature-change' {
						changed := objc_allocate_class(cls, c'VinixChangedOperationTarget', 0)
						assert objc_add_method(changed, u64(selector), implementation, c'q16@0:8'); objc_register_class(changed)
						assert objc_set_class(target, changed) == cls
					}
					if mode == 'target-reinit' { api.message(operation, c'initWithTarget:selector:object:', target, u64(selector), 0) }
					if mode == 'cancelled-result' { api.message(operation, c'cancel', 0, 0, 0) }
					api.message(operation, c'start', 0, 0, 0)
					if mode == 'void-result' || mode == 'cancelled-result' { api.message(operation, c'result', 0, 0, 0) }
				}
				else { api.message(object, unsafe { &char(mode.str) }, 0, 0, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }
		assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	assert ios_runtime.live == 0; objc_stop(); system_data_stop()
	println('IOS-INVOCATION-OPERATION-REJECT:39 invocation, scheduling, dependency, priority, coding, malformed ABI, subclass, provenance, reentry, active destruction and result cases fail explicitly')
}
