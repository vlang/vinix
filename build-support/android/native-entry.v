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
type NativeServiceMain = fn (&char, &char, &char, &char, &char, i32, i32) i32

fn service_launch() !(nativeaccountauth.ServiceLaunch, int, int) {
	if os.args.len !in [4, 6, 8] || os.args[2] != '--service-fd'
		|| (os.args.len >= 6 && os.args[4] != '--authenticator-fd')
		|| (os.args.len == 8 && os.args[6] != '--ui-fd') {
		return error('usage: vinix-android-native APK --service-fd FD [--authenticator-fd FD [--ui-fd FD]]')
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
	mut ui_fd := -1
	if os.args.len >= 6 {
		auth_fd := strconv.atoi(os.args[5])!
		if auth_fd < 3 || auth_fd > 2147483647 || auth_fd == fd || auth_fd.str() != os.args[5] {
			return error('invalid authenticator command descriptor')
		}
		nativeaccountauth.verify_root_channel(auth_fd)!
		auth_flags := C.fcntl(i32(auth_fd), C.F_GETFD)
		if auth_flags < 0 || C.fcntl(i32(auth_fd), C.F_SETFD, auth_flags | C.FD_CLOEXEC) != 0 {
			return error('cannot protect authenticator command descriptor')
		}
		os.setenv('VINIX_ANDROID_AUTHENTICATOR_FD',auth_fd.str(),true)
		if os.args.len == 8 {
			ui_fd = strconv.atoi(os.args[7])!
			if ui_fd < 3 || ui_fd > 2147483647 || ui_fd in [fd, auth_fd] || ui_fd.str() != os.args[7] {
				return error('invalid authenticator UI descriptor')
			}
			nativeaccountauth.verify_root_channel(ui_fd)!
			ui_flags := C.fcntl(i32(ui_fd), C.F_GETFD)
			if ui_flags < 0 || C.fcntl(i32(ui_fd), C.F_SETFD, ui_flags | C.FD_CLOEXEC) != 0 {
				return error('cannot protect authenticator UI descriptor')
			}
		}
	}
	return launch, fd, ui_fd
}

fn main() {
	// Only the verified service argv may introduce a command channel.
	os.unsetenv('VINIX_ANDROID_AUTHENTICATOR_FD')
	root := os.getenv_opt('VINIX_ANDROID_ROOT') or { '/opt/vinix-android-aarch64' }
	if os.args.len < 2 {
		eprintln('usage: vinix-android-native APK [ACTIVITY] | APK --service-fd FD [--authenticator-fd FD [--ui-fd FD]]')
		exit(2)
	}
	service_mode := os.args.len > 2 && os.args[2] == '--service-fd'
	mut launch := nativeaccountauth.ServiceLaunch{}
	mut control_fd := -1
	mut ui_fd := -1
	if service_mode {
		selected, fd, selected_ui := service_launch() or {
			eprintln('Android service launch rejected: ' + err.msg())
			exit(1)
		}
		launch = selected
		control_fd = fd
		ui_fd = selected_ui
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
		exit(int(entry(root.str, os.args[1].str, launch.package_name.str, launch.service.str, launch.action.str, i32(control_fd), i32(ui_fd))))
	}
	entry := unsafe { NativeMain(C.dlsym(library, c'vinix_android_native_main')) }
	if voidptr(entry) == unsafe { nil } {
		eprintln('native Android entry point missing')
		exit(1)
	}
	activity := if os.args.len > 2 { os.args[2] } else { '' }
	exit(int(entry(root.str, os.args[1].str, activity.str)))
}
