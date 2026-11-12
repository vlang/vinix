// SPDX-License-Identifier: GPL-2.0-or-later
// Current-checkout JNI build; no historical compiler or bundle pins.
module main

import androidtools
import json2
import os

fn run(argv []string, log string) ! {
	code := os.system(argv.map(os.quoted_path(it)).join(' ') + ' > ' + os.quoted_path(log) + ' 2>&1')
	if code != 0 { return error('command failed (${code}): ${argv.join(" ")}; see ${log}') }
}

fn build(framework string, output string) ! {
	repo := os.real_path(os.dir(@FILE) + '/../..')
	v := '/Users/alex/code/v/v'
	if os.exists(output) { return error('output must be fresh: ' + output) }
	os.mkdir_all(output + '/native/atlframework')!
	os.mkdir_all(output + '/tools')!
	os.setenv('VINIX_V_COMPILER', v, true)
	os.setenv('V', v, true)
	os.setenv('VEXE', v, true)
	os.chdir(repo)!
	run([v, 'version'], output + '/v-version.log')!
	for directory in ['atlframework', 'nativews'] {
		for name in os.ls(repo + '/build-support/android/' + directory)! {
			if name.ends_with('.v') {
				target := output + '/native/atlframework/' + name
				if os.exists(target) { return error('duplicate native source: ' + name) }
				os.cp(repo + '/build-support/android/' + directory + '/' + name, target)!
			}
		}
	}
	spec := os.read_file(repo + '/build-support/android/nativews/bindings.txt')!
	os.write_file(output + '/native/atlframework/ws_generated.v', androidtools.native_ws_bindings(spec, framework + '/smali')!)!
	headers := os.getenv_opt('VINIX_ANDROID_NATIVE_HEADERS') or {
		'/Users/alex/.local/state/vinix/android/account-native-compile-2026-10-26-r1'
	}
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		os.cp(headers + '/' + name, output + '/native/' + name)!
	}
	run([v, '-new-compiler', '-no-parallel', '-nocache', '-cc', 'cc', '-path', '@vlib|' + repo + '/tests/linuxkpi', '-o', output + '/tools/generate', repo + '/tests/linuxkpi/generate_module.v'], output + '/compile-generator.log')!
	run([output + '/tools/generate', output + '/native/atlframework', output + '/native/android-native.c', '--arch', 'arm64'], output + '/generate.log')!
	runtime := os.getenv_opt('VINIX_ANDROID_RUNTIME') or {
		repo + '/build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
	}
	run(['/opt/homebrew/bin/aarch64-linux-musl-gcc', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden',
		'-shared', '-fPIC', '-I' + output + '/native', '-Wl,-z,max-page-size=65536', '-Wl,--no-undefined',
		'-Wl,--allow-shlib-undefined', output + '/native/android-native.c', runtime + '/usr/lib/art/libandroidfw.so',
		'-Wl,--no-as-needed', runtime + '/usr/lib/libpng16.so.16', runtime + '/usr/lib/libsqlite3.so.0', '-ldl', '-lm',
		'-o', output + '/native/libvinix-android-native.so'], output + '/link.log')!
	elf := os.read_bytes(output + '/native/libvinix-android-native.so')!
	if elf.len < 64 || elf[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || elf[16..20] != [u8(3), 0, 183, 0] {
		return error('expected AArch64 ELF64 shared library')
	}
	os.write_file(output + '/build.json', json2.encode({
		'compiler': v, 'framework': framework, 'headers': headers, 'runtime': runtime,
		'scope': 'Current sources and current V; host build only, ARM execution pending'
	}, prettify: true))!
	println('CURRENT-NATIVE-LATEST-BUILD-PASS ' + output)
}

fn main() {
	if os.args.len != 3 { eprintln('usage: build-current-native-latest FRAMEWORK FRESH_OUTPUT'); exit(2) }
	build(os.abs_path(os.args[1]), os.abs_path(os.args[2])) or { eprintln(err); exit(1) }
}
