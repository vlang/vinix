// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type AFName = fn (&char) u64
type AFMessage = fn (u64, u64, u64, u64, u64) u64
type AFRetain = fn (u64) u64
type AFRelease = fn (u64)
type AFPool = fn () u64
type AFBytes = fn (u64, &char, i64, u32) bool
struct AFApi { native bool foundation u64 objc u64 core u64 }
struct AFCells { values [20]u64 }
__global avfoundation_teardown_calls = 0
__global avfoundation_note_calls = 0
__global avfoundation_note = u64(0)
__global avfoundation_note_api = AFApi{}
fn af_names() [20]string { return ['_AVCaptureDeviceTypeBuiltInTelephotoCamera','_AVCaptureDeviceTypeBuiltInUltraWideCamera','_AVCaptureDeviceTypeBuiltInWideAngleCamera','_AVCaptureDeviceTypeExternal','_AVCaptureDeviceTypeMicrophone','_AVCaptureSessionDidStartRunningNotification','_AVCaptureSessionDidStopRunningNotification','_AVCaptureSessionInterruptionEndedNotification','_AVCaptureSessionPresetHigh','_AVCaptureSessionRuntimeErrorNotification','_AVCaptureSessionWasInterruptedNotification','_AVMediaTypeAudio','_AVMediaTypeClosedCaption','_AVMediaTypeSubtitle','_AVMediaTypeText','_AVMediaTypeTimecode','_AVPlayerItemDidPlayToEndTimeNotification','_AVCaptureSessionPresetMedium','_AVLayerVideoGravityResizeAspectFill','_AVMediaTypeVideo',]! }
fn af_texts() [20]string { return ['AVCaptureDeviceTypeBuiltInTelephotoCamera','AVCaptureDeviceTypeBuiltInUltraWideCamera','AVCaptureDeviceTypeBuiltInWideAngleCamera','AVCaptureDeviceTypeExternal','AVCaptureDeviceTypeMicrophone','AVCaptureSessionDidStartRunningNotification','AVCaptureSessionDidStopRunningNotification','AVCaptureSessionInterruptionEndedNotification','AVCaptureSessionPresetHigh','AVCaptureSessionRuntimeErrorNotification','AVCaptureSessionWasInterruptedNotification','soun','clcp','sbtl','text','tmcd','AVPlayerItemDidPlayToEndTimeNotification','AVCaptureSessionPresetMedium','AVLayerVideoGravityResizeAspectFill','vide',]! }
fn af_api(native bool) AFApi {
	$if macos { if native {
		return AFApi{true, u64(C.dlopen(c'/System/Library/Frameworks/AVFoundation.framework/AVFoundation', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2))}
	} }
	return AFApi{}
}
fn af_cell(api AFApi, name string) u64 {
	if api.native { return u64(C.dlsym(voidptr(api.foundation), unsafe { &char(name.str + 1) })) }
	return runtime_symbol('/System/Library/Frameworks/AVFoundation.framework/AVFoundation', name) or { panic(err) }
}
fn af_class(api AFApi, name &char) u64 {
	if api.native { return unsafe { AFName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn af_msg(api AFApi, object u64, name &char, a u64, b u64, c u64) u64 {
	if api.native {
		selector := unsafe { AFName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
		return unsafe { AFMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
	}
	return unsafe { AFMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn af_retain(api AFApi, value u64) u64 {
	if api.native { return unsafe { AFRetain(C.dlsym(voidptr(api.objc), c'objc_retain'))(value) } }
	return objc_retain(value)
}
fn af_release(api AFApi, value u64) {
	if api.native { unsafe { AFRelease(C.dlsym(voidptr(api.objc), c'objc_release'))(value) }; return }
	objc_release(value)
}
fn af_pool(api AFApi) u64 {
	if api.native { return unsafe { AFPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
	return objc_pool_push()
}
fn af_pop(api AFApi, pool u64) {
	if api.native { unsafe { AFRelease(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
	objc_pool_pop(pool)
}
fn af_text(api AFApi, value u64, expected string) {
	assert value != 0
	if !api.native { assert string_text(value) == expected; return }
	mut buffer := [1024]u8{}
	assert unsafe { AFBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(value, &char(&buffer[0]), 1024, 0x08000100) }
	assert buffer[expected.len] == 0 && C.memcmp(unsafe { &buffer[0] }, expected.str, usize(expected.len)) == 0
}

type AFMessage4 = fn (u64, u64, u64, u64, u64, u64) u64
type AFAllocateClass = fn (u64, &char, usize) u64
type AFAddMethod = fn (u64, u64, u64, &char) bool
fn af_selector(api AFApi, name &char) u64 {
 if api.native { return unsafe { AFName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) } }
 return u64(name)
}
fn af_msg4(api AFApi, object u64, name &char, a u64, b u64, c u64, d u64) u64 {
 if api.native { return unsafe { AFMessage4(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, af_selector(api, name), a, b, c, d) } }
 return unsafe { AFMessage4(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c, d) }
}
__global avfoundation_expected_name = u64(0)
fn af_reader(api AFApi, offset int) AFCells {
 mut cells := [20]u64{}; names := af_names(); texts := af_texts()
 for turn in 0 .. 16 {
  pool := af_pool(api)
  for step in 0 .. 20 {
   i := (offset + step) % 20; cell := af_cell(api, names[i]); assert cell != 0 && cell % 8 == 0
   if turn == 0 { cells[i] = cell } else { assert cells[i] == cell }
   value := read64(cell); af_text(api, value, texts[i])
   assert af_retain(api, value) == value; af_release(api, value)
   assert af_msg(api, af_retain(api, value), c'autorelease', 0, 0, 0) == value
   copy := af_msg(api, value, c'copy', 0, 0, 0); af_text(api, copy, texts[i]); af_release(api, copy)
  }
  af_pop(api, pool)
 }
 return AFCells{cells}
}
fn af_shared(api AFApi) {
 mut workers := []thread AFCells{}
 for offset in 0 .. 8 { workers << spawn af_reader(api, offset) }
 mut cells := [20]u64{}
 for i, worker in workers { got := worker.wait().values; if i == 0 { cells = got } else { assert cells == got } }
 unsafe { workers.free() }
 mut values := [20]u64{}
 for i, cell in cells {
  values[i] = read64(cell)
  for j in 0 .. i { assert cell != cells[j] && values[i] != values[j] }
 }
 pool := af_pool(api)
 array := af_msg(api, af_class(api, c'NSArray'), c'arrayWithObjects:count:', u64(unsafe { &values[0] }), 20, 0)
 dictionary := af_msg(api, af_class(api, c'NSDictionary'), c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &values[0] }), u64(unsafe { &values[0] }), 20)
 assert array != 0 && dictionary != 0
 af_retain(api, array); af_retain(api, dictionary); af_pop(api, pool)
 check := af_pool(api)
 assert af_msg(api, array, c'count', 0, 0, 0) == 20 && af_msg(api, dictionary, c'count', 0, 0, 0) == 20
 for i, text in af_texts() {
  equal := af_msg(api, af_class(api, c'NSString'), c'stringWithUTF8String:', u64(text.str), 0, 0)
  af_text(api, af_msg(api, array, c'objectAtIndex:', u64(i), 0, 0), text)
  af_text(api, af_msg(api, dictionary, c'objectForKey:', equal, 0, 0), text)
 }
 af_release(api, array); af_release(api, dictionary); af_pop(api, check)
 if !api.native { assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 }
}
fn af_note_received(object u64, selector &char, notification u64) {
 api := avfoundation_note_api
 name := af_msg(api, notification, c'name', 0, 0, 0)
 assert af_msg(api, name, c'isEqualToString:', avfoundation_expected_name, 0, 0) != 0
 assert avfoundation_note == 0
 avfoundation_note = af_retain(api, notification); avfoundation_note_calls++
}
fn af_notifications(api AFApi) {
 avfoundation_note_api = api; assert avfoundation_note == 0
 pool := af_pool(api); parent := af_class(api, c'NSObject')
 observer_class := if api.native { unsafe { AFAllocateClass(C.dlsym(voidptr(api.objc), c'objc_allocateClassPair'))(parent, c'VinixAVFoundationObserver', 0) } } else { objc_allocate_class(parent, c'VinixAVFoundationObserver', 0) }
 assert observer_class != 0
 action := af_selector(api, c'vinixAVFoundationNotification:'); implementation := u64(unsafe { voidptr(af_note_received) })
 if api.native {
  assert unsafe { AFAddMethod(C.dlsym(voidptr(api.objc), c'class_addMethod'))(observer_class, action, implementation, c'v24@0:8@16') }
  unsafe { AFRelease(C.dlsym(voidptr(api.objc), c'objc_registerClassPair'))(observer_class) }
 } else { assert objc_add_method(observer_class, action, implementation, c'v24@0:8@16'); objc_register_class(observer_class) }
 observer := af_msg(api, observer_class, c'new', 0, 0, 0); filter := af_msg(api, parent, c'new', 0, 0, 0)
 center := af_msg(api, af_class(api, c'NSNotificationCenter'), c'defaultCenter', 0, 0, 0)
 for index in [5,6,7,9,10,16]! {
  before := avfoundation_note_calls; name := read64(af_cell(api, af_names()[index])); avfoundation_expected_name = name
  text := af_texts()[index]; equal := af_msg(api, af_class(api, c'NSString'), c'stringWithUTF8String:', u64(text.str), 0, 0)
  af_msg4(api, center, c'addObserver:selector:name:object:', observer, action, name, filter)
  af_msg(api, center, c'postNotificationName:object:userInfo:', equal, 0, 0); assert avfoundation_note_calls == before
  af_msg(api, center, c'postNotificationName:object:userInfo:', equal, filter, 0); assert avfoundation_note_calls == before + 1 && avfoundation_note != 0
  af_msg(api, center, c'removeObserver:name:object:', observer, equal, filter)
  af_msg(api, center, c'postNotificationName:object:userInfo:', name, filter, 0); assert avfoundation_note_calls == before + 1
  af_release(api, avfoundation_note); avfoundation_note = 0
 }
 // A zeroing-weak registration remains for runtime shutdown to drain while
 // its constant notification name and filter are still registered.
 af_msg4(api, center, c'addObserver:selector:name:object:', observer, action, avfoundation_expected_name, filter)
 af_release(api, observer); af_release(api, filter); af_pop(api, pool)
 if !api.native { assert ios_runtime.live == 1 && ios_runtime.observers.len == 1 }
}
fn af_teardown(object u64, selector &char) {
 assert ios_runtime.swift_concurrency_retired
 for i, name in af_names() { cell := avfoundation_constant_symbol(name) or { panic('AVFoundation global retired before pool callback') }; assert string_text(read64(cell)) == af_texts()[i] }
 avfoundation_teardown_calls++
}
fn test_avfoundation_constants() {
 $if macos {
  api := af_api(true); af_shared(api); af_notifications(api)
  println('IOS-AVFOUNDATION-CONSTANTS-NATIVE: twenty NSString pointer cells, exact media FourCCs, immutable copies, retained arrays/dictionaries, six notification names with equal strings and object filters, eight concurrent readers')
 }
 if _ := avfoundation_constant_symbol('_AVMediaTypeAudio') { assert false }
 for _ in 0 .. 2 {
  objc_start(); assert ios_runtime.avfoundation_constants_arena == 0
  ios_runtime.swift_concurrency_retired = true
  if _ := avfoundation_constant_symbol('_AVMediaTypeAudio') { assert false }
  ios_runtime.swift_concurrency_retired = false
  af_shared(AFApi{}); af_notifications(AFApi{})
  for symbol in af_names() { for library in ['/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/UIKit.framework/UIKit','/usr/lib/libSystem.B.dylib']! { if _ := runtime_symbol(library, symbol) { assert false } } }
  if _ := avfoundation_constant_symbol('_AVCaptureDeviceTypeInvented') { assert false }
  probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixAVFoundationTeardownProbe', 0); assert probe != 0
  assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(af_teardown) }), c'v16@0:8'); objc_register_class(probe); objc_autorelease(objc_new(probe))
  ios_runtime.swift_concurrency_retired = true
  before := avfoundation_teardown_calls; objc_stop()
  assert avfoundation_teardown_calls == before + 1 && ios_runtime.avfoundation_constants_arena == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.observers.len == 0
  if _ := avfoundation_constant_symbol('_AVMediaTypeAudio') { assert false }
 }
 println('IOS-AVFOUNDATION-CONSTANTS: stable sealed globals, exact native strings, retained collections, equal-name notifications, contended publication, pool teardown availability and two drained/unmapped runtimes')
}
