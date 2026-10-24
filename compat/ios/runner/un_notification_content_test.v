// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

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
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceVariable(voidptr, &char) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.objc_storeWeak(&u64, voidptr) voidptr

type ContentSend = fn (u64, u64, u64, u64, u64) u64
type ContentDoubleGet = fn (u64, u64) f64
type ContentDoubleSet = fn (u64, u64, f64)
struct ContentApi { native bool send u64 }
fn content_api() ContentApi { return ContentApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
fn (api ContentApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api ContentApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api ContentApi) msg(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { ContentSend(voidptr(api.send))(object, api.sel(name), a, b, c) }
}
fn (api ContentApi) release(object u64) { api.msg(object, c'release', 0, 0, 0) }
fn (api ContentApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api ContentApi) pop(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api ContentApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api ContentApi) weak_destroy(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api ContentApi) string(value string, mutable bool) u64 {
	return api.msg(api.msg(api.cls(if mutable { 'NSMutableString' } else { 'NSString' }), c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(value.str), u64(value.len), 4)
}
fn (api ContentApi) text(object u64) string {
	assert object != 0
	length := api.msg(object, c'lengthOfBytesUsingEncoding:', 4, 0, 0)
	bytes := api.msg(object, c'UTF8String', 0, 0, 0); assert bytes != 0
	return if length == 0 { '' } else { unsafe { tos(&u8(voidptr(bytes)), int(length)) } }
}
fn (api ContentApi) score(object u64) f64 { return unsafe { ContentDoubleGet(voidptr(api.send))(object, api.sel(c'relevanceScore')) } }
fn (api ContentApi) set_score(object u64, value f64) { unsafe { ContentDoubleSet(voidptr(api.send))(object, api.sel(c'setRelevanceScore:'), value) } }

fn content_metadata(api ContentApi) {
	for name in ['UNNotificationContent', 'UNMutableNotificationContent']! {
		cls := api.cls(name); assert cls != 0
		parent := api.cls(if name == 'UNNotificationContent' { 'NSObject' } else { 'UNNotificationContent' })
		$if macos { if api.native {
			assert C.class_getInstanceSize(unsafe { voidptr(cls) }) == 296
			assert u64(C.class_getSuperclass(unsafe { voidptr(cls) })) == parent
		} }
		if !api.native { assert objc_class_size(cls) == 296 && objc_class_parent(cls) == parent }
		for i, property in un_content_properties() {
			key := '_' + property
			encoding := match i { 0 { '@"NSArray"' } 1 { '@"NSNumber"' } 5 { '@"UNNotificationSound"' } 11 { '@"NSDictionary"' } else { '@"NSString"' } }
			$if macos { if api.native {
				ivar := C.class_getInstanceVariable(unsafe { voidptr(cls) }, key.str)
				assert ivar != unsafe { nil } && C.ivar_getOffset(ivar) == isize(un_content_offsets()[i])
				assert unsafe { C.ivar_getTypeEncoding(ivar).vstring() } == encoding
			} }
			if !api.native {
				ivar := objc_find_ivar(cls, key.str); assert ivar != 0
				assert objc_ivar_offset(ivar) == i64(un_content_offsets()[i]) && ctext(u64(objc_ivar_types(ivar))) == encoding
			}
		}
		mut selectors := []string{}
		for property in un_content_properties() { selectors << property }
		selectors << ['init', 'copyWithZone:', 'mutableCopyWithZone:', 'summaryArgumentCount', 'interruptionLevel', 'relevanceScore']
		if name == 'UNMutableNotificationContent' { for setter in un_content_setters() { selectors << setter }; selectors << ['setSummaryArgumentCount:', 'setInterruptionLevel:', 'setRelevanceScore:'] }
		for selector in selectors {
			expected := un_content_types(name, false, selector) or { panic(selector) }
			mut actual := ''
			$if macos { if api.native {
				method := C.class_getInstanceMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.sel(selector.str)) })
				assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() }
			} }
			if !api.native { method := objc_instance_method(cls, u64(selector.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
			assert actual == expected, selector + ': ' + actual
		}
	}
}

fn content_shared(api ContentApi) {
	pool := api.pool(); content_metadata(api)
	for mutable in [false, true]! {
		object := api.msg(api.cls(if mutable { 'UNMutableNotificationContent' } else { 'UNNotificationContent' }), c'new', 0, 0, 0)
		for i, property in un_content_properties() {
			value := api.msg(object, property.str, 0, 0, 0)
			if i in [0, 11]! { assert value != 0 && api.msg(value, c'count', 0, 0, 0) == 0 }
			else if i in [3, 4, 7, 9]! { assert api.text(value) == '' }
			else { assert value == 0, property }
		}
		assert api.msg(object, c'summaryArgumentCount', 0, 0, 0) == 0 && api.msg(object, c'interruptionLevel', 0, 0, 0) == 1 && api.score(object) == 0
		for selector in [c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:']! {
			copy := api.msg(object, selector, 0, 0, 0); assert copy != 0
			is_mutable := unsafe { selector.vstring() }.starts_with('mutable')
			assert (copy == object) == (!mutable && !is_mutable)
			assert api.msg(copy, c'class', 0, 0, 0) == api.cls(if is_mutable { 'UNMutableNotificationContent' } else { 'UNNotificationContent' })
			api.release(copy)
		}
		api.release(object)
	}
	object := api.msg(api.cls('UNMutableNotificationContent'), c'new', 0, 0, 0)
	for i, property in un_content_properties() {
		if i in [0, 1, 5, 11]! { continue }
		for text in ['', 'notification text', 'é😀', 'a\x00' + 'b']! {
			input := api.string(text, true); api.msg(object, un_content_setters()[i].str, input, 0, 0)
			stored := api.msg(object, property.str, 0, 0, 0); assert stored != input && api.text(stored) == text
			early_copy := api.msg(object, c'copy', 0, 0, 0)
			early_mutable := api.msg(object, c'mutableCopy', 0, 0, 0)
			replacement := api.string('changed', false); api.msg(input, c'setString:', replacement, 0, 0); api.release(replacement); api.release(input)
			assert api.text(stored) == text
			assert api.text(api.msg(object, property.str, 0, 0, 0)) == if i in [4, 6]! { 'changed' } else { text }, property
			for early in [early_copy, early_mutable]! {
				assert api.text(api.msg(early, property.str, 0, 0, 0)) == text, property
				api.release(early)
			}
		}
	}
	for pair in [[c'setSummaryArgumentCount:', c'summaryArgumentCount']!, [c'setInterruptionLevel:', c'interruptionLevel']!]! {
		for value in [u64(0), 8, ~u64(0)]! { api.msg(object, pair[0], value, 0, 0); assert api.msg(object, pair[1], 0, 0, 0) == value }
	}
	for i, value in [f64(-1), 0.5, 2]! { api.set_score(object, value); assert api.score(object) == [f64(0), 0.5, 1]![i] }
	copy := api.msg(object, c'copy', 0, 0, 0)
	for i, setter in un_content_setters() {
		api.msg(object, setter.str, 0, 0, 0)
		value := api.msg(object, un_content_properties()[i].str, 0, 0, 0)
		if i == 0 { assert value != 0 && api.msg(value, c'count', 0, 0, 0) == 0 }
		else if i in [3, 4, 7]! { assert api.text(value) == '' }
		else { assert value == 0 }
		if i !in [0, 1, 5, 11]! { assert api.text(api.msg(copy, un_content_properties()[i].str, 0, 0, 0)) == if i in [4, 6]! { 'changed' } else { 'a\x00' + 'b' }, un_content_properties()[i] }
	}
	assert api.msg(copy, c'summaryArgumentCount', 0, 0, 0) == ~u64(0) && api.msg(copy, c'interruptionLevel', 0, 0, 0) == ~u64(0) && api.score(copy) == 1
	// The request owns an immutable snapshot, including after the input is released.
	input := api.string('request content survives the mutable source', true); api.msg(object, c'setTitle:', input, 0, 0); api.release(input)
	identifier := api.string('content-request', false)
	request := api.msg(api.cls('UNNotificationRequest'), c'requestWithIdentifier:content:trigger:', identifier, object, 0); api.release(identifier)
	stored := api.msg(request, c'content', 0, 0, 0)
	assert stored != 0 && stored != object && api.msg(stored, c'class', 0, 0, 0) == api.cls('UNNotificationContent')
	mut weak := u64(0); api.weak(unsafe { &weak }, stored)
	api.release(object); api.release(copy)
	assert api.text(api.msg(stored, c'title', 0, 0, 0)) == 'request content survives the mutable source'
	api.pop(pool); assert weak == 0; api.weak_destroy(unsafe { &weak })
}

__global content_callback_mode = ''
__global content_callback_fired = false
__global content_callback_source = u64(0)
__global content_callback_weak = u64(0)
fn content_worker() {
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	if content_callback_source != 0 {
		api := content_api(); replacement := api.string('changed in callback', false)
		api.msg(content_callback_source, c'setString:', replacement, 0, 0); api.release(replacement); api.release(content_callback_source)
	}
}
fn content_constructor(object u64, _selector &char) u64 {
	if content_callback_mode == '' || content_callback_fired { return object }
	content_callback_fired = true
	match content_callback_mode {
		'isa' { objc_set_class(object, ios_runtime.names['NSObject']); return object }
		'body' { unsafe { *(&u64(object + 24)) = 3 }; return object }
		'state' { obj_header(object).un_content.initialized = true; return object }
		else {}
	}
	worker := spawn content_worker(); worker.wait()
	if content_callback_mode == 'fail' { objc_store_weak(unsafe { &content_callback_weak }, object); return 0 }
	return object
}
fn content_override(_object u64, _selector &char) u64 { return 99 }
fn content_runtime(api ContentApi) {
	cls := api.cls('UNMutableNotificationContent'); base := api.cls('UNNotificationContent')
	for name in ['UNNotificationContent', 'UNMutableNotificationContent']! {
		library := '/System/Library/Frameworks/UserNotifications.framework/UserNotifications'
		assert runtime_symbol(library, '_OBJC_CLASS_$_' + name) or { panic(err) } == api.cls(name)
		assert runtime_symbol(library, '_OBJC_METACLASS_$_' + name) or { panic(err) } == read64(api.cls(name))
	}
	assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(content_constructor) }), c'@16@0:8')
	assert objc_add_method(api.cls('NSString'), u64(c'.cxx_construct'), u64(unsafe { voidptr(content_constructor) }), c'@16@0:8')
	for mode in ['success', 'fail']! {
		content_callback_source = 0; content_callback_fired = false; content_callback_mode = mode
		object := api.msg(cls, c'new', 0, 0, 0); content_callback_mode = ''
		assert content_callback_fired
		if mode == 'fail' { assert object == 0 && content_callback_weak == 0; api.weak_destroy(unsafe { &content_callback_weak }) }
		else { assert object != 0; api.release(object) }
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	object := api.msg(cls, c'new', 0, 0, 0)
	for selector in [c'supportsSecureCoding', c'initWithCoder:', c'encodeWithCoder:', c'description', c'hash', c'isEqual:', c'enterSecurityScope']! {
		assert objc_instance_method(cls, u64(selector)) == 0 && !objc_responds(object, selector)
	}
	immutable := api.msg(base, c'new', 0, 0, 0)
	assert !objc_responds(immutable, c'setTitle:') && objc_instance_method(base, u64(c'setTitle:')) == 0; api.release(immutable)
	// Source bytes must be snapshotted before the NSString constructor can reenter.
	input := api.string('snapshot before reentrant NSString construction', true)
	content_callback_source = input; content_callback_fired = false; content_callback_mode = 'success'
	api.msg(object, c'setTitle:', input, 0, 0); content_callback_mode = ''; content_callback_source = 0
	assert content_callback_fired && api.text(api.msg(object, c'title', 0, 0, 0)) == 'snapshot before reentrant NSString construction'
	pool := api.pool()
	for i in [4, 6]! {
		property := un_content_properties()[i]
		for copying in [false, true]! {
			source := api.string('retained input before constructor', true)
			api.msg(object, un_content_setters()[i].str, source, 0, 0)
			content_callback_source = source; content_callback_fired = false; content_callback_mode = 'success'
			result := if copying { api.msg(object, c'copy', 0, 0, 0) } else { api.msg(object, property.str, 0, 0, 0) }
			content_callback_mode = ''; content_callback_source = 0
			assert content_callback_fired
			assert api.text(if copying { api.msg(result, property.str, 0, 0, 0) } else { result }) == 'retained input before constructor'
			assert api.text(api.msg(object, property.str, 0, 0, 0)) == 'changed in callback'
			if copying { api.release(result) }
		}
		for selector in [property, 'copy', 'mutableCopy']! {
			before := ios_runtime.live
			content_callback_fired = false; content_callback_mode = 'fail'
			assert api.msg(object, selector.str, 0, 0, 0) == 0
			content_callback_mode = ''
			assert content_callback_fired && content_callback_weak == 0 && ios_runtime.live == before
			api.weak_destroy(unsafe { &content_callback_weak })
		}
	}
	api.pop(pool)
	associated := objc_copy_value(object, false); assert associated != object && objc_is_kind(associated, base); api.release(associated)
	mut weak := u64(0); api.weak(unsafe { &weak }, api.msg(object, c'title', 0, 0, 0))
	objc_set_class(object, api.cls('NSObject')); api.release(object); assert weak == 0; api.weak_destroy(unsafe { &weak })
	mut guarded := [39]u64{}; guarded[0] = 0x1122334455667788; guarded[38] = 0x8877665544332211
	caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller
	assert api.msg(caller, c'init', 0, 0, 0) == caller
	assert objc_destruct_instance(caller) == caller && caller !in ios_runtime.objects
	assert guarded[0] == 0x1122334455667788 && guarded[38] == 0x8877665544332211
	assert objc_add_method(cls, u64(c'description'), u64(unsafe { voidptr(content_override) }), c'@16@0:8')
	overridden := api.msg(cls, c'new', 0, 0, 0); assert objc_responds(overridden, c'description') && api.msg(overridden, c'description', 0, 0, 0) == 99; api.release(overridden)
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
}
fn test_un_notification_content() {
	$if macos {
		native_send := C.dlsym(voidptr(i64(-2)), c'objc_msgSend'); assert native_send != unsafe { nil }
		content_shared(ContentApi{true, u64(native_send)})
		println('IOS-UN-CONTENT-NATIVE: layout, encodings, defaults, nil normalization, UTF8 snapshots, scalar bounds, copy classes and request ownership PASS')
	}
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!; api := content_api(); content_shared(api); content_runtime(api)
		objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	}
	println('IOS-UN-CONTENT: native parity, reentrant constructors, caller storage, isa cleanup, associated copies, native overrides and two balanced lifetimes PASS')
}
fn test_un_notification_content_rejections() {
	objc_start(); system_data_start()!; api := content_api()
	modes := ['raw', 'spoof', 'isa', 'body', 'scalar', 'reinit', 'immutable', 'copy-zone', 'mutable-zone', 'subclass', 'caller-subclass', 'badge', 'sound', 'attachments', 'userInfo', 'wrong-string', 'raw-string', 'oversize', 'invalid-utf8', 'nan', 'request-raw', 'request-isa', 'constructor-isa', 'constructor-body', 'constructor-state', 'encodeWithCoder:', 'description', 'enterSecurityScope']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			cls := api.cls('UNMutableNotificationContent'); object := api.msg(cls, c'new', 0, 0, 0)
			match mode {
				'raw' { api.msg(objc_allocate(cls), c'title', 0, 0, 0) }
				'spoof' { fake := objc_new(api.cls('NSObject')); objc_set_class(fake, cls); api.msg(fake, c'title', 0, 0, 0) }
				'isa' { objc_set_class(object, api.cls('NSObject')); api.msg(object, c'title', 0, 0, 0) }
				'body' { unsafe { *(&u64(object + 184)) = 1 }; api.msg(object, c'title', 0, 0, 0) }
				'scalar' { unsafe { *(&u64(object + 248)) = 3 }; api.msg(object, c'interruptionLevel', 0, 0, 0) }
				'reinit' { api.msg(object, c'init', 0, 0, 0) }
				'immutable' { api.msg(api.msg(api.cls('UNNotificationContent'), c'new', 0, 0, 0), c'setTitle:', 0, 0, 0) }
				'copy-zone' { api.msg(object, c'copyWithZone:', 1, 0, 0) }
				'mutable-zone' { api.msg(object, c'mutableCopyWithZone:', 1, 0, 0) }
				'subclass', 'caller-subclass' { custom := objc_allocate_class(cls, c'UnsupportedContent', 0); objc_register_class(custom); if mode == 'subclass' { objc_allocate(custom) } else { mut storage := [37]u64{}; objc_construct_instance(custom, u64(unsafe { &storage[0] })) } }
				'badge', 'sound' { api.msg(object, if mode == 'badge' { c'setBadge:' } else { c'setSound:' }, objc_new(api.cls('NSObject')), 0, 0) }
				'attachments', 'userInfo' {
					collection := objc_new(api.cls(if mode == 'attachments' { 'NSMutableArray' } else { 'NSMutableDictionary' }))
					obj_header(collection).items << owned_string('nonempty')
					api.msg(object, if mode == 'attachments' { c'setAttachments:' } else { c'setUserInfo:' }, collection, 0, 0)
				}
				'wrong-string' { api.msg(object, c'setTitle:', objc_new(api.cls('NSObject')), 0, 0) }
				'raw-string' { api.msg(object, c'setTitle:', objc_allocate(api.cls('NSMutableString')), 0, 0) }
				'oversize' { api.msg(object, c'setTitle:', api.string('x'.repeat(65537), false), 0, 0) }
				'invalid-utf8' { api.msg(object, c'setTitle:', owned_string('\xff'), 0, 0) }
				'nan' { api.set_score(object, bits.f64_from_bits(0x7ff8000000000000)) }
				'request-raw', 'request-isa' {
					value := if mode == 'request-raw' { objc_allocate(cls) } else { objc_set_class(object, api.cls('NSObject')); object }
					api.msg(api.cls('UNNotificationRequest'), c'requestWithIdentifier:content:trigger:', api.string('id', false), value, 0)
				}
				'constructor-isa', 'constructor-body', 'constructor-state' {
					assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(content_constructor) }), c'@16@0:8')
					content_callback_mode = mode.all_after('constructor-'); content_callback_fired = false; api.msg(cls, c'new', 0, 0, 0)
				}
				else { api.msg(object, mode.str, 0, 0, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }
		assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	println('IOS-UN-CONTENT-REJECT: ' + modes.len.str() + ' invalid values, provenance, constructors, copies and unsupported API cases PASS')
}
