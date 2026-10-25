// SPDX-License-Identifier: GPL-2.0-or-later
module main

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlerror() &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getName(voidptr) &char
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
type TextFieldSend = fn (u64, voidptr, u64) u64
fn msg(object u64, selector &char, argument u64) u64 {
	return unsafe { TextFieldSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), argument) }
}
fn main() {
	if C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/UIKit.framework/UIKit', 2) == unsafe { nil } {
		panic(unsafe { C.dlerror().vstring() })
	}
	cls := C.objc_getClass(c'UITextField')
	assert cls != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	object := msg(u64(cls), c'new', 0)
	assert object != 0
	// UIKit forwards UITextInputTraits accessors to its trait object.
	for selector in [c'isSecureTextEntry', c'keyboardType', c'keyboardAppearance', c'returnKeyType', c'autocapitalizationType', c'autocorrectionType', c'spellCheckingType', c'enablesReturnKeyAutomatically']! {
		msg(object, selector, 0)
	}
	println('UITextField SIZE ${C.class_getInstanceSize(cls)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }}')
	for selector in [c'init', c'initWithFrame:', c'text', c'setText:', c'placeholder', c'setPlaceholder:', c'delegate', c'setDelegate:', c'isSecureTextEntry', c'setSecureTextEntry:', c'textAlignment', c'setTextAlignment:', c'borderStyle', c'setBorderStyle:', c'clearsOnBeginEditing', c'setClearsOnBeginEditing:', c'keyboardType', c'setKeyboardType:', c'keyboardAppearance', c'setKeyboardAppearance:', c'returnKeyType', c'setReturnKeyType:', c'autocapitalizationType', c'setAutocapitalizationType:', c'autocorrectionType', c'setAutocorrectionType:', c'spellCheckingType', c'setSpellCheckingType:', c'enablesReturnKeyAutomatically', c'setEnablesReturnKeyAutomatically:', c'isEditing']! {
		mut method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
		if method == unsafe { nil } {
			assert msg(object, c'respondsToSelector:', u64(C.sel_registerName(selector))) != 0
			method = C.class_getInstanceMethod(C.objc_getClass(c'UITextInputTraits'), C.sel_registerName(selector))
		}
		assert method != unsafe { nil }
		println('METHOD ${unsafe { selector.vstring() }} ${unsafe { C.method_getTypeEncoding(method).vstring() }}')
	}
	for selector in [c'text', c'placeholder', c'delegate', c'isSecureTextEntry', c'textAlignment', c'borderStyle', c'clearsOnBeginEditing', c'keyboardType', c'keyboardAppearance', c'returnKeyType', c'autocapitalizationType', c'autocorrectionType', c'spellCheckingType', c'enablesReturnKeyAutomatically', c'isEditing']! {
		value := msg(object, selector, 0)
		println('DEFAULT ${unsafe { selector.vstring() }} ${value}')
		if selector == c'text' { assert value != 0 && msg(value, c'length', 0) == 0 }
	}
	for property in ['Text', 'Placeholder']! {
		value := msg(msg(u64(C.objc_getClass(c'NSMutableString')), c'alloc', 0), c'initWithUTF8String:', u64(c'original'))
		setter := 'set' + property + ':'
		getter := property.to_lower()
		msg(object, setter.str, value)
		stored := msg(object, getter.str, 0)
		msg(value, c'appendString:', msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'-changed')))
		assert stored != value && unsafe { (&char(msg(stored, c'UTF8String', 0))).vstring() } == 'original'
		msg(value, c'release', 0)
		msg(object, setter.str, 0)
		nil_value := msg(object, getter.str, 0)
		assert if property == 'Text' { nil_value != 0 && msg(nil_value, c'length', 0) == 0 } else { nil_value == 0 }
		println('COPY ${property} snapshots mutable strings; nil normalized=' + (nil_value != 0).str())
	}
	delegate := msg(u64(C.objc_getClass(c'NSObject')), c'new', 0)
	msg(object, c'setDelegate:', delegate)
	msg(delegate, c'release', 0)
	assert msg(object, c'delegate', 0) == 0
	println('WEAK delegate zeroed after target release')
	msg(object, c'release', 0)
	msg(pool, c'drain', 0)
	println('IOS-UITEXTFIELD-INSPECT: metadata, defaults, copied text and placeholder, weak delegate')
}
