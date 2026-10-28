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

type SessionConfigurationSetter = fn (u64, u64, u64, u64, u64, &u64) bool

fn session_configuration_msg(object u64, selector &char, argument u64) u64 {
	mut frame := RegisterFrame{}
	frame.x[0] = object; frame.x[1] = u64(selector); frame.x[2] = argument
	assert objc_dispatch(mut frame, 0) == 0
	return frame.x[0]
}

fn session_configuration_set(object u64, category u64, mode u64, options u64, output u64) u64 {
	mut frame := RegisterFrame{}
	frame.x[0] = object; frame.x[1] = u64(c'setCategory:mode:options:error:')
	frame.x[2] = category; frame.x[3] = mode; frame.x[4] = options; frame.x[5] = output
	assert objc_dispatch(mut frame, 0) == 0
	return frame.x[0]
}

fn session_configuration_worker(session u64, category u64, mode u64, options u64) {
	for _ in 0 .. 256 {
		assert session_configuration_set(session, category, mode, options, 0) == 1
		observed := string_text(session_configuration_msg(session, c'category', 0))
		assert observed in ['AVAudioSessionCategoryPlayback', 'AVAudioSessionCategoryAmbient']
		assert session_configuration_msg(session, c'categoryOptions', 0) in [u64(1), 3]
		assert string_text(session_configuration_msg(session, c'mode', 0)) == 'AVAudioSessionModeDefault'
	}
}

fn test_audio_session_configuration() {
	selectors := [c'setCategory:mode:options:error:', c'categoryOptions', c'mode']!
	types := ['B48@0:8@16@24Q32^@40', 'Q16@0:8', '@16@0:8']!
	$if macos {
		assert C.dlopen(c'/System/Library/Frameworks/AVFAudio.framework/AVFAudio', 2) != unsafe { nil }
		cls := C.objc_getClass(c'AVAudioSession')
		for i, name in selectors {
			selector := C.sel_registerName(name)
			method := C.class_getInstanceMethod(cls, selector)
			assert method != unsafe { nil } && C.method_getImplementation(method) != unsafe { nil }
			assert ctext(u64(C.method_getTypeEncoding(method))) == types[i]
			assert C.class_getClassMethod(cls, selector) == unsafe { nil }
		}
		println('IOS-AUDIO-CONFIGURATION-NATIVE: setter BOOL, NSUInteger, NSError output and getter metadata PASS; native audio-server calls unverified')
	}
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		cls := ios_runtime.names['AVAudioSession']
		session := session_configuration_msg(cls, c'sharedInstance', 0)
		assert session_configuration_msg(session, c'categoryOptions', 0) == 0
		assert string_text(session_configuration_msg(session, c'mode', 0)) == 'AVAudioSessionModeDefault'
		assert string_text(session_configuration_msg(session, c'category', 0)) == 'AVAudioSessionCategorySoloAmbient'
		for i, selector in selectors {
			method := objc_instance_method(cls, u64(selector))
			assert method != 0 && ctext(u64(objc_method_types(method))) == types[i]
			assert objc_instance_method(read64(cls), u64(selector)) == 0
			assert session_configuration_msg(session, c'respondsToSelector:', u64(selector)) == 1
		}
		for missing in [c'setActive:error:', c'setCategory:', c'setCategory:error:', c'vinixMissingAudioQuery']! {
			assert session_configuration_msg(session, c'respondsToSelector:', u64(missing)) == 0
		}
		signature := session_configuration_msg(session, c'methodSignatureForSelector:', u64(selectors[0]))
		assert session_configuration_msg(signature, c'numberOfArguments', 0) == 6
		assert session_configuration_msg(signature, c'methodReturnLength', 0) == 1
		assert ctext(session_configuration_msg(signature, c'getArgumentTypeAtIndex:', 5)) == '^@'
		mode := owned_string('AVAudioSessionModeDefault')
		playback := owned_string('AVAudioSessionCategoryPlayback')
		ambient := owned_string('AVAudioSessionCategoryAmbient')
		solo := owned_string('AVAudioSessionCategorySoloAmbient')
		mutable := objc_allocate(ios_runtime.names['NSMutableString'])
		assert session_configuration_msg(mutable, c'initWithString:', playback) == mutable
		mut error_object := u64(0x12345678)
		assert session_configuration_set(session, mutable, mode, 2, u64(&error_object)) == 1
		assert error_object == 0x12345678 // Success leaves NSError ** untouched.
		session_configuration_msg(mutable, c'setString:', ambient)
		objc_release(mutable)
		assert string_text(session_configuration_msg(session, c'category', 0)) == 'AVAudioSessionCategoryPlayback'
		assert session_configuration_msg(session, c'categoryOptions', 0) == 3
		getter_value := session_configuration_msg(session, c'category', 0)
		method := objc_instance_method(cls, u64(selectors[0]))
		imp := objc_method_imp(method)
		assert unsafe { SessionConfigurationSetter(voidptr(imp))(session, u64(selectors[0]), ambient, mode, 0, &error_object) }
		assert error_object == 0x12345678
		assert session_configuration_msg(session, c'categoryOptions', 0) == 1
		assert session_configuration_set(session, solo, mode, 0, 0) == 1
		// A previous getter remains valid when configuration is replaced.
		assert string_text(getter_value) == 'AVAudioSessionCategoryPlayback'
		for options in [u64(0), 1, 2, 3, 0x11, 0x13] {
			assert session_configuration_set(session, playback, mode, options, 0) == 1
			assert session_configuration_msg(session, c'categoryOptions', 0) == if options & 2 != 0 { options | 1 } else { options }
		}
		bad_text := owned_string('AVAudioSessionCategoryPlayback\x00suffix')
		wrong_object := objc_allocate(ios_runtime.names['NSObject'])
		for bad in [u64(0), 1, cls, wrong_object, bad_text] {
			assert session_configuration_set(session, bad, mode, 0, 0) == 0
			assert session_configuration_set(session, playback, bad, 0, 0) == 0
		}
		for options in [u64(4), 8, 0x10, 0x20, 0x40, 0x80, 0x100, u64(1) << 32, u64(1) << 63, ~u64(0)] {
			error_object = 0
			assert session_configuration_set(session, playback, mode, options, u64(&error_object)) == 0
			assert error_object != 0 && objc_is_kind(error_object, ios_runtime.names['NSError'])
			assert i64(session_configuration_msg(error_object, c'code', 0)) == -50
			assert string_text(session_configuration_msg(error_object, c'domain', 0)) == 'NSOSStatusErrorDomain'
		}
		for name in ['AVAudioSessionCategoryRecord', 'AVAudioSessionCategoryPlayAndRecord', 'AVAudioSessionCategoryMultiRoute', 'AVAudioSessionCategoryAudioProcessing'] {
			unsupported := owned_string(name)
			error_object = 0
			assert session_configuration_set(session, unsupported, mode, 0, u64(&error_object)) == 0
			assert i64(session_configuration_msg(error_object, c'code', 0)) == 561145203
			objc_release(unsupported)
		}
		movie := owned_string('AVAudioSessionModeMoviePlayback')
		assert session_configuration_set(session, playback, movie, 0, u64(&error_object)) == 0
		assert i64(session_configuration_msg(error_object, c'code', 0)) == 561145203
		assert session_configuration_set(session, solo, movie, 0, u64(&error_object)) == 0
		assert i64(session_configuration_msg(error_object, c'code', 0)) == -50
		// All failures preserve the complete previous configuration.
		assert string_text(session_configuration_msg(session, c'category', 0)) == 'AVAudioSessionCategoryPlayback'
		assert session_configuration_msg(session, c'categoryOptions', 0) == 0x13
		assert session_configuration_msg(session, c'isOtherAudioPlaying', 0) == 0
		mut workers := []thread{}
		for i in 0 .. 8 { workers << spawn session_configuration_worker(session, if i & 1 == 0 { playback } else { ambient }, mode, 2) }
		workers.wait()
		unsafe { workers.free() }
		for value in [mode, playback, ambient, solo, bad_text, wrong_object, movie]! { objc_release(value) }
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-AUDIO-CONFIGURATION: inactive output configuration, validation, NSError, immutable snapshots, BOOL ABI, eight workers and two drained runtimes PASS')
}
