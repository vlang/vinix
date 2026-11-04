// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.dlsym(voidptr, &char) voidptr
fn C.dlopen(&char, int) voidptr

type FeedbackSend = fn (u64, u64, u64) u64
type FeedbackIntensitySend = fn (u64, u64, f64)

fn feedback_invoke(imp u64, object u64, selector &char, value u64) u64 {
	if ctext(u64(selector)) == 'impactOccurredWithIntensity:' {
		unsafe { FeedbackIntensitySend(voidptr(imp))(object, u64(selector), f64(value) / 2) }
		return 0
	}
	return unsafe { FeedbackSend(voidptr(imp))(object, u64(selector), value) }
}

fn feedback_message(object u64, selector &char, value u64) u64 {
	return feedback_invoke(u64(unsafe { voidptr(C.ios_objc_msgsend) }), object, selector, value)
}

fn device_feedback_message(native bool, object u64, selector &char, value u64) u64 {
	$if macos { if native {
		return unsafe { FeedbackSend(C.dlsym(voidptr(-2), c'objc_msgSend'))(object, u64(C.sel_registerName(selector)), value) }
	} }
	return feedback_message(object, selector, value)
}

fn device_feedback_case(native bool, cls u64, number_cls u64, string_cls u64) {
	device := device_feedback_message(native, cls, c'currentDevice', 0)
	for text in ['_feedbackSupportLevel', 'feedbackSupportLevel']! {
		key := device_feedback_message(native, string_cls, c'stringWithUTF8String:', u64(text.str))
		value := device_feedback_message(native, device, c'valueForKey:', key)
		assert value != 0 && device_feedback_message(native, value, c'isKindOfClass:', number_cls) != 0;
		assert device_feedback_message(native, value, c'longLongValue', 0) == 0;
		assert device_feedback_message(native, value, c'intValue', 0) == 0;
		assert ctext(device_feedback_message(native, value, c'objCType', 0)) == 'q';
	}
	assert device_feedback_message(native, device, c'_feedbackSupportLevel', 0) == 0;
	for selector in [c'valueForKey:', c'_feedbackSupportLevel']! {
		mut types := ''
		$if macos { if native {
			method := C.class_getInstanceMethod(unsafe { voidptr(cls) }, C.sel_registerName(selector))
			assert method != unsafe { nil };
			types = unsafe { cstring_to_vstring(C.method_getTypeEncoding(method)) }
		} }
		if !native {
			assert objc_responds(device, selector) && !objc_responds(cls, selector);
			method := objc_instance_method(cls, u64(selector))
			assert method != 0 && objc_instance_method(ios_runtime.names['NSObject'], u64(selector)) == 0;
			types = ctext(u64(objc_method_types(method)))
		}
		assert types == if ctext(u64(selector)) == 'valueForKey:' { '@24@0:8@16' } else { 'q16@0:8' };
	}
}

fn device_feedback_override(_ u64, _ u64) u64 { return 2 }
fn device_feedback_worker(cls u64) {
	for _ in 0 .. 128 {
		pool := objc_pool_push()
		device_feedback_case(false, cls, ios_runtime.names['NSNumber'], ios_runtime.names['NSString'])
		objc_pool_pop(pool)
	}
}

fn device_feedback_runtime() {
	cls := ios_runtime.names['UIDevice']
	device_feedback_case(false, cls, ios_runtime.names['NSNumber'], ios_runtime.names['NSString'])
	device := feedback_message(cls, c'currentDevice', 0)
	subclass := objc_allocate_class(cls, c'VinixDeviceFeedbackFixture', 0)
	objc_register_class(subclass)
	assert objc_class_method(subclass, u64(c'valueForKey:')) == 0;
	key := objc_autorelease(owned_string('_feedbackSupportLevel'))
	object := objc_new(subclass)
	method := objc_instance_method(subclass, u64(c'valueForKey:'))
	assert method != 0;
	first := feedback_invoke(objc_method_imp(method), object, c'valueForKey:', key)
	assert feedback_message(first, c'longLongValue', 0) == 0;
	assert objc_add_method(subclass, u64(c'_feedbackSupportLevel'), u64(unsafe { voidptr(device_feedback_override) }), c'q16@0:8');
	second := feedback_message(object, c'valueForKey:', key)
	assert feedback_message(second, c'longLongValue', 0) == 2;
	assert feedback_message(device, c'_feedbackSupportLevel', 0) == 0;
	objc_release(object)
	mut workers := []thread{}
	for _ in 0 .. 4 { workers << spawn device_feedback_worker(cls) }
	workers.wait(); unsafe { workers.free() }
}

__global feedback_override_calls int

fn feedback_override(_object u64, _selector u64, value u64) u64 {
	assert value == 2
	feedback_override_calls++
	return 0
}

fn feedback_intensity_override(_object u64, _selector u64, intensity f64) {
	assert intensity == 0.5
	feedback_override_calls++
}

fn feedback_repeat(object u64, selector &char) {
	for _ in 0 .. 1000 {
		feedback_message(object, c'prepare', 0)
		feedback_message(object, selector, 0)
		feedback_message(object, selector, 1)
		feedback_message(object, selector, 2)
		if objc_is_kind(object, ios_runtime.names['UIImpactFeedbackGenerator']) {
			for value in 0 .. 3 { feedback_message(object, c'impactOccurredWithIntensity:', u64(value)) }
		}
	}
}

fn feedback_runtime() {
	library := '/System/Library/Frameworks/UIKit.framework/UIKit'
	base := ios_runtime.names['UIFeedbackGenerator']
	for name in ['UIFeedbackGenerator', 'UINotificationFeedbackGenerator', 'UISelectionFeedbackGenerator', 'UIImpactFeedbackGenerator']! {
		cls := ios_runtime.names[name]; assert cls != 0
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + name
			address := runtime_symbol(library, symbol) or { panic(err) }
			assert address == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/usr/lib/libobjc.A.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! {
				if _ := runtime_symbol(wrong, symbol) { assert false, wrong + ': ' + symbol }
			}
		}
		assert objc_class_parent(cls) == if cls == base { ios_runtime.names['NSObject'] } else { base }
		// This is the shim's minimal opaque storage, not a measured UIKit layout.
		assert objc_class_size(cls) == 8
		mut count := u32(99); ivars := objc_copy_ivars(cls, &count); C.free(ivars); assert count == 0
		object := feedback_message(cls, c'alloc', 0)
		assert feedback_message(object, c'init', 0) == object
		assert feedback_message(object, c'isKindOfClass:', base) != 0
		for selector in [c'prepare', c'notificationOccurred:', c'selectionChanged', c'initWithStyle:', c'impactOccurred', c'impactOccurredWithIntensity:']! {
			wanted := ctext(u64(selector)) == 'prepare' || (ctext(u64(selector)) == 'notificationOccurred:' && name == 'UINotificationFeedbackGenerator')
				|| (ctext(u64(selector)) == 'selectionChanged' && name == 'UISelectionFeedbackGenerator')
				|| (ctext(u64(selector)) in ['initWithStyle:', 'impactOccurred', 'impactOccurredWithIntensity:']! && name == 'UIImpactFeedbackGenerator')
			assert objc_responds(object, selector) == wanted
			assert !objc_responds(cls, selector) && objc_class_method(cls, u64(selector)) == 0
			method := objc_instance_method(cls, u64(selector))
			assert (method != 0) == wanted
			if !wanted { continue }
			expected := match ctext(u64(selector)) {
				'notificationOccurred:' { 'v24@0:8q16' }
				'initWithStyle:' { '@24@0:8q16' }
				'impactOccurredWithIntensity:' { 'v24@0:8d16' }
				else { 'v16@0:8' }
			}
			assert ctext(u64(objc_method_types(method))) == expected
			assert ctext(objc_method_name(method)) == ctext(u64(selector))
			signature := feedback_message(object, c'methodSignatureForSelector:', u64(selector)); assert signature != 0
			initializing := ctext(u64(selector)) == 'initWithStyle:'
			assert ctext(feedback_message(signature, c'methodReturnType', 0)) == if initializing { '@' } else { 'v' }
			assert feedback_message(signature, c'methodReturnLength', 0) == if initializing { u64(8) } else { u64(0) }
			assert feedback_message(signature, c'numberOfArguments', 0) == if expected == 'v16@0:8' { u64(2) } else { u64(3) }
			if expected != 'v16@0:8' { assert ctext(feedback_message(signature, c'getArgumentTypeAtIndex:', 2)) == if expected == 'v24@0:8d16' { 'd' } else { 'q' } }
			result := feedback_invoke(objc_method_imp(method), object, selector, 2)
			if initializing { assert result == object }
			mut guarded := [u64(0x12345678), 0, 0xabcdef12]!
			caller := objc_construct_instance(cls, u64(unsafe { &guarded[1] }))
			assert feedback_message(caller, c'init', 0) == caller
			caller_result := feedback_message(caller, selector, 2)
			if initializing { assert caller_result == caller }
			assert objc_destruct_instance(caller) == caller
			assert guarded == [u64(0x12345678), cls, 0xabcdef12]!
		}
		for selector in [c'copy', c'copyWithZone:', c'mutableCopy', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding']! {
			assert !objc_responds(object, selector) && objc_instance_method(cls, u64(selector)) == 0
		}
		if name == 'UIImpactFeedbackGenerator' {
			for style in 0 .. 5 {
				styled := feedback_message(cls, c'alloc', 0)
				assert feedback_message(styled, c'initWithStyle:', u64(style)) == styled
				feedback_message(styled, c'impactOccurred', 0)
				feedback_message(styled, c'release', 0)
				assert styled !in ios_runtime.objects
			}
		}
		selector := if name == 'UINotificationFeedbackGenerator' { c'notificationOccurred:' } else if name == 'UISelectionFeedbackGenerator' { c'selectionChanged' } else if name == 'UIImpactFeedbackGenerator' { c'impactOccurred' } else { c'prepare' }
		baseline := ios_runtime.live
		feedback_repeat(object, selector)
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn feedback_repeat(object, selector) }
		workers.wait()
		assert ios_runtime.live == baseline && ios_runtime.block_refs.len == 0
		feedback_message(object, c'release', 0)
		assert object !in ios_runtime.objects
	}
	cls := ios_runtime.names['UINotificationFeedbackGenerator']
	subclass := objc_allocate_class(cls, c'VinixNotificationFeedbackFixture', 0); assert subclass != 0
	objc_register_class(subclass)
	object := feedback_message(subclass, c'new', 0)
	assert objc_responds(object, c'prepare') && objc_responds(object, c'notificationOccurred:')
	feedback_message(object, c'prepare', 0); feedback_message(object, c'notificationOccurred:', 1)
	method := objc_instance_method(subclass, u64(c'notificationOccurred:')); saved := objc_method_imp(method)
	assert objc_add_method(subclass, u64(c'notificationOccurred:'), u64(unsafe { voidptr(feedback_override) }), c'v24@0:8q16')
	feedback_override_calls = 0
	feedback_message(object, c'notificationOccurred:', 2); assert feedback_override_calls == 1
	unsafe { FeedbackSend(voidptr(saved))(object, u64(c'notificationOccurred:'), 2) }
	assert feedback_override_calls == 1
	feedback_message(object, c'release', 0)
	impact_subclass := objc_allocate_class(ios_runtime.names['UIImpactFeedbackGenerator'], c'VinixImpactFeedbackFixture', 0)
	assert impact_subclass != 0; objc_register_class(impact_subclass)
	impact := feedback_message(impact_subclass, c'alloc', 0)
	assert feedback_message(impact, c'initWithStyle:', 4) == impact
	assert objc_responds(impact, c'prepare') && objc_responds(impact, c'impactOccurredWithIntensity:')
	impact_method := objc_instance_method(impact_subclass, u64(c'impactOccurredWithIntensity:'))
	impact_saved := objc_method_imp(impact_method)
	feedback_message(impact, c'impactOccurredWithIntensity:', 1)
	assert objc_add_method(impact_subclass, u64(c'impactOccurredWithIntensity:'), u64(unsafe { voidptr(feedback_intensity_override) }), c'v24@0:8d16')
	feedback_override_calls = 0
	feedback_message(impact, c'impactOccurredWithIntensity:', 1); assert feedback_override_calls == 1
	feedback_invoke(impact_saved, impact, c'impactOccurredWithIntensity:', 1)
	assert feedback_override_calls == 1
	feedback_message(impact, c'release', 0)
	assert !objc_responds(ios_runtime.names['NSObject'], c'prepare')
}

fn test_feedback_runtime() {
	$if macos {
		assert C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/UIKit.framework/UIKit', 2) != unsafe { nil };
		pool := device_feedback_message(true, u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
		device_feedback_case(true, u64(C.objc_getClass(c'UIDevice')), u64(C.objc_getClass(c'NSNumber')), u64(C.objc_getClass(c'NSString')))
		device_feedback_message(true, pool, c'drain', 0)
		println('IOS-DEVICE-FEEDBACK-NATIVE: both KVC keys, boxed q zero, private getter and method signatures PASS')
	}
	for _ in 0 .. 2 {
		system_data_start() or { panic(err) }; objc_start(); pool := objc_pool_push()
		feedback_runtime()
		device_feedback_runtime()
		objc_pool_pop(pool); objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
		system_data_stop()
	}
	println('IOS-FEEDBACK: UIKit imports, hierarchy, instance-only object/void/integer/double ABI, reflection, guarded storage, all five impact styles, concurrent no-op requests, subclass overrides and two balanced shutdown cycles PASS')
	println('IOS-DEVICE-FEEDBACK: scoped KVC capability lookup, NSNumber ownership, getter overrides, inherited IMPs, four concurrent readers and two clean lifetimes PASS')
}
