// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#flag -framework UserNotifications
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceVariable(voidptr, &char) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.objc_storeWeak(&u64, voidptr) voidptr

type SoundSend = fn (u64, u64, u64, u64, u64) u64
type SoundDouble = fn (u64, u64) f64
struct SoundApi { native bool send u64 }
fn sound_api() SoundApi { return SoundApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
fn (api SoundApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api SoundApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api SoundApi) msg(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { SoundSend(voidptr(api.send))(object, api.sel(name), a, b, c) }
}
fn (api SoundApi) release(object u64) { api.msg(object, c'release', 0, 0, 0) }
fn (api SoundApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api SoundApi) pop(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api SoundApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api SoundApi) weak_destroy(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api SoundApi) string(value string, mutable bool) u64 {
	return api.msg(api.msg(api.cls(if mutable { 'NSMutableString' } else { 'NSString' }), c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(value.str), u64(value.len), 4)
}
fn (api SoundApi) text(object u64) string {
	assert object != 0
	length := api.msg(object, c'lengthOfBytesUsingEncoding:', 4, 0, 0)
	bytes := api.msg(object, c'UTF8String', 0, 0, 0); assert bytes != 0
	return if length == 0 { '' } else { unsafe { tos(&u8(voidptr(bytes)), int(length)) } }
}
fn sound_metadata(api SoundApi) {
	cls := api.cls('UNNotificationSound'); assert cls != 0
	$if macos { if api.native {
		assert C.class_getInstanceSize(unsafe { voidptr(cls) }) == 104
		assert u64(C.class_getSuperclass(unsafe { voidptr(cls) })) == api.cls('NSObject')
	} }
	if !api.native { assert objc_class_size(cls) == 104 && objc_class_parent(cls) == api.cls('NSObject') }
	for i, property in un_sound_ivars() {
		key := '_' + property; expected := un_sound_ivar_types()[i]
		$if macos { if api.native {
			ivar := C.class_getInstanceVariable(unsafe { voidptr(cls) }, key.str)
			assert ivar != unsafe { nil } && C.ivar_getOffset(ivar) == isize(un_sound_offsets()[i])
			assert unsafe { C.ivar_getTypeEncoding(ivar).vstring() } == expected
		} }
		if !api.native { ivar := objc_find_ivar(cls, key.str); assert ivar != 0 && objc_ivar_offset(ivar) == i64(un_sound_offsets()[i]) && ctext(u64(objc_ivar_types(ivar))) == expected }
	}
	for meta in [false, true]! {
		selectors := if meta { ['defaultSound', 'soundNamed:'] } else { ['copy', 'copyWithZone:', 'alertType', 'alertTopic', 'audioCategory', 'audioVolume', 'maximumDuration', 'isCritical', 'shouldIgnoreAccessibilityDisabledVibrationSetting', 'shouldIgnoreRingerSwitch', 'shouldRepeat', 'toneFileName', 'toneFileURL', 'toneIdentifier', 'toneMediaLibraryItemIdentifier', 'vibrationIdentifier', 'vibrationPatternFileURL'] }
		for selector in selectors {
			expected := un_sound_types('UNNotificationSound', meta, selector) or { panic(selector) }
			mut actual := ''
			$if macos { if api.native {
				method := if meta { C.class_getClassMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.sel(selector.str)) }) } else { C.class_getInstanceMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.sel(selector.str)) }) }
				assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() }
			} }
			if !api.native { method := if meta { objc_class_method(cls, u64(selector.str)) } else { objc_instance_method(cls, u64(selector.str)) }; assert method != 0; actual = ctext(u64(objc_method_types(method))) }
			assert actual == expected, selector + ': ' + actual
		}
	}
}
fn sound_values(api SoundApi, object u64) {
	assert object != 0 && api.msg(object, c'alertType', 0, 0, 0) == 17
	for selector in [c'alertTopic', c'audioCategory', c'audioVolume', c'isCritical', c'shouldIgnoreAccessibilityDisabledVibrationSetting', c'shouldIgnoreRingerSwitch', c'shouldRepeat', c'toneFileURL', c'toneIdentifier', c'toneMediaLibraryItemIdentifier', c'vibrationIdentifier', c'vibrationPatternFileURL']! { assert api.msg(object, selector, 0, 0, 0) == 0 }
	assert unsafe { SoundDouble(voidptr(api.send))(object, api.sel(c'maximumDuration')) } == 0
	for selector in [c'copy', c'copyWithZone:']! { assert api.msg(object, selector, 0, 0, 0) == object; api.release(object) }
}
fn sound_shared(api SoundApi) {
	pool := api.pool(); sound_metadata(api); cls := api.cls('UNNotificationSound')
	default := api.msg(cls, c'defaultSound', 0, 0, 0); sound_values(api, default)
	assert api.msg(default, c'toneFileName', 0, 0, 0) == 0
	assert api.msg(cls, c'defaultSound', 0, 0, 0) != default
	nil_sound := api.msg(cls, c'soundNamed:', 0, 0, 0); sound_values(api, nil_sound)
	assert api.msg(nil_sound, c'toneFileName', 0, 0, 0) == 0
	for value in ['', 'alert.caf', 'é😀.wav', 'a\x00' + 'b']! {
		input := api.string(value, true); object := api.msg(cls, c'soundNamed:', input, 0, 0)
		stored := api.msg(object, c'toneFileName', 0, 0, 0); assert stored != input && api.text(stored) == value
		replacement := api.string('changed.wav', false); api.msg(input, c'setString:', replacement, 0, 0); api.release(replacement); api.release(input)
		assert api.text(api.msg(object, c'toneFileName', 0, 0, 0)) == value; sound_values(api, object)
	}
	api.pop(pool)
	// Content and its request snapshot retain the same immutable sound.
	inner := api.pool(); filename := api.string('retained.caf', false)
	object := api.msg(cls, c'soundNamed:', filename, 0, 0); api.release(filename)
	content := api.msg(api.cls('UNMutableNotificationContent'), c'new', 0, 0, 0)
	api.msg(content, c'setSound:', object, 0, 0)
	mut weak := u64(0); api.weak(unsafe { &weak }, object)
	copy := api.msg(content, c'copy', 0, 0, 0); mutable := api.msg(content, c'mutableCopy', 0, 0, 0)
	identifier := api.string('sound-request', false)
	request := api.msg(api.cls('UNNotificationRequest'), c'requestWithIdentifier:content:trigger:', identifier, content, 0)
	api.release(identifier); api.msg(request, c'retain', 0, 0, 0)
	api.msg(content, c'setSound:', 0, 0, 0); assert api.msg(content, c'sound', 0, 0, 0) == 0; api.release(content)
	api.pop(inner); assert weak == object
	// Native property getters can autorelease retained return values. Drain
	// those reads before checking that the last owning snapshot was released.
	inspection := api.pool()
	for item in [copy, mutable, api.msg(request, c'content', 0, 0, 0)]! { assert api.msg(item, c'sound', 0, 0, 0) == object && api.text(api.msg(object, c'toneFileName', 0, 0, 0)) == 'retained.caf' }
	api.release(copy); api.release(mutable); assert weak != 0; api.release(request)
	api.pop(inspection)
	assert weak == 0; api.weak_destroy(unsafe { &weak })
}

__global sound_callback_mode = ''
__global sound_callback_fired = false
__global sound_callback_source = u64(0)
__global sound_callback_weak = u64(0)
fn sound_worker() {
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	if sound_callback_source != 0 {
		api := sound_api(); replacement := api.string('changed in callback', false)
		api.msg(sound_callback_source, c'setString:', replacement, 0, 0); api.release(replacement); api.release(sound_callback_source)
	}
}
fn sound_constructor(object u64, _selector &char) u64 {
	if sound_callback_mode == '' || sound_callback_fired { return object }
	sound_callback_fired = true
	match sound_callback_mode {
		'isa' { objc_set_class(object, ios_runtime.names['NSObject']); return object }
		'body' { unsafe { *(&u64(object + 24)) = 3 }; return object }
		'state' { obj_header(object).un_sound_initialized = true; return object }
		else {}
	}
	worker := spawn sound_worker(); worker.wait()
	if sound_callback_mode == 'fail' { objc_store_weak(unsafe { &sound_callback_weak }, object); return 0 }
	return object
}
fn sound_override(_object u64, _selector &char) u64 { return 99 }
fn sound_runtime(api SoundApi) {
	cls := api.cls('UNNotificationSound'); library := '/System/Library/Frameworks/UserNotifications.framework/UserNotifications'
	assert runtime_symbol(library, '_OBJC_CLASS_$_UNNotificationSound') or { panic(err) } == cls
	assert runtime_symbol(library, '_OBJC_METACLASS_$_UNNotificationSound') or { panic(err) } == read64(cls)
	assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(sound_constructor) }), c'@16@0:8')
	assert objc_add_method(api.cls('NSString'), u64(c'.cxx_construct'), u64(unsafe { voidptr(sound_constructor) }), c'@16@0:8')
	for named in [false, true]! {
		for mode in ['success', 'fail']! {
			input := if named { api.string('before constructor', true) } else { u64(0) }
			before := ios_runtime.live
			sound_callback_source = input; sound_callback_fired = false; sound_callback_mode = mode
			object := un_sound_create(cls, input); sound_callback_mode = ''; sound_callback_source = 0
			assert sound_callback_fired
			if mode == 'fail' { assert object == 0 && sound_callback_weak == 0; api.weak_destroy(unsafe { &sound_callback_weak }) }
			else { assert object != 0; if named { assert api.text(api.msg(object, c'toneFileName', 0, 0, 0)) == 'before constructor' }; api.release(object) }
			assert ios_runtime.live == before - if named { i64(1) } else { i64(0) }
		}
	}
	// Fail the sound constructor after its filename snapshot was allocated.
	input := api.string('cleanup.caf', false)
	sound_callback_mode = 'fail'; sound_callback_fired = true
	assert objc_replace_method(api.cls('NSString'), u64(c'.cxx_construct'), u64(unsafe { voidptr(sound_inert_constructor) }), c'@16@0:8') != 0
	sound_callback_fired = false; before := ios_runtime.live
	assert un_sound_create(cls, input) == 0; sound_callback_mode = ''
	assert sound_callback_fired && sound_callback_weak == 0 && ios_runtime.live == before
	api.weak_destroy(unsafe { &sound_callback_weak }); api.release(input)
	object := un_sound_create(cls, 0)
	for selector in [c'mutableCopy', c'supportsSecureCoding', c'initWithCoder:', c'encodeWithCoder:', c'description', c'hash', c'isEqual:']! { assert objc_instance_method(cls, u64(selector)) == 0 && !objc_responds(object, selector) }
	assert objc_copy_value(object, false) == object; api.release(object); api.release(object)
	input2 := api.string('isa-cleanup.caf', false); changed := un_sound_create(cls, input2); api.release(input2)
	mut weak := u64(0); api.weak(unsafe { &weak }, api.msg(changed, c'toneFileName', 0, 0, 0))
	objc_set_class(changed, api.cls('NSObject')); api.release(changed); assert weak == 0; api.weak_destroy(unsafe { &weak })
	mut guarded := [15]u64{}; guarded[0] = 0x1122334455667788; guarded[14] = 0x8877665544332211
	caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller
	assert objc_destruct_instance(caller) == caller && caller !in ios_runtime.objects
	assert guarded[0] == 0x1122334455667788 && guarded[14] == 0x8877665544332211
	assert objc_add_method(cls, u64(c'description'), u64(unsafe { voidptr(sound_override) }), c'@16@0:8')
	overridden := un_sound_create(cls, 0); assert objc_responds(overridden, c'description') && api.msg(overridden, c'description', 0, 0, 0) == 99; api.release(overridden)
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
}
fn sound_inert_constructor(object u64, _selector &char) u64 { return object }
fn test_un_notification_sound() {
	$if macos {
		native_send := C.dlsym(voidptr(i64(-2)), c'objc_msgSend'); assert native_send != unsafe { nil }
		sound_shared(SoundApi{true, u64(native_send)})
		println('IOS-UN-SOUND-NATIVE: layout, encodings, defaults, nil names, UTF8 snapshots, immutable copies and content/request ownership PASS')
	}
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!; api := sound_api(); sound_shared(api); sound_runtime(api)
		objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	}
	println('IOS-UN-SOUND: native parity, reentrant and failed constructors, caller storage, isa cleanup, associated copies, native overrides and two balanced lifetimes PASS')
}
fn test_un_notification_sound_rejections() {
	objc_start(); system_data_start()!; api := sound_api()
	modes := ['raw', 'raw-copy', 'new', 'init', 'spoof', 'isa', 'raw-isa', 'body', 'padding', 'filename', 'copy-zone', 'subclass', 'caller-subclass', 'factory-subclass', 'wrong-string', 'raw-string', 'oversize', 'invalid-utf8', 'content-raw', 'content-isa', 'constructor-isa', 'constructor-body', 'constructor-state', 'mutableCopy', 'encodeWithCoder:', 'description', 'defaultCriticalSound', 'defaultCriticalSoundWithAudioVolume:', 'criticalSoundNamed:', 'criticalSoundNamed:withAudioVolume:', 'defaultRingtoneSound', 'ringtoneSoundNamed:', 'defaultSystemSound']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			cls := api.cls('UNNotificationSound'); object := un_sound_create(cls, 0)
			match mode {
				'raw', 'raw-copy' { api.msg(objc_allocate(cls), if mode == 'raw' { c'toneFileName' } else { c'copy' }, 0, 0, 0) }
				'new' { api.msg(cls, c'new', 0, 0, 0) }
				'init' { api.msg(object, c'init', 0, 0, 0) }
				'spoof' { fake := objc_new(api.cls('NSObject')); objc_set_class(fake, cls); api.msg(fake, c'toneFileName', 0, 0, 0) }
				'isa', 'raw-isa' { if mode == 'isa' { objc_set_class(object, api.cls('NSObject')) } else { unsafe { *(&u64(object)) = api.cls('NSObject') } }; api.msg(object, c'toneFileName', 0, 0, 0) }
				'body', 'padding', 'filename' { offset := if mode == 'body' { 8 } else if mode == 'padding' { 48 } else { 56 }; unsafe { *(&u64(object + u64(offset))) = if mode == 'padding' { u64(1) << 40 } else { u64(1) } }; api.msg(object, c'toneFileName', 0, 0, 0) }
				'copy-zone' { api.msg(object, c'copyWithZone:', 1, 0, 0) }
				'subclass', 'caller-subclass', 'factory-subclass' { custom := objc_allocate_class(cls, c'UnsupportedSound', 0); objc_register_class(custom); if mode == 'subclass' { objc_allocate(custom) } else if mode == 'factory-subclass' { api.msg(custom, c'defaultSound', 0, 0, 0) } else { mut storage := [13]u64{}; objc_construct_instance(custom, u64(unsafe { &storage[0] })) } }
				'wrong-string' { un_sound_create(cls, objc_new(api.cls('NSObject'))) }
				'raw-string' { un_sound_create(cls, objc_allocate(api.cls('NSMutableString'))) }
				'oversize' { un_sound_create(cls, api.string('x'.repeat(65537), false)) }
				'invalid-utf8' { un_sound_create(cls, owned_string('\xff')) }
				'content-raw', 'content-isa' { content := api.msg(api.cls('UNMutableNotificationContent'), c'new', 0, 0, 0); value := if mode == 'content-raw' { objc_allocate(cls) } else { objc_set_class(object, api.cls('NSObject')); object }; api.msg(content, c'setSound:', value, 0, 0) }
				'constructor-isa', 'constructor-body', 'constructor-state' { assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(sound_constructor) }), c'@16@0:8'); sound_callback_mode = mode.all_after('constructor-'); sound_callback_fired = false; un_sound_create(cls, 0) }
				else { api.msg(if mode.starts_with('default') || mode.starts_with('critical') || mode.starts_with('ringtone') { cls } else { object }, mode.str, 0, 0, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }
		assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	println('IOS-UN-SOUND-REJECT: ' + modes.len.str() + ' invalid values, provenance, constructors, copies and unsupported API cases PASS')
}
