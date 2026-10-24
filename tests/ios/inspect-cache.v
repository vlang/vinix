// SPDX-License-Identifier: GPL-2.0-or-later
// Record the installed Apple cache defaults and ownership behavior.
module main

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_storeWeak(&u64, voidptr) voidptr
type Send = fn (u64, voidptr, u64, u64, u64, u64) u64
fn msg(object u64, selector &char, a u64, b u64, c u64, d u64) u64 {
	return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, b, c, d) }
}
fn main() {
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0, 0)
	cls := u64(C.objc_getClass(c'NSCache')); object := msg(cls, c'new', 0, 0, 0, 0)
	println('DEFAULT name.length=${msg(msg(object, c'name', 0, 0, 0, 0), c'length', 0, 0, 0, 0)}')
	for selector in [c'delegate', c'countLimit', c'totalCostLimit', c'evictsObjectsWithDiscardedContent', c'minimumObjectCount', c'evictsObjectsWhenApplicationEntersBackground']! {
		println('DEFAULT ${unsafe { selector.vstring() }}=${msg(object, selector, 0, 0, 0, 0)}')
	}
	name := msg(msg(u64(C.objc_getClass(c'NSMutableString')), c'alloc', 0, 0, 0, 0), c'initWithUTF8String:', u64(c'before'), 0, 0, 0)
	msg(object, c'setName:', name, 0, 0, 0)
	changed := msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'changed'), 0, 0, 0)
	msg(name, c'setString:', changed, 0, 0, 0)
	stored := msg(object, c'name', 0, 0, 0, 0)
	println('NAME ${unsafe { (&char(voidptr(msg(stored, c'UTF8String', 0, 0, 0, 0)))).vstring() }}')
	embedded := 'a\x00' + 'b'
	nul_name := msg(msg(u64(C.objc_getClass(c'NSString')), c'alloc', 0, 0, 0, 0), c'initWithBytes:length:encoding:', u64(embedded.str), u64(embedded.len), 4, 0)
	msg(object, c'setName:', nul_name, 0, 0, 0)
	println('NUL-NAME input=${msg(nul_name, c'length', 0, 0, 0, 0)} stored=${msg(msg(object, c'name', 0, 0, 0, 0), c'length', 0, 0, 0, 0)}')
	msg(nul_name, c'release', 0, 0, 0, 0)
	msg(object, c'setName:', 0, 0, 0, 0); println('NIL-NAME length=${msg(msg(object, c'name', 0, 0, 0, 0), c'length', 0, 0, 0, 0)}')
	key := msg(u64(C.objc_getClass(c'NSObject')), c'new', 0, 0, 0, 0)
	value := msg(u64(C.objc_getClass(c'NSObject')), c'new', 0, 0, 0, 0)
	delegate := msg(u64(C.objc_getClass(c'NSObject')), c'new', 0, 0, 0, 0)
	mut weak_key := u64(0); mut weak_value := u64(0); mut weak_delegate := u64(0)
	C.objc_storeWeak(unsafe { &weak_key }, unsafe { voidptr(key) }); C.objc_storeWeak(unsafe { &weak_value }, unsafe { voidptr(value) }); C.objc_storeWeak(unsafe { &weak_delegate }, unsafe { voidptr(delegate) })
	msg(object, c'setDelegate:', delegate, 0, 0, 0); msg(delegate, c'release', 0, 0, 0, 0)
	println('DELEGATE alive=${weak_delegate != 0} cleared=${msg(object, c'delegate', 0, 0, 0, 0) == 0}')
	msg(object, c'setDelegate:', 0, 0, 0, 0)
	// This key does not implement copying. NSCache must retain it directly.
	msg(object, c'setObject:forKey:cost:', value, key, 2, 0)
	msg(key, c'release', 0, 0, 0, 0); msg(value, c'release', 0, 0, 0, 0)
	println('ENTRY key=${weak_key != 0} value=${weak_value != 0} identity=${msg(object, c'objectForKey:', weak_key, 0, 0, 0) == weak_value}')
	msg(object, c'removeAllObjects', 0, 0, 0, 0); msg(pool, c'drain', 0, 0, 0, 0)
	println('REMOVED key=${weak_key == 0} value=${weak_value == 0}')
	msg(object, c'release', 0, 0, 0, 0); msg(name, c'release', 0, 0, 0, 0)
	for slot in [unsafe { &weak_key }, unsafe { &weak_value }, unsafe { &weak_delegate }]! { C.objc_storeWeak(slot, unsafe { nil }) }
}
