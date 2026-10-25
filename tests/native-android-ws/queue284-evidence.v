// SPDX-License-Identifier: GPL-2.0-or-later
// Audit a native-only bounded main-queue pump regression over sealed276/282.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}

@[typedef]
struct C.CC_SHA256_CTX {}

fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const compound = 'build/android-maps/compound284'
const prepared_root = '/Users/alex/.local/state/vinix/android/compound284-2026-10-25'
const same_jar = '92b069b1dbb31b08960d00d4f33f84b068a3adf53af9339f2ef3c1a6478f0618'
const baseline_native = '5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca'
const archive276 = '/Users/alex/.local/state/vinix/android/compound276-2026-10-24'
const manifest276 = '37bfa8ec3449adf8a294e0b1f3ff3cabfa49123c228f308d9919cab7531d5fa4'
const archive282 = '/Users/alex/.local/state/vinix/android/compound282-2026-10-25'
const manifest282 = 'd966016994e234c6f4d8b2bf4a39fc041be60023fc7f61a1cf653fedeaf857d4'
const prelaunch282 = '2d9a307a57f3ffd5f07170a61cb6fb42361cc65ab260e78c158be2c9b05edefc'
const fixture_source = 'aa7fb0285c0df2fd47ce478e337480471db097e14af0741217795c77dbed1a15'
const queue_source = 'ff4bb8c0657a240d47bf6164879a02e6db994aa74ad5d160c53b046d20478fa0'
const runtime_source = '4a55617a8e2f2013c6ac51c29e8c3919a53bc269b34d4b46dffdfdc5ab17ed94'
const compiler_path = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const tool_root = '/Users/alex/.local/state/vinix/android/queue284-evidence-tool-fast5-2026-10-25'
const pass_markers = ['BOOTSTRAP-QUEUE-PUMP-PASS', 'BOOTSTRAP-QUEUE-PUMP-COMPLETE-PASS', 'BOOTSTRAP-READY']
const jar_path = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native_path = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'

fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		if C.CC_SHA256_Init(unsafe { &state }) != 1 { return error('CC_SHA256_Init failed') }
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			if C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) != 1 { return error('CC_SHA256_Update failed') }
		}
		mut result := [32]u8{}
		if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) != 1 { return error('CC_SHA256_Final failed') }
		return result[..].hex()
	} $else {
		mut state := sha256.new()
		defer { unsafe { state.free() } }
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			if state.write(buffer[..n])! != n { return error('SHA256 short write') }
		}
		mut result := []u8{len: 32}
		defer { unsafe { result.free() } }
		state.checksum_into(mut result)
		return result.hex()
	}
}

// Preserve the original portable backend for independent byte-equivalence tests.
fn portable_hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		digest.write(bytes[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn object(path string) !map[string]json2.Any { return json2.decode[map[string]json2.Any](os.read_file(path)!)! }
fn pins(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }

// Constructed integers and decoded JSON numbers can use different Any variants.
// Round-trip the complete expected object before exact decoded-map comparison.
fn canonical_object(value map[string]json2.Any) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](json2.encode(value))!
}

// Include hidden paths; preserve links in inventories instead of following them.
fn catalog(root string, relative string, mut out map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		if os.is_link(path) { out[key] = 'link:' + os.readlink(path)! }
		else if os.is_dir(path) { out[key] = 'directory'; catalog(root, key, mut out)! }
		else { assert os.is_file(path), path; out[key] = hash(path)! }
	}
}

fn inventory(root string) !map[string]string { mut out := map[string]string{}; catalog(root, '', mut out)!; return out }

fn files(root string) !map[string]string {
	mut out := inventory(root)!
	for path, digest in out.clone() {
		if digest == 'directory' { out.delete(path) }
		else { assert !digest.starts_with('link:'), root + '/' + path }
	}
	return out
}

fn clone_tree(from string, to string, mut excluded map[string]string) ! {
	assert !os.exists(to) && !os.is_link(to), to
	if os.is_link(from) { os.mkdir_all(os.dir(to))!; os.symlink(os.readlink(from)!, to)!; return }
	if os.is_dir(from) {
		os.mkdir_all(to)!
		for name in os.ls(from)! { clone_tree(from + '/' + name, to + '/' + name, mut excluded)! }
	} else if os.is_file(from) {
		os.mkdir_all(os.dir(to))!
		r := os.exec(['cp', '-c', from, to])
		assert r.exit_code == 0, r.output
	} else {
		assert os.lstat(from)!.get_filetype() == .socket, from
		assert from in ['baseline', 'fixed'].map(os.abs_path(compound + '/run-' + it + '/bootstrap-fixture/qmp.sock')), from
		excluded[from] = 'closed Unix socket; endpoint has no file content'
	}
}

fn retained(root string, path string) !string {
	for prefix in [compound + '/', os.abs_path(compound) + '/'] {
		if path.starts_with(prefix) { return root + '/prelaunch/' + path.all_after(prefix) }
	}
	for prefix in ['/prelaunch/inputs/', '/prelaunch/closure-inputs/', '/prelaunch-external-inputs/'] {
		for input in [path, os.abs_path(path)] {
			candidate := root + prefix + input.trim_left('/')
			if os.is_file(candidate) { return candidate }
		}
	}
	return error('missing retained input: ' + path)
}

fn sources(root string, count int, actual bool) !map[string]string {
	exact := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + '/exact-sources.json.gz')!)!.bytestr())!
	manifest := pins(root + '/sources.json')!
	assert exact.len == count && manifest.len == count, root
	for path, text in exact { assert sha256.sum(text.bytes()).hex() == manifest[path]!, path }
	if actual {
		dir := root + if os.is_dir(root + '/sources') { '/sources' } else { '/atlframework' }
		mut found := map[string]string{}
		for path, digest in files(dir)! { if path.ends_with('.v') { found[path] = digest } }
		assert found == manifest, 'complete source tree ' + dir
	}
	return exact
}

fn once(source string, old string, replacement string) string {
	assert source.count(old) == 1, old
	return source.replace(old, replacement)
}

// Reverse only the qualified231 timing probes, leaving production text exact.
fn without_timing(source string) string {
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
	for i in 0 .. plain.len { text = once(text, probed[i], plain[i]) }
	return text
}

fn verify_sources(pre string) ! {
	old := sources(pre + '/baseline-native', 83, false)!
	new := sources(pre + '/native', 83, true)!
	mut changed := []string{}
	for path, source in old { if new[path]! != source { changed << path } }
	changed.sort()
	assert changed == ['queue.v', 'runtime.v']
	assert json2.decode[[]string](os.read_file(pre + '/native/source-delta.json')!)! == changed
	assert sha256.sum(new['queue.v']!.bytes()).hex() == queue_source
	assert hash(pre + '/source/reviewed-queue.v')! == queue_source
	assert new['queue.v']! == os.read_file(pre + '/source/reviewed-queue.v')!
	assert hash(pre + '/source/reviewed-runtime.v')! == runtime_source
	assert without_timing(new['runtime.v']!) == os.read_file(pre + '/source/reviewed-runtime.v')!
	mut expected := without_timing(old['runtime.v']!)
	expected = once(expected, '\tmain_thread   usize\n', '\tmain_thread   usize\n\tqueue_pump_active bool\n\tqueue_pump_polls i32\n\tqueue_pump_deadline i64\n')
	expected = once(expected, "\t\t\tstatic_void(e, c'android/os/Looper', c'loop', c'()V', nil)\n", "\t\t\tws_queue_begin_pump()\n\t\t\tstatic_void(e, c'android/os/Looper', c'loop', c'()V', nil)\n\t\t\tws_queue_end_pump()\n")
	assert expected == without_timing(new['runtime.v']!), 'exact runtime pump delta; timing231 unchanged'
	assert new['timing231.v']! == old['timing231.v']!
	assert sources(pre + '/framework', 127, true)! == sources(pre + '/baseline-framework', 127, false)!, 'same framework282 source closure'
	assert json2.decode[[]string](os.read_file(pre + '/framework/source-delta.json')!)!.len == 0
	assert hash(pre + '/source/queue-pump-fixture.v')! == fixture_source
}

fn verify_references(root string) ! {
	pre := root + '/prelaunch'
	for item in [['276', archive276, manifest276], ['282', archive282, manifest282]] {
		assert hash(pre + '/qualified' + item[0] + '-sha256.json')! == item[2]
		assert pins(pre + '/qualified' + item[0] + '-reference.json')! == {'path': item[1], 'sha256': item[2]}
	}
	old := pins(pre + '/qualified276-sha256.json')!
	framework := pins(pre + '/qualified282-sha256.json')!
	for kind in ['native', 'framework'] {
		sealed := if kind == 'native' { old } else { framework }
		for name in ['sources.json', 'exact-sources.json.gz'] { assert hash(pre + '/baseline-' + kind + '/' + name)! == sealed['prelaunch/' + kind + '/' + name]!, kind + '/' + name }
	}
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h', 'bindings.txt'] { assert hash(pre + '/native/' + name)! == old['prelaunch/native/' + name]!, name }
	for name in ['api-impl.jar', 'framework-manifest.json'] { assert hash(pre + '/framework/' + name)! == framework['prelaunch/framework/' + name]!, name }
	assert hash(pre + '/baseline-native/libvinix-android-native.so')! == old['prelaunch/native/libvinix-android-native.so']!
	assert hash(pre + '/qualified276-frozen-inputs.json')! == old['prelaunch/frozen-inputs.json']!
	assert hash(pre + '/qualified276-native-generator-v-files.json')! == old['prelaunch/native-generator-v-files.json']!
	assert hash(retained(root, compiler_path)!)! == compiler_pin
	compiler_reference := pins(pre + '/compiler-reference.json')!
	assert compiler_reference['path']! == compiler_path && compiler_reference['sha256']! == compiler_pin
	assert compiler_reference['origin']! == archive276 + '/prelaunch/inputs/Users/alex/code/v/v_old'
	assert compiler_reference['origin_manifest']! == manifest276 && compiler_reference['VROOT']! == '/Users/alex/code/v'
	for field in ['V', 'VINIX_V_COMPILER', 'inner_compiler_selected'] { assert compiler_reference[field]! == os.abs_path(compiler_path), field }
	assert compiler_pin == pins(pre + '/qualified276-frozen-inputs.json')!['/Users/alex/code/v/v_old']!
	current_inputs := pins(pre + '/frozen-inputs.json')!
	for path, digest in pins(pre + '/qualified276-frozen-inputs.json')! {
		if path == '/opt/homebrew/bin/aarch64-linux-musl-gcc' || path.contains('/calculator/overlay/') { assert current_inputs[path]! == digest, 'same historical GCC and explicit link libraries: ' + path }
	}
	assert framework['prelaunch-sha256.json']! == prelaunch282
	assert hash(pre + '/source/suite.v')! == framework['prelaunch/source/suite.v']!, 'same historical raw classifier source'
	assert hash(pre + '/source/config282.json')! == framework['prelaunch/fixed.json']!
}

fn verify_inputs(root string) ! {
	pre := root + '/prelaunch'
	mut actual := map[string]string{}
	for name in ['prelaunch', 'prelaunch-external-inputs'] {
		for path, digest in inventory(root + '/' + name)! {
			if digest != 'directory' { actual[name + '/' + path] = digest }
		}
	}
	assert actual == pins(root + '/prelaunch-sha256.json')!, 'complete retained prelaunch inventory'
	for path, digest in pins(pre + '/frozen-inputs.json')! { assert hash(pre + '/inputs/' + path.trim_left('/'))! == digest, path }
	for label in ['native-generator', 'fixture', 'suite'] {
		listing := os.read_file(pre + '/' + label + '-v-files.txt')!.split_into_lines().filter(it.ends_with('.v'))
		closure := pins(pre + '/' + label + '-v-files.json')!
		mut expected := map[string]string{}
		for path in listing { expected[path] = hash(pre + '/closure-inputs/' + path.trim_left('/'))! }
		assert closure == expected && closure.len > 0, 'complete consumed V source closure: ' + label
	}
	assert pins(pre + '/native-generator-v-files.json')! == pins(pre + '/qualified276-native-generator-v-files.json')!
	compiler := compiler_path
	runtime := compound + '/inputs/build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
	commands := {
		'generate-native': [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', 'run', 'tests/linuxkpi/generate_module.v', compound + '/native/atlframework', compound + '/native/android-native.c', '--arch', 'arm64']
		'build-native': ['/opt/homebrew/bin/aarch64-linux-musl-gcc', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden', '-shared', '-fPIC', '-I' + compound + '/native', '-Wl,-z,max-page-size=65536', '-Wl,--allow-shlib-undefined', compound + '/native/android-native.c', runtime + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed', runtime + '/usr/lib/libpng16.so.16', runtime + '/usr/lib/libsqlite3.so.0', '-ldl', '-lm', '-o', compound + '/native/libvinix-android-native.so']
		'fixture-generator': [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', compound + '/fixture-generator', compound + '/source/queue-pump-fixture.v']
		'fixture': [compound + '/fixture-generator', compound + '/apk']
		'suite-compiler': [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-path', compound + '/suite-support|@vlib|@vmodules', '-o', compound + '/suite', compound + '/source/suite.v']
		'suite-self-test': [compound + '/suite', '--self-test']
	}
	outputs := {'generate-native': 'native/android-native.c', 'build-native': 'native/libvinix-android-native.so', 'fixture-generator': 'fixture-generator', 'fixture': 'apk/probe.apk', 'suite-compiler': 'suite', 'suite-self-test': ''}
	for label, argv in commands {
		before := object(pre + '/' + label + '-before.json')!
		done := object(pre + '/' + label + '-receipt.json')!
		assert before['completed_utc']!.str() == '' && before['output_sha256']!.str() == ''
		for key, value in before { if key !in ['completed_utc', 'output_sha256'] { assert done[key]! == value, label + ':' + key } }
		assert done['argv']!.as_array().map(it.str()) == argv, label + ': exact argv'
		assert done['attempt']!.str() == '284' && done['VINIX_COMPOUND_ATTEMPT']!.str() == '284'
		assert done['VROOT']!.str() == '/Users/alex/code/v'
		for field in ['V', 'VINIX_V_COMPILER'] { assert done[field]!.str() == os.abs_path(compiler_path), field }
		assert done['exit_code']!.int() == 0 && done['started_utc']!.str() != '' && done['completed_utc']!.str() != ''
		assert done['compiler_sha256']!.str() == hash(retained(root, compiler)!)!
		assert done['command_binary_sha256']!.str() == hash(retained(root, argv[0])!)!
		assert done['input_files']!.as_map()[argv[0]]!.str() == done['command_binary_sha256']!.str()
		mut expected_sources := map[string]string{}
		for path in argv.filter(it.ends_with('.v')) { expected_sources[path] = hash(retained(root, path)!)! }
		assert json2.decode[map[string]string](json2.encode(done['sources']!))! == expected_sources
		for field in ['input_files', 'sources'] {
			for path, digest in done[field]!.as_map() { assert hash(retained(root, path)!)! == digest.str(), label + ':' + path }
		}
		output := outputs[label]!
		assert done['output_sha256']!.str() == if output == '' { '' } else { hash(pre + '/' + output)! }, label
		assert os.is_file(pre + '/' + label + '.log')
	}
	assert os.read_file(pre + '/suite-self-test.log')!.contains('APK-SUITE-CLASSIFICATION-PASS no-window-pass-after-failure')
	assert hash(pre + '/framework/api-impl.jar')! == same_jar
	assert hash(pre + '/baseline-native/libvinix-android-native.so')! == baseline_native
	assert hash(pre + '/native/libvinix-android-native.so')! != baseline_native
	mut equality := {'same_apk': hash(pre + '/apk/probe.apk')!}
	old_pins := pins(pre + '/qualified276-sha256.json')!
	for name in ['boot.img', 'efivars.fd'] {
		digest := hash(pre + '/vm-baseline/' + name)!
		assert digest == hash(pre + '/vm-fixed/' + name)! && digest == old_pins['prelaunch/vm-fixed/' + name]!
		equality['vm/' + name] = digest
	}
	assert hash(pre + '/base-runtime.tar')! == old_pins['prelaunch/base-runtime.tar']!
	mut expected_config := object(pre + '/source/config282.json')!
	mut expected_app := expected_config['applications']!.as_array()[0].as_map().clone()
	expected_app['apk'] = os.abs_path(compound + '/apk/probe.apk')
	expected_app['source'] = os.abs_path(compound + '/source/queue-pump-fixture.v')
	expected_app['startup_seconds'] = json2.Any(90)
	expected_config['applications'] = json2.Any([json2.Any(expected_app)])
	expected_config['base_module'] = os.abs_path(compound + '/base-runtime.tar')
	for field in ['boot_image', 'efivars', 'native_dir', 'output'] { expected_config.delete(field) }
	sealed282 := pins(pre + '/qualified282-sha256.json')!
	// Guest execution inputs retain historical equality. The same newly built
	// APK is inspected with the retained284 host tools in both runs.
	for field in ['qemu', 'firmware', 'input_tool'] {
		path := expected_config[field]!.str()
		digest := hash(retained(root, path)!)!
		mut historical := ''
		for prefix in ['prelaunch-external-inputs/', 'prelaunch/inputs/'] {
			if value := sealed282[prefix + path.trim_left('/')] { historical = value }
		}
		assert historical != '' && digest == historical, 'same retained historical common tool: ' + field
	}
	mut common := map[string]map[string]string{}
	mut configs := map[string]map[string]json2.Any{}
	for mode in ['baseline', 'fixed'] {
		mut runtime_files := files(pre + '/native-' + mode)!
		assert runtime_files['api-impl.jar']! == same_jar
		assert runtime_files['libvinix-android-native.so']! == if mode == 'baseline' { baseline_native } else { hash(pre + '/native/libvinix-android-native.so')! }
		runtime_files.delete('libvinix-android-native.so')
		for name, digest in runtime_files { if name != 'api-impl.jar' { assert digest == old_pins['prelaunch/native-fixed/' + name]!, name } }
		common[mode] = runtime_files
		mut config := object(pre + '/' + mode + '.json')!
		apps := config['applications']!.as_array()
		assert apps.len == 1
		app := apps[0].as_map()
		assert app['id']!.str() == 'bootstrap-fixture' && app['package']!.str() == 'org.vinix.bootstrap'
		assert app['startup_seconds']!.int() == 90
		assert app['apk']!.str() == os.abs_path(compound + '/apk/probe.apk')
		assert app['source']!.str() == os.abs_path(compound + '/source/queue-pump-fixture.v')
		assert config['base_module']!.str() == os.abs_path(compound + '/base-runtime.tar')
		for field, suffix in {'boot_image': 'vm-' + mode + '/boot.img', 'efivars': 'vm-' + mode + '/efivars.fd', 'native_dir': 'native-' + mode, 'output': 'run-' + mode} {
			assert config[field]!.str() == os.abs_path(compound + '/' + suffix), field
			config.delete(field)
		}
		configs[mode] = config
	}
	assert common['baseline'] == common['fixed'], 'native library is the sole runtime delta'
	for path, digest in common['baseline'] { equality['native/' + path] = digest }
	assert equality == pins(pre + '/paired-initial-equality.json')!
	assert configs['baseline'] == configs['fixed'], 'same observation, fixture, runner and all common configuration'
	assert configs['fixed'] == canonical_object(expected_config)!, 'exact historical common configuration and declared fixture/window changes'
}

fn staged_files(base string) !map[string]string {
	mut out := map[string]string{}
	for path, digest in files(base + '/module/opt/vinix-android-aarch64')! { out['opt/vinix-android-aarch64/' + path] = digest }
	for path in ['usr/bin/run-android', 'usr/bin/vinix-desktop', 'usr/bin/vinix-android-calculator', 'usr/bin/run-android-calculator', 'usr/bin/vinix-session', 'opt/android-test/native-guest'] { out[path] = hash(base + '/module/' + path)! }
	return out
}

fn expected_overlays(native string) !map[string]string {
	mut out := map[string]string{}
	for path, source in {
		native_path: 'libvinix-android-native.so'
		jar_path: 'api-impl.jar'
		'opt/vinix-android-aarch64/usr/lib/art/native-ws/libdl_bio.so.0': 'libdl_bio.so.0'
		'opt/vinix-android-aarch64/usr/bin/vinix-android-native': 'vinix-android-native'
		'usr/bin/run-android': 'run-android'
		'usr/bin/vinix-desktop': 'vinix-desktop'
		'usr/bin/vinix-android-calculator': 'vinix-desktop'
		'usr/bin/run-android-calculator': 'popular-launcher'
		'usr/bin/vinix-session': 'vinix-session'
		'opt/android-test/native-guest': 'guest'
		'opt/vinix-android-aarch64/usr/lib/libvinix-android-compat.so': 'libvinix-android-compat.so'
		'opt/vinix-android-aarch64/usr/share/zoneinfo/tzdata': 'tzdata'
		'opt/vinix-android-aarch64/etc/ssl/certs/java/cacerts': 'cacerts'
		'opt/vinix-android-aarch64/usr/share/vinix-android-ws/bionic_translation/cfg.d/native.cfg': 'bionic-ws.cfg'
	} { out[path] = hash(native + '/' + source)! }
	for name in ['libglapi.so.0', 'libvinix-ws-GLESv1_CM.so', 'libvinix-ws-GLESv2.so'] { out['opt/vinix-android-aarch64/usr/lib/art/native-ws/' + name] = hash(native + '/' + name)! }
	for provider in ['egl-ws', 'vulkan-ws'] {
		for path, digest in files(native + '/' + provider)! { out['opt/vinix-android-aarch64/usr/lib/art/native-ws/' + path] = digest }
	}
	return out
}

fn raw_observation(serial string) map[string]json2.Any {
	begin := serial.contains('APK-SUITE-BEGIN id=bootstrap-fixture ')
	ready := serial.contains('ANDROID-WS-READY backend=vinix-native')
	exited := serial.contains('APK-SUITE-EXIT id=bootstrap-fixture ')
	mut failures := []string{}
	for line in serial.split_into_lines() {
		if ['ANDROID-WS-FAIL', 'APK-SUITE-DEPENDENCY-FAIL', 'ANDROID-WS-DEPENDENCY-FAIL', 'ANDROID-WS-PROCESS-FAIL', 'JNI DETECTED ERROR', 'NoClassDefFoundError', 'NoSuchMethodError', 'UnsatisfiedLinkError', 'ClassNotFoundException', 'NoSuchFieldError', 'APK-SUITE-EXIT id='].any(line.contains(it)) { failures << line.trim_space() }
	}
	return {'launcher_entered': json2.Any(begin), 'backend_ready': json2.Any(ready), 'process_exited': json2.Any(exited), 'native_maps_observed': json2.Any(serial.contains('APK-SUITE-MAPS id=bootstrap-fixture ')), 'functional_passed': json2.Any(json2.Null{}), 'failure_markers': json2.Any(failures), 'outcome': json2.Any(if !begin { 'harness_failure' } else if exited || failures.len > 0 { 'startup_failed' } else if ready { 'window_observed' } else { 'startup_timeout' })}
}

fn verify_runs(root string) ! {
	pre := root + '/prelaunch'
	verify_backend(root + '/checker')!
	assert hash(root + '/checker/compiler')! == compiler_pin
	for suffix in ['', '.v'] { assert hash(root + '/run-tool/queue284-evidence' + suffix)! == hash(root + '/checker/queue284-evidence' + suffix)! }
	assert hash(root + '/checker/queue284-evidence')! == hash(os.executable())!, 'use the frozen retained checker'
	before_compile := object(root + '/checker/compile-before.json')!
	done_compile := object(root + '/checker/compile-receipt.json')!
	for key, value in before_compile { assert done_compile[key]! == value }
	backend := pins(root + '/checker/backend/backend.json')!
	assert done_compile['argv']!.as_array().map(it.str()) == [compiler_path, '-nocache', '-cc', backend['cc']!, '-cflags', '-O2', '-o', tool_root + '/queue284-evidence', tool_root + '/queue284-evidence.v']
	assert done_compile['VROOT']!.str() == '/Users/alex/code/v' && done_compile['compiler_sha256']!.str() == compiler_pin
	assert done_compile['source_sha256']!.str() == hash(root + '/checker/queue284-evidence.v')!
	assert done_compile['bootstrap_sha256']!.str() == hash(root + '/checker/bootstrap')!
	assert done_compile['output_sha256']!.str() == hash(root + '/checker/queue284-evidence')!
	assert done_compile['stdout_sha256']!.str() == hash(root + '/checker/compile.log')!
	assert done_compile['exit_code']!.int() == 0 && done_compile['started_utc']!.str() != '' && done_compile['completed_utc']!.str() != ''
	closure := pins(root + '/checker/v-files.json')!
	mut expected_closure := map[string]string{}
	for path in os.read_file(root + '/checker/v-files.txt')!.split_into_lines().filter(it.ends_with('.v')) { expected_closure[path] = hash(root + '/checker/closure-inputs/' + path.trim_left('/'))! }
	assert closure == expected_closure && closure.len > 0
	mut stages := map[string]map[string]string{}
	for mode in ['baseline', 'fixed'] {
		base := root + '/run-' + mode
		before := object(base + '-before.json')!
		done := object(base + '-receipt.json')!
		for key, value in before { assert done[key]! == value, mode + ':' + key }
		assert before['argv']!.as_array().map(it.str()) == [compound + '/suite', compound + '/' + mode + '.json']
		config := object(pre + '/' + mode + '.json')!
		frozen := pins(pre + '/frozen-inputs.json')!
		mut expected_inspection := map[string]json2.Any{}
		for field in ['java', 'aapt2', 'apksigner'] { path := config[field]!.str(); expected_inspection[path] = frozen[path]! }
		assert before['inspection_tool_sha256']!.as_map() == expected_inspection, 'same retained284 host APK inspection tools'
		for key, path in {'suite_sha256': pre + '/suite', 'config_sha256': pre + '/' + mode + '.json', 'external_prelaunch_inventory_sha256': root + '/prelaunch-sha256.json', 'runner_sha256': root + '/run-tool/queue284-evidence', 'runner_source_sha256': root + '/run-tool/queue284-evidence.v', 'stdout_sha256': base + '.log', 'results_sha256': base + '/results.json'} { assert done[key]!.str() == hash(path)!, mode + ':' + key }
		assert done['exit_code']!.int() == 0 && done['started_utc']!.str() != '' && done['completed_utc']!.str() != ''
		rows := json2.decode[[]json2.Any](os.read_file(base + '/results.json')!)!
		assert rows.len == 1
		row := rows[0].as_map()
		assert row['id']!.str() == 'bootstrap-fixture'
		assert row['metadata']!.as_map()['apk_sha256']!.str() == hash(pre + '/apk/probe.apk')!
		assert row['container_sha256']!.str() == hash(pre + '/apk/probe.apk')!
		serial := os.read_file(base + '/bootstrap-fixture/serial.log')!
		assert gzip.decompress(os.read_bytes(base + '/bootstrap-fixture/serial.log.gz')!)!.bytestr() == serial
		assert sha256.sum(serial.bytes()).hex() == row['serial_sha256']!.str()
		assert hash(base + '/bootstrap-fixture/application.png')! == row['screenshot_sha256']!.str()
		assert row['startup_timeout_seconds']!.int() == 90
		for key, value in raw_observation(serial) { assert row[key]! == value, 'unaltered raw classifier: ' + key }
		assert row['launcher_entered']!.bool() && row['native_maps_observed']!.bool()
		observation := object(base + '/bootstrap-fixture/observation-before-capture.json')!
		for field in ['observation_elapsed_seconds', 'qemu_alive_before_capture'] { assert row[field]! == observation[field]!, mode + ':' + field }
		if mode == 'baseline' {
			assert row['process_exited']!.bool() && row['outcome']!.str() == 'startup_failed'
			assert serial.count('APK-SUITE-EXIT id=bootstrap-fixture code=1') == 1
			assert serial.contains('java.lang.AssertionError: first pre-draw must run during pending chain: 0 < count < 1024') || serial.contains('java.lang.AssertionError: completion requires all 1024 ordered tasks, an earlier partial frame and elapsed delay')
			for marker in pass_markers { assert !serial.contains(marker), marker }
		} else {
			assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
			mut last := -1
			for marker in pass_markers { assert serial.count(marker) == 1, marker; at := serial.index(marker) or { panic(marker) }; assert at > last, 'ordered markers'; last = at }
			for bad in ['java.lang.AssertionError', 'ANDROID-WS-FAIL', 'JNI DETECTED ERROR', 'APK-SUITE-EXIT id=bootstrap-fixture'] { assert !serial.contains(bad), bad }
			for failure in row['failure_markers']!.as_array() {
				assert failure.str() in ['java.lang.NoSuchFieldError: no type "Lnge;" found and so no field "bB" could be found in class "Lorg/vinix/bootstrap/Main;" or its superclasses', 'Caused by: java.lang.ClassNotFoundException: nge'], failure.str()
			}
			assert observation['observation_elapsed_seconds']!.int() >= 90 && observation['qemu_alive_before_capture']!.bool(), 'completed natural observation with QEMU alive'
		}
		stages[mode] = pins(base + '/staged-runtime-sha256.json')!
		actual := staged_files(base)!
		assert actual == stages[mode], 'complete staged runtime map'
		for path, digest in expected_overlays(pre + '/native-' + mode)! { assert actual[path]! == digest, 'staged overlay consumes prepared bytes: ' + path }
		assert stages[mode][jar_path]! == same_jar
		assert stages[mode][native_path]! == if mode == 'baseline' { baseline_native } else { hash(pre + '/native/libvinix-android-native.so')! }
	}
	assert stages['baseline'].len == stages['fixed'].len
	for path, digest in stages['baseline'] { if path != native_path { assert stages['fixed'][path]! == digest, 'native-only staged delta: ' + path } }
}

fn verify(root string) ! { verify_inputs(root)!; verify_references(root)!; verify_sources(root + '/prelaunch')!; verify_runs(root)! }

// Exercise the same real launch metadata without creating a run or guest.
fn run_metadata(base string, mode string) !map[string]json2.Any {
	assert base == compound && mode in ['baseline', 'fixed']
	assert !os.exists(base + '/run-' + mode + '/results.json')
	argv := [base + '/suite', base + '/' + mode + '.json']
	config := object(argv[1])!
	frozen := pins(base + '/frozen-inputs.json')!
	mut inspection_tools := map[string]json2.Any{}
	for field in ['java', 'aapt2', 'apksigner'] {
		path := config[field]!.str()
		assert hash(path)! == frozen[path]!, 'same retained284 APK inspection tool: ' + field
		inspection_tools[path] = frozen[path]!
	}
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()), 'suite_sha256': json2.Any(hash(argv[0])!), 'config_sha256': json2.Any(hash(argv[1])!), 'external_prelaunch_inventory_sha256': json2.Any(hash(prepared_root + '/prelaunch-sha256.json')!), 'runner_sha256': json2.Any(hash(os.executable())!), 'runner_source_sha256': json2.Any(hash(@FILE)!)}
	receipt['inspection_tool_sha256'] = inspection_tools
	return receipt
}

fn run_pair(base string, mode string) ! {
	mut receipt := run_metadata(base, mode)!
	argv := receipt['argv']!.as_array().map(it.str())
	inspection_tools := receipt['inspection_tool_sha256']!.as_map()
	tool := base + '/run-tool'
	if !os.exists(tool) {
		os.mkdir_all(tool)!
		os.cp(@FILE, tool + '/queue284-evidence.v')!
		os.cp(os.executable(), tool + '/queue284-evidence')!
	}
	assert hash(@FILE)! == hash(tool + '/queue284-evidence.v')!
	assert hash(os.executable())! == hash(tool + '/queue284-evidence')!
	prefix := base + '/run-' + mode
	os.write_file(prefix + '-before.json', json2.encode(receipt, prettify: true) + '\n')!
	r := os.exec(argv)
	os.write_file(prefix + '.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	receipt['stdout_sha256'] = hash(prefix + '.log')!
	for key, path in {'suite_sha256': argv[0], 'config_sha256': argv[1], 'external_prelaunch_inventory_sha256': prepared_root + '/prelaunch-sha256.json', 'runner_sha256': tool + '/queue284-evidence', 'runner_source_sha256': tool + '/queue284-evidence.v'} { assert receipt[key]!.str() == hash(path)!, key }
	for path, digest in inspection_tools { assert hash(path)! == digest.str(), 'APK inspection tool unchanged through run: ' + path }
	if r.exit_code == 0 {
		receipt['results_sha256'] = hash(prefix + '/results.json')!
		stage := staged_files(prefix)!
		os.write_file(prefix + '/staged-runtime-sha256.json', json2.encode(stage, prettify: true) + '\n')!
	}
	os.write_file(prefix + '-receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	assert r.exit_code == 0, r.output
	println('QUEUE284 RUN ' + mode + ' complete; raw results retained')
}

fn self_test() ! {
	decoded := json2.decode[map[string]json2.Any]('{"applications":[{"startup_seconds":90,"enabled":true}],"label":"same"}')!
	expected_app := {'startup_seconds': json2.Any(90), 'enabled': json2.Any(true)}
	expected := {'applications': json2.Any([json2.Any(expected_app)]), 'label': json2.Any('same')}
	assert expected != decoded, 'regression reproduces constructed-versus-decoded numeric variants'
	normalized := canonical_object(expected)!
	assert normalized == decoded, 'canonical exact comparison preserves numeric JSON value'
	assert normalized != json2.decode[map[string]json2.Any]('{"applications":[{"startup_seconds":91,"enabled":true}],"label":"same"}')!, 'changed nested number rejected'
	assert normalized != json2.decode[map[string]json2.Any]('{"applications":[{"startup_seconds":90,"enabled":true,"extra":true}],"label":"same"}')!, 'extra nested field rejected'
	assert normalized != json2.decode[map[string]json2.Any]('{"applications":[{"startup_seconds":90}],"label":"same"}')!, 'missing nested field rejected'
	prefix := 'APK-SUITE-BEGIN id=bootstrap-fixture package=test\nANDROID-WS-READY backend=vinix-native\n'
	assert raw_observation(prefix)['outcome']!.str() == 'window_observed'
	assert raw_observation(prefix + 'java.lang.ClassNotFoundException: nge\n')['outcome']!.str() == 'startup_failed'
	assert raw_observation(prefix + 'APK-SUITE-EXIT id=bootstrap-fixture code=1\n')['process_exited']!.bool()
	assert raw_observation('ANDROID-WS-READY backend=vinix-native')['outcome']!.str() == 'harness_failure'
	scratch := os.temp_dir() + '/queue284-evidence-' + os.getpid().str()
	assert !os.exists(scratch)
	os.mkdir_all(scratch + '/.hidden')!
	defer { os.rmdir_all(scratch) or {} }
	os.write_file(scratch + '/.hidden/proof', 'closure')!
	assert files(scratch)! == {'.hidden/proof': sha256.sum('closure'.bytes()).hex()}
	println('QUEUE284 EVIDENCE SELF-TEST PASS exact canonical JSON, hidden closure and honest failure classification')
}

fn hash_self_test(root string) ! {
	assert !os.exists(root)
	os.mkdir_all(root)!
	mut receipt := {'argv': json2.Any(os.args), 'started_utc': json2.Any(time.utc().str()), 'backend': json2.Any('darwin-commoncrypto'), 'chunk_bytes': json2.Any(1024 * 1024), 'source_sha256': json2.Any(hash(@FILE)!), 'binary_sha256': json2.Any(hash(os.executable())!)}
	os.write_file(root + '/before.json', json2.encode(receipt, prettify: true) + '\n')!
	mut expected := {
		'empty': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		'abc': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
		'nist-long': '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1'
		'million-a': 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0'
		'binary-64m': 'f49c27347e38012ce129d8be15b11f11248e4006fd33cdd64b4e7eaa9d0bc07c'
	}
	os.write_file(root + '/empty', '')!
	os.write_file(root + '/abc', 'abc')!
	os.write_file(root + '/nist-long', 'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')!
	os.write_file_array(root + '/million-a', []u8{len: 1000000, init: `a`})!
	block := []u8{len: 1024 * 1024, init: u8((index * 37 + index / 251) & 255)}
	mut large := os.create(root + '/binary-64m')!
	for _ in 0 .. 64 { assert large.write(block)! == block.len }
	large.close()
	for size in [1, 55, 56, 63, 64, 65, 1024 * 1024 - 1, 1024 * 1024, 1024 * 1024 + 1] {
		data := []u8{len: size, init: u8((index * 37 + index / 251) & 255)}
		name := 'binary-' + size.str()
		os.write_file_array(root + '/' + name, data)!
		expected[name] = sha256.sum(data).hex()
	}
	for name, digest in expected {
		assert hash(root + '/' + name)! == digest, 'CommonCrypto known vector: ' + name
		assert portable_hash(root + '/' + name)! == digest, 'portable known vector: ' + name
	}
	mut missing_rejected := false
	_ := hash(root + '/absent') or { missing_rejected = true; '' }
	assert missing_rejected
	os.write_file(root + '/vectors.json', json2.encode(expected, prettify: true) + '\n')!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(0)
	receipt['vectors_sha256'] = hash(root + '/vectors.json')!
	os.write_file(root + '/receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	println('QUEUE284 HASH PASS known vectors, binary block boundaries, missing input and 64MiB cross-backend equality')
}

fn retain_backend() ! {
	$if !macos { return error('this retained backend qualification requires macOS') }
	mut metadata := {'backend': 'darwin-commoncrypto', 'chunk_bytes': '1048576', 'context': 'SDK-owned CC_SHA256_CTX', 'CC_LONG': 'uint32_t', 'runtime_scope': 'CommonCrypto from libSystem/dyld shared cache; SDK headers and link stub retained, OS build recorded; no runtime shared-cache byte audit claimed'}
	cc := os.find_abs_path_of_executable('cc')!
	metadata['cc'] = cc
	metadata['cc_sha256'] = hash(cc)!
	for name, argv in {'sdk-path': ['xcrun', '--show-sdk-path'], 'sdk-version': ['xcrun', '--show-sdk-version'], 'cc-version': [cc, '--version'], 'os-build': ['sw_vers']} {
		r := os.exec(argv)
		assert r.exit_code == 0, r.output
		os.mkdir_all(tool_root + '/backend')!
		os.write_file(tool_root + '/backend/' + name + '.log', r.output)!
		metadata[name] = r.output.trim_space()
		metadata[name + '_sha256'] = hash(tool_root + '/backend/' + name + '.log')!
	}
	mut excluded := map[string]string{}
	clone_tree(metadata['sdk-path']! + '/usr/include/CommonCrypto', tool_root + '/backend/headers', mut excluded)!
	clone_tree(metadata['sdk-path']! + '/usr/lib/system/libcommonCrypto.tbd', tool_root + '/backend/libcommonCrypto.tbd', mut excluded)!
	assert excluded.len == 0
	os.write_file(tool_root + '/backend/headers.json', json2.encode(files(tool_root + '/backend/headers')!, prettify: true) + '\n')!
	metadata['link_stub_sha256'] = hash(tool_root + '/backend/libcommonCrypto.tbd')!
	probe := tool_root + '/backend/CommonCrypto-probe.c'
	os.write_file(probe, '#include <CommonCrypto/CommonDigest.h>\nint main(void) { return sizeof(CC_SHA256_CTX) == 0; }\n')!
	argv := [cc, '-M', probe]
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()), 'cc_sha256': json2.Any(hash(cc)!), 'probe_sha256': json2.Any(hash(probe)!)}
	os.write_file(tool_root + '/backend/dependencies-before.json', json2.encode(receipt, prettify: true) + '\n')!
	r := os.exec(argv)
	os.write_file(tool_root + '/backend/dependencies.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = r.exit_code
	receipt['stdout_sha256'] = hash(tool_root + '/backend/dependencies.log')!
	os.write_file(tool_root + '/backend/dependencies-receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	assert r.exit_code == 0, r.output
	mut paths := r.output.replace('\\\n', ' ').fields()[1..].clone()
	paths << [cc, metadata['sdk-path']! + '/SDKSettings.json', metadata['sdk-path']! + '/usr/lib/libSystem.tbd', metadata['sdk-path']! + '/usr/lib/system/libcommonCrypto.tbd']
	mut inputs := map[string]string{}
	for path in paths {
		if path in inputs { continue }
		inputs[path] = hash(path)!
		destination := tool_root + '/backend/inputs/' + path.trim_left('/')
		os.mkdir_all(os.dir(destination))!
		os.cp(os.real_path(path), destination)!
		assert hash(destination)! == inputs[path]!
	}
	os.write_file(tool_root + '/backend/inputs-before.json', json2.encode(inputs, prettify: true) + '\n')!
	os.write_file(tool_root + '/backend/backend.json', json2.encode(metadata, prettify: true) + '\n')!
}

fn verify_backend(root string) ! {
	metadata := pins(root + '/backend/backend.json')!
	assert metadata['backend']! == 'darwin-commoncrypto' && metadata['chunk_bytes']! == '1048576'
	assert files(root + '/backend/headers')! == pins(root + '/backend/headers.json')!
	assert os.is_file(root + '/backend/headers/CommonDigest.h')
	assert hash(root + '/backend/libcommonCrypto.tbd')! == metadata['link_stub_sha256']!
	for name in ['sdk-path', 'sdk-version', 'cc-version', 'os-build'] { assert hash(root + '/backend/' + name + '.log')! == metadata[name + '_sha256']! }
	dep_before := object(root + '/backend/dependencies-before.json')!
	dep_done := object(root + '/backend/dependencies-receipt.json')!
	for key, value in dep_before { assert dep_done[key]! == value }
	assert dep_done['argv']!.as_array().map(it.str()) == [metadata['cc']!, '-M', tool_root + '/backend/CommonCrypto-probe.c']
	assert dep_done['cc_sha256']!.str() == metadata['cc_sha256']!
	assert dep_done['probe_sha256']!.str() == hash(root + '/backend/CommonCrypto-probe.c')!
	assert dep_done['stdout_sha256']!.str() == hash(root + '/backend/dependencies.log')!
	assert dep_done['exit_code']!.int() == 0 && dep_done['started_utc']!.str() != '' && dep_done['completed_utc']!.str() != ''
	inputs := pins(root + '/backend/inputs-before.json')!
	assert inputs == pins(root + '/backend/inputs-after.json')!, 'backend inputs unchanged during actual compilation'
	mut paths := os.read_file(root + '/backend/dependencies.log')!.replace('\\\n', ' ').fields()[1..].clone()
	paths << [metadata['cc']!, metadata['sdk-path']! + '/SDKSettings.json', metadata['sdk-path']! + '/usr/lib/libSystem.tbd', metadata['sdk-path']! + '/usr/lib/system/libcommonCrypto.tbd']
	mut expected := map[string]string{}
	for path in paths { expected[path] = hash(root + '/backend/inputs/' + path.trim_left('/'))! }
	assert inputs == expected && inputs[metadata['cc']!]! == metadata['cc_sha256']!
	assert inputs[metadata['sdk-path']! + '/usr/include/CommonCrypto/CommonDigest.h']! != ''
	before := object(root + '/hash-vectors/before.json')!
	done := object(root + '/hash-vectors/receipt.json')!
	for key, value in before { assert done[key]! == value }
	assert done['source_sha256']!.str() == hash(root + '/queue284-evidence.v')!
	assert done['binary_sha256']!.str() == hash(root + '/queue284-evidence')!
	assert done['argv']!.as_array().map(it.str()) == [tool_root + '/queue284-evidence', '--hash-self-test', tool_root + '/hash-vectors']
	assert done['backend']!.str() == 'darwin-commoncrypto' && done['chunk_bytes']!.int() == 1024 * 1024
	assert done['exit_code']!.int() == 0 && done['started_utc']!.str() != '' && done['completed_utc']!.str() != ''
	assert done['vectors_sha256']!.str() == hash(root + '/hash-vectors/vectors.json')!
	vectors := pins(root + '/hash-vectors/vectors.json')!
	assert vectors.len == 14 && vectors['binary-64m']! == 'f49c27347e38012ce129d8be15b11f11248e4006fd33cdd64b4e7eaa9d0bc07c'
	for name, digest in vectors { assert hash(root + '/hash-vectors/' + name)! == digest }
}

// Preserve the actual assertion-enabled compiler invocation before first VM.
fn compile_checker() ! {
	assert !os.exists(tool_root) && hash(compiler_path)! == compiler_pin
	os.mkdir_all(tool_root)!
	os.cp(@FILE, tool_root + '/queue284-evidence.v')!
	os.cp(os.executable(), tool_root + '/bootstrap')!
	os.cp(compiler_path, tool_root + '/compiler')!
	retain_backend()!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('V', os.abs_path(compiler_path), true)
	os.setenv('VINIX_V_COMPILER', os.abs_path(compiler_path), true)
	listing := os.exec([compiler_path, '-print-v-files', tool_root + '/queue284-evidence.v'])
	assert listing.exit_code == 0, listing.output
	os.write_file(tool_root + '/v-files.txt', listing.output)!
	mut closure := map[string]string{}
	mut excluded := map[string]string{}
	for path in listing.output.split_into_lines().filter(it.ends_with('.v')) {
		closure[path] = hash(path)!
		clone_tree(path, tool_root + '/closure-inputs/' + path.trim_left('/'), mut excluded)!
	}
	os.write_file(tool_root + '/v-files.json', json2.encode(closure, prettify: true) + '\n')!
	backend := pins(tool_root + '/backend/backend.json')!
	argv := [compiler_path, '-nocache', '-cc', backend['cc']!, '-cflags', '-O2', '-o', tool_root + '/queue284-evidence', tool_root + '/queue284-evidence.v']
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()), 'VROOT': json2.Any(os.getenv('VROOT')), 'compiler_sha256': json2.Any(hash(compiler_path)!), 'source_sha256': json2.Any(hash(argv.last())!), 'bootstrap_sha256': json2.Any(hash(os.executable())!)}
	os.write_file(tool_root + '/compile-before.json', json2.encode(receipt, prettify: true) + '\n')!
	r := os.exec(argv)
	os.write_file(tool_root + '/compile.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	receipt['stdout_sha256'] = hash(tool_root + '/compile.log')!
	if r.exit_code == 0 { receipt['output_sha256'] = hash(tool_root + '/queue284-evidence')! }
	os.write_file(tool_root + '/compile-receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	assert r.exit_code == 0, r.output
	for path, digest in pins(tool_root + '/backend/headers.json')! { assert hash(backend['sdk-path']! + '/usr/include/CommonCrypto/' + path)! == digest, 'SDK headers unchanged during checker compilation: ' + path }
	assert hash(backend['sdk-path']! + '/usr/lib/system/libcommonCrypto.tbd')! == backend['link_stub_sha256']!
	mut after := map[string]string{}
	for path, digest in pins(tool_root + '/backend/inputs-before.json')! { after[path] = hash(path)!; assert after[path]! == digest, 'consumed backend input unchanged: ' + path }
	os.write_file(tool_root + '/backend/inputs-after.json', json2.encode(after, prettify: true) + '\n')!
	for path, digest in closure { assert hash(path)! == digest }
	assert hash(compiler_path)! == compiler_pin && hash(argv.last())! == receipt['source_sha256']!.str()
	println('QUEUE284 CHECKER COMPILED ' + receipt['output_sha256']!.str())
}

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	assert os.args.len >= 2
	if os.args[1] == '--self-test' { assert os.args.len == 2; self_test()!; return }
	if os.args[1] == '--run-metadata' { assert os.args.len == 4; println(json2.encode(run_metadata(os.args[2], os.args[3])!, prettify: true)); return }
	if os.args[1] == '--hash-self-test' { assert os.args.len == 3; hash_self_test(os.args[2])!; return }
	if os.args[1] == '--hash-pin' { assert os.args.len == 4 && hash(os.args[2])! == os.args[3]; println('QUEUE284 HASH PIN PASS ' + os.args[3]); return }
	if os.args[1] == 'compile' { assert os.args.len == 2; compile_checker()!; return }
	if os.args[1] == '--assertion-probe' { assert false, 'assertions enabled'; return }
	assert os.args.len in [3, 4], 'run BASE MODE | retain BASE BUNDLE | preflight BUNDLE | seal BUNDLE | check BUNDLE MANIFEST_SHA256'
	if os.args[1] == 'run' { assert os.args.len == 4; run_pair(os.args[2], os.args[3])!; return }
	if os.args[1] == 'retain' {
		assert os.args.len == 4 && os.args[2] == compound
		base := os.real_path(os.args[2])
		root := os.real_path(os.args[3])
		assert root == os.args[3] && !root.starts_with(os.real_path(os.getwd()) + '/') && os.is_dir(root + '/prelaunch')
		mut excluded := map[string]string{}
		for name in ['run-baseline', 'run-fixed', 'vm-baseline', 'vm-fixed', 'run-tool'] { clone_tree(base + '/' + name, root + '/' + name, mut excluded)! }
		for mode in ['baseline', 'fixed'] {
			for suffix in ['-before.json', '-receipt.json', '.log'] { clone_tree(base + '/run-' + mode + suffix, root + '/run-' + mode + suffix, mut excluded)! }
		}
		assert hash(os.executable())! == hash(tool_root + '/queue284-evidence')!
		clone_tree(tool_root, root + '/checker', mut excluded)!
		os.write_file(root + '/excluded-special-files.json', json2.encode(excluded, prettify: true) + '\n')!
		println('QUEUE284 EVIDENCE RETAINED')
		return
	}
	root := os.real_path(os.args[2])
	assert os.is_abs_path(root) && !root.starts_with(os.real_path(os.getwd()) + '/')
	if os.args[1] == 'preflight' {
		assert os.args.len == 3
		compile_receipt := object(tool_root + '/compile-receipt.json')!
		assert compile_receipt['output_sha256']!.str() == hash(os.executable())!
		assert compile_receipt['source_sha256']!.str() == hash(@FILE)!
		assert compile_receipt['exit_code']!.int() == 0 && compile_receipt['compiler_sha256']!.str() == compiler_pin
		verify_backend(tool_root)!
		verify_inputs(root)!
		verify_references(root)!
		verify_sources(root + '/prelaunch')!
		println('QUEUE284 EVIDENCE PREFLIGHT PASS same fixture/JAR, native-only source/build delta and complete prepared closure')
	} else if os.args[1] == 'seal' {
		assert os.args.len == 3 && !os.exists(root + '/sha256.json')
		verify(root)!
		os.write_file(root + '/sha256.json', json2.encode(inventory(root)!, prettify: true) + '\n')!
		println('QUEUE284 EVIDENCE SEALED ' + hash(root + '/sha256.json')!)
	} else {
		assert os.args[1] == 'check' && os.args.len == 4
		assert hash(root + '/sha256.json')! == os.args[3], 'manifest pin mismatch'
		mut actual := inventory(root)!
		actual.delete('sha256.json')
		assert actual == pins(root + '/sha256.json')!, 'complete inventory required'
		verify(root)!
		println('QUEUE284 EVIDENCE PASS baseline276 exact queue/frame invariant failure; fixed284 partial frame and ordered completion; same APK/JAR, native-only delta and natural90s observation; raw classifiers unchanged; complete retained closure')
	}
}
