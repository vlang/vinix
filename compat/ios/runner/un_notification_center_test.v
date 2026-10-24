// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#flag -framework UserNotifications
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceVariable(voidptr, &char) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.objc_storeWeak(&u64, voidptr) voidptr

type CenterSend = fn (u64, u64, u64, u64) u64
struct CenterApi { native bool send u64 }
fn center_api() CenterApi { return CenterApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
fn (api CenterApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api CenterApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api CenterApi) msg(object u64, name &char, a u64, b u64) u64 {
	return unsafe { CenterSend(voidptr(api.send))(object, api.sel(name), a, b) }
}
fn (api CenterApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0, 0) } }
	return objc_pool_push()
}
fn (api CenterApi) pop(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api CenterApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api CenterApi) weak_destroy(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn center_metadata(api CenterApi) {
	cls := api.cls('UNUserNotificationCenter'); assert cls != 0
	$if macos { if api.native {
		assert C.class_getInstanceSize(unsafe { voidptr(cls) }) == 40
		assert u64(C.class_getSuperclass(unsafe { voidptr(cls) })) == api.cls('NSObject')
	} }
	if !api.native { assert objc_class_size(cls) == 40 && objc_class_parent(cls) == api.cls('NSObject') }
	for index, pair in [['_delegate', '@"<UNUserNotificationCenterDelegate>"']!, ['_bundleIdentifier', '@"NSString"']!, ['_queue', '@"NSObject<OS_dispatch_queue>"']!, ['_privateDelegate', '@"<UNUserNotificationCenterDelegatePrivate>"']!]! {
		$if macos { if api.native {
			ivar := C.class_getInstanceVariable(unsafe { voidptr(cls) }, pair[0].str)
			assert ivar != unsafe { nil } && C.ivar_getOffset(ivar) == 8 + index * 8
			assert unsafe { C.ivar_getTypeEncoding(ivar).vstring() } == pair[1]
		} }
		if !api.native {
			ivar := objc_find_ivar(cls, pair[0].str); assert ivar != 0
			assert objc_ivar_offset(ivar) == i64(8 + index * 8) && ctext(u64(objc_ivar_types(ivar))) == pair[1]
		}
	}
	for name, encoding in {'currentNotificationCenter': '@16@0:8', 'delegate': '@16@0:8', 'setDelegate:': 'v24@0:8@16', 'supportsContentExtensions': 'B16@0:8'} {
		for meta in [false, true]! {
			if name == 'currentNotificationCenter' && !meta { continue }
			if name in ['delegate', 'setDelegate:']! && meta { continue }
			mut actual := ''
			$if macos { if api.native {
				method := if meta { C.class_getClassMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.sel(name.str)) }) } else { C.class_getInstanceMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.sel(name.str)) }) }
				assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() }
			} }
			if !api.native { method := objc_instance_method(if meta { read64(cls) } else { cls }, u64(name.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
			assert actual == encoding
		}
	}
}
fn center_shared(api CenterApi) {
	pool := api.pool(); center_metadata(api)
	cls := api.cls('UNUserNotificationCenter'); object := api.msg(cls, c'currentNotificationCenter', 0, 0)
	assert object != 0 && api.msg(object, c'delegate', 0, 0) == 0
	mut center_weak := u64(0); api.weak(unsafe { &center_weak }, object)
	api.pop(pool); assert center_weak == object
	assert api.msg(cls, c'currentNotificationCenter', 0, 0) == object
	outer := api.pool()
	for _ in 0 .. 3 {
		delegate := api.msg(api.cls('NSObject'), c'new', 0, 0)
		replacement := api.msg(api.cls('NSObject'), c'new', 0, 0)
		mut weak := u64(0); api.weak(unsafe { &weak }, delegate)
		api.msg(object, c'setDelegate:', delegate, 0)
		// Getter protects its return value until the caller's pool drains.
		inner := api.pool(); assert api.msg(object, c'delegate', 0, 0) == delegate
		api.msg(delegate, c'release', 0, 0); assert weak == delegate
		api.msg(object, c'setDelegate:', replacement, 0)
		api.pop(inner); assert weak == 0
		inner2 := api.pool(); assert api.msg(object, c'delegate', 0, 0) == replacement; api.pop(inner2)
		api.msg(replacement, c'release', 0, 0); assert api.msg(object, c'delegate', 0, 0) == 0
		api.weak_destroy(unsafe { &weak })
	}
	delegate := api.msg(api.cls('NSObject'), c'new', 0, 0)
	api.msg(object, c'setDelegate:', delegate, 0); api.msg(object, c'setDelegate:', 0, 0)
	assert api.msg(object, c'delegate', 0, 0) == 0; api.msg(delegate, c'release', 0, 0)
	api.pop(outer); api.weak_destroy(unsafe { &center_weak })
}

__global center_callback_mode = ''
__global center_callback_weak = u64(0)
__global center_callback_count = 0
fn center_lock_worker() { C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock() }
fn center_cached_worker(expected u64) {
	api := center_api(); pool := api.pool()
	assert api.msg(api.cls('UNUserNotificationCenter'), c'currentNotificationCenter', 0, 0) == expected
	api.pop(pool)
}
fn center_constructor(object u64, _selector &char) u64 {
	center_callback_count++
	match center_callback_mode {
		'isa' { objc_set_class(object, ios_runtime.names['NSObject']) }
		'state' { obj_header(object).un_center_initialized = true }
		'body' { unsafe { *(&u64(object + 16)) = 1 } }
		'delegate' { unsafe { *(&u64(object + 8)) = 1 } }
		'reentry' { un_center_current(ios_runtime.names['UNUserNotificationCenter']) }
		else { worker := spawn center_lock_worker(); worker.wait() }
	}
	if center_callback_mode == 'fail' { objc_store_weak(unsafe { &center_callback_weak }, object); return 0 }
	return object
}
fn center_override(_object u64, _selector &char) u64 { return 99 }
fn test_un_notification_center() {
	$if macos {
		native_send := C.dlsym(voidptr(i64(-2)), c'objc_msgSend'); assert native_send != unsafe { nil }
		center_shared(CenterApi{true, u64(native_send)})
		println('IOS-UN-CENTER-NATIVE: layout, encodings, singleton, getter lifetime, replacement, nil and zeroing weak delegate PASS')
	}
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!; api := center_api(); cls := api.cls('UNUserNotificationCenter')
		library := '/System/Library/Frameworks/UserNotifications.framework/UserNotifications'
		assert runtime_symbol(library, '_OBJC_CLASS_$_UNUserNotificationCenter') or { panic(err) } == cls
		assert runtime_symbol(library, '_OBJC_METACLASS_$_UNUserNotificationCenter') or { panic(err) } == read64(cls)
		assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(center_constructor) }), c'@16@0:8')
		center_callback_mode = 'fail'; center_callback_count = 0
		assert api.msg(cls, c'currentNotificationCenter', 0, 0) == 0 && center_callback_count == 1
		assert center_callback_weak == 0 && ios_runtime.user_notification_center == 0 && ios_runtime.live == 0
		api.weak_destroy(unsafe { &center_callback_weak }); center_callback_mode = ''
		center_shared(api); object := api.msg(cls, c'currentNotificationCenter', 0, 0)
		assert center_callback_count == 2
		for _ in 0 .. 8 { worker := spawn center_cached_worker(object); worker.wait() }
		assert api.msg(cls, c'supportsContentExtensions', 0, 0) == 0 && api.msg(object, c'supportsContentExtensions', 0, 0) == 0
		for selector in [c'new', c'init', c'copy', c'encodeWithCoder:', c'requestAuthorizationWithOptions:completionHandler:', c'addNotificationRequest:withCompletionHandler:', c'getPendingNotificationRequestsWithCompletionHandler:', c'setNotificationCategories:', c'setBadgeCount:withCompletionHandler:', c'notificationSettings', c'queue', c'privateDelegate']! {
			assert objc_instance_method(cls, u64(selector)) == 0 && !objc_responds(object, selector)
		}
		raw := objc_allocate(cls); objc_set_class(raw, api.cls('NSObject')); objc_release(raw)
		mut guarded := [u64(0x1122334455667788), 0, 0, 0, 0, 0, 0x8877665544332211]!
		caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller
		objc_set_class(caller, api.cls('NSObject')); assert objc_destruct_instance(caller) == caller
		assert caller !in ios_runtime.objects && guarded[0] == 0x1122334455667788 && guarded[6] == 0x8877665544332211
		assert objc_add_method(cls, u64(c'notificationSettings'), u64(unsafe { voidptr(center_override) }), c'@16@0:8')
		assert objc_instance_method(cls, u64(c'notificationSettings')) != 0 && objc_responds(object, c'notificationSettings')
		assert api.msg(object, c'notificationSettings', 0, 0) == 99
		// Shutdown uses allocation provenance after an isa change and clears weak slots.
		mut weak := u64(0); api.weak(unsafe { &weak }, object)
		delegate := objc_new(api.cls('NSObject')); api.msg(object, c'setDelegate:', delegate, 0)
		objc_set_class(object, api.cls('NSObject')); objc_stop(); assert weak == 0
		objc_release(delegate); api.weak_destroy(unsafe { &weak })
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
		system_data_stop()
	}
	println('IOS-UN-CENTER: native parity, constructor lock handoff/failure/retry, cached threads, capability, reflection, caller storage, isa cleanup and two balanced lifetimes PASS')
}
fn test_un_notification_center_rejections() {
	objc_start(); system_data_start()!; api := center_api()
	modes := ['new', 'init', 'raw', 'caller', 'spoof', 'isa', 'copy-isa', 'subclass', 'caller-subclass', 'factory-subclass', 'destruct', 'destruct-isa', 'dealloc', 'body', 'weak-body', 'stopped', 'constructor-isa', 'constructor-state', 'constructor-body', 'constructor-delegate', 'constructor-reentry', 'requestAuthorizationWithOptions:completionHandler:', 'setNotificationCategories:', 'getNotificationSettingsWithCompletionHandler:', 'addNotificationRequest:withCompletionHandler:', 'removeAllPendingNotificationRequests', 'getDeliveredNotificationsWithCompletionHandler:', 'setBadgeCount:withCompletionHandler:', 'copy', 'encodeWithCoder:', 'privateDelegate']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			pool := api.pool(); cls := api.cls('UNUserNotificationCenter')
			if mode.starts_with('constructor-') {
				assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(center_constructor) }), c'@16@0:8')
				center_callback_mode = mode.all_after('constructor-')
			}
			object := api.msg(cls, c'currentNotificationCenter', 0, 0)
			match mode {
				'new' { api.msg(cls, c'new', 0, 0) }
				'init' { api.msg(objc_allocate(cls), c'init', 0, 0) }
				'raw' { api.msg(objc_allocate(cls), c'delegate', 0, 0) }
				'caller' { mut storage := [5]u64{}; api.msg(objc_construct_instance(cls, u64(unsafe { &storage[0] })), c'delegate', 0, 0) }
				'spoof' { fake := objc_new(api.cls('NSObject')); objc_set_class(fake, cls); api.msg(fake, c'delegate', 0, 0) }
				'isa', 'copy-isa' { objc_set_class(object, api.cls('NSObject')); if mode == 'copy-isa' { objc_copy_value(object, false) } else { api.msg(object, c'delegate', 0, 0) } }
				'subclass', 'caller-subclass', 'factory-subclass' { custom := objc_allocate_class(cls, c'UnsupportedCenter', 0); objc_register_class(custom); if mode == 'caller-subclass' { mut storage := [5]u64{}; objc_construct_instance(custom, u64(unsafe { &storage[0] })) } else if mode == 'factory-subclass' { api.msg(custom, c'currentNotificationCenter', 0, 0) } else { objc_allocate(custom) } }
				'destruct', 'destruct-isa' { if mode == 'destruct-isa' { objc_set_class(object, api.cls('NSObject')) }; objc_destruct_instance(object) }
				'dealloc' { objc_release(object) }
				'body' { unsafe { *(&u64(object + 24)) = 1 }; api.msg(object, c'delegate', 0, 0) }
				'weak-body' { unsafe { *(&u64(object + 8)) = 1 }; api.msg(object, c'delegate', 0, 0) }
				'stopped' { un_center_stop(); api.msg(cls, c'currentNotificationCenter', 0, 0) }
				else { if !mode.starts_with('constructor-') { api.msg(object, mode.str, 0, 0) } }
			}
			api.pop(pool); C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }
		assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	println('IOS-UN-CENTER-REJECT: ' + modes.len.str() + ' storage, constructors, shutdown, copies, services and unsupported API cases PASS')
}
