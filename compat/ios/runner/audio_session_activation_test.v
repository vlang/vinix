// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <dlfcn.h>
	fn C.objc_getClass(&char) voidptr
	fn C.sel_registerName(&char) voidptr
	fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
	fn C.class_getClassMethod(voidptr, voidptr) voidptr
	fn C.method_getTypeEncoding(voidptr) &char
	fn C.method_getImplementation(voidptr) voidptr
	fn C.dlopen(&char, int) voidptr
}

type SessionActivationSetter = fn (u64, u64, bool, &u64) bool

fn session_activation_msg(object u64, selector &char, argument u64, output u64) u64 {
	mut frame := RegisterFrame{}
	frame.x[0] = object; frame.x[1] = u64(selector)
	frame.x[2] = argument; frame.x[3] = output
	assert objc_dispatch(mut frame, 0) == 0
	return frame.x[0]
}

fn session_activation_error(error_object u64) {
	assert error_object != 0 && objc_is_kind(error_object, ios_runtime.names['NSError'])
	assert string_text(session_activation_msg(error_object, c'domain', 0, 0)) == 'NSOSStatusErrorDomain'
	assert session_activation_msg(error_object, c'code', 0, 0) == 561145203
}

fn session_activation_worker(session u64) {
	for _ in 0 .. 256 {
		pool := objc_pool_push()
		mut error_object := u64(0x12345678)
		assert session_activation_msg(session, c'setActive:error:', 0, u64(&error_object)) == 1
		assert error_object == 0x12345678
		assert session_activation_msg(session, c'setActive:error:', 1, u64(&error_object)) == 0
		session_activation_error(error_object)
		objc_pool_pop(pool)
	}
}

fn test_audio_session_activation() {
	selector := c'setActive:error:'
	types := 'B28@0:8B16^@20'
	$if macos {
		assert C.dlopen(c'/System/Library/Frameworks/AVFAudio.framework/AVFAudio', 2) != unsafe { nil }
		cls := C.objc_getClass(c'AVAudioSession')
		assert cls != unsafe { nil }
		name := C.sel_registerName(selector)
		method := C.class_getInstanceMethod(cls, name)
		assert method != unsafe { nil } && C.method_getImplementation(method) != unsafe { nil }
		assert ctext(u64(C.method_getTypeEncoding(method))) == types
		assert C.class_getClassMethod(cls, name) == unsafe { nil }
		println('IOS-AUDIO-ACTIVATION-NATIVE: instance-only BOOL setter and NSError metadata PASS; native audio-server calls unverified')
	}
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		cls := ios_runtime.names['AVAudioSession']
		session := session_activation_msg(cls, c'sharedInstance', 0, 0)
		method := objc_instance_method(cls, u64(selector))
		assert method != 0 && ctext(u64(objc_method_types(method))) == types
		assert objc_instance_method(read64(cls), u64(selector)) == 0
		assert session_activation_msg(session, c'respondsToSelector:', u64(selector), 0) == 1
		assert session_activation_msg(cls, c'respondsToSelector:', u64(selector), 0) == 0
		for missing in [c'setActive:', c'setActive:withOptions:error:', c'vinixMissingAudioQuery']! {
			assert session_activation_msg(session, c'respondsToSelector:', u64(missing), 0) == 0
		}
		signature := session_activation_msg(session, c'methodSignatureForSelector:', u64(selector), 0)
		assert session_activation_msg(signature, c'numberOfArguments', 0, 0) == 4
		assert session_activation_msg(signature, c'methodReturnLength', 0, 0) == 1
		assert ctext(session_activation_msg(signature, c'getArgumentTypeAtIndex:', 2, 0)) == 'B'
		assert ctext(session_activation_msg(signature, c'getArgumentTypeAtIndex:', 3, 0)) == '^@'
		category := owned_string('AVAudioSessionCategoryPlayback')
		mode := owned_string('AVAudioSessionModeDefault')
		assert audio_session_set_configuration(session, category, mode, 2, 0)
		assert session_activation_msg(session, c'setAllowHapticsAndSystemSoundsDuringRecording:error:', 1, 0) == 1
		for value in [u64(0), 1, u64(1) << 32, u64(1) << 32 | 1] {
			local_pool := objc_pool_push()
			mut error_object := u64(0x12345678)
			assert session_activation_msg(session, selector, value, u64(&error_object)) == u64(u8(value) == 0)
			if u8(value) == 0 { assert error_object == 0x12345678 }
			else { session_activation_error(error_object) }
			assert session_activation_msg(session, selector, value, 0) == u64(u8(value) == 0)
			objc_pool_pop(local_pool)
		}
		// Direct IMP callers receive a real autoreleased NSError on failure.
		imp := objc_method_imp(method)
		local_pool := objc_pool_push()
		mut error_object := u64(0)
		assert !unsafe { SessionActivationSetter(voidptr(imp))(session, u64(selector), true, &error_object) }
		session_activation_error(error_object)
		retained_error := objc_retain(error_object)
		assert unsafe { SessionActivationSetter(voidptr(imp))(session, u64(selector), false, &error_object) }
		assert error_object == retained_error
		objc_pool_pop(local_pool)
		session_activation_error(retained_error)
		objc_release(retained_error)
		live := ios_runtime.live
		refs := obj_header(session).refs
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn session_activation_worker(session) }
		workers.wait()
		unsafe { workers.free() }
		assert ios_runtime.live == live && obj_header(session).refs == refs
		assert string_text(session_activation_msg(session, c'category', 0, 0)) == 'AVAudioSessionCategoryPlayback'
		assert string_text(session_activation_msg(session, c'mode', 0, 0)) == 'AVAudioSessionModeDefault'
		assert session_activation_msg(session, c'categoryOptions', 0, 0) == 3
		assert session_activation_msg(session, c'allowHapticsAndSystemSoundsDuringRecording', 0, 0) == 1
		assert session_activation_msg(session, c'isOtherAudioPlaying', 0, 0) == 0
		// Both configuration errors and activation failures use the same domain.
		assert !audio_session_set_configuration(session, 0, mode, 0, u64(&error_object))
		assert i64(session_activation_msg(error_object, c'code', 0, 0)) == -50
		assert string_text(session_activation_msg(error_object, c'domain', 0, 0)) == 'NSOSStatusErrorDomain'
		objc_release(category); objc_release(mode)
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-AUDIO-ACTIVATION: unavailable activation NSError, idempotent deactivation, BOOL ABI, nil output, retained error lifetime, unchanged configuration, eight workers and two drained runtimes PASS')
}
