// SPDX-License-Identifier: GPL-2.0-or-later
// Native-only284: qualified276 native83 plus queue/runtime fairness; framework282.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const base = 'build/android-maps/compound284'
const audit = '/Users/alex/.local/state/vinix/android/compound284-2026-10-25'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const archive276 = '/Users/alex/.local/state/vinix/android/compound276-2026-10-24'
const archive282 = '/Users/alex/.local/state/vinix/android/compound282-2026-10-25'
const seal276 = '37bfa8ec3449adf8a294e0b1f3ff3cabfa49123c228f308d9919cab7531d5fa4'
const seal282 = 'd966016994e234c6f4d8b2bf4a39fc041be60023fc7f61a1cf653fedeaf857d4'
const jar282 = '92b069b1dbb31b08960d00d4f33f84b068a3adf53af9339f2ef3c1a6478f0618'
const native276 = '5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca'
const fixture_name = 'queue-pump-fixture.v'
const fixture_pin = 'aa7fb0285c0df2fd47ce478e337480471db097e14af0741217795c77dbed1a15'
const queue_pin = 'ff4bb8c0657a240d47bf6164879a02e6db994aa74ad5d160c53b046d20478fa0'
const runtime_pin = '4a55617a8e2f2013c6ac51c29e8c3919a53bc269b34d4b46dffdfdc5ab17ed94'

fn hash(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := f.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn all_files(root string) ![]string {
	mut files := []string{}
	for name in os.ls(root)! {
		path := root + '/' + name
		if os.is_dir(path) { files << all_files(path)! } else if os.is_file(path) { files << path }
	}
	files.sort()
	return files
}

fn checked(argv []string) !string {
	r := os.exec(argv)
	if r.exit_code != 0 { return error(argv.str() + '\n' + r.output) }
	return r.output
}

fn write_json[T](path string, value T) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn clone_file(from string, to string) ! {
	assert !os.exists(to), to
	os.mkdir_all(os.dir(to))!
	checked(['cp', '-c', os.real_path(from), to])!
}

fn clone_tree(from string, to string) ! {
	assert !os.exists(to), to
	os.mkdir_all(to)!
	for name in os.ls(from)! {
		path := os.real_path(from + '/' + name)
		if os.is_dir(path) { clone_tree(path, to + '/' + name)! }
		else { clone_file(path, to + '/' + name)! }
	}
}

fn reference(root string, seal string, relative string, to string) ! {
	assert hash(root + '/sha256.json')! == seal
	pins := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	assert hash(root + '/' + relative)! == pins[relative]!, relative
	clone_file(root + '/' + relative, to)!
}

fn once(source string, old string, replacement string) string {
	assert source.count(old) == 1, old
	return source.replace(old, replacement)
}

// Exact inverse substitutions retain all timing231 probes without importing
// unrelated live native sources. Both directions are tested before freezing.
fn timing(source string, add bool) string {
	mut text := source
	looper := "\t\t\tstatic_void(e, c'android/os/Looper', c'loop', c'()V', nil)\n" + if source.contains('\t\t\tws_queue_end_pump()\n') { '\t\t\tws_queue_end_pump()\n' } else { '' }
	plain := [
		'\t\tfor ws.running {\n',
		looper,
		'\t\t\tws_frames_dispatch()\n',
		'\t\t\tif ws.dirty { ws_render(e) }\n',
		'\t\t\tif !pending(e) { ws_input(e) }\n',
	]
	probed := [
		'\t\tfor ws.running {\n\t\t\tws_timing231_loop++\n\t\t\ttiming231_loop_start := ws_millis()\n\t\t\ttiming231_looper := ws_millis()\n',
		looper + "\t\t\tws_timing231_phase(c'looper', timing231_looper)\n",
		"\t\t\ttiming231_frames := ws_millis()\n\t\t\tws_frames_dispatch()\n\t\t\tws_timing231_phase(c'frame_callbacks', timing231_frames)\n",
		"\t\t\tif ws.dirty {\n\t\t\t\ttiming231_render := ws_millis()\n\t\t\t\tws_render(e)\n\t\t\t\tws_timing231_phase(c'render_total', timing231_render)\n\t\t\t}\n",
		"\t\t\ttiming231_input := ws_millis()\n\t\t\tif !pending(e) { ws_input(e) }\n\t\t\tws_timing231_phase(c'input', timing231_input)\n\t\t\tws_timing231_phase(c'loop_total', timing231_loop_start)\n",
	]
	for i in 0 .. plain.len {
		text = once(text, if add { plain[i] } else { probed[i] }, if add { probed[i] } else { plain[i] })
	}
	return text
}

fn closure(label string, argv []string) ! {
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
	for path, pin in json2.decode[map[string]string](os.read_file(base + '/' + label + '-v-files.json')!)! {
		assert hash(path)! == pin, path
		assert hash(base + '/closure-inputs/' + path.trim_left('/'))! == pin, path
	}
}

fn freeze_sources(kind string) ! {
	root := if kind == 'native' { archive276 } else { archive282 }
	seal := if kind == 'native' { seal276 } else { seal282 }
	for name in ['sources.json', 'exact-sources.json.gz'] {
		reference(root, seal, 'prelaunch/' + kind + '/' + name, base + '/baseline-' + kind + '/' + name)!
	}
	old := json2.decode[map[string]string](gzip.decompress(os.read_bytes(base + '/baseline-' + kind + '/exact-sources.json.gz')!)!.bytestr())!
	old_pins := json2.decode[map[string]string](os.read_file(base + '/baseline-' + kind + '/sources.json')!)!
	assert old.len == if kind == 'native' { 83 } else { 127 }
	assert old.len == old_pins.len
	mut exact := old.clone()
	if kind == 'native' {
		queue := os.read_file('build-support/android/nativews/queue.v')!
		runtime := os.read_file('build-support/android/nativews/runtime.v')!
		assert sha256.sum(queue.bytes()).hex() == queue_pin
		assert sha256.sum(runtime.bytes()).hex() == runtime_pin
		assert timing(timing(old['runtime.v']!, false), true) == old['runtime.v']!
		exact['queue.v'] = queue
		exact['runtime.v'] = timing(runtime, true)
		assert timing(exact['runtime.v']!, false) == runtime
		clone_file('build-support/android/nativews/queue.v', base + '/source/reviewed-queue.v')!
		clone_file('build-support/android/nativews/runtime.v', base + '/source/reviewed-runtime.v')!
	}
	mut pins := map[string]string{}
	mut delta := []string{}
	for name, source in exact {
		assert sha256.sum(old[name]!.bytes()).hex() == old_pins[name]!, name
		prefix := if kind == 'native' { '/atlframework/' } else { '/sources/' }
		os.mkdir_all(os.dir(base + '/' + kind + prefix + name))!
		os.write_file(base + '/' + kind + prefix + name, source)!
		pins[name] = sha256.sum(source.bytes()).hex()
		if old[name]! != source { delta << name }
	}
	delta.sort()
	assert delta == if kind == 'native' { ['queue.v', 'runtime.v'] } else { []string{} }
	write_json(base + '/' + kind + '/sources.json', pins)!
	write_json(base + '/' + kind + '/source-delta.json', delta)!
	os.write_file_array(base + '/' + kind + '/exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
}

fn freeze() ! {
	assert !os.exists(base + '/native') && !os.exists(audit)
	os.mkdir_all(base + '/source')!
	for name in ['queue-pump-build.v', 'queue-pump-run.v'] { clone_file('tests/native-android-ws/' + name, base + '/source/' + name)! }
	for pair in [[archive276, seal276, 'qualified276'], [archive282, seal282, 'qualified282']] {
		assert hash(pair[0] + '/sha256.json')! == pair[1]
		clone_file(pair[0] + '/sha256.json', base + '/' + pair[2] + '-sha256.json')!
		write_json(base + '/' + pair[2] + '-reference.json', {'path': pair[0], 'sha256': pair[1]})!
	}
	freeze_sources('native')!
	freeze_sources('framework')!
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h', 'bindings.txt'] {
		reference(archive276, seal276, 'prelaunch/native/' + name, base + '/native/' + name)!
	}
	for name in ['api-impl.jar', 'framework-manifest.json'] {
		reference(archive282, seal282, 'prelaunch/framework/' + name, base + '/framework/' + name)!
	}
	reference(archive276, seal276, 'prelaunch/native/libvinix-android-native.so', base + '/baseline-native/libvinix-android-native.so')!
	assert hash(base + '/framework/api-impl.jar')! == jar282 && hash(base + '/baseline-native/libvinix-android-native.so')! == native276
	assert hash('tests/native-android-ws/' + fixture_name)! == fixture_pin
	clone_file('tests/native-android-ws/' + fixture_name, base + '/source/' + fixture_name)!
	mut inputs := map[string]string{}
	inputs['build-support/find-v.sh'] = hash('build-support/find-v.sh')!
	reference(archive276, seal276, 'prelaunch/frozen-inputs.json', base + '/qualified276-frozen-inputs.json')!
	for path, pin in json2.decode[map[string]string](os.read_file(base + '/qualified276-frozen-inputs.json')!)! {
		if path == '/Users/alex/code/v/v_old' {
			assert hash(compiler)! == pin
			inputs[compiler] = pin
		} else if path == '/opt/homebrew/bin/aarch64-linux-musl-gcc' || path.contains('/calculator/overlay/') {
			assert hash(path)! == pin, path
			inputs[path] = pin
		}
	}
	for path in ['/opt/homebrew/opt/openjdk@25/bin/java', '/opt/homebrew/opt/openjdk@25/bin/keytool', '/usr/bin/zip', 'build/android-native-ws/aapt2', 'build/android-native-ws/android-15/lib/apksigner.jar', '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'] { inputs[path] = hash(path)! }
	for path in all_files('build/android-framework/tools')!.filter(it.ends_with('.jar')) { inputs[path] = hash(path)! }
	cross := '/opt/homebrew/bin/aarch64-linux-musl-gcc'
	for name in ['cc1', 'as', 'collect2', 'ld'] {
		path := checked([cross, '-print-prog-name=' + name])!.trim_space()
		assert os.is_file(path), path
		inputs[path] = hash(path)!
	}
	for name in ['libgcc.a', 'crtbeginS.o', 'crtendS.o', 'crti.o', 'crtn.o', 'libc.so', 'libgcc_s.so'] {
		path := checked([cross, '-print-file-name=' + name])!.trim_space()
		assert os.is_file(path), path
		inputs[path] = hash(path)!
	}
	include := checked([cross, '-print-file-name=include'])!.trim_space()
	for path in all_files(include)! { inputs[path] = hash(path)! }
	sysroot := checked([cross, '-print-sysroot'])!.trim_space()
	assert os.is_dir(sysroot + '/include')
	for path in all_files(sysroot + '/include')! { inputs[path] = hash(path)! }
	write_json(base + '/crosscompiler-closure-scope.json', {'scope': 'New284 consumed compiler programs, GCC and musl headers, default link objects/libraries and specs. Historical276 froze its GCC driver and three explicit runtime link libraries, not this complete additional toolchain closure; no retrospective full toolchain audit is claimed.', 'sysroot': sysroot})!
	os.write_file(base + '/crosscompiler-specs.txt', checked([cross, '-dumpspecs'])!)!
	for path, _ in inputs { clone_file(path, base + '/inputs/' + path.trim_left('/'))! }
	write_json(base + '/frozen-inputs.json', inputs)!
	selected := checked(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', os.getwd()])!.trim_space()
	assert os.real_path(selected) == os.real_path(compiler)
	assert hash(selected)! == hash(compiler)!
	write_json(base + '/compiler-reference.json', {'path': compiler, 'sha256': hash(compiler)!, 'origin': archive276 + '/prelaunch/inputs/Users/alex/code/v/v_old', 'origin_manifest': seal276, 'VROOT': os.getenv('VROOT'), 'V': os.getenv('V'), 'VINIX_V_COMPILER': os.getenv('VINIX_V_COMPILER'), 'inner_compiler_selected': selected, 'scope': 'Exact retained276 compiler copied privately. Shared v_old changed; first failed freeze preserved separately. Actual generator V closure must equal276; retained find-v.sh selects this same compiler through V and VINIX_V_COMPILER. No shared compiler restoration.'})!
	closure('native-generator', [compiler, '-print-v-files', 'tests/linuxkpi/generate_module.v'])!
	reference(archive276, seal276, 'prelaunch/native-generator-v-files.json', base + '/qualified276-native-generator-v-files.json')!
	assert json2.decode[map[string]string](os.read_file(base + '/qualified276-native-generator-v-files.json')!)! == json2.decode[map[string]string](os.read_file(base + '/native-generator-v-files.json')!)!
	closure('fixture', [compiler, '-print-v-files', base + '/source/' + fixture_name])!
	println('COMPOUND284 FROZEN native83 queue/runtime only; timing231 retained; same282 framework127/JAR')
}

fn verify() ! {
	for kind in ['native', 'framework'] {
		prefix := base + '/' + kind + if kind == 'native' { '/atlframework/' } else { '/sources/' }
		mut actual := map[string]string{}
		for path in all_files(prefix.trim_right('/'))!.filter(it.ends_with('.v')) { actual[path.all_after(prefix)] = hash(path)! }
		assert actual == json2.decode[map[string]string](os.read_file(base + '/' + kind + '/sources.json')!)!
	}
	for path, pin in json2.decode[map[string]string](os.read_file(base + '/frozen-inputs.json')!)! {
		assert hash(path)! == pin, path
		assert hash(base + '/inputs/' + path.trim_left('/'))! == pin, path
	}
	assert hash(base + '/framework/api-impl.jar')! == jar282
	assert hash(base + '/baseline-native/libvinix-android-native.so')! == native276
}

fn compile_step(label string, argv []string, output string) ! {
	assert !os.exists(base + '/' + label + '-before.json'), label
	mut sources := map[string]string{}
	mut files := map[string]string{}
	for path in argv.filter(os.is_file(it)) {
		files[path] = hash(path)!
		if path.ends_with('.v') { sources[path] = files[path]! }
	}
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()), 'completed_utc': json2.Any(''), 'attempt': json2.Any('284'), 'VROOT': json2.Any(os.getenv('VROOT')), 'V': json2.Any(os.getenv('V')), 'VINIX_V_COMPILER': json2.Any(os.getenv('VINIX_V_COMPILER')), 'VINIX_COMPOUND_ATTEMPT': json2.Any(os.getenv('VINIX_COMPOUND_ATTEMPT')), 'compiler_sha256': json2.Any(hash(compiler)!), 'command_binary_sha256': json2.Any(hash(os.real_path(argv[0]))!), 'sources': json2.decode[json2.Any](json2.encode(sources))!, 'input_files': json2.decode[json2.Any](json2.encode(files))!, 'output_sha256': json2.Any('')}
	write_json(base + '/' + label + '-before.json', receipt)!
	r := os.exec(argv)
	os.write_file(base + '/' + label + '.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	if r.exit_code == 0 && output != '' { receipt['output_sha256'] = hash(output)! }
	write_json(base + '/' + label + '-receipt.json', receipt)!
	if r.exit_code != 0 { return error(label + ' failed:\n' + r.output) }
}

fn build() ! {
	verify()!
	verify_closure('native-generator')!
	compile_step('generate-native', [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', 'run', 'tests/linuxkpi/generate_module.v', base + '/native/atlframework', base + '/native/android-native.c', '--arch', 'arm64'], base + '/native/android-native.c')!
	verify_closure('native-generator')!
	runtime := base + '/inputs/build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
	compile_step('build-native', ['/opt/homebrew/bin/aarch64-linux-musl-gcc', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden', '-shared', '-fPIC', '-I' + base + '/native', '-Wl,-z,max-page-size=65536', '-Wl,--allow-shlib-undefined', base + '/native/android-native.c', runtime + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed', runtime + '/usr/lib/libpng16.so.16', runtime + '/usr/lib/libsqlite3.so.0', '-ldl', '-lm', '-o', base + '/native/libvinix-android-native.so'], base + '/native/libvinix-android-native.so')!
	verify_closure('fixture')!
	compile_step('fixture-generator', [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', base + '/fixture-generator', base + '/source/' + fixture_name], base + '/fixture-generator')!
	verify_closure('fixture')!
	compile_step('fixture', [base + '/fixture-generator', base + '/apk'], base + '/apk/probe.apk')!
	verify()!
	println('COMPOUND284 BUILT native=' + hash(base + '/native/libvinix-android-native.so')! + ' APK=' + hash(base + '/apk/probe.apk')!)
}

fn prepare() ! {
	verify()!
	for pair in [['fixture', '/apk/probe.apk'], ['build-native', '/native/libvinix-android-native.so']] {
		receipt := json2.decode[map[string]json2.Any](os.read_file(base + '/' + pair[0] + '-receipt.json')!)!
		assert receipt['exit_code']!.int() == 0 && receipt['completed_utc']!.str() != ''
		assert receipt['output_sha256']!.str() == hash(base + pair[1])!
	}
	assert !os.exists(base + '/baseline.json') && !os.exists(audit)
	reference(archive282, seal282, 'prelaunch/source/suite.v', base + '/source/suite.v')!
	reference(archive282, seal282, 'prelaunch/suite-support/nativeapk/install.v', base + '/suite-support/nativeapk/install.v')!
	reference(archive282, seal282, 'prelaunch/fixed.json', base + '/source/config282.json')!
	clone_file(os.executable(), base + '/prepare-runs-binary')!
	closure('suite', [compiler, '-print-v-files', '-path', base + '/suite-support|@vlib|@vmodules', base + '/source/suite.v'])!
	verify_closure('suite')!
	compile_step('suite-compiler', [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-path', base + '/suite-support|@vlib|@vmodules', '-o', base + '/suite', base + '/source/suite.v'], base + '/suite')!
	verify_closure('suite')!
	compile_step('suite-self-test', [base + '/suite', '--self-test'], '')!
	reference(archive276, seal276, 'prelaunch/base-runtime.tar', base + '/base-runtime.tar')!
	old_pins := json2.decode[map[string]string](os.read_file(base + '/qualified276-sha256.json')!)!
	for mode in ['baseline', 'fixed'] {
		dir := base + '/native-' + mode
		origin := archive276 + '/prelaunch/native-fixed'
		os.mkdir_all(dir)!
		for name in os.ls(origin)! {
			if name in ['api-impl.jar', 'libvinix-android-native.so'] { continue }
			if os.is_dir(origin + '/' + name) { clone_tree(origin + '/' + name, dir + '/' + name)! }
			else { clone_file(origin + '/' + name, dir + '/' + name)! }
		}
		for path in all_files(dir)! {
			name := path.all_after(dir + '/')
			assert hash(path)! == old_pins['prelaunch/native-fixed/' + name]!, name
		}
		clone_file(base + '/framework/api-impl.jar', dir + '/api-impl.jar')!
		library := if mode == 'baseline' { '/baseline-native/libvinix-android-native.so' } else { '/native/libvinix-android-native.so' }
		clone_file(base + library, dir + '/libvinix-android-native.so')!
		for name in ['boot.img', 'efivars.fd'] { reference(archive276, seal276, 'prelaunch/vm-fixed/' + name, base + '/vm-' + mode + '/' + name)! }
		mut config := json2.decode[map[string]json2.Any](os.read_file(base + '/source/config282.json')!)!
		mut app := config['applications']!.as_array()[0].as_map().clone()
		app['apk'] = os.abs_path(base + '/apk/probe.apk')
		app['source'] = os.abs_path(base + '/source/' + fixture_name)
		app['startup_seconds'] = json2.Any(90)
		config['applications'] = json2.Any([json2.Any(app)])
		config['base_module'] = os.abs_path(base + '/base-runtime.tar')
		config['native_dir'] = os.abs_path(dir)
		config['output'] = os.abs_path(base + '/run-' + mode)
		config['boot_image'] = os.abs_path(base + '/vm-' + mode + '/boot.img')
		config['efivars'] = os.abs_path(base + '/vm-' + mode + '/efivars.fd')
		write_json(base + '/' + mode + '.json', config)!
	}
	mut equality := map[string]string{}
	mut changed := []string{}
	for path in all_files(base + '/native-baseline')! {
		name := path.all_after(base + '/native-baseline/')
		if hash(path)! != hash(base + '/native-fixed/' + name)! { changed << name }
		else { equality['native/' + name] = hash(path)! }
	}
	assert changed == ['libvinix-android-native.so']
	assert all_files(base + '/native-baseline')!.len == all_files(base + '/native-fixed')!.len
	for name in ['boot.img', 'efivars.fd'] {
		assert hash(base + '/vm-baseline/' + name)! == hash(base + '/vm-fixed/' + name)!
		equality['vm/' + name] = hash(base + '/vm-baseline/' + name)!
	}
	equality['same_apk'] = hash(base + '/apk/probe.apk')!
	write_json(base + '/paired-initial-equality.json', equality)!
	verify()!
	mut pins := map[string]string{}
	for path in all_files(base)! { pins[path] = hash(path)! }
	for path in ['build/android-run', 'build/android-maps/maps-interact-unique258', 'build/qemu-horizontal/bin/qemu-system-aarch64', '/opt/homebrew/share/qemu/edk2-aarch64-code.fd'] { pins[path] = hash(path)! }
	write_json(base + '/prelaunch-sha256.json', pins)!
	clone_tree(base, audit + '/prelaunch')!
	for path in pins.keys().filter(!it.starts_with(base + '/')) { clone_file(path, audit + '/prelaunch-external-inputs/' + path.trim_left('/'))! }
	mut manifest := map[string]string{}
	for path in all_files(audit)! { manifest[path.all_after(audit + '/')] = hash(path)! }
	write_json(audit + '/prelaunch-sha256.json', manifest)!
	for path, pin in manifest { assert hash(audit + '/' + path)! == pin, path }
	println('COMPOUND284 PRELAUNCH PASS entries=' + manifest.len.str() + ' manifest=' + hash(audit + '/prelaunch-sha256.json')!)
}

fn self_test() ! {
	old := os.read_file(archive276 + '/prelaunch/native/atlframework/runtime.v')!
	assert timing(timing(old, false), true) == old
	live := os.read_file('build-support/android/nativews/runtime.v')!
	assert timing(timing(live, true), false) == live
	scratch := os.temp_dir() + '/queue284-inventory-' + os.getpid().str()
	assert !os.exists(scratch)
	os.mkdir_all(scratch + '/.hidden/nested')!
	defer { os.rmdir_all(scratch) or {} }
	os.write_file(scratch + '/.hidden/nested/proof', 'hidden')!
	assert all_files(scratch)! == [scratch + '/.hidden/nested/proof']
	println('QUEUE284 SELF-TEST PASS timing roundtrip and hidden inventory')
}

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	assert os.args.len == 2, 'freeze|build|prepare-runs|verify|--self-test'
	os.setenv('VINIX_COMPOUND_ATTEMPT', '284', true)
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('V', os.abs_path(compiler), true)
	os.setenv('VINIX_V_COMPILER', os.abs_path(compiler), true)
	match os.args[1] {
		'freeze' { freeze()! }
		'build' { build()! }
		'prepare-runs' { prepare()! }
		'verify' { verify()! }
		'--self-test' { self_test()! }
		'--assertion-probe' { assert false }
		else { panic('unknown action') }
	}
}
