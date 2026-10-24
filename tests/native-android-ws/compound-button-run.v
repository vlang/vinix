// SPDX-License-Identifier: GPL-2.0-or-later
// Frozen paired regression preparation (264/266 use262; 268/270 use266). Select the
// attempt with VINIX_COMPOUND_ATTEMPT (default258). Run each action
// once from the repository root; run the two resulting suite/config pairs only
// after preparation. Baseline APK and native runtime are preserved unchanged.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const attempt = os.getenv_opt('VINIX_COMPOUND_ATTEMPT') or { '258' }
const base = 'build/android-maps/compound' + attempt
const baseline_attempt = if attempt in ['268', '270'] { '266' } else if attempt in ['264', '266'] { '262' } else { '247' }
const previous = 'build/android-maps/compound' + baseline_attempt
const fixture_name = if attempt in ['268', '270'] { 'compound-text-fixture.v' } else if attempt in ['264', '266'] { 'widget-geometry-fixture.v' } else { 'compound-button-fixture.v' }
const fixture_source = 'tests/native-android-ws/' + fixture_name
const fixture_frozen = base + '/source/' + fixture_name
const compiler = '/Users/alex/code/v/v_old'
const audit = '/Users/alex/.local/state/vinix/android/compound' + attempt + '-2026-10-24'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn checked(args []string) !string {
	r := os.exec(args)
	if r.exit_code != 0 { return error(args.str() + '\n' + r.output) }
	return r.output
}

fn write_json[T](path string, value T) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn clone_file(from string, to string) ! {
	assert !os.exists(to)
	os.mkdir_all(os.dir(to))!
	checked(['cp', '-c', os.real_path(from), to])!
}

fn snapshot(kind string, count int) !map[string]string {
	exact := json2.decode[map[string]string](gzip.decompress(os.read_bytes(previous + '/' + kind + '/exact-sources.json.gz')!)!.bytestr())!
	old := json2.decode[map[string]string](os.read_file(previous + '/' + kind + '/sources.json')!)!
	assert exact.len == count && old.len == count
	directory := if kind == 'framework' { '/sources/' } else { '/atlframework/' }
	for path, source in exact {
		assert sha256.sum(source.bytes()).hex() == old[path]!, path
		os.mkdir_all(os.dir(base + '/' + kind + directory + path))!
		os.write_file(base + '/' + kind + directory + path, source)!
	}
	return exact
}

fn framework_paths() string {
	return base + '/framework/sources|tests/host-policy|tests/linuxkpi|tests/native-generators|tests/native-guest-tools|build-support|tools|@vlib|@vmodules'
}

fn freeze_closure(label string, argv []string) ! {
	listing := checked(argv)!
	os.write_file(base + '/' + label + '-v-files.txt', listing)!
	mut pins := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		pins[path] = hash(path)!
		target := base + '/closure-inputs/' + path.trim_left('/')
		if !os.exists(target) { clone_file(path, target)! }
	}
	assert pins.len > 0
	write_json(base + '/' + label + '-v-files.json', pins)!
}

fn verify_closure(label string) ! {
	for path, expected in json2.decode[map[string]string](os.read_file(base + '/' + label + '-v-files.json')!)! {
		assert hash(path)! == expected, path
	}
}

fn section(source string, marker string, next string) string {
	assert source.count(marker) == 1, marker
	tail := source.all_after(marker)
	if next == '' {
		assert !tail.contains('\nfn ') && !tail.contains('\npub fn '), marker
		return marker + tail
	}
	assert source.count(next) == 1 && tail.contains(next), next
	return marker + tail.all_before(next)
}

fn replace_section(original string, live string, marker string, next string) string {
	old := section(original, marker, next)
	replacement := section(live, marker, next)
	assert old.all_before('\n') == replacement.all_before('\n'), marker
	prefix := original.all_before(marker)
	return prefix + replacement + original[prefix.len + old.len..]
}

fn replace_binding_body(original string, symbol string, body string) string {
	marker := "@[export: '${symbol}']\n"
	assert original.count(marker) == 1
	tail := original.all_after(marker)
	assert tail.contains('\n@[export: ')
	old := tail.all_before('\n@[export: ')
	assert old.count('    unsafe {\n') == 1 && old.count('\n }\n}\n') == 1
	replacement := old.all_before('    unsafe {\n') + '    unsafe {\n ' + body + '\n }\n}\n'
	return original.all_before(marker) + marker + replacement + '\n@[export: ' + tail.all_after('\n@[export: ')
}

fn freeze_geometry_native(native map[string]string) ! {
	old := native['ws_views.v']!
	live := os.read_file('build-support/android/nativews/ws_views.v')!
	marker := 'struct WsView {\n'
	next := '\nfn ws_view('
	old_struct := section(old, marker, next)
	live_struct := section(live, marker, next)
	mut kept := []string{}
	mut added := map[string]string{}
	for line in live_struct.split_into_lines() {
		parts := line.fields()
		if parts.len > 0 && parts[0] in ['min_height', 'min_height_pixels'] {
			assert parts.len == 2 && parts[1] == if parts[0] == 'min_height' { 'i32' } else { 'bool' }
			assert parts[0] !in added
			added[parts[0]] = parts[1]
		} else { kept << line }
	}
	assert added.len == 2 && kept.join('\n') == old_struct.trim_right('\n')
	mut updated := replace_section(old, live, marker, next)
	updated = replace_section(updated, live, 'fn ws_measure(', '\nfn ws_layout(')
	os.write_file(base + '/native/atlframework/ws_views.v', updated)!
	mut rows := map[string]string{}
	for line in os.read_file('build-support/android/nativews/bindings.txt')!.split_into_lines() {
		parts := line.split('|')
		if parts.len == 3 && parts[0] == 'android/widget/TextView' && parts[1] in ['setMinLines', 'getMinLines', 'setMinHeight', 'getMinHeight'] {
			assert parts[1] !in rows
			rows[parts[1]] = line
		}
	}
	assert rows.len == 4
	mut generated := native['ws_generated.v']!
	for pair in [['setMinLines', 'Java_android_widget_TextView_setMinLines__I'], ['getMinLines', 'Java_android_widget_TextView_getMinLines__']] {
		generated = replace_binding_body(generated, pair[1], rows[pair[0]]!.all_after_last('|'))
	}
	for spec in [['setMinHeight', 'Java_android_widget_TextView_setMinHeight__I', 'ws_geometry_set_min_height', 'e voidptr, this voidptr, p0 i32', ''], ['getMinHeight', 'Java_android_widget_TextView_getMinHeight__', 'ws_geometry_get_min_height', 'e voidptr, this voidptr', 'i32']] {
		assert !generated.contains("@[export: '${spec[1]}']") && !generated.contains('fn ' + spec[2] + '(')
		generated += "\n@[export: '${spec[1]}']\nfn ${spec[2]}(${spec[3]}) ${spec[4]} {\n    unsafe {\n ${rows[spec[0]]!.all_after_last('|')}\n }\n}\n"
	}
	os.write_file(base + '/native/atlframework/ws_generated.v', generated)!
	write_json(base + '/native/binding-rows.json', rows)!
	clone_file('build-support/android/nativews/bindings.txt', base + '/native/bindings.txt')!
}

fn freeze() ! {
	assert !os.exists(base + '/framework') && !os.exists(base + '/native')
	write_json(base + '/attempt.json', {'attempt': attempt, 'VINIX_COMPOUND_ATTEMPT': os.getenv('VINIX_COMPOUND_ATTEMPT'), 'base': base, 'audit': audit, 'baseline_attempt': baseline_attempt, 'fixture_source': fixture_source, 'fixture_frozen': fixture_frozen})!
	assert hash(previous + '/framework/api-impl.jar')! == if attempt in ['268', '270'] { '69f560aef5965acd2e4c1eba35a545dae5c8e48708695b0c747a1267d75643c3' } else if attempt in ['264', '266'] { 'a37ffeceffd29e7bd5db825e079949f5a6e3f71dd04edba8c61239bd1971b71c' } else { '73a10513135f9e264df9afdc7139c5370d67016d864be82fe0d6b2adba1f459b' }
	assert hash(previous + '/native/libvinix-android-native.so')! == if attempt in ['268', '270'] { '0a9928b59585bc7e1d6518c22a9a388f5bb99e4f43f3c0838d6c1c47588fb680' } else if attempt in ['264', '266'] { '3bbc2d9439961be351f18e391f305ded393d7a10b67f1cf2e80adad2a6569b80' } else { '78893e6767c9398a7d6cb513f0f34b8536604afaa065e383f46cb98e9d003f37' }
	framework := snapshot('framework', 125)!
	if attempt in ['268', '270'] {
		file := 'androidtools/framework_classes.v'
		live := os.read_file('tests/native-android-tools/' + file)!
		os.write_file(base + '/framework/sources/' + file, replace_section(framework[file]!, live, 'fn framework_text_widgets(', '\nfn framework_check_widgets('))!
	} else if attempt in ['264', '266'] {
		for spec in [['androidtools/framework_geometry.v', 'fn framework_view_geometry(', '\nfn framework_viewgroup_clipping('], ['androidtools/framework_view_canvas.v', 'fn framework_view_canvas(', ''], ['androidtools/framework_classes.v', 'fn framework_text_widgets(', '\nfn framework_check_widgets(']] {
			live := os.read_file('tests/native-android-tools/' + spec[0])!
			os.write_file(base + '/framework/sources/' + spec[0], replace_section(framework[spec[0]]!, live, spec[1], spec[2]))!
		}
	} else {
	file := 'androidtools/framework_classes.v'
	marker := 'fn framework_check_widgets(smali string) ! {'
	live := os.read_file('tests/native-android-tools/' + file)!
	old := framework[file]!
	assert old.count(marker) == 1 && live.count(marker) == 1
	assert !old.all_after(marker).contains('\nfn ') && !live.all_after(marker).contains('\nfn ')
	os.write_file(base + '/framework/sources/' + file, old.all_before(marker) + marker + live.all_after(marker))!
	}
	native := snapshot('native', 83)!
	if attempt in ['268', '270'] {
		live := os.read_file('build-support/android/nativews/ws_views.v')!
		os.write_file(base + '/native/atlframework/ws_views.v', replace_section(native['ws_views.v']!, live, 'fn ws_draw_content(', '\nfn ws_draw_children('))!
		binding_hash := json2.decode[map[string]string](os.read_file(previous + '/frozen-inputs.json')!)!['build-support/android/nativews/bindings.txt']!
		assert hash(previous + '/native/bindings.txt')! == binding_hash
		assert hash('build-support/android/nativews/bindings.txt')! == binding_hash
		clone_file(previous + '/native/bindings.txt', base + '/native/bindings.txt')!
	} else if attempt in ['264', '266'] { freeze_geometry_native(native)! } else {
	old_native := native['check_widgets.v']!
	live_native := os.read_file('build-support/android/nativews/check_widgets.v')!
	native_marker := 'fn ws_checked('
	next := '\nfn ws_check_listener('
	assert old_native.count(native_marker) == 1 && live_native.count(native_marker) == 1
	assert old_native.all_after(next) == live_native.all_after(next)
	os.write_file(base + '/native/atlframework/check_widgets.v', old_native.all_before(native_marker) + native_marker + live_native.all_after(native_marker).all_before(next) + next + old_native.all_after(next))!
	}
	for kind, count in {'framework': 125, 'native': 83} {
		directory := if kind == 'framework' { '/sources/' } else { '/atlframework/' }
		mut sources := map[string]string{}
		mut exact := map[string]string{}
		mut delta := []string{}
		baseline := if kind == 'framework' { framework } else { native }
		for path in os.walk_ext(base + '/' + kind + directory, '.v') {
			name := path.all_after(base + '/' + kind + directory)
			sources[name] = hash(path)!
			exact[name] = os.read_file(path)!
			if exact[name] != baseline[name]! { delta << name }
		}
		assert sources.len == count
		delta.sort()
		expected := if attempt in ['268', '270'] {
			if kind == 'framework' { ['androidtools/framework_classes.v'] } else { ['ws_views.v'] }
		} else if attempt in ['264', '266'] {
			if kind == 'framework' { ['androidtools/framework_classes.v', 'androidtools/framework_geometry.v', 'androidtools/framework_view_canvas.v'] } else { ['ws_generated.v', 'ws_views.v'] }
		} else { if kind == 'framework' { ['androidtools/framework_classes.v'] } else { ['check_widgets.v'] } }
		assert delta == expected, delta.str()
		write_json(base + '/' + kind + '/sources.json', sources)!
		write_json(base + '/' + kind + '/source-delta.json', json2.Any(delta))!
		os.write_file_array(base + '/' + kind + '/exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
	}
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] { clone_file(previous + '/native/' + name, base + '/native/' + name)! }
	os.mkdir_all(base + '/source')!
	os.cp(fixture_source, fixture_frozen)!
	os.cp('tests/native-android-ws/compound-button-build.v', base + '/build-framework.v')!
	os.cp(@FILE, base + '/source/compound-button-run.v')!
	manifest := json2.decode[map[string]json2.Any](os.read_file(previous + '/framework/framework-manifest.json')!)!
	mut inputs := map[string]string{}
	for path, digest in manifest['sources']!.as_map() {
		if path.starts_with('build-support/android/atlframework/') {
			assert hash(path)! == digest.str(), path
			inputs[path] = digest.str()
			clone_file(path, base + '/source/' + path)!
		}
	}
	for path in [compiler, '/opt/homebrew/opt/openjdk@25/bin/java', '/opt/homebrew/bin/aarch64-linux-musl-gcc',
		'/usr/bin/cc', '/usr/bin/clang', '/usr/bin/zip', '/opt/homebrew/opt/openjdk@25/bin/keytool',
		'build/android-native-ws/aapt2', 'build/android-native-ws/android-15/lib/apksigner.jar',
		'tests/linuxkpi/generate_module.v', 'tests/native-android-tools/androidtools/framework_classes.v',
		'build-support/android/nativews/check_widgets.v', fixture_source,
		'tests/native-android-ws/compound-button-run.v', 'tests/native-android-ws/compound-button-build.v',
		'/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		'/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'] {
		inputs[path] = hash(path)!
	}
	if attempt in ['264', '266'] {
		for path in ['tests/native-android-tools/androidtools/framework_geometry.v', 'tests/native-android-tools/androidtools/framework_view_canvas.v', 'build-support/android/nativews/ws_views.v', 'build-support/android/nativews/bindings.txt'] { inputs[path] = hash(path)! }
	}
	if attempt in ['268', '270'] {
		for path in ['build-support/android/nativews/ws_views.v', 'build-support/android/nativews/bindings.txt', previous + '/native/bindings.txt'] { inputs[path] = hash(path)! }
	}
	for name in ['usr/lib/art/libandroidfw.so', 'usr/lib/libpng16.so.16', 'usr/lib/libsqlite3.so.0'] {
		path := 'build/android-framework/calculator/overlay/opt/vinix-android-aarch64/' + name
		inputs[path] = hash(path)!
	}
	for path in os.walk_ext('build/android-framework/tools', '.jar') { inputs[path] = hash(path)! }
	for path in os.walk_ext('tests/linuxkpi/hosttest', '.v').filter(!it.ends_with('_test.v')) { inputs[path] = hash(path)! }
	for path in os.walk_ext('tests/host-policy/policyhost', '.v').filter(!it.ends_with('_test.v')) { inputs[path] = hash(path)! }
	for path in inputs.keys() {
		target := base + '/inputs/' + path.trim_left('/')
		if !os.exists(target) { clone_file(path, target)! }
	}
	write_json(base + '/frozen-inputs.json', inputs)!
	freeze_closure('framework', [compiler, '-print-v-files', '-enable-globals', '-path', framework_paths(), base + '/build-framework.v'])!
	freeze_closure('native-generator', [compiler, '-print-v-files', 'tests/linuxkpi/generate_module.v'])!
	freeze_closure('fixture', [compiler, '-print-v-files', fixture_frozen])!
	println('COMPOUND' + attempt + ' FROZEN baseline=' + baseline_attempt + ' framework=125 native=83 bounded deltas fixture=' + hash(fixture_frozen)!)
}

fn compile_step(label string, argv []string, output string) ! {
	started := time.utc().str()
	mut sources := map[string]string{}
	for path in argv.filter(it.ends_with('.v') && os.is_file(it)) { sources[path] = hash(path)! }
	mut files := map[string]string{}
	for path in argv.filter(os.is_file(it)) { files[path] = hash(path)! }
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(started), 'completed_utc': json2.Any(''),
		'attempt': json2.Any(attempt), 'VINIX_COMPOUND_ATTEMPT': json2.Any(os.getenv('VINIX_COMPOUND_ATTEMPT')),
		'compiler_sha256': json2.Any(hash(compiler)!), 'command_binary_sha256': json2.Any(hash(os.real_path(argv[0]))!), 'sources': json2.decode[json2.Any](json2.encode(sources))!, 'input_files': json2.decode[json2.Any](json2.encode(files))!, 'output_sha256': json2.Any('')}
	write_json(base + '/' + label + '-before.json', json2.Any(receipt))!
	r := os.exec(argv)
	os.write_file(base + '/' + label + '.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	if r.exit_code == 0 && output != '' { receipt['output_sha256'] = hash(output)! }
	write_json(base + '/' + label + '-receipt.json', json2.Any(receipt))!
	if r.exit_code != 0 { return error(label + ' failed: ' + r.output) }
}

fn build() ! {
	for path, expected in json2.decode[map[string]string](os.read_file(base + '/frozen-inputs.json')!)! {
		assert hash(path)! == expected, path
	}
	verify_closure('framework')!
	compile_step('build-framework-compiler', [compiler, '-nocache', '-cc', 'cc', '-enable-globals', '-cflags', '-O2', '-path', framework_paths(), '-o', base + '/build-framework', base + '/build-framework.v'], base + '/build-framework')!
	verify_closure('framework')!
	compile_step('build-framework', [base + '/build-framework'], base + '/framework/api-impl.jar')!
	os.setenv('VINIX_V_COMPILER', compiler, true)
	verify_closure('native-generator')!
	compile_step('generate-native', [compiler, '-nocache', '-cc', 'cc', 'run', 'tests/linuxkpi/generate_module.v', base + '/native/atlframework', base + '/native/android-native.c', '--arch', 'arm64'], base + '/native/android-native.c')!
	verify_closure('native-generator')!
	runtime := 'build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
	compile_step('build-native', ['/opt/homebrew/bin/aarch64-linux-musl-gcc', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden', '-shared', '-fPIC', '-I' + base + '/native', '-Wl,-z,max-page-size=65536', '-Wl,--allow-shlib-undefined', base + '/native/android-native.c', runtime + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed', runtime + '/usr/lib/libpng16.so.16', runtime + '/usr/lib/libsqlite3.so.0', '-ldl', '-lm', '-o', base + '/native/libvinix-android-native.so'], base + '/native/libvinix-android-native.so')!
	verify_closure('fixture')!
	compile_step('fixture-compiler', [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', base + '/fixture-generator', fixture_frozen], base + '/fixture-generator')!
	verify_closure('fixture')!
	compile_step('fixture', [base + '/fixture-generator', base + '/apk'], base + '/apk/probe.apk')!
	println('COMPOUND' + attempt + ' BUILT framework=' + hash(base + '/framework/api-impl.jar')! + ' native=' + hash(base + '/native/libvinix-android-native.so')! + ' apk=' + hash(base + '/apk/probe.apk')!)
}

fn clone_tree(from string, to string) ! {
	os.mkdir_all(to)!
	for name in os.ls(from)! {
		path := os.real_path(from + '/' + name)
		if os.is_dir(path) { clone_tree(path, to + '/' + name)! }
		else { clone_file(path, to + '/' + name)! }
	}
}

fn prepare_runs() ! {
	assert os.is_file(base + '/framework/api-impl.jar') && os.is_file(base + '/native/libvinix-android-native.so')
	assert os.is_file(base + '/apk/probe.apk') && !os.exists(base + '/baseline.json')
	os.cp(@FILE, base + '/source/compound-button-run-prepare.v')!
	clone_file(os.executable(), base + '/prepare-runs-binary')!
	for kind in ['framework', 'native'] {
		for name in ['sources.json', 'exact-sources.json.gz'] {
			clone_file(previous + '/' + kind + '/' + name, base + '/baseline-' + kind + '/' + name)!
		}
	}
	clone_file(previous + '/framework/framework-manifest.json', base + '/baseline-framework/framework-manifest.json')!
	if attempt in ['268', '270'] { clone_file(previous + '/native/bindings.txt', base + '/baseline-native/bindings.txt')! }
	clone_file('build/android-maps/suite239-stream.v', base + '/source/suite239-stream-original.v')!
	mut suite := os.read_file('build/android-maps/suite239-stream.v')!
	original_observation := suite.all_after('fn observation(').all_before('// Real companion packages')
	old_capture := '\tcapture := os.exec([settings[\'input_tool\']!.str(), \'screenshot\', \'--socket\', socket, \'--destination\',\n\t\tframe])'
	new_capture := '\tresult[\'observation_elapsed_seconds\'] = json2.Any(time.now().unix() - begin_at)\n\tresult[\'qemu_alive_before_capture\'] = json2.Any(qemu.is_alive())\n\tos.write_file(state + \'/observation-before-capture.json\', json2.encode(result, prettify: true) + \'\\n\')!\n\tcapture := os.exec([\'build/android-maps/maps-interact-unique258\', state, \'capture\', \'application\'])'
	assert suite.count(old_capture) == 1 && suite.count('fn main() {') == 1
	suite = suite.replace(old_capture, new_capture).replace('fn main() {', 'fn main() {\n\t$if prod { eprintln("requires assertions; compile without -prod"); exit(2) }')
	assert suite.all_after('fn observation(').all_before('// Real companion packages') == original_observation
	os.write_file(base + '/source/suite.v', suite)!
	os.mkdir_all(base + '/suite-support/nativeapk')!
	os.cp('build-support/android/nativeapk/install.v', base + '/suite-support/nativeapk/install.v')!
	freeze_closure('suite', [compiler, '-print-v-files', '-path', base + '/suite-support|@vlib|@vmodules', base + '/source/suite.v'])!
	verify_closure('suite')!
	compile_step('suite-compiler', [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-path', base + '/suite-support|@vlib|@vmodules', '-o', base + '/suite', base + '/source/suite.v'], base + '/suite')!
	verify_closure('suite')!
	os.write_file(base + '/suite-self-test.log', checked([base + '/suite', '--self-test'])!)!
	clone_file('build/android-native-ws/original-qemu-runtime.tar', base + '/base-runtime.tar')!
	for mode in ['baseline', 'fixed'] {
		dir := base + '/native-' + mode
		os.mkdir_all(dir)!
		origin := previous + '/native-fixed'
		for name in ['libdl_bio.so.0', 'vinix-android-native', 'run-android', 'vinix-desktop', 'guest', 'popular-launcher', 'libvinix-android-compat.so', 'tzdata', 'cacerts', 'bionic-ws.cfg', 'libglapi.so.0', 'libvinix-ws-GLESv1_CM.so', 'libvinix-ws-GLESv2.so', 'vinix-session'] {
			if os.is_file(origin + '/' + name) { clone_file(origin + '/' + name, dir + '/' + name)! }
		}
		for name in ['egl-ws', 'vulkan-ws'] { if os.is_dir(origin + '/' + name) { clone_tree(os.real_path(origin + '/' + name), dir + '/' + name)! } }
		framework := if mode == 'baseline' { previous } else { base }
		clone_file(framework + '/framework/api-impl.jar', dir + '/api-impl.jar')!
		clone_file(framework + '/native/libvinix-android-native.so', dir + '/libvinix-android-native.so')!
		vm := base + '/vm-' + mode
		for name in ['boot.img', 'efivars.fd'] { clone_file('build/android-native-ws/vm/' + name, vm + '/' + name)! }
		mut config := json2.decode[map[string]json2.Any](os.read_file(previous + '/fixed.json')!)!
		mut apps := config['applications']!.as_array()
		mut app := apps[0].as_map().clone()
		app['apk'] = os.abs_path(base + '/apk/probe.apk')
		app['source'] = os.abs_path(fixture_frozen)
		app['startup_seconds'] = json2.Any(30)
		apps[0] = json2.Any(app)
		config['applications'] = json2.Any(apps)
		config['base_module'] = os.abs_path(base + '/base-runtime.tar')
		config['native_dir'] = os.abs_path(dir)
		config['output'] = os.abs_path(base + '/run-' + mode)
		config['boot_image'] = os.abs_path(vm + '/boot.img')
		config['efivars'] = os.abs_path(vm + '/efivars.fd')
		write_json(base + '/' + mode + '.json', config)!
	}
	mut equality := map[string]string{}
	mut baseline_files := os.walk_ext(base + '/native-baseline', '').filter(os.is_file(it)).map(it.all_after(base + '/native-baseline/')).filter(it !in ['api-impl.jar', 'libvinix-android-native.so'])
	mut fixed_files := os.walk_ext(base + '/native-fixed', '').filter(os.is_file(it)).map(it.all_after(base + '/native-fixed/')).filter(it !in ['api-impl.jar', 'libvinix-android-native.so'])
	baseline_files.sort()
	fixed_files.sort()
	assert baseline_files == fixed_files
	for name in ['boot.img', 'efivars.fd'] {
		equality['vm/' + name] = hash(base + '/vm-baseline/' + name)!
		assert equality['vm/' + name]! == hash(base + '/vm-fixed/' + name)!, name
	}
	for path in os.walk_ext(base + '/native-fixed', '') {
		if !os.is_file(path) { continue }
		name := path.all_after(base + '/native-fixed/')
		if name in ['api-impl.jar', 'libvinix-android-native.so'] { continue }
		equality['native/' + name] = hash(path)!
		assert equality['native/' + name]! == hash(base + '/native-baseline/' + name)!, name
	}
	equality['same_apk'] = hash(base + '/apk/probe.apk')!
	write_json(base + '/paired-initial-equality.json', equality)!
	mut pins := map[string]string{}
	for path in os.walk_ext(base, '') {
		if os.is_file(path) && !path.ends_with('/prelaunch-sha256.json') { pins[path] = hash(path)! }
	}
	assert hash('build/android-maps/maps-interact-unique258')! == 'abd2dfbb01fddc83ffffae481b5d1fcab35b9ebd279f3f47abae237b00134208'
	for path in ['build/android-run', 'build/android-maps/maps-interact-unique258', 'build/qemu-horizontal/bin/qemu-system-aarch64', '/opt/homebrew/share/qemu/edk2-aarch64-code.fd', 'build/android-native-ws/aapt2', 'build/android-native-ws/android-15/lib/apksigner.jar'] { pins[path] = hash(path)! }
	write_json(base + '/prelaunch-sha256.json', pins)!
	assert !os.exists(audit + '/prelaunch')
	clone_tree(base, audit + '/prelaunch')!
	for path in pins.keys().filter(!it.starts_with(base + '/')) {
		clone_file(path, audit + '/prelaunch-external-inputs/' + path.trim_left('/'))!
	}
	mut independent := map[string]string{}
	for path in os.walk_ext(audit, '') {
		if os.is_file(path) { independent[path.all_after(audit + '/')] = hash(path)! }
	}
	write_json(audit + '/prelaunch-sha256.json', independent)!
	println('COMPOUND' + attempt + ' RUNS PREPARED same signed APK; private baseline' + baseline_attempt + '/fixed' + attempt + ' media; original classifier; bounded finalcapture; prelaunch=' + hash(base + '/prelaunch-sha256.json')!)
}

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	assert attempt.len == 3 && attempt.bytes().all(it >= `0` && it <= `9`)
	assert os.args.len == 2
	match os.args[1] { 'freeze' { freeze()! } 'build' { build()! } 'prepare-runs' { prepare_runs()! } else { panic('freeze|build|prepare-runs') } }
}
