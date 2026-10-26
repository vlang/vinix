// SPDX-License-Identifier: GPL-2.0-or-later
// Native APK launcher. ART uses a private libc and libraries; WS supplies the
// inherited surface/input connection. No display toolkit or X server starts.
module main

import os
import nativeapk
import nativeidentity
import nativecache
import nativeaccountauth

#include <sys/resource.h>
struct C.rlimit {
pub:
	rlim_cur u64
	rlim_max u64
}

fn C.setrlimit(int, &C.rlimit) int

fn main() {
	run() or {
		eprintln('run-android: ${err}')
		exit(1)
	}
}

fn run() ! {
	root := os.getenv_opt('VINIX_ANDROID_ROOT') or { '/opt/vinix-android-aarch64' }
	if os.args.len == 2 && os.args[1] == '--help' {
		println('usage: run-android APK [-l ACTIVITY] [-w WIDTH -h HEIGHT]\nRequires an inherited Vinix WS surface and input pipe.\nHeadless service host: run-android APK --service-fd N; requires a live root Unix peer,\nroot-provisioned account registry and explicit Unix credentials.\nOptional root-only Unix identity: VINIX_ANDROID_UID/GID=10000..19999,\nANDROID_APP_DATA_DIR and VINIX_ANDROID_HOME must name prepared target-owned directories.')
		return
	}
	if os.args.len < 2 { return error('usage: run-android APK [-l ACTIVITY]') }
	apk := os.abs_path(os.args[1])
	if !os.is_file(apk) { return error('cannot read APK: ' + apk) }
	mut activity := ''
	mut at := 2
	mut service_fd := -1
	if os.args.len >= 3 && os.args[2] == '--service-fd' {
		if os.args.len != 4 { return error('service host requires exactly APK --service-fd N') }
		value := os.args[3]
		if value.len == 0 || value.len > 10 || !value.bytes().all(it >= `0` && it <= `9`)
			|| value.u64() < 3 || value.u64() > 0x7fffffff {
			return error('invalid service control descriptor')
		}
		service_fd = value.int()
		at = os.args.len
	}
	for at < os.args.len {
		option := os.args[at]
		if option == '' {
			at++
			continue
		}
		if option in ['-l', '-w', '-h'] && at + 1 < os.args.len {
			if option == '-l' {
				activity = os.args[at + 1]
			} else {
				value := os.args[at + 1]
				if value.len == 0 || !value.bytes().all(it >= `0` && it <= `9`) || value.int() < 64 || value.int() > 4096 {
					return error('surface dimensions must be between 64 and 4096')
				}
				os.setenv(if option == '-w' {
					'VINIX_SURFACE_WIDTH'
				} else {
					'VINIX_SURFACE_HEIGHT'
				}, value, true)
			}
			at += 2
		} else {
			return error('unsupported native APK option: ' + option)
		}
	}
	stack_kb := (os.getenv_opt('VINIX_ANDROID_STACK_KB') or { '32768' }).int()
	if stack_kb < 8192 || stack_kb > 262144 {
		return error('VINIX_ANDROID_STACK_KB must be between 8192 and 262144')
	}
	stack := C.rlimit{ rlim_cur: u64(stack_kb) * 1024, rlim_max: u64(stack_kb) * 1024 }
	if C.setrlimit(3, &stack) != 0 { return error('cannot set ART stack limit') }
	data_root := os.getenv_opt('XDG_DATA_HOME') or { (os.getenv_opt('HOME') or { '/root' }) + '/.local/share' }
	data := os.getenv_opt('ANDROID_APP_DATA_DIR') or { data_root + '/vinix/android/' + os.base(apk) + '_' }
	identity := nativeidentity.from_environment()!
	nativeaccountauth.verify_environment_launch(apk, identity.uid, identity.gid, identity.enabled)!
	if service_fd >= 0 {
		if !identity.enabled || os.getenv_opt('VINIX_ANDROID_ACCOUNT_REGISTRY') == none {
			return error('service host requires a protected registry and explicit Unix credentials')
		}
		nativeaccountauth.inherit_root_channel(service_fd)!
		identity.activate_headless(apk, root)!
	} else {
		identity.activate(apk, root, os.getenv('VINIX_SURFACE_PATH'))!
	}
	nativecache.prepare()!
	os.mkdir_all(data)!
	native := nativeapk.install(apk, data, 'arm64-v8a')!
	os.setenv('VINIX_ANDROID_NATIVE_DIR', native, true)
	os.setenv('BIONIC_LD_LIBRARY_PATH', native + ':' + data + '/*', true)
	os.setenv('XDG_DATA_DIRS', root + '/usr/share/vinix-android-ws', true)
	os.setenv('ANDROID_APP_DATA_DIR', data, true)
	os.setenv('VINIX_ANDROID_ROOT', root, true)
	os.setenv('ANDROID_ROOT', root, true)
	os.setenv('ANDROID_DATA', data, true)
	os.setenv('VINIX_ALLOW_WX', '1', true)
	os.setenv('LD_PRELOAD', root + '/usr/lib/libvinix-android-compat.so', true)
	paths := root + '/usr/lib/art/native-ws:' + root + '/lib:' + root + '/usr/lib:' + root + '/usr/lib/art:' + root + '/usr/lib/java/dex/art/natives'
	os.setenv('LD_LIBRARY_PATH', paths, true)
	for name in ['DISPLAY', 'WAYLAND_DISPLAY', 'GDK_BACKEND', 'GTK_PATH', 'RUN_FROM_BUILDDIR'] {
		os.unsetenv(name)
	}
	for entry in os.ls(root + '/usr/share/icu')! {
		if os.is_dir(root + '/usr/share/icu/' + entry) {
			os.setenv('ICU_DATA', root + '/usr/share/icu/' + entry, true)
		}
	}
	mut arguments := ['--library-path', paths, root + '/usr/bin/vinix-android-native', apk]
	if service_fd >= 0 { arguments << ['--service-fd', service_fd.str()] }
	else { arguments << activity }
	os.execvp(root + '/lib/ld-musl-aarch64.so.1', arguments)!
}
