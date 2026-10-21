// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <dlfcn.h>

fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlerror() &char

type NativeMain = fn (&char, &char, &char) i32

fn main() {
	root := os.getenv_opt('VINIX_ANDROID_ROOT') or { '/opt/vinix-android-aarch64' }
	if os.args.len < 2 {
		eprintln('usage: vinix-android-native APK [ACTIVITY]')
		exit(2)
	}
	path := root + '/usr/lib/art/libvinix-android-native.so'
	library := unsafe { C.dlopen(path.str, 2 | 256) }
	if library == unsafe { nil } {
		eprintln(unsafe { cstring_to_vstring(C.dlerror()) })
		exit(1)
	}
	entry := unsafe { NativeMain(C.dlsym(library, c'vinix_android_native_main')) }
	if voidptr(entry) == unsafe { nil } {
		eprintln('native Android entry point missing')
		exit(1)
	}
	activity := if os.args.len > 2 { os.args[2] } else { '' }
	exit(int(entry(root.str, os.args[1].str, activity.str)))
}
