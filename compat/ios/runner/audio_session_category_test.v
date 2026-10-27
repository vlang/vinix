// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#flag -framework CoreFoundation
	#include <objc/runtime.h>
	#include <CoreFoundation/CFString.h>
	#include <dlfcn.h>
	fn C.objc_getClass(&char) voidptr
	fn C.sel_registerName(&char) voidptr
	fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
	fn C.class_getClassMethod(voidptr, voidptr) voidptr
	fn C.method_getTypeEncoding(voidptr) &char
	fn C.method_getImplementation(voidptr) voidptr
	fn C.dlopen(&char, int) voidptr
	fn C.dlsym(voidptr, &char) voidptr
	fn C.CFStringGetCString(voidptr, &char, i64, u32) bool
}

type SessionCategoryObject = fn (u64, u64) u64

fn session_category_msg(object u64, selector &char, argument u64) u64 {
	mut frame := RegisterFrame{}
	frame.x[0] = object; frame.x[1] = u64(selector); frame.x[2] = argument
	assert objc_dispatch(mut frame, 0) == 0
	return frame.x[0]
}

fn session_category_worker(cls u64) u64 {
	mut first := u64(0)
	for _ in 0 .. 256 {
		session := session_category_msg(cls, c'sharedInstance', 0)
		category := session_category_msg(session, c'category', 0)
		assert category != 0
		if first == 0 { first = category } else { assert category == first }
		assert string_text(category) == 'AVAudioSessionCategorySoloAmbient'
		assert objc_retain(category) == category
		objc_release(category)
	}
	return first
}

fn test_audio_session_category() {
	$if macos {
		library := C.dlopen(c'/System/Library/Frameworks/AVFAudio.framework/AVFAudio', 2)
		assert library != unsafe { nil }
		cls := C.objc_getClass(c'AVAudioSession')
		selector := C.sel_registerName(c'category')
		method := C.class_getInstanceMethod(cls, selector)
		assert method != unsafe { nil }
		assert ctext(u64(C.method_getTypeEncoding(method))) == '@16@0:8'
		assert C.class_getClassMethod(cls, selector) == unsafe { nil }
		assert C.method_getImplementation(method) != unsafe { nil }
		cell := C.dlsym(library, c'AVAudioSessionCategorySoloAmbient')
		assert cell != unsafe { nil }
		mut buffer := [128]u8{init: 0xaa}
		assert C.CFStringGetCString(unsafe { *(&voidptr(cell)) }, unsafe { &char(&buffer[8]) }, 112, 0x08000100)
		assert unsafe { tos_clone(&buffer[8]) } == 'AVAudioSessionCategorySoloAmbient'
		for i in 0 .. 8 { assert buffer[i] == 0xaa && buffer[120 + i] == 0xaa }
		// Apple's documented default is soloAmbient. Native sharedInstance blocks
		// in synchronous audio-server XPC on this headless host (prior checkpoint).
		println('IOS-AUDIO-CATEGORY-NATIVE: object metadata, instance-only getter and guarded SoloAmbient constant PASS; native session calls unverified')
	}
	for constant_first in [false, true]! {
		objc_start()
		cls := ios_runtime.names['AVAudioSession']
		assert ios_runtime.audio_session == 0 && ios_runtime.live == 0
		if constant_first {
			assert runtime_symbol('/System/Library/Frameworks/AVFAudio.framework/AVFAudio', '_AVAudioSessionCategorySoloAmbient')! != 0
		}
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn session_category_worker(cls) }
		results := workers.wait()
		for category in results { assert category == results[0] }
		category := results[0]
		unsafe { results.free(); workers.free() }
		object := session_category_msg(cls, c'sharedInstance', 0)
		assert ios_runtime.live == 2 && ios_runtime.objects.len == 2
		assert obj_header(object).refs == 1 && obj_header(category).refs == 1
		for framework in ['/System/Library/Frameworks/AVFAudio.framework/AVFAudio', '/System/Library/Frameworks/AVFoundation.framework/AVFoundation']! {
			cell := runtime_symbol(framework, '_AVAudioSessionCategorySoloAmbient')!
			assert read64(cell) == category && cell != category
		}
		assert cf_type_id(category) == cf_string_id()
		assert session_category_msg(object, c'respondsToSelector:', u64(c'category')) == 1
		assert session_category_msg(cls, c'respondsToSelector:', u64(c'category')) == 0
		for missing in [c'setCategory:', c'setCategory:error:', c'vinixMissingAudioQuery']! {
			assert session_category_msg(object, c'respondsToSelector:', u64(missing)) == 0
			assert objc_instance_method(cls, u64(missing)) == 0
		}
		method := objc_instance_method(cls, u64(c'category'))
		assert method != 0 && ctext(u64(objc_method_types(method))) == '@16@0:8'
		assert objc_instance_method(read64(cls), u64(c'category')) == 0
		pool := objc_pool_push()
		signature := session_category_msg(object, c'methodSignatureForSelector:', u64(c'category'))
		assert signature != 0
		assert session_category_msg(signature, c'numberOfArguments', 0) == 2
		assert session_category_msg(signature, c'methodReturnLength', 0) == 8
		assert ctext(session_category_msg(signature, c'methodReturnType', 0)) == '@'
		imp := objc_method_imp(method)
		assert imp != 0 && unsafe { SessionCategoryObject(voidptr(imp))(object, u64(c'category')) } == category
		// The getter does not transfer its cache ownership to callers.
		objc_autorelease(objc_retain(category))
		objc_pool_pop(pool)
		assert session_category_msg(object, c'category', 0) == category
		assert ios_runtime.live == 2 && obj_header(category).refs == 1
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-AUDIO-CATEGORY: SoloAmbient default, object signatures, direct IMP, framework identity, eight concurrent workers, both lookup orders and two drained runtimes PASS')
}
