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
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceVariable(voidptr, &char) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.objc_storeWeak(&u64, voidptr) voidptr

type TriggerSend = fn (u64, u64, u64, u64) u64
struct TriggerApi { native bool send u64 }
fn trigger_api() TriggerApi { return TriggerApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
fn (api TriggerApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api TriggerApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api TriggerApi) msg(object u64, name &char, a u64, b u64) u64 {
	return unsafe { TriggerSend(voidptr(api.send))(object, api.sel(name), a, b) }
}
fn (api TriggerApi) release(object u64) { api.msg(object, c'release', 0, 0) }
fn (api TriggerApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0, 0) } }
	return objc_pool_push()
}
fn (api TriggerApi) pop(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api TriggerApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api TriggerApi) weak_destroy(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api TriggerApi) create(components u64, repeats u64) u64 {
	return api.msg(api.cls('UNCalendarNotificationTrigger'), c'triggerWithDateMatchingComponents:repeats:', components, repeats)
}
fn trigger_metadata(api TriggerApi) {
	for index, name in ['UNNotificationTrigger', 'UNCalendarNotificationTrigger']! {
		cls := api.cls(name); parent := api.cls(if index == 0 { 'NSObject' } else { 'UNNotificationTrigger' })
		assert cls != 0
		ivar_name := if index == 0 { c'_repeats' } else { c'_dateComponents' }
		expected := if index == 0 { 'B' } else { '@"NSDateComponents"' }
		$if macos { if api.native {
			assert C.class_getInstanceSize(unsafe { voidptr(cls) }) == usize(16 + index * 8)
			assert u64(C.class_getSuperclass(unsafe { voidptr(cls) })) == parent
			ivar := C.class_getInstanceVariable(unsafe { voidptr(cls) }, ivar_name)
			assert C.ivar_getOffset(ivar) == 8 + index * 8
			assert unsafe { C.ivar_getTypeEncoding(ivar).vstring() } == expected
		} }
		if !api.native {
			assert objc_class_size(cls) == u64(16 + index * 8) && objc_class_parent(cls) == parent
			ivar := objc_find_ivar(cls, ivar_name)
			assert ivar != 0 && objc_ivar_offset(ivar) == i64(8 + index * 8)
			assert ctext(u64(objc_ivar_types(ivar))) == expected
		}
		for selector, encoding in {'repeats': 'B16@0:8', 'copyWithZone:': '@24@0:8^{_NSZone=}16'} {
			mut actual := ''
			$if macos { if api.native { method := C.class_getInstanceMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.sel(selector.str)) }); assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() } } }
			if !api.native { method := objc_instance_method(cls, u64(selector.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
			assert actual == encoding
		}
	}
	if !api.native {
		cls := api.cls('UNCalendarNotificationTrigger')
		assert ctext(u64(objc_method_types(objc_instance_method(read64(cls), u64(c'triggerWithDateMatchingComponents:repeats:'))))) == '@28@0:8@16B24'
		assert ctext(u64(objc_method_types(objc_instance_method(cls, u64(c'dateComponents'))))) == '@16@0:8'
	}
}
fn trigger_shared(api TriggerApi) {
	pool := api.pool(); trigger_metadata(api)
	mut input_weak := u64(0); mut stored_weak := u64(0); mut trigger_weak := u64(0)
	components := api.msg(api.cls('NSDateComponents'), c'new', 0, 0)
	api.weak(unsafe { &input_weak }, components)
	// Empty and partial date patterns are accepted; evaluation is separate.
	empty := api.create(components, 0)
	assert empty != 0 && api.msg(api.msg(empty, c'dateComponents', 0, 0), c'year', 0, 0) == 0x7fffffffffffffff
	api.msg(components, c'setYear:', 2026, 0); api.msg(components, c'setHour:', 7, 0)
	api.msg(components, c'setMonth:', 10, 0); api.msg(components, c'setDay:', 24, 0)
	api.msg(components, c'setMinute:', 31, 0); api.msg(components, c'setSecond:', 52, 0)
	calendar := api.msg(api.cls('NSCalendar'), c'currentCalendar', 0, 0)
	zone := api.msg(api.cls('NSTimeZone'), c'timeZoneForSecondsFromGMT:', 3600, 0)
	api.msg(components, c'setCalendar:', calendar, 0); api.msg(components, c'setTimeZone:', zone, 0)
	for repeats in [u64(0), 1, 2, 128, 255, 256, 257]! {
		object := api.create(components, repeats)
		assert object != 0 && api.msg(object, c'repeats', 0, 0) == (repeats & 1)
	}
	object := api.create(components, 0); stored := api.msg(object, c'dateComponents', 0, 0)
	api.weak(unsafe { &stored_weak }, stored); api.weak(unsafe { &trigger_weak }, object)
	assert stored != components && stored == api.msg(object, c'dateComponents', 0, 0)
	for selector, value in {'year': u64(2026), 'month': 10, 'day': 24, 'minute': 31, 'second': 52} {
		assert api.msg(stored, selector.str, 0, 0) == value
	}
	stored_calendar := api.msg(stored, c'calendar', 0, 0)
	assert stored_calendar != api.msg(components, c'calendar', 0, 0)
	api.msg(api.msg(components, c'calendar', 0, 0), c'setFirstWeekday:', 7, 0)
	assert api.msg(stored_calendar, c'firstWeekday', 0, 0) != 7
	assert api.msg(api.msg(stored, c'timeZone', 0, 0), c'secondsFromGMT', 0, 0) == 3600
	api.msg(components, c'setHour:', 8, 0)
	assert api.msg(stored, c'hour', 0, 0) == 7
	api.msg(stored, c'setHour:', 9, 0)
	assert api.msg(api.msg(object, c'dateComponents', 0, 0), c'hour', 0, 0) == 9 && api.msg(components, c'hour', 0, 0) == 8
	for selector in [c'copy', c'copyWithZone:']! { copy := api.msg(object, selector, 0, 0); assert copy == object; api.release(copy) }
	api.release(components); assert input_weak == 0 && stored_weak != 0
	api.pop(pool); assert stored_weak == 0 && trigger_weak == 0
	api.weak_destroy(unsafe { &input_weak }); api.weak_destroy(unsafe { &stored_weak }); api.weak_destroy(unsafe { &trigger_weak })
}

__global trigger_callback_mode = ''
__global trigger_callback_source = u64(0)
__global trigger_callback_fired = false
__global trigger_callback_weak = u64(0)
fn trigger_worker() {
	api := trigger_api()
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	api.msg(trigger_callback_source, c'setHour:', 23, 0)
	api.release(trigger_callback_source)
}
fn trigger_constructor(object u64, _selector &char) u64 {
	if trigger_callback_mode == '' || trigger_callback_fired { return object }
	trigger_callback_fired = true
	if trigger_callback_mode == 'isa' { objc_set_class(object, ios_runtime.names['NSObject']); return object }
	if trigger_callback_mode == 'state' { obj_header(object).un_trigger_initialized = true; return object }
	worker := spawn trigger_worker(); worker.wait()
	if trigger_callback_mode == 'fail' { objc_store_weak(unsafe { &trigger_callback_weak }, object); return 0 }
	return object
}
fn trigger_override(_object u64, _selector &char) u64 { return 99 }
fn trigger_components_constructor(object u64, _selector &char) u64 {
	if trigger_callback_mode != 'copy-fail' { return object }
	trigger_callback_fired = true
	objc_store_weak(unsafe { &trigger_callback_weak }, object)
	return 0
}
fn trigger_runtime_lifetimes(api TriggerApi) {
	pool := api.pool(); cls := api.cls('UNCalendarNotificationTrigger')
	inspection_pool := api.pool()
	inspection_source := api.msg(api.cls('NSDateComponents'), c'new', 0, 0)
	inspection := api.create(inspection_source, 0)
	api.release(inspection_source)
	for name in ['UNNotificationTrigger', 'UNCalendarNotificationTrigger']! {
		library := '/System/Library/Frameworks/UserNotifications.framework/UserNotifications'
		assert runtime_symbol(library, '_OBJC_CLASS_$_' + name) or { panic(err) } == api.cls(name)
		assert runtime_symbol(library, '_OBJC_METACLASS_$_' + name) or { panic(err) } == read64(api.cls(name))
	}
	for selector in [c'nextTriggerDate', c'encodeWithCoder:', c'mutableCopy', c'description', c'hash', c'isEqual:']! {
		assert objc_instance_method(cls, u64(selector)) == 0
		assert !objc_responds(cls, selector)
		assert !objc_responds(inspection, selector)
	}
	api.pop(inspection_pool)
	assert objc_add_method(api.cls('NSDateComponents'), u64(c'.cxx_construct'), u64(unsafe { voidptr(trigger_components_constructor) }), c'@16@0:8')
	copy_source := api.msg(api.cls('NSDateComponents'), c'new', 0, 0)
	trigger_callback_mode = 'copy-fail'; trigger_callback_fired = false
	assert api.create(copy_source, 0) == 0 && trigger_callback_fired && trigger_callback_weak == 0
	trigger_callback_mode = ''; api.weak_destroy(unsafe { &trigger_callback_weak }); api.release(copy_source)
	assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(trigger_constructor) }), c'@16@0:8')
	for mode in ['success', 'fail']! {
		inner := api.pool(); components := api.msg(api.cls('NSDateComponents'), c'new', 0, 0)
		api.msg(components, c'setHour:', 7, 0)
		mut weak := u64(0); api.weak(unsafe { &weak }, components)
		trigger_callback_source = components; trigger_callback_fired = false; trigger_callback_mode = mode
		result := api.create(components, 0); trigger_callback_mode = ''; trigger_callback_source = 0
		assert trigger_callback_fired && weak == 0
		if mode == 'success' { assert result != 0 && api.msg(api.msg(result, c'dateComponents', 0, 0), c'hour', 0, 0) == 7 }
		else { assert result == 0 && trigger_callback_weak == 0; api.weak_destroy(unsafe { &trigger_callback_weak }) }
		api.weak_destroy(unsafe { &weak }); api.pop(inner)
		assert ios_runtime.live == 2 && ios_runtime.objects.len == 2
	}
	// Storage provenance survives isa changes, including destructor cleanup.
	inner := api.pool(); components := api.msg(api.cls('NSDateComponents'), c'new', 0, 0)
	object := api.create(components, 0); stored := api.msg(object, c'dateComponents', 0, 0)
	mut weak := u64(0); api.weak(unsafe { &weak }, stored)
	objc_set_class(object, api.cls('NSObject')); api.release(components); api.pop(inner)
	assert weak == 0; api.weak_destroy(unsafe { &weak })
	mut guarded := [u64(0x1122334455667788), 0, 0, 0, 0x8877665544332211]!
	caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller
	objc_set_class(caller, api.cls('NSObject')); assert objc_destruct_instance(caller) == caller
	assert caller !in ios_runtime.objects && guarded[0] == 0x1122334455667788 && guarded[4] == 0x8877665544332211
	// Native application methods precede the unsupported-selector filter.
	assert objc_add_method(cls, u64(c'nextTriggerDate'), u64(unsafe { voidptr(trigger_override) }), c'@16@0:8')
	assert objc_instance_method(cls, u64(c'nextTriggerDate')) != 0
	components2 := api.msg(api.cls('NSDateComponents'), c'new', 0, 0)
	overridden := api.create(components2, 0)
	assert objc_responds(overridden, c'nextTriggerDate')
	assert api.msg(overridden, c'nextTriggerDate', 0, 0) == 99
	api.release(components2); api.pop(pool)
	assert ios_runtime.live == 2 && ios_runtime.objects.len == 2 && ios_runtime.weak.len == 0
}
fn test_un_calendar_trigger() {
	$if macos {
		native_send := C.dlsym(voidptr(i64(-2)), c'objc_msgSend'); assert native_send != unsafe { nil }
		trigger_shared(TriggerApi{true, u64(native_send)})
		println('IOS-UN-CALENDAR-NATIVE: metadata, BOOL ABI, snapshots, getter identity and weak ownership PASS')
	}
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!; api := trigger_api()
		trigger_shared(api); trigger_runtime_lifetimes(api)
		objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	}
	println('IOS-UN-CALENDAR: native parity, reentrant constructor success/failure, caller storage, isa cleanup, native override and two balanced lifetimes PASS')
}
fn test_un_calendar_trigger_rejections() {
	objc_start(); system_data_start()!; api := trigger_api()
	modes := ['nil', 'wrong', 'calendar', 'raw-components', 'components-isa', 'raw-trigger', 'spoof', 'trigger-isa', 'copy-isa', 'new', 'base-new', 'init', 'subclass', 'caller-subclass', 'nextTriggerDate', 'encodeWithCoder:', 'mutableCopy', 'description', 'copy-zone', 'constructor-isa', 'constructor-state']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			pool := api.pool(); cls := api.cls('UNCalendarNotificationTrigger'); components := api.msg(api.cls('NSDateComponents'), c'new', 0, 0)
			object := api.create(components, 0)
			match mode {
				'nil' { api.create(0, 0) }
				'wrong' { api.create(objc_new(api.cls('NSObject')), 0) }
				'calendar' { api.create(api.msg(api.cls('NSCalendar'), c'currentCalendar', 0, 0), 0) }
				'raw-components' { api.create(objc_allocate(api.cls('NSDateComponents')), 0) }
				'components-isa' { objc_set_class(components, api.cls('NSObject')); api.create(components, 0) }
				'raw-trigger' { api.msg(objc_allocate(cls), c'repeats', 0, 0) }
				'spoof' { fake := objc_new(api.cls('NSObject')); objc_set_class(fake, cls); api.msg(fake, c'repeats', 0, 0) }
				'trigger-isa', 'copy-isa' { objc_set_class(object, api.cls('NSObject')); if mode == 'copy-isa' { objc_copy_value(object, false) } else { api.msg(object, c'repeats', 0, 0) } }
				'new', 'base-new' { api.msg(if mode == 'base-new' { api.cls('UNNotificationTrigger') } else { cls }, c'new', 0, 0) }
				'init' { api.msg(objc_allocate(cls), c'init', 0, 0) }
				'subclass', 'caller-subclass' { custom := objc_allocate_class(cls, c'UnsupportedCalendarTrigger', 0); objc_register_class(custom); if mode == 'subclass' { objc_allocate(custom) } else { mut storage := [3]u64{}; objc_construct_instance(custom, u64(unsafe { &storage[0] })) } }
				'copy-zone' { api.msg(object, c'copyWithZone:', 1, 0) }
				'constructor-isa', 'constructor-state' { assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(trigger_constructor) }), c'@16@0:8'); trigger_callback_mode = if mode == 'constructor-isa' { 'isa' } else { 'state' }; trigger_callback_fired = false; api.create(components, 0) }
				else { api.msg(object, mode.str, 0, 0) }
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
	println('IOS-UN-CALENDAR-REJECT: ' + modes.len.str() + ' invalid inputs, uninitialized/default construction, provenance, unsupported APIs and constructor mutation PASS')
}
