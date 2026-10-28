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

type SessionHapticsSetter = fn (u64, u64, bool, &u64) bool
type SessionHapticsGetter = fn (u64, u64) bool

fn session_haptics_msg(object u64, selector &char, argument u64, output u64) u64 {
	mut frame := RegisterFrame{}
	frame.x[0] = object; frame.x[1] = u64(selector)
	frame.x[2] = argument; frame.x[3] = output
	assert objc_dispatch(mut frame, 0) == 0
	return frame.x[0]
}

fn session_haptics_worker(session u64, value u64) {
	for _ in 0 .. 256 {
		mut error_object := u64(0x12345678)
		assert session_haptics_msg(session, c'setAllowHapticsAndSystemSoundsDuringRecording:error:', value, u64(&error_object)) == 1
		assert error_object == 0x12345678
		assert session_haptics_msg(session, c'allowHapticsAndSystemSoundsDuringRecording', 0, 0) in [u64(0), 1]
	}
}

fn test_audio_session_haptics() {
	selectors := [c'setAllowHapticsAndSystemSoundsDuringRecording:error:', c'allowHapticsAndSystemSoundsDuringRecording']!
	types := ['B28@0:8B16^@20', 'B16@0:8']!
	$if macos {
		assert C.dlopen(c'/System/Library/Frameworks/AVFAudio.framework/AVFAudio', 2) != unsafe { nil }
		cls := C.objc_getClass(c'AVAudioSession')
		assert cls != unsafe { nil }
		for i, name in selectors {
			selector := C.sel_registerName(name)
			method := C.class_getInstanceMethod(cls, selector)
			assert method != unsafe { nil } && C.method_getImplementation(method) != unsafe { nil }
			assert ctext(u64(C.method_getTypeEncoding(method))) == types[i]
			assert C.class_getClassMethod(cls, selector) == unsafe { nil }
		}
		println('IOS-AUDIO-HAPTICS-NATIVE: instance-only BOOL setter/getter and NSError metadata PASS; native audio-server calls unverified')
	}
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		cls := ios_runtime.names['AVAudioSession']
		session := session_haptics_msg(cls, c'sharedInstance', 0, 0)
		assert session_haptics_msg(session, selectors[1], 0, 0) == 0
		for i, selector in selectors {
			method := objc_instance_method(cls, u64(selector))
			assert method != 0 && ctext(u64(objc_method_types(method))) == types[i]
			assert objc_instance_method(read64(cls), u64(selector)) == 0
			assert session_haptics_msg(session, c'respondsToSelector:', u64(selector), 0) == 1
			assert session_haptics_msg(cls, c'respondsToSelector:', u64(selector), 0) == 0
		}
		for missing in [c'setAllowHapticsAndSystemSoundsDuringRecording:', c'vinixMissingAudioQuery']! {
			assert session_haptics_msg(session, c'respondsToSelector:', u64(missing), 0) == 0
		}
		signature := session_haptics_msg(session, c'methodSignatureForSelector:', u64(selectors[0]), 0)
		assert session_haptics_msg(signature, c'numberOfArguments', 0, 0) == 4
		assert session_haptics_msg(signature, c'methodReturnLength', 0, 0) == 1
		assert ctext(session_haptics_msg(signature, c'getArgumentTypeAtIndex:', 2, 0)) == 'B'
		assert ctext(session_haptics_msg(signature, c'getArgumentTypeAtIndex:', 3, 0)) == '^@'
		mut error_object := u64(0x12345678)
		for value in [u64(1), 0, u64(1) << 32 | 1, u64(1) << 32] {
			assert session_haptics_msg(session, selectors[0], value, u64(&error_object)) == 1
			assert error_object == 0x12345678
			assert session_haptics_msg(session, selectors[1], 0, 0) == u64(u8(value) != 0)
		}
		setter := objc_method_imp(objc_instance_method(cls, u64(selectors[0])))
		getter := objc_method_imp(objc_instance_method(cls, u64(selectors[1])))
		assert unsafe { SessionHapticsSetter(voidptr(setter))(session, u64(selectors[0]), true, &error_object) }
		assert unsafe { SessionHapticsGetter(voidptr(getter))(session, u64(selectors[1])) }
		assert error_object == 0x12345678
		// Category changes and errors must preserve the independent policy.
		category := owned_string('AVAudioSessionCategoryPlayback')
		mode := owned_string('AVAudioSessionModeDefault')
		assert audio_session_set_configuration(session, category, mode, 2, 0)
		assert !audio_session_set_configuration(session, 0, mode, 0, 0)
		assert session_haptics_msg(session, selectors[1], 0, 0) == 1
		assert session_haptics_msg(session, c'categoryOptions', 0, 0) == 3
		live := ios_runtime.live
		refs := obj_header(session).refs
		mut workers := []thread{}
		for i in 0 .. 8 { workers << spawn session_haptics_worker(session, u64(i & 1)) }
		workers.wait()
		unsafe { workers.free() }
		assert ios_runtime.live == live && obj_header(session).refs == refs
		assert session_haptics_msg(session, selectors[0], 0, 0) == 1
		assert session_haptics_msg(session, selectors[1], 0, 0) == 0
		assert session_haptics_msg(session, c'categoryOptions', 0, 0) == 3
		objc_release(category); objc_release(mode)
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-AUDIO-HAPTICS: inactive policy, default false, BOOL ABI, untouched NSError, configuration independence, eight workers and two drained runtimes PASS')
}
