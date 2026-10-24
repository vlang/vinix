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
fn C.class_getInstanceVariable(voidptr, &char) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
type TelephonySend = fn (u64, u64, u64) u64
struct TelephonyApi { native bool send u64 }
fn telephony_api() TelephonyApi { return TelephonyApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
fn (api TelephonyApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api TelephonyApi) msg(object u64, selector &char, value u64) u64 {
	mut sel := u64(selector)
	$if macos { if api.native { sel = u64(C.sel_registerName(selector)) } }
	return unsafe { TelephonySend(voidptr(api.send))(object, sel, value) }
}
fn (api TelephonyApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0) } }
	return objc_pool_push()
}
fn (api TelephonyApi) pop(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0); return } }
	objc_pool_pop(pool)
}
fn (api TelephonyApi) retain(object u64) {
	$if macos { if api.native { api.msg(object, c'retain', 0); return } }
	objc_retain(object)
}
fn (api TelephonyApi) release(object u64) {
	$if macos { if api.native { api.msg(object, c'release', 0); return } }
	objc_release(object)
}
fn telephony_check_metadata(api TelephonyApi) {
	cls := api.cls('CTTelephonyNetworkInfo'); assert cls != 0
	$if macos { if api.native { assert C.class_getInstanceSize(voidptr(cls)) == 40 && u64(C.class_getSuperclass(voidptr(cls))) == api.cls('NSObject') } }
	if !api.native { assert objc_class_size(cls) == 40 && objc_class_parent(cls) == api.cls('NSObject') }
	for i, key in telephony_ivars() {
		mut offset := i64(0); mut types := ''
		$if macos { if api.native { ivar := C.class_getInstanceVariable(voidptr(cls), key.str); assert ivar != unsafe { nil }; offset = i64(C.ivar_getOffset(ivar)); types = unsafe { C.ivar_getTypeEncoding(ivar).vstring() } } }
		if !api.native { ivar := objc_find_ivar(cls, key.str); assert ivar != 0; offset = objc_ivar_offset(ivar); types = ctext(u64(objc_ivar_types(ivar))) }
		assert offset == 8 + i * 8 && types == telephony_ivar_types()[i]
	}
	for selector in ['init', 'delegate', 'setDelegate:', 'dataServiceIdentifier', 'subscriberCellularProvider', 'serviceSubscriberCellularProviders', 'serviceCurrentRadioAccessTechnology', 'currentRadioAccessTechnology', 'serviceSubscriberCellularProvidersDidUpdateNotifier', 'setServiceSubscriberCellularProvidersDidUpdateNotifier:', 'subscriberCellularProviderDidUpdateNotifier', 'setSubscriberCellularProviderDidUpdateNotifier:']! {
		mut actual := ''
		$if macos { if api.native { method := C.class_getInstanceMethod(voidptr(cls), C.sel_registerName(selector.str)); assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() } } }
		if !api.native { method := objc_instance_method(cls, u64(selector.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
		assert actual == telephony_types('CTTelephonyNetworkInfo', false, selector) or { panic(selector) }, selector + ': ' + actual
	}
}
struct TelephonyBlockState { mut: copies i64 disposals i64 calls i64 object u64 reenter bool destroy bool }
struct TelephonyBlockDescriptor { reserved u64 size u64 copy u64 dispose u64 }
struct TelephonyBlockLiteral { isa u64 flags u32 reserved u32 invoke u64 descriptor u64 capture u64 }
fn telephony_lock_probe(object u64) { assert telephony_api().msg(object, c'dataServiceIdentifier', 0) == 0 }
fn telephony_block_probe(state &TelephonyBlockState) {
	if state.destroy { objc_destruct_instance(state.object) }
	if state.reenter { worker := spawn telephony_lock_probe(state.object); worker.wait() }
}
fn telephony_block_copy(_destination u64, source u64) {
	state := unsafe { &TelephonyBlockState(read64(source + 32)) }; C.ios_ref_change(unsafe { &state.copies }, 1); telephony_block_probe(state)
}
fn telephony_block_dispose(block u64) {
	state := unsafe { &TelephonyBlockState(read64(block + 32)) }; C.ios_ref_change(unsafe { &state.disposals }, 1); telephony_block_probe(state)
}
fn telephony_block_invoke(block u64, _service u64) {
	state := unsafe { &TelephonyBlockState(read64(block + 32)) }; C.ios_ref_change(unsafe { &state.calls }, 1)
}
fn telephony_shared(api TelephonyApi) {
	telephony_check_metadata(api); pool := api.pool()
	object := api.msg(api.cls('CTTelephonyNetworkInfo'), c'new', 0)
	for selector in [c'delegate', c'dataServiceIdentifier', c'subscriberCellularProvider', c'currentRadioAccessTechnology', c'serviceSubscriberCellularProvidersDidUpdateNotifier', c'subscriberCellularProviderDidUpdateNotifier']! { assert api.msg(object, selector, 0) == 0, unsafe { selector.vstring() } }
	for selector in [c'serviceSubscriberCellularProviders', c'serviceCurrentRadioAccessTechnology']! {
		dictionary := api.msg(object, selector, 0)
		assert dictionary != 0 && api.msg(dictionary, c'isKindOfClass:', api.cls('NSDictionary')) != 0 && api.msg(dictionary, c'count', 0) == 0
	}
	inner := api.pool(); delegate := api.msg(api.cls('NSObject'), c'new', 0)
	api.msg(object, c'setDelegate:', delegate); assert api.msg(object, c'delegate', 0) == delegate
	api.release(delegate); api.pop(inner); assert api.msg(object, c'delegate', 0) == 0
	mut isa := u64(0)
	$if macos { if api.native { isa = u64(C.dlsym(voidptr(-2), c'_NSConcreteStackBlock')) } }
	if !api.native { isa = block_isa(0) }
	descriptor := TelephonyBlockDescriptor{0, sizeof(TelephonyBlockLiteral), u64(unsafe { voidptr(telephony_block_copy) }), u64(unsafe { voidptr(telephony_block_dispose) })}
	for index in 0 .. 2 {
		setter := if index == 0 { c'setServiceSubscriberCellularProvidersDidUpdateNotifier:' } else { c'setSubscriberCellularProviderDidUpdateNotifier:' }
		getter := if index == 0 { c'serviceSubscriberCellularProvidersDidUpdateNotifier' } else { c'subscriberCellularProviderDidUpdateNotifier' }
		mut state := TelephonyBlockState{object: object, reenter: !api.native}
		literal := TelephonyBlockLiteral{isa, u32(1) << 25, 0, u64(unsafe { voidptr(telephony_block_invoke) }), u64(unsafe { &descriptor }), u64(unsafe { &state })}
		original := u64(unsafe { &literal }); scope := api.pool()
		api.msg(object, setter, original); assert state.copies == 1 && state.disposals == 0 && state.calls == 0
		stored := api.msg(object, getter, 0); assert stored != 0 && stored != original && stored == read64(object + 16 + u64(index) * 8)
		api.retain(stored); api.msg(object, setter, stored)
		assert state.copies == 1 && state.disposals == 0
		api.msg(object, setter, 0); assert api.msg(object, getter, 0) == 0
		api.pop(scope); assert state.disposals == 0
		telephony_block_invoke(stored, 0); assert state.calls == 1
		api.release(stored); assert state.disposals == 1
	}
	api.release(object); api.pop(pool)
}
fn telephony_thread(object u64) {
	api := telephony_api(); pool := api.pool()
	for _ in 0 .. 100 { api.msg(object, c'setDelegate:', object); assert api.msg(object, c'dataServiceIdentifier', 0) == 0; api.msg(object, c'delegate', 0); api.msg(object, c'setDelegate:', 0) }
	api.pop(pool)
}
fn telephony_runtime() {
	api := telephony_api(); cls := api.cls('CTTelephonyNetworkInfo'); library := '/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony'
	assert runtime_symbol(library, '_OBJC_CLASS_$_CTTelephonyNetworkInfo') or { panic(err) } == cls
	assert runtime_symbol(library, '_OBJC_METACLASS_$_CTTelephonyNetworkInfo') or { panic(err) } == read64(cls)
	for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libobjc.A.dylib']! {
		if _ := runtime_symbol(wrong, '_OBJC_CLASS_$_CTTelephonyNetworkInfo') { assert false, wrong }
		if _ := runtime_symbol(wrong, '_OBJC_METACLASS_$_CTTelephonyNetworkInfo') { assert false, wrong }
	}
	object := api.msg(cls, c'new', 0); mut workers := []thread{}
	for _ in 0 .. 4 { workers << spawn telephony_thread(object) }; workers.wait()
	for selector in [c'copy', c'mutableCopy', c'initWithCoder:', c'encodeWithCoder:', c'radioAccessTechnology', c'serviceSignalStrength', c'serviceCellId']! { assert !objc_responds(object, selector) && objc_instance_method(cls, u64(selector)) == 0 }
	// Teardown must release the copied notifier and unregister the weak slot
	// using allocation provenance after the visible class changes.
	state := TelephonyBlockState{object: object}
	descriptor := TelephonyBlockDescriptor{0, sizeof(TelephonyBlockLiteral), u64(unsafe { voidptr(telephony_block_copy) }), u64(unsafe { voidptr(telephony_block_dispose) })}
	literal := TelephonyBlockLiteral{block_isa(0), u32(1) << 25, 0, u64(unsafe { voidptr(telephony_block_invoke) }), u64(unsafe { &descriptor }), u64(unsafe { &state })}
	api.msg(object, c'setDelegate:', object)
	api.msg(object, c'setSubscriberCellularProviderDidUpdateNotifier:', u64(unsafe { &literal }))
	objc_set_class(object, api.cls('NSObject')); api.release(object)
	assert state.copies == 1 && state.disposals == 1
	mut guarded := [7]u64{}; guarded[0] = 0x1122334455667788; guarded[6] = 0x8877665544332211
	pool := api.pool(); caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller && telephony_initialize(caller) == caller
	api.msg(caller, c'setDelegate:', caller); assert api.msg(caller, c'delegate', 0) == caller
	// The getter owns an autorelease, so drain it before explicit caller destruction.
	api.pop(pool)
	assert objc_destruct_instance(caller) == caller && caller !in ios_runtime.objects
	assert guarded[0] == 0x1122334455667788 && guarded[6] == 0x8877665544332211
	assert ios_runtime.live == 1 && ios_runtime.objects.len == 1 && ios_runtime.empty_dictionary != 0
	assert ios_runtime.weak.len == 0 && ios_runtime.block_refs.len == 0
}
fn test_coretelephony() {
	$if macos {
		assert C.dlopen(c'/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony', 2) != unsafe { nil }
		telephony_shared(TelephonyApi{true, u64(C.dlsym(voidptr(-2), c'objc_msgSend'))})
		println('IOS-TELEPHONY-NATIVE: layout, encodings, no-service defaults, weak delegate and copied notifiers PASS')
	}
	for _ in 0 .. 2 { objc_start(); system_data_start()!; telephony_shared(telephony_api()); telephony_runtime(); objc_stop(); assert ios_runtime.live == 0; system_data_stop() }
	println('IOS-TELEPHONY: native parity, callback reentry, concurrency, caller storage, isa cleanup and two balanced lifetimes PASS')
}
fn test_coretelephony_rejections() {
	objc_start(); system_data_start()!; api := telephony_api()
	modes := ['raw', 'spoof', 'isa', 'raw-isa', 'body', 'delegate-body', 'subclass', 'caller-subclass', 'reinit', 'not-block', 'associated-copy', 'active-destroy', 'copy-destroy', 'copy', 'mutableCopy', 'encodeWithCoder:', 'radioAccessTechnology', 'serviceSignalStrength', 'serviceCellId']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1]); cls := api.cls('CTTelephonyNetworkInfo'); object := api.msg(cls, c'new', 0)
			match mode {
				'raw' { api.msg(objc_allocate(cls), c'delegate', 0) }
				'spoof' { fake := objc_new(api.cls('NSObject')); objc_set_class(fake, cls); api.msg(fake, c'delegate', 0) }
				'isa', 'raw-isa' { if mode == 'isa' { objc_set_class(object, api.cls('NSObject')) } else { unsafe { *(&u64(object)) = api.cls('NSObject') } }; api.msg(object, c'delegate', 0) }
				'body', 'delegate-body' { unsafe { *(&u64(object + if mode == 'body' { u64(16) } else { u64(8) })) = object }; api.msg(object, c'delegate', 0) }
				'subclass', 'caller-subclass' { custom := objc_allocate_class(cls, c'UnsupportedTelephony', 0); objc_register_class(custom); if mode == 'subclass' { objc_allocate(custom) } else { mut storage := [5]u64{}; objc_construct_instance(custom, u64(unsafe { &storage[0] })) } }
				'reinit' { telephony_initialize(object) }
				'not-block' { api.msg(object, c'setSubscriberCellularProviderDidUpdateNotifier:', object) }
				'associated-copy' { objc_copy_value(object, false) }
				'active-destroy' { telephony_enter(object); objc_destruct_instance(object) }
				'copy-destroy' {
					state := TelephonyBlockState{object: object, destroy: true}; descriptor := TelephonyBlockDescriptor{0, sizeof(TelephonyBlockLiteral), u64(unsafe { voidptr(telephony_block_copy) }), u64(unsafe { voidptr(telephony_block_dispose) })}
					literal := TelephonyBlockLiteral{block_isa(0), u32(1) << 25, 0, u64(unsafe { voidptr(telephony_block_invoke) }), u64(unsafe { &descriptor }), u64(unsafe { &state })}; api.msg(object, c'setSubscriberCellularProviderDidUpdateNotifier:', u64(unsafe { &literal }))
				}
				else { api.msg(object, mode.str, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }; assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	println('IOS-TELEPHONY-REJECT: ' + modes.len.str() + ' invalid storage, subclasses, copies and unsupported API cases PASS')
}
