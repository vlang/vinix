// SPDX-License-Identifier: GPL-2.0-or-later
// Compile the freestanding WebView delta over a previously sealed native tree.
// Results stay outside Git; this does not substitute for an ART/browser run.
module main

import os
import androidtools

fn run(work string, label string, argv []string) ! {
	result := os.exec(argv)
	os.write_file(work + '/' + label + '.log', result.output)!
	if result.exit_code != 0 { return error(label + ': ' + result.output) }
}

fn web_binding(line string) bool {
	return line.starts_with('android/webkit/WebView|')
		|| line.starts_with('android/webkit/CookieManager|')
		|| line.starts_with('android/view/View|native_destructor|')
}

fn main() {
	if os.args.len != 4 {
		eprintln('usage: check-native-webview SEALED_BUILD FRAMEWORK_SMALI OUTPUT_DIR')
		exit(2)
	}
	base := os.real_path(os.args[1])
	smali := os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	if os.exists(work) {
		eprintln('output directory already exists')
		exit(2)
	}
	os.mkdir_all(work + '/atlframework')!
	for name in os.ls(base + '/native/atlframework')! {
		if name.ends_with('.v') {
			os.cp(base + '/native/atlframework/' + name, work + '/atlframework/' + name)!
		}
	}
	for name in ['webview.v', 'html.v', 'ws_views.v', 'bootstrap.v', 'runtime.v'] {
		os.cp('build-support/android/nativews/' + name, work + '/atlframework/' + name)!
	}
	// Optional account delta belongs to its implementation owner. Capture and
	// compile it without changing that source or claiming account execution.
	for name in ['account_client.v', 'account_text.v'] {
		path := 'build-support/android/nativews/' + name
		if os.is_file(path) { os.cp(path, work + '/atlframework/' + name)! }
	}
	// The sealed tree supplies unrelated JNI bindings. Select the WebView
	// delta verbatim from production while other account bindings are in flight.
	old_lines := os.read_file(base + '/native/bindings.txt')!.split_into_lines()
	web_lines := os.read_file('build-support/android/nativews/bindings.txt')!.split_into_lines().filter(web_binding(it))
	mut lines := old_lines.filter(!web_binding(it))
	lines << web_lines
	spec := lines.join('\n')
	os.write_file(work + '/bindings.txt', spec)!
	mut generated := os.read_file(base + '/native/atlframework/ws_generated.v')!
	mut additions := []string{}
	for line in web_lines {
		parts := line.split('|')
		key := parts[0] + '|' + parts[1] + '|'
		previous := old_lines.filter(it.starts_with(key))
		if previous.len == 0 {
			additions << line
			continue
		}
		assert previous.len == 1
		body := previous[0].all_after(key)
		if body != parts[2] {
			assert generated.count(body) == 1, 'ambiguous sealed JNI binding: ' + key
			generated = generated.replace(body, parts[2])
		}
	}
	for line in web_lines {
		if line.trim_space() == '' || line.starts_with('#') { continue }
		class_name := line.all_before('|')
		path := work + '/smali/' + class_name + '.smali'
		os.mkdir_all(os.dir(path))!
		os.cp(smali + '/' + class_name + '.smali', path)!
	}
	mut web_sources := []string{}
	for name in ['WebView', 'WebSettings', 'WebViewClient', 'CookieManager'] {
		web_sources << os.read_file(smali + '/android/webkit/' + name + '.smali')!
	}
	patched := androidtools.framework_webview_sources(web_sources[0], web_sources[1], web_sources[2], web_sources[3])!
	for name, source in patched {
		os.write_file(work + '/smali/android/webkit/' + name + '.smali', source)!
	}
	new_bindings := androidtools.native_ws_bindings(additions.join('\n'), work + '/smali')!
	generated += '\n' + new_bindings.all_after('module atlframework\n').replace('fn ws_binding_', 'fn ws_web_binding_')
	os.write_file(work + '/atlframework/ws_generated.v', generated)!
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		os.cp(base + '/native/' + name, work + '/' + name)!
	}
	bootstrap := os.read_file(work + '/atlframework/bootstrap.v')!
	runtime := os.read_file(work + '/atlframework/runtime.v')!
	init_at := bootstrap.index('ws_web_init()') or { panic('missing browser init') }
	load_at := bootstrap.index('C.dlopen(') or { panic('missing VM bootstrap') }
	assert init_at < load_at
	assert runtime.contains('ws_queue_end_pump()\n\t\t\tws_web_pump(e)')
	assert runtime.contains('ws_web_shutdown(e)')
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('V', base + '/tools/v_old276', true)
	os.setenv('VINIX_V_COMPILER', base + '/tools/v_old276', true)
	run(work, 'generate', [base + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2',
		'run', os.real_path('tests/linuxkpi/generate_module.v'), work + '/atlframework',
		work + '/android-native.c', '--arch', 'arm64'])!
	run(work, 'cross-syntax', ['/opt/homebrew/bin/aarch64-linux-musl-gcc', '-D_GNU_SOURCE', '-Wall',
		'-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter',
		'-fsyntax-only', '-I' + work, work + '/android-native.c'])!
	println('NATIVE-WEBVIEW-COMPILE-PASS weak-view-lifetime engine-frame-copy JNI-looper-hooks cookies')
}
