// SPDX-License-Identifier: GPL-2.0-or-later
// Native suspended-task inspection. Never resumes a task or starts a transfer.
module main

import os
import math.bits

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.method_getTypeEncoding(voidptr) &char
fn C.dlsym(voidptr, &char) voidptr
type Send = fn (u64, voidptr, u64) u64
type GetFloat = fn (u64, voidptr) f32
type WeakInit = fn (&u64, u64) u64
type WeakDestroy = fn (&u64)

fn msg(object u64, selector &char, arg u64) u64 {
	return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), arg) }
}
fn cls(name &char) u64 { return u64(C.objc_getClass(name)) }
fn text(object u64) string {
	return if object == 0 { '<nil>' } else { unsafe { cstring_to_vstring(&char(msg(object, c'UTF8String', 0))) } }
}
fn main() {
	assert os.args.len == 2
	outer := msg(cls(c'NSAutoreleasePool'), c'new', 0)
	for name in [c'NSURLSessionTask', c'NSURLSessionDownloadTask', c'NSURLSessionDataTask', c'NSURLSessionUploadTask']! {
		println('${unsafe { cstring_to_vstring(name) }} instance-size=${C.class_getInstanceSize(unsafe { voidptr(cls(name)) })}')
	}
	config := msg(cls(c'NSURLSessionConfiguration'), c'ephemeralSessionConfiguration', 0)
	session := msg(msg(cls(c'NSURLSession'), c'sessionWithConfiguration:', config), c'retain', 0)
	for name in [c'dataTaskWithRequest:', c'dataTaskWithURL:']! {
		method := C.class_getInstanceMethod(unsafe { voidptr(cls(c'NSURLSession')) }, C.sel_registerName(name))
		assert method != unsafe { nil }
		println('${unsafe { cstring_to_vstring(name) }} types=${unsafe { cstring_to_vstring(C.method_getTypeEncoding(method)) }}')
	}
	inner := msg(cls(c'NSAutoreleasePool'), c'new', 0)
	url := msg(cls(c'NSURL'), c'fileURLWithPath:', msg(cls(c'NSString'), c'stringWithUTF8String:', u64(c'/vinix/no-transfer')))
	mode := os.args[1]
	request := msg(cls(if mode == 'immutable-request' { c'NSURLRequest' } else { c'NSMutableURLRequest' }), c'requestWithURL:', url)
	task := if mode == 'nil-request' { msg(session, c'dataTaskWithRequest:', 0) }
		else if mode == 'nil-url' { msg(session, c'dataTaskWithURL:', 0) }
		else if mode == 'url' { msg(session, c'dataTaskWithURL:', url) }
		else { msg(session, c'dataTaskWithRequest:', request) }
	assert task != 0
	println('class=${text(msg(task, c'className', 0))}')
	for getter in [c'taskIdentifier', c'state', c'countOfBytesClientExpectsToSend', c'countOfBytesClientExpectsToReceive', c'countOfBytesSent', c'countOfBytesReceived', c'countOfBytesExpectedToSend', c'countOfBytesExpectedToReceive', c'response', c'error']! {
		println('${unsafe { cstring_to_vstring(getter) }}=${i64(msg(task, getter, 0))}')
	}
	priority := unsafe { GetFloat(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(task, C.sel_registerName(c'priority')) }
	println('priority-bits=${bits.f32_bits(priority)}')
	original := msg(task, c'originalRequest', 0)
	current := msg(task, c'currentRequest', 0)
	println('requests: nonnil=${original != 0 && current != 0} identity=${original == current} input=${original == request} mutable=${msg(original, c'isKindOfClass:', cls(c'NSMutableURLRequest')) != 0}')
	println('current-mutable=${msg(current, c'isKindOfClass:', cls(c'NSMutableURLRequest')) != 0}')
	if mode != 'immutable-request' { msg(request, c'setHTTPMethod:', msg(cls(c'NSString'), c'stringWithUTF8String:', u64(c'POST'))) }
	println('method-after-input-mutation=${text(msg(original, c'HTTPMethod', 0))}')
	second := msg(session, c'dataTaskWithURL:', url)
	println('second-identifier=${msg(second, c'taskIdentifier', 0)}')
	mut weak_task := u64(0)
	unsafe { WeakInit(C.dlsym(voidptr(i64(-2)), c'objc_initWeak'))(&weak_task, task) }
	msg(inner, c'drain', 0)
	println('unresumed-task-alive-after-pool=${weak_task != 0}')
	msg(session, c'invalidateAndCancel', 0)
	msg(session, c'release', 0)
	msg(outer, c'drain', 0)
	unsafe { WeakDestroy(C.dlsym(voidptr(i64(-2)), c'objc_destroyWeak'))(&weak_task) }
}
