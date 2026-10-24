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

type RequestSend = fn (u64, u64, u64, u64, u64) u64
struct RequestApi { native bool send u64 }
fn request_api() RequestApi { return RequestApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
fn (api RequestApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api RequestApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api RequestApi) msg(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { RequestSend(voidptr(api.send))(object, api.sel(name), a, b, c) }
}
fn (api RequestApi) release(object u64) { api.msg(object, c'release', 0, 0, 0) }
fn (api RequestApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api RequestApi) pop(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api RequestApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api RequestApi) weak_destroy(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api RequestApi) string(value string, mutable bool) u64 {
	return api.msg(api.msg(api.cls(if mutable { 'NSMutableString' } else { 'NSString' }), c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(value.str), u64(value.len), 4)
}
fn (api RequestApi) text(object u64) string {
	assert object != 0
	length := api.msg(object, c'lengthOfBytesUsingEncoding:', 4, 0, 0)
	bytes := api.msg(object, c'UTF8String', 0, 0, 0); assert bytes != 0
	return if length == 0 { '' } else { unsafe { tos(&u8(voidptr(bytes)), int(length)) } }
}
fn (api RequestApi) trigger() u64 {
	components := api.msg(api.cls('NSDateComponents'), c'new', 0, 0, 0)
	api.msg(components, c'setHour:', 7, 0, 0)
	result := api.msg(api.cls('UNCalendarNotificationTrigger'), c'triggerWithDateMatchingComponents:repeats:', components, 1, 0)
	api.release(components)
	return result
}
fn (api RequestApi) create(identifier u64, trigger u64) u64 {
	return api.msg(api.cls('UNNotificationRequest'), c'requestWithIdentifier:content:trigger:', identifier, 0, trigger)
}
fn request_metadata(api RequestApi) {
	cls := api.cls('UNNotificationRequest'); assert cls != 0
	$if macos { if api.native {
		assert C.class_getInstanceSize(unsafe { voidptr(cls) }) == 40
		assert u64(C.class_getSuperclass(unsafe { voidptr(cls) })) == api.cls('NSObject')
	} }
	if !api.native { assert objc_class_size(cls) == 40 && objc_class_parent(cls) == api.cls('NSObject') }
	for index, pair in [['_content', '@"UNNotificationContent"']!, ['_trigger', '@"UNNotificationTrigger"']!, ['_destinations', 'Q']!, ['_identifier', '@"NSString"']!]! {
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
	for name, encoding in {'identifier': '@16@0:8', 'content': '@16@0:8', 'trigger': '@16@0:8', 'copyWithZone:': '@24@0:8^{_NSZone=}16', 'requestWithIdentifier:content:trigger:': '@40@0:8@16@24@32'} {
		factory := name == 'requestWithIdentifier:content:trigger:'
		mut actual := ''
		$if macos { if api.native {
			method := if factory { C.class_getClassMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.sel(name.str)) }) } else { C.class_getInstanceMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.sel(name.str)) }) }
			assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() }
		} }
		if !api.native {
			method := objc_instance_method(if factory { read64(cls) } else { cls }, u64(name.str)); assert method != 0
			actual = ctext(u64(objc_method_types(method)))
		}
		assert actual == encoding
	}
}
fn request_shared(api RequestApi) {
	pool := api.pool(); request_metadata(api)
	for value in ['', 'message-identifier', 'é😀', 'a\x00' + 'b']! {
		for mutable in [false, true]! {
			identifier := api.string(value, mutable)
			object := api.create(identifier, 0)
			stored := api.msg(object, c'identifier', 0, 0, 0)
			assert object != 0 && api.text(stored) == value && stored == api.msg(object, c'identifier', 0, 0, 0)
			assert api.msg(object, c'content', 0, 0, 0) == 0 && api.msg(object, c'trigger', 0, 0, 0) == 0
			if mutable {
				assert stored != identifier
				replacement := api.string('changed', false); api.msg(identifier, c'setString:', replacement, 0, 0); api.release(replacement)
				assert api.text(stored) == value
			}
			api.release(identifier)
			for selector in [c'copy', c'copyWithZone:']! { copy := api.msg(object, selector, 0, 0, 0); assert copy == object; api.release(copy) }
		}
	}
	// Drain the trigger's factory pool so the request is its only remaining owner.
	inner := api.pool(); trigger := api.trigger(); api.msg(trigger, c'retain', 0, 0, 0); api.pop(inner)
	identifier := api.string('a sufficiently long mutable notification identifier', true)
	mut input_weak := u64(0); mut id_weak := u64(0); mut trigger_weak := u64(0); mut object_weak := u64(0)
	api.weak(unsafe { &input_weak }, identifier); api.weak(unsafe { &trigger_weak }, trigger)
	object := api.create(identifier, trigger); stored := api.msg(object, c'identifier', 0, 0, 0)
	api.weak(unsafe { &id_weak }, stored); api.weak(unsafe { &object_weak }, object)
	api.release(identifier); api.release(trigger)
	assert input_weak == 0 && id_weak != 0 && trigger_weak != 0
	assert api.msg(object, c'trigger', 0, 0, 0) == trigger && api.msg(trigger, c'repeats', 0, 0, 0) == 1
	assert api.msg(api.msg(trigger, c'dateComponents', 0, 0, 0), c'hour', 0, 0, 0) == 7
	api.pop(pool); assert id_weak == 0 && trigger_weak == 0 && object_weak == 0
	api.weak_destroy(unsafe { &input_weak }); api.weak_destroy(unsafe { &id_weak }); api.weak_destroy(unsafe { &trigger_weak }); api.weak_destroy(unsafe { &object_weak })
}

__global request_callback_mode = ''
__global request_callback_source = u64(0)
__global request_callback_trigger = u64(0)
__global request_callback_fired = false
__global request_callback_weak = u64(0)
fn request_worker() {
	api := request_api()
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	replacement := api.string('mutated during construction', false)
	api.msg(request_callback_source, c'setString:', replacement, 0, 0); api.release(replacement)
	api.release(request_callback_source); api.release(request_callback_trigger)
}
fn request_constructor(object u64, _selector &char) u64 {
	if request_callback_mode == '' || request_callback_fired { return object }
	string_phase := obj_header(object).allocation_cls == ios_runtime.names['NSString']
	if string_phase != request_callback_mode.starts_with('string-') { return object }
	request_callback_fired = true
	match request_callback_mode {
		'isa' { objc_set_class(object, ios_runtime.names['NSObject']); return object }
		'state' { obj_header(object).un_request_initialized = true; return object }
		'body' { unsafe { *(&u64(object + 24)) = 3 }; return object }
		'string-isa' { objc_set_class(object, ios_runtime.names['NSObject']); return object }
		'trigger-isa' { objc_set_class(request_callback_trigger, ios_runtime.names['NSObject']); return object }
		else {}
	}
	worker := spawn request_worker(); worker.wait()
	if request_callback_mode.ends_with('-fail') { objc_store_weak(unsafe { &request_callback_weak }, object); return 0 }
	return object
}
fn request_override(_object u64, _selector &char) u64 { return 99 }
fn request_runtime_lifetimes(api RequestApi) {
	pool := api.pool(); cls := api.cls('UNNotificationRequest')
	library := '/System/Library/Frameworks/UserNotifications.framework/UserNotifications'
	assert runtime_symbol(library, '_OBJC_CLASS_$_UNNotificationRequest') or { panic(err) } == cls
	assert runtime_symbol(library, '_OBJC_METACLASS_$_UNNotificationRequest') or { panic(err) } == read64(cls)
	id := api.string('inspection', false); inspection_pool := api.pool(); inspection := api.create(id, 0)
	for selector in [c'encodeWithCoder:', c'mutableCopy', c'description', c'hash', c'isEqual:', c'destinations', c'enterSecurityScope']! {
		assert objc_instance_method(cls, u64(selector)) == 0 && !objc_responds(inspection, selector)
	}
	api.pop(inspection_pool); api.release(id)
	assert objc_add_method(api.cls('NSString'), u64(c'.cxx_construct'), u64(unsafe { voidptr(request_constructor) }), c'@16@0:8')
	assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(request_constructor) }), c'@16@0:8')
	for mode in ['string-success', 'string-fail', 'request-success', 'request-fail']! {
		inner := api.pool(); input := api.string('the identifier snapshot before constructor callbacks', true)
		trigger_pool := api.pool(); trigger := api.trigger(); api.msg(trigger, c'retain', 0, 0, 0); api.pop(trigger_pool)
		mut weak := u64(0); mut trigger_weak := u64(0)
		api.weak(unsafe { &weak }, input); api.weak(unsafe { &trigger_weak }, trigger)
		request_callback_source = input; request_callback_trigger = trigger; request_callback_mode = mode; request_callback_fired = false
		object := api.create(input, trigger); request_callback_mode = ''
		assert request_callback_fired && weak == 0
		if mode.ends_with('-success') {
			assert object != 0 && trigger_weak != 0 && api.msg(object, c'trigger', 0, 0, 0) == trigger
			assert api.text(api.msg(object, c'identifier', 0, 0, 0)) == 'the identifier snapshot before constructor callbacks'
		} else { assert object == 0 && trigger_weak == 0 && request_callback_weak == 0; api.weak_destroy(unsafe { &request_callback_weak }) }
		api.pop(inner); assert trigger_weak == 0
		api.weak_destroy(unsafe { &weak }); api.weak_destroy(unsafe { &trigger_weak })
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	// Destruction follows allocation provenance even after an isa change.
	inner := api.pool(); identifier := api.string('destruction of a copied identifier', true); trigger := api.trigger()
	object := api.create(identifier, trigger); mut id_weak := u64(0); mut trigger_weak := u64(0)
	api.weak(unsafe { &id_weak }, api.msg(object, c'identifier', 0, 0, 0)); api.weak(unsafe { &trigger_weak }, trigger)
	objc_set_class(object, api.cls('NSObject')); api.release(identifier); api.pop(inner)
	assert id_weak == 0 && trigger_weak == 0; api.weak_destroy(unsafe { &id_weak }); api.weak_destroy(unsafe { &trigger_weak })
	mut guarded := [u64(0x1122334455667788), 0, 0, 0, 0, 0, 0x8877665544332211]!
	caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller
	objc_set_class(caller, api.cls('NSObject')); assert objc_destruct_instance(caller) == caller
	assert caller !in ios_runtime.objects && guarded[0] == 0x1122334455667788 && guarded[6] == 0x8877665544332211
	assert objc_add_method(cls, u64(c'description'), u64(unsafe { voidptr(request_override) }), c'@16@0:8')
	assert objc_instance_method(cls, u64(c'description')) != 0
	identifier2 := api.string('override', false); overridden := api.create(identifier2, 0)
	assert objc_responds(overridden, c'description') && api.msg(overridden, c'description', 0, 0, 0) == 99
	api.release(identifier2); api.pop(pool)
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
}
fn test_un_notification_request() {
	$if macos {
		native_send := C.dlsym(voidptr(i64(-2)), c'objc_msgSend'); assert native_send != unsafe { nil }
		request_shared(RequestApi{true, u64(native_send)})
		println('IOS-UN-REQUEST-NATIVE: layout, encodings, identifier snapshots, nil content, trigger identity, self copies and weak ownership PASS')
	}
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!; api := request_api()
		request_shared(api); request_runtime_lifetimes(api)
		objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	}
	println('IOS-UN-REQUEST: native parity, reentrant success/failure at both constructors, caller storage, isa cleanup, native override and two balanced lifetimes PASS')
}
fn test_un_notification_request_rejections() {
	objc_start(); system_data_start()!; api := request_api()
	modes := ['nil-id', 'wrong-id', 'raw-mutable-id', 'id-isa', 'oversize', 'invalid-utf8', 'content', 'wrong-trigger', 'raw-trigger', 'trigger-isa', 'raw-request', 'spoof', 'request-isa', 'copy-isa', 'new', 'init', 'subclass', 'caller-subclass', 'copy-zone', 'encodeWithCoder:', 'description', 'destinations', 'private-factory', 'constructor-isa', 'constructor-state', 'constructor-body', 'constructor-string-isa', 'constructor-trigger-isa']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			pool := api.pool(); cls := api.cls('UNNotificationRequest'); identifier := api.string('identifier', true); trigger := api.trigger(); object := api.create(identifier, trigger)
			match mode {
				'nil-id' { api.create(0, 0) }
				'wrong-id' { api.create(objc_new(api.cls('NSObject')), 0) }
				'raw-mutable-id' { api.create(objc_allocate(api.cls('NSMutableString')), 0) }
				'id-isa' { objc_set_class(identifier, api.cls('NSObject')); api.create(identifier, 0) }
				'oversize' { api.create(api.string('x'.repeat(65537), false), 0) }
				'invalid-utf8' { bad := owned_string('\xff'); api.create(bad, 0) }
				'content' { api.msg(cls, c'requestWithIdentifier:content:trigger:', identifier, objc_new(api.cls('NSObject')), trigger) }
				'wrong-trigger' { api.create(identifier, objc_new(api.cls('NSObject'))) }
				'raw-trigger' { api.create(identifier, objc_allocate(api.cls('UNCalendarNotificationTrigger'))) }
				'trigger-isa' { objc_set_class(trigger, api.cls('NSObject')); api.create(identifier, trigger) }
				'raw-request' { api.msg(objc_allocate(cls), c'identifier', 0, 0, 0) }
				'spoof' { fake := objc_new(api.cls('NSObject')); objc_set_class(fake, cls); api.msg(fake, c'identifier', 0, 0, 0) }
				'request-isa', 'copy-isa' { objc_set_class(object, api.cls('NSObject')); if mode == 'copy-isa' { objc_copy_value(object, false) } else { api.msg(object, c'identifier', 0, 0, 0) } }
				'new' { api.msg(cls, c'new', 0, 0, 0) }
				'init' { api.msg(objc_allocate(cls), c'init', 0, 0, 0) }
				'subclass', 'caller-subclass' { custom := objc_allocate_class(cls, c'UnsupportedRequest', 0); objc_register_class(custom); if mode == 'subclass' { objc_allocate(custom) } else { mut storage := [5]u64{}; objc_construct_instance(custom, u64(unsafe { &storage[0] })) } }
				'copy-zone' { api.msg(object, c'copyWithZone:', 1, 0, 0) }
				'private-factory' { api.msg(cls, c'requestWithIdentifier:pushPayload:bundleIdentifier:', identifier, 0, 0) }
				'constructor-isa', 'constructor-state', 'constructor-body', 'constructor-string-isa', 'constructor-trigger-isa' {
					assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(request_constructor) }), c'@16@0:8')
					assert objc_add_method(api.cls('NSString'), u64(c'.cxx_construct'), u64(unsafe { voidptr(request_constructor) }), c'@16@0:8')
					request_callback_trigger = trigger; request_callback_mode = mode.all_after('constructor-'); request_callback_fired = false; api.create(identifier, trigger)
				}
				else { api.msg(object, mode.str, 0, 0, 0) }
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
	println('IOS-UN-REQUEST-REJECT: ' + modes.len.str() + ' invalid inputs, uninitialized/default construction, provenance, unsupported APIs and constructor mutation PASS')
}
