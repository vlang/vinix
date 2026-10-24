// SPDX-License-Identifier: GPL-2.0-or-later
// Native measurements for the bounded notification sound implementation.
module main

#flag -framework Foundation
#flag -framework UserNotifications
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
type Send = fn (u64, voidptr, u64) u64
type DoubleSend = fn (u64, voidptr) f64
fn msg(object u64, selector &char, argument u64) u64 {
	return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), argument) }
}
fn text(object u64) string {
	return if object == 0 { '<nil>' } else { unsafe { (&char(voidptr(msg(object, c'UTF8String', 0)))).vstring() } }
}
fn main() {
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	cls := u64(C.objc_getClass(c'UNNotificationSound'))
	for selector in [c'defaultSound']! {
		object := msg(cls, selector, 0)
		duration := unsafe { DoubleSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(c'maximumDuration')) }
		println('DURATION maximum=${duration}')
		println('SOUND ${unsafe { selector.vstring() }} name=${text(msg(object, c'toneFileName', 0))} type=${msg(object, c'alertType', 0)} volume=${msg(object, c'audioVolume', 0)}')
		copy := msg(object, c'copy', 0)
		println('COPY self=${object == copy} default-again=${object == msg(cls, c'defaultSound', 0)}')
		msg(copy, c'release', 0)
		println('DEFAULT topic=${text(msg(object, c'alertTopic', 0))} category=${text(msg(object, c'audioCategory', 0))} identifier=${text(msg(object, c'toneIdentifier', 0))} critical=${msg(object, c'isCritical', 0)} ringer=${msg(object, c'shouldIgnoreRingerSwitch', 0)} repeat=${msg(object, c'shouldRepeat', 0)} accessibility=${msg(object, c'shouldIgnoreAccessibilityDisabledVibrationSetting', 0)}')
	}
	for value in ['', 'alert.caf', 'é😀.wav']! {
		input := msg(msg(u64(C.objc_getClass(c'NSMutableString')), c'alloc', 0), c'initWithUTF8String:', u64(value.str))
		object := msg(cls, c'soundNamed:', input)
		name := msg(object, c'toneFileName', 0)
		msg(input, c'setString:', msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'changed.wav')))
		msg(input, c'release', 0)
		copy := msg(object, c'copy', 0)
		println('NAMED ${value} before=${text(name)} after=${text(msg(object, c'toneFileName', 0))} copy-self=${object == copy} type=${msg(object, c'alertType', 0)}')
		msg(copy, c'release', 0)
		println('DETAIL topic=${text(msg(object, c'alertTopic', 0))} category=${text(msg(object, c'audioCategory', 0))} identifier=${text(msg(object, c'toneIdentifier', 0))} critical=${msg(object, c'isCritical', 0)} ringer=${msg(object, c'shouldIgnoreRingerSwitch', 0)} repeat=${msg(object, c'shouldRepeat', 0)} accessibility=${msg(object, c'shouldIgnoreAccessibilityDisabledVibrationSetting', 0)}')
		content := msg(u64(C.objc_getClass(c'UNMutableNotificationContent')), c'new', 0)
		msg(content, c'setSound:', object)
		content_copy := msg(content, c'copy', 0)
		println('CONTENT same=${msg(content, c'sound', 0) == object} snapshot-same=${msg(content_copy, c'sound', 0) == object}')
		msg(content_copy, c'release', 0); msg(content, c'release', 0)
	}
	nil_sound := msg(cls, c'soundNamed:', 0)
	println('NIL object=${nil_sound != 0} name=${text(msg(nil_sound, c'toneFileName', 0))} type=${msg(nil_sound, c'alertType', 0)}')
	msg(pool, c'drain', 0)
}
