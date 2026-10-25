// SPDX-License-Identifier: GPL-2.0-or-later
module main

type FeedbackSend = fn (u64, u64, u64) u64

fn feedback_message(object u64, selector &char, value u64) u64 {
	return unsafe { FeedbackSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), value) }
}

__global feedback_override_calls int

fn feedback_override(_object u64, _selector u64, value u64) u64 {
	assert value == 2
	feedback_override_calls++
	return 0
}

fn feedback_repeat(object u64, selector &char) {
	for _ in 0 .. 1000 {
		feedback_message(object, c'prepare', 0)
		feedback_message(object, selector, 0)
		feedback_message(object, selector, 1)
		feedback_message(object, selector, 2)
	}
}

fn feedback_runtime() {
	library := '/System/Library/Frameworks/UIKit.framework/UIKit'
	base := ios_runtime.names['UIFeedbackGenerator']
	for name in ['UIFeedbackGenerator', 'UINotificationFeedbackGenerator', 'UISelectionFeedbackGenerator']! {
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
		for selector in [c'prepare', c'notificationOccurred:', c'selectionChanged']! {
			wanted := ctext(u64(selector)) == 'prepare' || (ctext(u64(selector)) == 'notificationOccurred:' && name == 'UINotificationFeedbackGenerator')
				|| (ctext(u64(selector)) == 'selectionChanged' && name == 'UISelectionFeedbackGenerator')
			assert objc_responds(object, selector) == wanted
			assert !objc_responds(cls, selector) && objc_class_method(cls, u64(selector)) == 0
			method := objc_instance_method(cls, u64(selector))
			assert (method != 0) == wanted
			if !wanted { continue }
			expected := if ctext(u64(selector)) == 'notificationOccurred:' { 'v24@0:8q16' } else { 'v16@0:8' }
			assert ctext(u64(objc_method_types(method))) == expected
			assert ctext(objc_method_name(method)) == ctext(u64(selector))
			signature := feedback_message(object, c'methodSignatureForSelector:', u64(selector)); assert signature != 0
			assert ctext(feedback_message(signature, c'methodReturnType', 0)) == 'v'
			assert feedback_message(signature, c'methodReturnLength', 0) == 0
			assert feedback_message(signature, c'numberOfArguments', 0) == if expected == 'v24@0:8q16' { u64(3) } else { u64(2) }
			if expected == 'v24@0:8q16' { assert ctext(feedback_message(signature, c'getArgumentTypeAtIndex:', 2)) == 'q' }
			unsafe { FeedbackSend(voidptr(objc_method_imp(method)))(object, u64(selector), 2) }
			mut guarded := [u64(0x12345678), 0, 0xabcdef12]!
			caller := objc_construct_instance(cls, u64(unsafe { &guarded[1] }))
			assert feedback_message(caller, c'init', 0) == caller
			feedback_message(caller, selector, 2)
			assert objc_destruct_instance(caller) == caller
			assert guarded == [u64(0x12345678), cls, 0xabcdef12]!
		}
		for selector in [c'copy', c'copyWithZone:', c'mutableCopy', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding']! {
			assert !objc_responds(object, selector) && objc_instance_method(cls, u64(selector)) == 0
		}
		selector := if name == 'UINotificationFeedbackGenerator' { c'notificationOccurred:' } else if name == 'UISelectionFeedbackGenerator' { c'selectionChanged' } else { c'prepare' }
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
	println('IOS-FEEDBACK: UIKit imports, hierarchy, instance-only void/integer ABI, reflection, guarded storage, concurrent no-op requests, subclass overrides and two balanced shutdown cycles PASS')
}
