// SPDX-License-Identifier: GPL-2.0-or-later
module main

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getName(voidptr) &char
fn C.class_getImageName(voidptr) &char
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char

type AudioSend = fn (u64, voidptr, u64, u64) u64
type AudioQueue = fn (&char, u64) u64
type AudioRelease = fn (u64)
type AudioWeak = fn (&u64, u64) u64
fn msg(object u64, selector &char, a u64, b u64) u64 {
	return unsafe { AudioSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, b) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/AVFoundation.framework/AVFoundation', 2) != unsafe { nil }
	cls := C.objc_getClass(c'AVCaptureAudioDataOutput')
	assert cls != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0)
	println('IMAGE ${unsafe { C.class_getImageName(cls).vstring() }}')
	println('AVCaptureAudioDataOutput SIZE ${C.class_getInstanceSize(cls)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }}')
	println('AVCaptureOutput SIZE ${C.class_getInstanceSize(C.class_getSuperclass(cls))}')
	for selector in [c'init', c'setSampleBufferDelegate:queue:', c'sampleBufferDelegate', c'sampleBufferCallbackQueue', c'connections', c'connectionWithMediaType:', c'recommendedAudioSettingsForAssetWriterWithOutputFileType:']! {
		method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
		assert method != unsafe { nil }
		println('INSTANCE ${unsafe { selector.vstring() }} ${unsafe { C.method_getTypeEncoding(method).vstring() }}')
		class_method := C.class_getClassMethod(cls, C.sel_registerName(selector))
		println('CLASS ${unsafe { selector.vstring() }} present=${class_method != unsafe { nil }}')
		assert (class_method != unsafe { nil }) == (unsafe { selector.vstring() } == 'init')
	}
	output := msg(u64(cls), c'new', 0, 0)
	assert output != 0
	assert msg(output, c'sampleBufferDelegate', 0, 0) == 0
	assert msg(output, c'sampleBufferCallbackQueue', 0, 0) == 0
	assert msg(msg(output, c'connections', 0, 0), c'count', 0, 0) == 0
	assert msg(output, c'connectionWithMediaType:', 0, 0) == 0
	for name in ['com.apple.quicktime-movie', 'public.mpeg-4', 'public.3gpp', 'com.apple.m4v-video', 'com.apple.m4a-audio', 'com.apple.coreaudio-format', 'com.microsoft.waveform-audio', 'public.aiff-audio', 'public.aifc-audio', 'org.3gpp.adaptive-multi-rate-audio']! {
		file_type := msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(name.str), 0)
		assert msg(output, c'recommendedAudioSettingsForAssetWriterWithOutputFileType:', file_type, 0) == 0
	}
	println('UNCONNECTED recommended-settings-nil=true for ten file types')
	delegate := msg(u64(C.objc_getClass(c'NSObject')), c'new', 0, 0)
	queue := unsafe { AudioQueue(C.dlsym(voidptr(i64(-2)), c'dispatch_queue_create'))(c'vinix.audio.inspect', 0) }
	before := msg(delegate, c'retainCount', 0, 0)
	msg(output, c'setSampleBufferDelegate:queue:', delegate, queue)
	after := msg(delegate, c'retainCount', 0, 0)
	println('DELEGATE retainCount before=${before} after=${after}')
	assert before == after
	inner := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0)
	assert msg(output, c'sampleBufferDelegate', 0, 0) == delegate
	assert msg(output, c'sampleBufferCallbackQueue', 0, 0) == queue
	msg(output, c'setSampleBufferDelegate:queue:', 0, queue)
	assert msg(output, c'sampleBufferCallbackQueue', 0, 0) == 0
	println('NIL-DELEGATE queue-cleared=true')
	msg(output, c'setSampleBufferDelegate:queue:', 0, 0)
	assert msg(output, c'sampleBufferDelegate', 0, 0) == 0
	assert msg(output, c'sampleBufferCallbackQueue', 0, 0) == 0
	msg(inner, c'drain', 0, 0)
	assert msg(delegate, c'retainCount', 0, 0) == before
	msg(output, c'setSampleBufferDelegate:queue:', delegate, queue)
	mut weak := u64(0)
	unsafe { AudioWeak(C.dlsym(voidptr(i64(-2)), c'objc_storeWeak'))(&weak, delegate) }
	msg(delegate, c'release', 0, 0)
	assert weak == 0
	assert msg(output, c'sampleBufferDelegate', 0, 0) == 0
	println('DELEGATE zeroes-after-release=true')
	unsafe { AudioWeak(C.dlsym(voidptr(i64(-2)), c'objc_storeWeak'))(&weak, 0) }
	unsafe { AudioRelease(C.dlsym(voidptr(i64(-2)), c'dispatch_release'))(queue) }
	assert msg(output, c'sampleBufferCallbackQueue', 0, 0) == queue
	println('QUEUE survives-caller-release=true')
	msg(output, c'release', 0, 0)
	msg(pool, c'drain', 0, 0)
	println('IOS-CAPTURE-AUDIO-INSPECT: PASS')
}
