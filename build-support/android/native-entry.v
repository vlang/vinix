// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv
import nativeaccountauth

#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>

fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlerror() &char
fn C.getuid() u32
fn C.getgid() i32
fn C.fcntl(i32, i32, ...i32) i32

type NativeMain = fn (&char, &char, &char) i32
type NativeServiceMain = fn (&char, &char, &char, &char, &char, i32) i32

fn service_launch() !(nativeaccountauth.ServiceLaunch, int) {
	if os.args.len != 4 || os.args[2] != '--service-fd' {
		return error('usage: vinix-android-native APK --service-fd FD')
	}
	fd := strconv.atoi(os.args[3])!
	if fd < 3 || fd > 2147483647 || fd.str() != os.args[3] {
		return error('invalid service control descriptor')
	}
	path := os.getenv_opt('VINIX_ANDROID_ACCOUNT_REGISTRY') or { return error('service registry is required') }
	registry := nativeaccountauth.load(path)!
	launch := nativeaccountauth.verify_service_frame(fd, registry, os.args[1], C.getuid(), u32(C.getgid()))!
	flags := C.fcntl(i32(fd), C.F_GETFD)
	if flags < 0 || C.fcntl(i32(fd), C.F_SETFD, flags | C.FD_CLOEXEC) != 0 {
		return error('cannot protect service control descriptor')
	}
	return launch, fd
}

fn main() {
	root := os.getenv_opt('VINIX_ANDROID_ROOT') or { '/opt/vinix-android-aarch64' }
	if os.args.len < 2 {
		eprintln('usage: vinix-android-native APK [ACTIVITY] | APK --service-fd FD')
		exit(2)
	}
	service_mode := os.args.len > 2 && os.args[2] == '--service-fd'
	mut launch := nativeaccountauth.ServiceLaunch{}
	mut control_fd := -1
	if service_mode {
		selected, fd := service_launch() or {
			eprintln('Android service launch rejected: ' + err.msg())
			exit(1)
		}
		launch = selected
		control_fd = fd
	} else if os.args.len > 3 || (os.args.len > 2 && os.args[2].starts_with('--')) {
		eprintln('invalid Android launch arguments')
		exit(2)
	}
	path := root + '/usr/lib/art/libvinix-android-native.so'
	library := unsafe { C.dlopen(path.str, 2 | 256) }
	if library == unsafe { nil } {
		eprintln(unsafe { cstring_to_vstring(C.dlerror()) })
		exit(1)
	}
	if service_mode {
		entry := unsafe { NativeServiceMain(C.dlsym(library, c'vinix_android_native_service_main')) }
		if voidptr(entry) == unsafe { nil } {
			eprintln('native Android service entry point missing')
			exit(1)
		}
		exit(int(entry(root.str, os.args[1].str, launch.package_name.str, launch.service.str, launch.action.str, i32(control_fd))))
	}
	entry := unsafe { NativeMain(C.dlsym(library, c'vinix_android_native_main')) }
	if voidptr(entry) == unsafe { nil } {
		eprintln('native Android entry point missing')
		exit(1)
	}
	activity := if os.args.len > 2 { os.args[2] } else { '' }
	exit(int(entry(root.str, os.args[1].str, activity.str)))
}
