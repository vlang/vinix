// SPDX-License-Identifier: GPL-2.0-or-later
// Observe Foundation's receipt URL for an unbundled executable.
module main

import os

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.dlsym(voidptr, &char) voidptr
type ReceiptSend = fn (u64, voidptr, u64) u64

fn message(object u64, selector &char, argument u64) u64 {
	return unsafe { ReceiptSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), argument) }
}

fn main() {
	pool := message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	cls := u64(C.objc_getClass(c'NSBundle'))
	bundle := message(cls, c'mainBundle', 0)
	path := unsafe { (&char(voidptr(message(message(bundle, c'bundlePath', 0), c'UTF8String', 0)))).vstring() }
	method := C.class_getInstanceMethod(voidptr(cls), C.sel_registerName(c'appStoreReceiptURL'))
	assert method != unsafe { nil }
	types := unsafe { C.method_getTypeEncoding(method).vstring() }
	assert types == '@16@0:8'
	assert message(bundle, c'respondsToSelector:', u64(C.sel_registerName(c'appStoreReceiptURL'))) == 1
	assert message(cls, c'respondsToSelector:', u64(C.sel_registerName(c'appStoreReceiptURL'))) == 0
	assert !os.exists(os.join_path(path, 'Contents', '_MASReceipt', 'receipt'))
	assert !os.exists(os.join_path(path, 'StoreKit', 'receipt'))
	for _ in 0 .. 256 { assert message(bundle, c'appStoreReceiptURL', 0) == 0 }
	println('BUNDLE-RECEIPT-NATIVE: unbundled=nil reads=256 types=${types} instance=true class=false')
	println('BUNDLE-RECEIPT-NATIVE: path=${path}')
	message(pool, c'drain', 0)
}
