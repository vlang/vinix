// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import stringfloatcases

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.dlsym(voidptr, &char) voidptr
type Send = fn (u64, u64, u64, u64, u64) u64
type FloatSend = fn (u64, u64) f32

fn main() {
	address := C.dlsym(voidptr(-2), c'objc_msgSend')
	send := unsafe { Send(address) }
	floating := unsafe { FloatSend(address) }
	pool := send(u64(C.objc_getClass(c'NSAutoreleasePool')), u64(C.sel_registerName(c'new')), 0, 0, 0)
	mut observations := 0
	for name in ['NSString', 'NSMutableString'] {
		cls := C.objc_getClass(name.str)
		sel := C.sel_registerName(c'floatValue')
		method := C.class_getInstanceMethod(cls, sel)
		assert method != unsafe { nil }
		assert unsafe { C.method_getTypeEncoding(method).vstring() } == 'f16@0:8'
		println('FLOAT-METADATA: class=${name} types=f16@0:8')
		for item in stringfloatcases.cases() {
			object := send(u64(cls), u64(C.sel_registerName(c'alloc')), 0, 0, 0)
			text := send(object, u64(C.sel_registerName(c'initWithBytes:length:encoding:')), u64(item.input.str), u64(item.input.len), 4)
			assert text != 0
			value := math.f32_bits(floating(text, u64(sel)))
			println('FLOAT-NATIVE: class=${name} input=${item.input.bytes().hex()} bits=${value:08x}')
			assert value == item.bits
			send(text, u64(C.sel_registerName(c'release')), 0, 0, 0)
			observations++
		}
	}
	send(pool, u64(C.sel_registerName(c'drain')), 0, 0, 0)
	println('FLOAT-NATIVE: observations=${observations} PASS')
}
