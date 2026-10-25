// SPDX-License-Identifier: GPL-2.0-or-later
// Run individual native operations in separate processes: abstract methods may abort.
module main
import os
import math.bits
import time
#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
type TaskSend = fn (u64, voidptr, u64) u64
type TaskFloatGet = fn (u64, voidptr) f32
type TaskFloatSet = fn (u64, voidptr, f32)
fn msg(object u64, name &char, arg u64) u64 {
	return unsafe { TaskSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(name), arg) }
}
fn main() {
	assert os.args.len >= 3
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	cls := u64(C.objc_getClass(os.args[1].str)); assert cls != 0
	object := msg(cls, c'alloc', 0); println('alloc nonnil=${object != 0}')
	if os.args[2] == 'new' {
		msg(object, c'release', 0)
		made := msg(cls, c'new', 0); println('new nonnil=${made != 0}'); msg(made, c'release', 0)
	} else {
		selector := os.args[2]
		if selector == 'priority' {
			get := unsafe { TaskFloatGet(C.dlsym(voidptr(i64(-2)), c'objc_msgSend')) }
			set := unsafe { TaskFloatSet(C.dlsym(voidptr(i64(-2)), c'objc_msgSend')) }
			println('priority=${get(object, C.sel_registerName(c'priority'))}')
			for value in [f32(-1), 0.25, 2, bits.f32_from_bits(0x7fc00000), bits.f32_from_bits(0x7f800000), bits.f32_from_bits(0xff800000), 1, 0]! { set(object, C.sel_registerName(c'setPriority:'), value); println('set bits=${bits.f32_bits(value)}: bits=${bits.f32_bits(get(object, C.sel_registerName(c'priority')))}') }
		} else if selector == 'description' {
			text := msg(u64(C.objc_getClass(c'NSMutableString')), c'stringWithUTF8String:', u64(c'task'))
			msg(object, c'setTaskDescription:', text)
			println('description identity=${msg(object, c'taskDescription', 0) == text}')
			msg(text, c'setString:', msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'changed')))
			println('description=${unsafe { cstring_to_vstring(&char(msg(msg(object, c'taskDescription', 0), c'UTF8String', 0))) }}')
		} else if selector == 'lifecycle' {
			for operation in ['resume', 'suspend']! {
				mut child := os.new_process(os.executable())
				child.set_args([os.args[1], operation]); child.set_redirect_stdio_merged()
				child.run(); output := child.stdout_slurp(); child.wait()
				println('${operation} delayed child status=${child.code}\n${output}'); child.close()
			}
		} else if selector in ['resume', 'suspend']! {
			msg(object, selector.str, 0)
			// Keep the object alive while the native asynchronous callback executes.
			time.sleep(500 * time.millisecond)
			println('${selector} delayed state=${msg(object, c'state', 0)}')
		} else if selector == 'counts' {
			for getter in ['countOfBytesClientExpectsToSend', 'countOfBytesClientExpectsToReceive', 'countOfBytesSent', 'countOfBytesReceived', 'countOfBytesExpectedToSend', 'countOfBytesExpectedToReceive']! {
				setter := 'set' + getter[..1].to_upper() + getter[1..] + ':'
				println('${getter}=${i64(msg(object, getter.str, 0))}')
				for value in [i64(-1), 42, -2]! {
					msg(object, setter.str, u64(value))
					println('set ${value}: ${i64(msg(object, getter.str, 0))}')
				}
			}
		} else {
			result := msg(object, selector.str, 0)
			println('${selector}: value=${result} same=${result == object}')
			if selector in ['copy', 'copyWithZone:']! { msg(result, c'release', 0) }
		}
		msg(object, c'release', 0)
	}
	msg(pool, c'drain', 0)
}
