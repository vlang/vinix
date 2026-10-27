// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os
import crypto.sha256
import generators

fn native_ws_hex4(code u16) string {
	hex := code.hex()
	return '0'.repeat(4 - hex.len) + hex
}

pub fn native_ws_jni_escape(value string) string {
	mut result := ''
	for c in value.runes() {
		result += match c {
			`_` { '_1' }
			`;` { '_2' }
			`[` { '_3' }
			`/` { '_' }
			`$` { '_00024' }
			else {
				if c > 0xffff {
					n := u32(c) - 0x10000
					'_0' + native_ws_hex4(u16(0xd800 + (n >> 10))) + '_0' + native_ws_hex4(u16(0xdc00 + (n & 1023)))
				} else if c > 127 {
					'_0' + native_ws_hex4(u16(c))
				} else {
					c.str()
				}
			}
		}
	}
	return result
}

pub fn native_ws_abi(descriptor string) ![]string {
	mut result := []string{}
	mut at := 0
	for at < descriptor.len {
		c := descriptor[at]
		if c == `L` {
			end := descriptor[at..].index(';') or { return error('unterminated JNI object descriptor') }
			if end <= 1 { return error('empty JNI class name') }
			at += end
			result << 'voidptr'
		} else if c == `[` {
			for at < descriptor.len && descriptor[at] == `[` { at++ }
			if at == descriptor.len { return error('unterminated JNI array descriptor') }
			if descriptor[at] == `L` {
				end := descriptor[at..].index(';') or { return error('unterminated JNI array class') }
				if end <= 1 { return error('empty JNI array class') }
				at += end
			} else if descriptor[at] !in [`Z`, `B`, `C`, `S`, `I`, `J`, `F`, `D`] {
				return error('invalid JNI array element')
			}
			result << 'voidptr'
		} else {
			result << match c {
				`V` {
					if descriptor.len != 1 { return error('void JNI parameter') }
					''
				}
				`J` { 'i64' }
				`D` { 'f64' }
				`F` { 'f32' }
				`Z`, `B` { 'u8' }
				`S` { 'i16' }
				`C` { 'u16' }
				`I` { 'i32' }
				else { return error('invalid JNI primitive descriptor') }
			}
		}
		at++
	}
	return result
}

pub fn native_ws_cli(argv []string) !int {
	args := parse_arguments(argv, ['--cc', '--arch'], []string{}, []string{}, 3, 3, 'compile-native-ws SMALI_DIR RUNTIME_ROOT OUTPUT_DIR [--cc CC --arch arm64]')!
	build_native_ws(os.abs_path(args.positional[0]), os.abs_path(args.positional[1]), os.abs_path(args.positional[2]), args.value('--cc', 'aarch64-linux-musl-gcc'), args.value('--arch', 'arm64'))!
	return 0
}

fn native_ws_broadcast_bridge(source string) !bool {
	if source.count('.method public run()V') != 1 { return false }
	if source.split_into_lines().filter(it.starts_with('.class ')) != ['.class public final Landroid/atl/VinixBroadcast;']
		|| source.split_into_lines().filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;']
		|| source.count('.method ') != 4 || source.count('.end method') != 4
		|| source.count('run()V') != 1 {
		return error('unexpected broadcast Java task')
	}
	header := '.method public run()V'
	actual := header + source.all_after(header).all_before('.end method') + '.end method'
	// Baksmali emits .registers instead of .locals and adds blank/comment lines.
	// Compare every semantic line after that single equivalent register spelling.
	canonical := framework_broadcast_run_method().split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#'))
	normalized := actual.replace('.registers 5', '.locals 4').split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#'))
	if normalized != canonical { return error('noncanonical broadcast Java bridge') }
	return true
}

// Generate bindings separately so native delta fixtures can validate the exact
// framework declarations without rebuilding every runtime dependency.
pub fn native_ws_bindings(spec string, smali string) !string {
	mut generated := '@[translated]\nmodule atlframework\n'
	mut count := 0
	for line in spec.split_into_lines() {
		if line.trim_space() == '' || line.starts_with('#') { continue }
		parts := line.split('|')
		if parts.len != 3 { return error('invalid native binding: ' + line) }
		class_name, method_name, body := parts[0], parts[1], parts[2]
		source := os.read_file(smali + '/' + class_name + '.smali')!
		// Historical frameworks still require this lazy JNI export. New ones
		// replace only this task with the canonical Java pending-result bridge.
		// Keep every other stale/non-native binding an error.
		if class_name == 'android/atl/VinixBroadcast' && method_name == 'run'
			&& body == 'ws_broadcast_run(e,this)'
			&& native_ws_broadcast_bridge(source)! {
			continue
		}
		mut found := false
		for declaration in source.split_into_lines() {
			if !declaration.starts_with('.method ') || !declaration.contains(' native ') {
				continue
			}
			signature := declaration.all_after_last(' ')
			if (method_name.contains('(') && signature != method_name) || (!method_name.contains('(') && signature.all_before('(') != method_name) {
				continue
			}
			parameters := signature.all_after('(').all_before(')')
			results := native_ws_abi(signature.all_after(')'))!
			if results.len != 1 { return error('invalid native result descriptor') }
			result := results[0]
			mut args := ['e voidptr', 'this voidptr']
			for index, kind in native_ws_abi(parameters)! { args << 'p${index} ${kind}' }
			symbol := 'Java_' + native_ws_jni_escape(class_name) + '_' + native_ws_jni_escape(signature.all_before('(')) + '__' + native_ws_jni_escape(parameters)
			mut native_body := body
			if class_name == 'android/atl/GskCanvas' && method_name != 'finalize' {
				failure_return := if result == '' { 'return' } else if result == 'voidptr' { 'return nil' } else { 'return 0' }
				native_body = 'previous := ws_canvas_enter(e,this,p0); defer { ws_canvas_leave(previous) }; if pending(e) { ${failure_return} };\n' + native_body
			} else if class_name in ['android/view/View', 'android/view/ViewGroup'] && method_name in ['native_drawBackground', 'native_drawContent', 'native_drawChildren'] {
				native_body = "previous := ws_canvas_enter(e,p1,get_long(e,p1,c'android/atl/GskCanvas',c'snapshot')); defer { ws_canvas_leave(previous) }; if pending(e) { return };\n" + native_body
			}
			generated += "\n@[export: '${symbol}']\nfn ws_binding_${count}(${args.join(', ')}) ${result} {\n    unsafe {\n ${native_body}\n }\n}\n"
			count++
			found = true
		}
		if !found {
			return error('binding does not match native declaration: ' + class_name + '.' + method_name)
		}
	}
	return generated
}

pub fn build_native_ws(smali string, runtime string, output string, compiler string, arch string) ! {
	os.mkdir_all(output + '/atlframework')!
	build_native_timezones(runtime, output)!
	// Carry the runtime's generated Java trust store when updating older
	// guest images, which may predate JKS staging.
	os.cp(runtime + '/etc/ssl/certs/java/cacerts', output + '/cacerts')!
	vcompiler := os.real_path(os.find_abs_path_of_executable('v')!)
	os.cp(os.dir(vcompiler) + '/thirdparty/fontstash/stb_truetype.h', output + '/stb_truetype.h')!
	os.cp(os.dir(vcompiler) + '/thirdparty/stb_image/stb_image.h', output + '/stb_image.h')!
	sqlite_header := if os.is_file(runtime + '/usr/include/sqlite3.h') {
		runtime + '/usr/include/sqlite3.h'
	} else if os.is_file('/usr/include/sqlite3.h') {
		'/usr/include/sqlite3.h'
	} else {
		'/opt/homebrew/opt/sqlite/include/sqlite3.h'
	}
	os.cp(sqlite_header, output + '/sqlite3.h')!
	for dir in ['atlframework', 'nativews'] {
		for name in os.ls(root() + '/build-support/android/' + dir)! {
			if name.ends_with('.v') {
				os.cp(root() + '/build-support/android/' + dir + '/' + name, output + '/atlframework/' + name)!
			}
		}
	}
	// This upstream header describes the existing, GTK-independent resource ABI.
	header := output + '/androidfw_c_api.h'
	if !os.exists(header) {
		checked(['curl', '-fLsS',
			'https://gitlab.com/android_translation_layer/art_standalone/-/raw/e78bf68917bcaaf58fef3960cd88793b3b7f39cc/libandroidfw/include/androidfw/androidfw_c_api.h',
			'-o', header])!
	}
	if sha256.sum(os.read_bytes(header)!).hex() != 'e233a055133776838b8044ca43eb9e8dfac387a0580918786d60207276d37af4' {
		return error('libandroidfw header checksum mismatch')
	}
	// Bindings are explicit: a new native API is never silently stubbed.
	spec := os.read_file(root() + '/build-support/android/nativews/bindings.txt')!
	generated := native_ws_bindings(spec, smali)!
	count := generated.count('\nfn ws_binding_')
	os.write_file(output + '/atlframework/ws_generated.v', generated)!
	generators.generate_module(output + '/atlframework', output + '/android-native.c', arch, []string{})!
	generators.generate_module(root() + '/build-support/android/wsloader', output + '/android-loader.c', arch, []string{})!
	build_native_bionic(output, runtime, compiler, arch)!
	// Keep the preloaded Bionic ABI provider in step with the native loader.
	build_runtime(output + '/libvinix-android-compat.so', compiler, output + '/runtime-generated', arch)!
	build_native_gl_dispatch(output, compiler, arch)!
	build_native_egl_provider(output, runtime, compiler)!
	build_native_vulkan_loader(output, compiler, arch)!
	checked([compiler, '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label',
		'-Wno-unused-parameter', '-fvisibility=hidden', '-shared', '-fPIC', '-I' + output,
		'-Wl,-z,max-page-size=65536', '-Wl,--allow-shlib-undefined', output + '/android-native.c',
		runtime + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed',
		if os.is_file(runtime + '/usr/lib/libpng16.so.16') {
			runtime + '/usr/lib/libpng16.so.16'
		} else {
			'/usr/lib/libpng16.so.16'
		},
		if os.is_file(runtime + '/usr/lib/libsqlite3.so.0') {
			runtime + '/usr/lib/libsqlite3.so.0'
		} else {
			'/usr/lib/libsqlite3.so.0'
		}, '-ldl', '-lm', '-o', output + '/libvinix-android-native.so'])!
	checked(['v', '-os', 'linux', '-arch', arch, '-cc', compiler, '-gc', 'none', '-o',
		output + '/vinix-android-native', root() + '/build-support/android/native-entry.v'])!
	checked(['v', '-os', 'linux', '-arch', arch, '-cc', compiler, '-gc', 'none', '-o',
		output + '/run-android', '-cflags', '-O2', root() + '/build-support/android/native-run.v'])!
	println('ANDROID-WS-BUILD bindings=${count} library_sha256=' + sha256.sum(os.read_bytes(output + '/libvinix-android-native.so')!).hex())
}
