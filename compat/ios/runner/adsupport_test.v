// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_copyIvarList(voidptr, &u32) &voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
type AdvertisingSend = fn (u64, u64, u64) u64
struct AdvertisingApi { native bool send u64 }
fn advertising_api() AdvertisingApi { return AdvertisingApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
fn (api AdvertisingApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api AdvertisingApi) msg(object u64, selector &char, value u64) u64 {
	mut sel := u64(selector)
	$if macos { if api.native { sel = u64(C.sel_registerName(selector)) } }
	return unsafe { AdvertisingSend(voidptr(api.send))(object, sel, value) }
}
fn (api AdvertisingApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0) } }
	return objc_pool_push()
}
fn (api AdvertisingApi) pop(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0); return } }
	objc_pool_pop(pool)
}
fn (api AdvertisingApi) release(object u64) { api.msg(object, c'release', 0) }
fn advertising_metadata(api AdvertisingApi) {
	cls := api.cls('ASIdentifierManager'); assert cls != 0
	mut count := u32(99)
	$if macos { if api.native {
		assert C.class_getInstanceSize(voidptr(cls)) == 8 && u64(C.class_getSuperclass(voidptr(cls))) == api.cls('NSObject')
		ivars := C.class_copyIvarList(voidptr(cls), &count); C.free(ivars)
	} }
	if !api.native {
		assert objc_class_size(cls) == 8 && objc_class_parent(cls) == api.cls('NSObject')
		ivars := objc_copy_ivars(cls, &count); C.free(ivars)
	}
	assert count == 0
	for selector in ['sharedManager', 'advertisingIdentifier', 'isAdvertisingTrackingEnabled']! {
		meta := selector == 'sharedManager'; mut actual := ''
		$if macos { if api.native {
			method := if meta { C.class_getClassMethod(voidptr(cls), C.sel_registerName(selector.str)) } else { C.class_getInstanceMethod(voidptr(cls), C.sel_registerName(selector.str)) }
			assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() }
		} }
		if !api.native {
			method := if meta { objc_class_method(cls, u64(selector.str)) } else { objc_instance_method(cls, u64(selector.str)) }
			assert method != 0; actual = ctext(u64(objc_method_types(method)))
		}
		assert actual == adsupport_types('ASIdentifierManager', meta, selector) or { panic(selector) }
	}
}
fn advertising_uuid(api AdvertisingApi, uuid u64) {
	assert uuid != 0 && api.msg(uuid, c'isKindOfClass:', api.cls('NSUUID')) != 0
	mut bytes := [16]u8{init: 255}; api.msg(uuid, c'getUUIDBytes:', u64(unsafe { &bytes[0] }))
	for byte in bytes { assert byte == 0 }
	text := api.msg(uuid, c'UUIDString', 0)
	assert ctext(api.msg(text, c'UTF8String', 0)) == '00000000-0000-0000-0000-000000000000'
}
fn advertising_worker(expected u64) {
	api := advertising_api(); pool := api.pool()
	for _ in 0 .. 100 {
		object := api.msg(api.cls('ASIdentifierManager'), c'sharedManager', 0); assert object == expected
		assert api.msg(object, c'isAdvertisingTrackingEnabled', 0) == 0
		advertising_uuid(api, api.msg(object, c'advertisingIdentifier', 0))
	}
	api.pop(pool)
}
__global (
	advertising_fixture_mode string
	advertising_fixture_receiver u64
	advertising_fixture_calls i64
)
fn advertising_reentrant_factory() { assert adsupport_shared() != 0 }
fn advertising_receiver_probe(object u64) { assert advertising_api().msg(object, c'isAdvertisingTrackingEnabled', 0) == 0 }
fn advertising_constructor(object u64, _selector u64) u64 {
	if C.ios_ref_change(unsafe { &advertising_fixture_calls }, 1) != 0 { return object }
	match advertising_fixture_mode {
		'factory-reentry' { worker := spawn advertising_reentrant_factory(); worker.wait() }
		'candidate-destroy', 'uuid-destroy' { objc_destruct_instance(object) }
		'candidate-isa' { objc_set_class(object, ios_runtime.names['NSObject']) }
		'candidate-retire' { adsupport_stop() }
		'receiver-reentry' { worker := spawn advertising_receiver_probe(advertising_fixture_receiver); worker.wait() }
		'receiver-release' { objc_release(advertising_fixture_receiver) }
		'active-destroy' { objc_destruct_instance(advertising_fixture_receiver) }
		'receiver-isa' { objc_set_class(advertising_fixture_receiver, ios_runtime.names['NSObject']) }
		else {}
	}
	return object
}
fn advertising_install(cls u64, mode string) {
	advertising_fixture_mode = mode; advertising_fixture_calls = 0
	objc_replace_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(advertising_constructor) }), c'@16@0:8')
}
fn advertising_runtime() {
	api := advertising_api(); cls := api.cls('ASIdentifierManager'); advertising_metadata(api)
	library := '/System/Library/Frameworks/AdSupport.framework/AdSupport'
	assert runtime_symbol(library, '_OBJC_CLASS_$_ASIdentifierManager') or { panic(err) } == cls
	assert runtime_symbol(library, '_OBJC_METACLASS_$_ASIdentifierManager') or { panic(err) } == read64(cls)
	for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libobjc.A.dylib']! {
		for symbol in ['_OBJC_CLASS_$_ASIdentifierManager', '_OBJC_METACLASS_$_ASIdentifierManager']! { if _ := runtime_symbol(wrong, symbol) { assert false, wrong } }
	}
	if _ := runtime_symbol(library, 'ASUnknownFunction') { assert false }
	// A constructor on another thread publishes the winner before this candidate.
	advertising_install(cls, 'factory-reentry'); scope := api.pool()
	manager := api.msg(cls, c'sharedManager', 0); assert manager != 0 && advertising_fixture_calls == 2
	advertising_fixture_mode = ''; api.pop(scope)
	pool := api.pool(); assert api.msg(cls, c'sharedManager', 0) == manager
	assert api.msg(manager, c'init', 0) == manager && api.msg(manager, c'isAdvertisingTrackingEnabled', 0) == 0
	uuid := api.msg(manager, c'advertisingIdentifier', 0); advertising_uuid(api, uuid); api.msg(uuid, c'retain', 0)
	mut workers := []thread{}; for _ in 0 .. 4 { workers << spawn advertising_worker(manager) }; workers.wait()
	for selector in [c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'classForCoder', c'clearAdvertisingIdentifier', c'isUserOptedIn']! {
		assert !objc_responds(manager, selector) && objc_instance_method(cls, u64(selector)) == 0
	}
	method := objc_instance_method(cls, u64(c'isAdvertisingTrackingEnabled'))
	assert unsafe { AdvertisingSend(voidptr(objc_method_imp(method)))(manager, u64(c'isAdvertisingTrackingEnabled'), 0) } == 0
	allocated := api.msg(cls, c'new', 0); assert allocated != manager && api.msg(allocated, c'init', 0) == allocated
	advertising_uuid(api, api.msg(allocated, c'advertisingIdentifier', 0)); api.release(allocated)
	mut guarded := [3]u64{}; guarded[0] = 0x12345678; guarded[2] = 0xabcdef12
	caller := objc_construct_instance(cls, u64(unsafe { &guarded[1] })); assert api.msg(caller, c'init', 0) == caller
	advertising_uuid(api, api.msg(caller, c'advertisingIdentifier', 0)); assert objc_destruct_instance(caller) == caller
	assert guarded[0] == 0x12345678 && guarded[2] == 0xabcdef12
	// UUID construction must run without the manager lock and pin the receiver.
	concrete := api.cls('__NSConcreteUUID')
	for mode in ['receiver-reentry', 'receiver-release']! {
		receiver := api.msg(cls, c'new', 0); advertising_fixture_receiver = receiver
		advertising_install(concrete, mode)
		advertising_uuid(api, api.msg(receiver, c'advertisingIdentifier', 0)); assert advertising_fixture_calls == 1
		if mode == 'receiver-reentry' { api.release(receiver) } else { assert receiver !in ios_runtime.objects }
	}
	advertising_fixture_mode = ''
	api.pop(pool); pool2 := api.pool(); advertising_uuid(api, uuid); api.release(uuid)
	assert api.msg(cls, c'sharedManager', 0) == manager; api.pop(pool2)
}
fn test_advertising_runtime() {
	for _ in 0 .. 2 {
		system_data_start(); objc_start(); advertising_runtime(); objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.weak.len == 0; system_data_stop()
	}
	println('IOS-ADSUPPORT: metadata, zero UUIDs, shared cache, 400 concurrent queries, constructor reentry, receiver pinning, guarded storage and two balanced lifetimes PASS')
}
fn test_advertising_rejections() {
	system_data_start(); objc_start()
	modes := ['fake', 'spoof', 'raw-isa', 'set-isa', 'subclass', 'caller-subclass', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'clearAdvertisingIdentifier', 'isUserOptedIn', 'associated-copy', 'copy-provenance', 'cached-destroy', 'active-destroy', 'receiver-isa', 'candidate-destroy', 'candidate-isa', 'candidate-retire', 'retired-factory', 'uuid-destroy']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			api := advertising_api(); cls := api.cls('ASIdentifierManager')
			match mode {
				'fake' { mut raw := [1]u64{}; raw[0] = cls; api.msg(u64(unsafe { &raw[0] }), c'advertisingIdentifier', 0) }
				'spoof' { object := objc_new(api.cls('NSObject')); objc_set_class(object, cls); api.msg(object, c'init', 0) }
				'subclass', 'caller-subclass' {
					custom := objc_allocate_class(cls, c'UnsupportedAdvertisingManager', 0); objc_register_class(custom)
					if mode == 'subclass' { objc_new(custom) } else { mut storage := [1]u64{}; objc_construct_instance(custom, u64(unsafe { &storage[0] })) }
				}
				'candidate-destroy', 'candidate-isa', 'candidate-retire' { advertising_install(cls, mode); adsupport_shared() }
				'retired-factory' { adsupport_stop(); adsupport_shared() }
				'cached-destroy' { objc_destruct_instance(adsupport_shared()) }
				else {
					object := objc_new(cls)
					match mode {
						'raw-isa' { unsafe { *(&u64(object)) = api.cls('NSObject') }; api.msg(object, c'advertisingIdentifier', 0) }
						'set-isa' { objc_set_class(object, api.cls('NSObject')); api.msg(object, c'isAdvertisingTrackingEnabled', 0) }
						'associated-copy', 'copy-provenance' { if mode == 'copy-provenance' { objc_set_class(object, api.cls('NSObject')) }; objc_copy_value(object, false) }
						'active-destroy', 'receiver-isa', 'uuid-destroy' { advertising_fixture_receiver = object; advertising_install(api.cls('__NSConcreteUUID'), mode); api.msg(object, c'advertisingIdentifier', 0) }
						else { api.msg(object, mode.str, 0) }
					}
				}
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }; assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	println('IOS-ADSUPPORT-REJECT: ' + modes.len.str() + ' invalid storage, subclasses, unsupported API and constructor lifetime violations PASS')
}
fn test_advertising_native() {
	$if macos {
		assert C.dlopen(c'/System/Library/Frameworks/AdSupport.framework/AdSupport', 2) != unsafe { nil }
		api := AdvertisingApi{true, u64(C.dlsym(voidptr(-2), c'objc_msgSend'))}; advertising_metadata(api); pool := api.pool()
		// macOS sometimes returns nil or different factory instances. Record that
		// separately; only compare the public disabled-tracking/zero-ID profile.
		for selector in [c'sharedManager', c'new']! {
			object := api.msg(api.cls('ASIdentifierManager'), selector, 0)
			if object != 0 {
				assert api.msg(object, c'isAdvertisingTrackingEnabled', 0) == 0
				uuid := api.msg(object, c'advertisingIdentifier', 0); if uuid != 0 { advertising_uuid(api, uuid) }
				if selector == c'new' { api.release(object) }
			}
		}
		api.pop(pool)
		println('IOS-ADSUPPORT-NATIVE: 8-byte layout, no ivars, three encodings and available disabled-tracking/zero-ID values PASS')
	}
}
