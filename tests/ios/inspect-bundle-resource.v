// SPDX-License-Identifier: GPL-2.0-or-later
// Measure Foundation's on-demand resource request without a resource manifest.
module main

import os

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
type ResourceSend = fn (u64, voidptr, u64, u64, u64) u64
type ResourceDouble = fn (u64, voidptr) f64
type ResourceSetDouble = fn (u64, voidptr, f64)
fn send(object u64, selector &char, a u64, b u64, c u64) u64 {
	return unsafe { ResourceSend(C.dlsym(voidptr(-2), c'objc_msgSend'))(object, C.sel_registerName(selector), a, b, c) }
}
fn cls(name &char) u64 { return u64(C.objc_getClass(name)) }
fn text(object u64) string {
	if object == 0 { return '<nil>' }
	return unsafe { (&char(send(object, c'UTF8String', 0, 0, 0))).vstring() }
}
fn main() {
	pool := send(cls(c'NSAutoreleasePool'), c'new', 0, 0, 0)
	mode := if os.args.len > 1 { os.args[1] } else { 'tags' }
	tag := send(cls(c'NSString'), c'stringWithUTF8String:', u64(c'missing-tag'), 0, 0)
	tags := send(cls(c'NSSet'), c'setWithObject:', tag, 0, 0)
	main_bundle := send(cls(c'NSBundle'), c'mainBundle', 0, 0, 0)
	mut request := send(cls(c'NSBundleResourceRequest'), c'alloc', 0, 0, 0)
	match mode {
		'default' { request = send(request, c'init', 0, 0, 0) }
		'nil' { request = send(request, c'initWithTags:', 0, 0, 0) }
		'empty' { request = send(request, c'initWithTags:', send(cls(c'NSSet'), c'set', 0, 0, 0), 0, 0) }
		'bundle' { request = send(request, c'initWithTags:bundle:', tags, main_bundle, 0) }
		'nil-bundle' { request = send(request, c'initWithTags:bundle:', tags, 0, 0) }
		else { request = send(request, c'initWithTags:', tags, 0, 0) }
	}
	println('RESOURCE ${mode}: object=${request != 0}')
	if request != 0 {
		println('tags=${text(send(send(request, c'tags', 0, 0, 0), c'description', 0, 0, 0))}')
		println('bundle=main:${send(request, c'bundle', 0, 0, 0) == main_bundle}')
		println('bundle=nil:${send(request, c'bundle', 0, 0, 0) == 0}')
		priority := unsafe { ResourceDouble(C.dlsym(voidptr(-2), c'objc_msgSend'))(request, C.sel_registerName(c'loadingPriority')) }
		println('priority=${priority}')
		progress := send(request, c'progress', 0, 0, 0)
		println('progress=${progress != 0} total=${i64(send(progress, c'totalUnitCount', 0, 0, 0))} completed=${send(progress, c'completedUnitCount', 0, 0, 0)}')
		for value in [f64(-1), 0.0, 0.75, 1.0, 2.0] {
			unsafe { ResourceSetDouble(C.dlsym(voidptr(-2), c'objc_msgSend'))(request, C.sel_registerName(c'setLoadingPriority:'), value) }
			actual := unsafe { ResourceDouble(C.dlsym(voidptr(-2), c'objc_msgSend'))(request, C.sel_registerName(c'loadingPriority')) }
			println('set=${value} priority=${actual}')
		}
		send(request, c'release', 0, 0, 0)
	}
	send(pool, c'drain', 0, 0, 0)
}
