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

type SessionActivityBool = fn (u64, u64) u8

fn session_activity_msg(object u64, selector &char, argument u64) u64 {
	mut frame := RegisterFrame{}
	frame.x[0] = object; frame.x[1] = u64(selector); frame.x[2] = argument
	assert objc_dispatch(mut frame, 0) == 0
	return frame.x[0]
}

fn session_activity_worker(cls u64) u64 {
	mut first := u64(0)
	for _ in 0 .. 256 {
		object := session_activity_msg(cls, c'sharedInstance', 0)
		assert object != 0
		if first == 0 { first = object } else { assert object == first }
		assert session_activity_msg(object, c'isOtherAudioPlaying', 0) == 0
		assert objc_retain(object) == object
		objc_release(object)
	}
	return first
}

fn test_audio_session_activity() {
	$if macos {
		assert C.dlopen(c'/System/Library/Frameworks/AVFAudio.framework/AVFAudio', 2) != unsafe { nil }
		cls := u64(C.objc_getClass(c'AVAudioSession'))
		assert cls != 0
		shared := u64(C.sel_registerName(c'sharedInstance'))
		query := u64(C.sel_registerName(c'isOtherAudioPlaying'))
		factory := C.class_getClassMethod(voidptr(cls), voidptr(shared))
		method := C.class_getInstanceMethod(voidptr(cls), voidptr(query))
		assert factory != unsafe { nil } && method != unsafe { nil }
		assert ctext(u64(C.method_getTypeEncoding(factory))) == '@16@0:8'
		assert ctext(u64(C.method_getTypeEncoding(method))) == 'B16@0:8'
		assert C.class_getClassMethod(voidptr(cls), voidptr(query)) == unsafe { nil }
		assert C.method_getImplementation(factory) != unsafe { nil }
		assert C.method_getImplementation(method) != unsafe { nil }
		// This headless Catalyst host blocks in the audio server's synchronous
		// XPC reply during sharedInstance. Compare metadata without opening a
		// session; native calls and system-wide activity remain unverified.
		println('IOS-AUDIO-ACTIVITY-NATIVE: instance/class method availability, BOOL encodings and nonnull IMPs PASS; native session calls unverified')
	}
	for _ in 0 .. 2 {
		objc_start()
		cls := ios_runtime.names['AVAudioSession']
		assert ios_runtime.audio_session == 0 && ios_runtime.live == 0
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn session_activity_worker(cls) }
		results := workers.wait()
		for object in results { assert object == results[0] }
		object := results[0]
		unsafe { results.free(); workers.free() }
		assert ios_runtime.live == 1 && ios_runtime.objects.len == 1
		assert obj_header(object).refs == 1 // The cache owns one reference.
		assert session_activity_msg(cls, c'respondsToSelector:', u64(c'sharedInstance')) == 1
		assert session_activity_msg(cls, c'respondsToSelector:', u64(c'isOtherAudioPlaying')) == 0
		assert session_activity_msg(object, c'respondsToSelector:', u64(c'isOtherAudioPlaying')) == 1
		for missing in [c'otherAudioPlaying', c'setOtherAudioPlaying:', c'vinixMissingAudioQuery']! {
			assert session_activity_msg(object, c'respondsToSelector:', u64(missing)) == 0
			assert objc_instance_method(cls, u64(missing)) == 0
		}
		method := objc_instance_method(cls, u64(c'isOtherAudioPlaying'))
		assert method != 0 && ctext(u64(objc_method_types(method))) == 'B16@0:8'
		assert objc_instance_method(read64(cls), u64(c'isOtherAudioPlaying')) == 0
		factory := objc_instance_method(read64(cls), u64(c'sharedInstance'))
		assert factory != 0 && ctext(u64(objc_method_types(factory))) == '@16@0:8'
		pool := objc_pool_push()
		signature := session_activity_msg(object, c'methodSignatureForSelector:', u64(c'isOtherAudioPlaying'))
		assert signature != 0
		assert session_activity_msg(signature, c'numberOfArguments', 0) == 2
		assert session_activity_msg(signature, c'methodReturnLength', 0) == 1
		assert ctext(session_activity_msg(signature, c'methodReturnType', 0)) == 'B'
		imp := objc_method_imp(method)
		assert imp != 0 && unsafe { SessionActivityBool(voidptr(imp))(object, u64(c'isOtherAudioPlaying')) } == 0
		// An autoreleased caller retain must not retire the cache's instance.
		objc_autorelease(objc_retain(object))
		objc_pool_pop(pool)
		assert session_activity_msg(cls, c'sharedInstance', 0) == object
		assert ios_runtime.live == 1 && obj_header(object).refs == 1
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-AUDIO-ACTIVITY: absent-provider false query, BOOL metadata/signatures, direct IMP, eight singleton workers, cache ownership and two drained runtimes PASS')
}
