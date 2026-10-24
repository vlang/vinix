// SPDX-License-Identifier: GPL-2.0-or-later
// Measure the installed Apple Foundation runtime, independently of the shim.
module main
import os
#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
type CredentialSend = fn (u64, voidptr, u64, u64, u64) u64
fn msg(object u64, selector &char, a u64, b u64, c u64) u64 {
	return unsafe { CredentialSend(C.dlsym(voidptr(-2), c'objc_msgSend'))(object, C.sel_registerName(selector), a, b, c) }
}
fn cls(name &char) u64 { return u64(C.objc_getClass(name)) }
fn text(object u64) string {
	if object == 0 { return '<nil>' }
	return unsafe { (&char(msg(object, c'UTF8String', 0, 0, 0))).vstring() }
}
fn main() {
	pool := msg(cls(c'NSAutoreleasePool'), c'new', 0, 0, 0)
	mode := if os.args.len > 1 { os.args[1] } else { 'password' }
	mut object := u64(0)
	if mode == 'default' {
		object = msg(cls(c'NSURLCredential'), c'new', 0, 0, 0)
	} else {
		user := if mode == 'nil-user' { u64(0) } else { msg(cls(c'NSString'), c'stringWithUTF8String:', u64(c'alice'), 0, 0) }
		password := if mode == 'nil-password' { u64(0) } else { msg(cls(c'NSString'), c'stringWithUTF8String:', u64(if mode == 'empty' { c'' } else { c'secret' }), 0, 0) }
		persistence := if mode == 'invalid-persistence' { u64(99) } else { u64(2) }
		object = msg(msg(cls(c'NSURLCredential'), c'alloc', 0, 0, 0), c'initWithUser:password:persistence:', user, password, persistence)
	}
	println('CREDENTIAL ${mode}: object=${object != 0}')
	if object != 0 && mode != 'default' {
		println('user=${text(msg(object, c'user', 0, 0, 0))} password=${text(msg(object, c'password', 0, 0, 0))} hasPassword=${msg(object, c'hasPassword', 0, 0, 0)} persistence=${msg(object, c'persistence', 0, 0, 0)}')
		println('identity=${msg(object, c'identity', 0, 0, 0)} certificates=${msg(object, c'certificates', 0, 0, 0)}')
		copied := msg(object, c'copy', 0, 0, 0)
		println('copy=self:${copied == object} equal:${msg(object, c'isEqual:', copied, 0, 0)}')
		msg(copied, c'release', 0, 0, 0)
	}
	msg(object, c'release', 0, 0, 0)
	msg(pool, c'drain', 0, 0, 0)
}
