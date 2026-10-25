// SPDX-License-Identifier: GPL-2.0-or-later
module main

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
	for _ in 0 .. 2 {
		system_data_start() or { panic(err) }; objc_start(); pool := objc_pool_push()
		feedback_runtime()
		objc_pool_pop(pool); objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
		system_data_stop()
	}
	println('IOS-FEEDBACK: UIKit imports, hierarchy, instance-only object/void/integer/double ABI, reflection, guarded storage, all five impact styles, concurrent no-op requests, subclass overrides and two balanced shutdown cycles PASS')
}
