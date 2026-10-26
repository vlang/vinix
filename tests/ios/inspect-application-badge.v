// SPDX-License-Identifier: GPL-2.0-or-later
// Isolated native Catalyst observation without UIApplicationMain or badge
// authorization. Getter results do not establish authorized badge display semantics.
module main

import os

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>

fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr

type BadgeSend = fn (u64, voidptr, u64) u64

fn msg(object u64, name &char, value u64) u64 {
	return unsafe { BadgeSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(name), value) }
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--bundle' {
		contents := os.abs_path(os.args[2]) + '/InspectBadge.app/Contents'
		os.mkdir_all(contents + '/MacOS')!
		binary := contents + '/MacOS/inspect'
		os.cp(os.executable(), binary)!
		os.write_file(contents + '/Info.plist', '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.vinix.badge-inspection</string><key>CFBundleExecutable</key><string>inspect</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>')!
		mut process := os.new_process(binary)
		process.set_redirect_stdio_merged()
		process.run()
		print(process.stdout_slurp())
		process.wait()
		code := process.code
		process.close()
		exit(code)
	}
	assert C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/UIKit.framework/UIKit', 2) != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	cls := C.objc_getClass(c'UIApplication')
	for name in [c'applicationIconBadgeNumber', c'setApplicationIconBadgeNumber:']! {
		method := C.class_getInstanceMethod(cls, C.sel_registerName(name))
		assert method != unsafe { nil }
		println('METHOD ${unsafe { name.vstring() }} ${unsafe { C.method_getTypeEncoding(method).vstring() }}')
	}
	mut application := msg(u64(cls), c'sharedApplication', 0)
	println('SHARED before init ${application != 0}')
	if application == 0 { application = msg(u64(cls), c'alloc', 0) }
	assert application != 0
	println('DEFAULT ${i64(msg(application, c'applicationIconBadgeNumber', 0))}')
	for value in [i64(1), 42, 0, -1, -42, i64(2147483648), i64(9223372036854775807), i64(-9223372036854775807) - 1]! {
		msg(application, c'setApplicationIconBadgeNumber:', u64(value))
		println('BADGE ${value} ${i64(msg(application, c'applicationIconBadgeNumber', 0))}')
	}
	msg(application, c'setApplicationIconBadgeNumber:', 0)
	msg(pool, c'drain', 0)
	println('IOS-APPLICATION-BADGE-INSPECT: PASS')
}
