// SPDX-License-Identifier: GPL-2.0-or-later
// Fresh Maps replay with Path operations; compare both overlays against Maps295.
module main

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

const base = 'build/android-maps/'
const target = base + 'maps298'
const output = base + 'attempt298'
const config = base + 'attempt298.json'
const retained = '/Users/alex/.local/state/vinix/android/maps298-2026-10-25'
const previous = '/Users/alex/.local/state/vinix/android/maps285-2026-10-25-prelaunch'
const previous_pin = 'e69637746f704240c9c9e19ecd85aa421df786c55931cf1ca361c51dbb07e895'
const previous_tree = previous + '/prelaunch/maps285'
const compiler = base + 'queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const source = 'tests/native-android-ws/maps298-run.v'
const native = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const jar = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const driver = base + 'maps-interact-unique258'
const outer_build = '/Users/alex/.local/state/vinix/android/maps298-run-build-c-2026-10-25'
const native293_pin = '8a19a48ad2fe03d643ebe446507db68ecbbbc406e704e5fd4ef3a5dfe5c12e2d'
const framework290_pin = '50fe71a5719b74fb4fe0cfd0531213b216cad87ee87fc78e5cb348f38237b232'
const comparison295 = '/Users/alex/.local/state/vinix/android/maps295-2026-10-25'
const comparison295_pin = 'da3bc668f77b42d0ad9255ebbc68685cc6f77fc0e6bc9b39b5d782a56d43ac53'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		if C.CC_SHA256_Init(unsafe { &state }) != 1 { return error('CC_SHA256_Init failed') }
		for {
			n := file.read(mut buffer) or {
				if err is os.Eof { break }
				return err
			}
			if n == 0 { break }
			if C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) != 1 {
				return error('CC_SHA256_Update failed')
			}
		}
		mut result := [32]u8{}
		if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) != 1 {
			return error('CC_SHA256_Final failed')
		}
		return result[..].hex()
	} $else {
		mut digest := sha256.new()
		defer { unsafe { digest.free() } }
		for {
			n := file.read(mut buffer) or {
				if err is os.Eof { break }
				return err
			}
			if n == 0 { break }
			if digest.write(buffer[..n])! != n { return error('SHA256 short write') }
		}
		mut result := []u8{len: 32}
		defer { unsafe { result.free() } }
		digest.checksum_into(mut result)
		return result.hex()
	}
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn require_pin(path string, pin string) ! {
	if pin.len != 64 || hash(path)! != pin { return error('wrong input pin: ' + path) }
}

fn checked(argv []string) !string {
	r := os.exec(argv)
	if r.exit_code != 0 { return error(argv.str() + ': ' + r.output) }
	return r.output
}

fn clone(from string, to string) ! {
	if os.exists(to) || os.is_link(to) { return error('fresh destination required: ' + to) }
	os.mkdir_all(os.dir(to))!
	checked([os.find_abs_path_of_executable('cp')!, '-c', '-R', '-P', from, to])!
}

fn clone_bytes(from string, to string) ! { clone(os.real_path(from), to)! }

fn inventory(root string, relative string, mut entries map[string]string, typed bool) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory {
				if typed { entries[key] = 'directory' }
				inventory(root, key, mut entries, typed)!
			}
			.symbolic_link {
				if typed { entries[key] = 'symlink:' + os.readlink(path)! }
			}
			else { return error('unexpected artifact: ' + path) }
		}
		if typed { entries['@mode:' + key] = (os.lstat(path)!.mode & 0o7777).str() }
	}
}

fn tree(root string, typed bool) !map[string]string {
	mut result := map[string]string{}
	inventory(root, '', mut result, typed)!
	return result
}

fn build_inventory(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory { build_inventory(root, key, mut entries)! }
			else { return error('unexpected build artifact: ' + path) }
		}
	}
}

fn qualify_build(root string, manifest_pin string, payload string, payload_pin string) !int {
	require_pin(root + '/sha256.json', manifest_pin)!
	expected := read_map(root + '/sha256.json')!
	if expected.len == 0 || 'sha256.json' in expected {
		return error('invalid build inventory')
	}
	if payload !in expected || expected[payload]! != payload_pin {
		return error('payload absent from authenticated build inventory')
	}
	mut actual := map[string]string{}
	build_inventory(root, '', mut actual)!
	actual.delete('sha256.json')
	equal(actual, expected)!
	require_pin(root + '/' + payload, payload_pin)!
	require_pin(root + '/sha256.json', manifest_pin)!
	return actual.len
}

fn qualify_builds() ! {
	for label in ['native296', 'framework296b'] {
		ref := read_map(retained + '/' + label + '-build-readback.json')!
		count := qualify_build(retained + '/' + label + '-build', ref['manifest_sha256']!,
			ref['payload']!, ref['payload_sha256']!)!
		if count.str() != ref['files_checked']! { return error('retained build count differs') }
	}
}

fn qualify_comparison295() ! {
	root := retained + '/comparison295'
	require_pin(root + '/prelaunch-sha256.json', comparison295_pin)!
	manifest := read_map(root + '/prelaunch-sha256.json')!
	for name in ['runtime-after.json', 'module-after-typed.json'] {
		require_pin(root + '/' + name, manifest['maps295/' + name]!)!
	}
}

fn equal(actual map[string]string, expected map[string]string) ! {
	if actual.len != expected.len { return error('inventory lengths differ') }
	for key, value in expected {
		if actual[key] or { '' } != value { return error('inventory differs: ' + key) }
	}
}

fn receipt(label string, argv []string) !int {
	mut record := {
		'argv':                 json2.Any(argv)
		'started_utc':          json2.Any(time.utc().str())
		'working_directory':    json2.Any(os.getwd())
		'VROOT':                json2.Any(os.getenv('VROOT'))
		'PATH':                 json2.Any(os.getenv('PATH'))
		'runner_source_sha256': json2.Any(hash(source)!)
		'runner_binary_sha256': json2.Any(hash(os.executable())!)
	}
	write_json(retained + '/' + label + '-before.json', record)!
	r := os.exec(argv)
	os.write_file(retained + '/' + label + '.log', r.output)!
	record['completed_utc'] = time.utc().str()
	record['exit_code'] = r.exit_code
	record['output_bytes'] = r.output.len
	record['output_sha256'] = hash(retained + '/' + label + '.log')!
	if label == 'suite-build' && r.exit_code == 0 {
		record['binary_sha256'] = hash(target + '/suite298')!
	}
	write_json(retained + '/' + label + '-receipt.json', record)!
	return r.exit_code
}

fn classifier(text string) !string {
	if text.count('fn observation(') != 1 || text.count('// Real companion packages') != 1 {
		return error('classifier bounds differ')
	}
	return text.all_after('fn observation(').all_before('// Real companion packages')
}

fn once(text string, from string, to string) !string {
	if text.count(from) != 1 { return error('source replacement is not unique: ' + from) }
	return text.replace(from, to)
}

fn quote(text string) string { return "'" + text.replace("'", r"'\''") + "'" }

fn stdin_hash() !string {
	mut digest := sha256.new()
	mut input := os.stdin()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := input.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn closure(unit string, path string, label string) ! {
	argv := [compiler, '-print-v-files', '-path', path, unit]
	listing := checked(argv)!
	os.write_file(retained + '/' + label + '-v-files.txt', listing)!
	mut pins := map[string]string{}
	for file in listing.split_into_lines().filter(it.ends_with('.v')) {
		pins[file] = hash(file)!
		clone_bytes(file, retained + '/' + label + '-closure/' + file.trim_left('/'))!
	}
	if pins.len < 10 { return error('incomplete source closure') }
	write_json(retained + '/' + label + '-v-files.json', pins)!
	write_json(retained + '/' + label + '-closure-receipt.json', {
		'argv':            json2.Any(argv)
		'completed_utc':   json2.Any(time.utc().str())
		'exit_code':       json2.Any(0)
		'compiler_sha256': json2.Any(hash(compiler)!)
	})!
}

fn qualify_runner_build() ! {
	record := object(outer_build + '/build-receipt.json')!
	if record['exit_code']!.int() != 0 { return error('runner build failed') }
	require_pin(source, record['source_sha256']!.str())!
	require_pin(os.executable(), record['binary_sha256']!.str())!
	require_pin(outer_build + '/maps298-run.v', record['source_sha256']!.str())!
	require_pin(outer_build + '/maps298-run', record['binary_sha256']!.str())!
	require_pin(compiler, compiler_pin)!
	require_pin(outer_build + '/v_old276', compiler_pin)!
	require_pin(record['cc_path']!.str(), record['cc_sha256']!.str())!
	require_pin(outer_build + '/closure-before.json', record['closure_before_sha256']!.str())!
	require_pin(outer_build + '/closure-after.json', record['closure_after_sha256']!.str())!
	require_pin(outer_build + '/closure-v-files.txt', record['closure_listing_sha256']!.str())!
	before := read_map(outer_build + '/closure-before.json')!
	if before.len < 10 { return error('incomplete runner build closure') }
	equal(read_map(outer_build + '/closure-after.json')!, before)!
	for path, pin in before {
		require_pin(path, pin)!
		require_pin(outer_build + '/closure/' + path.trim_left('/'), pin)!
	}
}

fn prepare(native_root string, native_manifest string, native_pin string,
	framework_root string, framework_manifest string, jar_pin string) ! {
	for path in [target, config, output, retained] {
		if os.exists(path) || os.is_link(path) { return error('fresh298 destination required: ' + path) }
	}
	if native_root != '/Users/alex/.local/state/vinix/android/path-ops296-native-build-2026-10-25'
		|| framework_root != '/Users/alex/.local/state/vinix/android/path-ops296b-framework-build-2026-10-25' {
		return error('qualified296 external build roots required')
	}
	qualify_runner_build()!
	native_path := native_root + '/native/libvinix-android-native.so'
	jar_path := framework_root + '/framework/api-impl.jar'
	require_pin(previous + '/prelaunch-sha256.json', previous_pin)!
	selected := read_map(previous + '/prelaunch-sha256.json')!
	for name in ['suite285.v', 'sources/nativeapk/install.v', 'runtime-after.json',
		'module-after-typed.json', 'vm/boot.img', 'vm/efivars.fd'] {
		require_pin(previous_tree + '/' + name, selected['maps285/' + name]!)!
	}
	require_pin(previous + '/prelaunch/attempt285.json', selected['attempt285.json']!)!
	require_pin(native_path, native_pin)!
	if native_pin == native293_pin {
		return error('new native296 Path operation input required')
	}
	native_build_entries := qualify_build(native_root, native_manifest,
		'native/libvinix-android-native.so', native_pin)!
	require_pin(jar_path, jar_pin)!
	if jar_pin == framework290_pin { return error('new framework296b Path operations required') }
	framework_build_entries := qualify_build(framework_root, framework_manifest,
		'framework/api-impl.jar', jar_pin)!
	require_pin(comparison295 + '/prelaunch-sha256.json', comparison295_pin)!
	comparison_manifest := read_map(comparison295 + '/prelaunch-sha256.json')!
	for name in ['runtime-after.json', 'module-after-typed.json'] {
		require_pin(comparison295 + '/prelaunch/maps295/' + name,
			comparison_manifest['maps295/' + name]!)!
	}
	require_pin(compiler, compiler_pin)!
	require_pin(driver, 'abd2dfbb01fddc83ffffae481b5d1fcab35b9ebd279f3f47abae237b00134208')!
	os.mkdir_all(target + '/vm')!
	os.mkdir_all(retained)!
	clone(native_root, retained + '/native296-build')!
	write_json(retained + '/native296-build-readback.json', {
		'original_root': native_root
		'manifest_sha256': native_manifest
		'payload': 'native/libvinix-android-native.so'
		'payload_sha256': native_pin
		'files_checked': native_build_entries.str()
	})!
	clone(framework_root, retained + '/framework296b-build')!
	write_json(retained + '/framework296b-build-readback.json', {
		'original_root': framework_root
		'manifest_sha256': framework_manifest
		'payload': 'framework/api-impl.jar'
		'payload_sha256': jar_pin
		'files_checked': framework_build_entries.str()
	})!
	qualify_builds()!
	clone_bytes(comparison295 + '/prelaunch-sha256.json', retained + '/comparison295/prelaunch-sha256.json')!
	for name in ['runtime-after.json', 'module-after-typed.json'] {
		clone_bytes(comparison295 + '/prelaunch/maps295/' + name, retained + '/comparison295/' + name)!
	}
	qualify_comparison295()!
	clone(previous_tree + '/module', target + '/module')!
	equal(tree(target + '/module', true)!, read_map(previous_tree + '/module-after-typed.json')!)!
	before := read_map(previous_tree + '/runtime-after.json')!
	equal(tree(target + '/module', false)!, before)!
	require_pin(target + '/module/' + jar, '92b069b1dbb31b08960d00d4f33f84b068a3adf53af9339f2ef3c1a6478f0618')!
	os.cp(native_path, target + '/module/' + native)!
	os.cp(jar_path, target + '/module/' + jar)!
	after := tree(target + '/module', false)!
	if before.len != 109 || after.len != 109 { return error('complete109 runtime required') }
	for key, pin in before {
		if key != native && key != jar && after[key]! != pin {
			return error('unexpected runtime change: ' + key)
		}
	}
	if after[native]! != native_pin || after[native]! == before[native]! {
		return error('new native input required')
	}
	if after[jar]! != jar_pin || after[jar]! == before[jar]! {
		return error('new framework input required')
	}
	mut expected_typed := read_map(previous_tree + '/module-after-typed.json')!
	expected_typed[native] = native_pin
	expected_typed[jar] = jar_pin
	equal(tree(target + '/module', true)!, expected_typed)!
	comparison_runtime := read_map(retained + '/comparison295/runtime-after.json')!
	if comparison_runtime.len != 109 || comparison_runtime[jar]! != framework290_pin ||
		comparison_runtime[native]! != native293_pin {
		return error('qualified maps295 runtime required')
	}
	mut delta := []string{}
	for key, pin in comparison_runtime {
		if after[key]! != pin { delta << key }
	}
	delta.sort()
	mut expected_delta := [native, jar]
	expected_delta.sort()
	if delta != expected_delta { return error('only framework296b and native296 may differ from maps295') }
	mut comparison_typed := read_map(retained + '/comparison295/module-after-typed.json')!
	comparison_typed[native] = native_pin
	comparison_typed[jar] = jar_pin
	equal(tree(target + '/module', true)!, comparison_typed)!
	write_json(retained + '/maps295-runtime-comparison.json', {
		'maps295_prelaunch_root': comparison295
		'maps295_prelaunch_manifest_sha256': comparison295_pin
		'runtime_entries': comparison_runtime.len.str()
		'unchanged_regular_entries': (comparison_runtime.len - delta.len).str()
		'typed_module_entries': comparison_typed.len.str()
		'changed_entries': delta.join(',')
		'native293_sha256': comparison_runtime[native]!
		'native296_sha256': native_pin
		'framework290_sha256': framework290_pin
		'framework296b_sha256': jar_pin
		'scope': 'Complete109 regular runtime and typed module comparison against two authenticated maps295 prelaunch inventories; no maps295 media or final results consumed.'
	})!
	write_json(target + '/module-after-typed.json', expected_typed)!
	write_json(target + '/runtime-before.json', before)!
	write_json(target + '/runtime-after.json', after)!
	for name in ['boot.img', 'efivars.fd'] {
		clone(previous_tree + '/vm/' + name, target + '/vm/' + name)!
	}
	module_arg := quote(target + '/module')
	boot_arg := quote(target + '/vm/boot.img')
	producer := quote(os.find_abs_path_of_executable('tar')!) + ' --format=ustar -b 1 -C ' + module_arg + ' -cf - .'
	stage := ['/bin/zsh', '-c',
		'set -o pipefail; ' + producer + ' | ' + quote(os.find_abs_path_of_executable('mcopy')!) + ' -o -i ' + boot_arg + ' - ::/boot/qemu-runtime.tar']
	if receipt('archive-stage', stage)! != 0 { return error('archive staging failed') }
	staged := checked(['/bin/zsh', '-c',
		'set -o pipefail; ' + producer + ' | ' + quote(os.executable()) + ' --hash-stdin'])!.trim_space()
	actual := checked(['/bin/zsh', '-c',
		'set -o pipefail; ' + quote(os.find_abs_path_of_executable('mtype')!) + ' -i ' + boot_arg + ' ::/boot/qemu-runtime.tar | ' + quote(os.executable()) + ' --hash-stdin'])!.trim_space()
	if staged.len != 64 || staged != actual { return error('FAT runtime differs from module') }
	write_json(retained + '/archive-stream.json', {
		'producer_sha256':     staged
		'fat_readback_sha256': actual
	})!
	original := os.read_file(previous_tree + '/suite285.v')!
	mut suite_text := original.replace('validate_styled285', 'validate_styled298').replace('MAPS285', 'MAPS298').replace('build/android-maps/maps285/', 'build/android-maps/maps298/')
	suite_text = once(suite_text, '586ed9a1c5ed14457744790ca4d44e1b6de31ff8dbc0d21253cf971d350eeb71', hash(target + '/runtime-after.json')!)!
	suite_text = once(suite_text, 'aa62a1ae7d005d55e1f73781b7e53fdd86dbe6c4ad9f131439598165b25d7ec2', hash(target + '/vm/boot.img')!)!
	// Use the same already-qualified bounded-memory CommonCrypto backend for large media hashes.
	helper := os.read_file(source)!
	hash_source := helper.all_after('fn hash(').all_before('fn object(')
	suite_text = suite_text.all_before('fn styled_hash(') + 'fn styled_hash(' + hash_source
	suite_text += '\n$if macos {\n\t#include <CommonCrypto/CommonDigest.h>\n}\n@[typedef]\nstruct C.CC_SHA256_CTX {}\nfn C.CC_SHA256_Init(voidptr) i32\nfn C.CC_SHA256_Update(voidptr, voidptr, u32) i32\nfn C.CC_SHA256_Final(&u8, voidptr) i32\n'
	if classifier(suite_text)! != classifier(original)! {
		return error('original observation changed')
	}
	os.write_file(target + '/suite298.v', suite_text)!
	clone_bytes(previous_tree + '/sources/nativeapk/install.v', target + '/sources/nativeapk/install.v')!
	mut settings := object(previous + '/prelaunch/attempt285.json')!
	settings['boot_image'] = target + '/vm/boot.img'
	settings['efivars'] = target + '/vm/efivars.fd'
	settings['output'] = output
	if settings['applications']!.as_array()[0].as_map()['startup_seconds']!.int() != 600 {
		return error('expected600 seconds')
	}
	write_json(config, settings)!
	closure(target + '/suite298.v', target + '/sources|@vlib|@vmodules', 'suite')!
	closure(source, '@vlib|@vmodules', 'runner')!
	if receipt('suite-build', [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-path',
		target + '/sources|@vlib|@vmodules', '-o', target + '/suite298', target + '/suite298.v'])! != 0 {
		return error('suite compilation failed')
	}
	if receipt('suite-self-test', [target + '/suite298', '--self-test'])! != 0 {
		return error('suite classifier self-test failed')
	}
	mut pins := map[string]string{}
	for path in [target + '/suite298.v', target + '/suite298', target + '/runtime-before.json',
		target + '/runtime-after.json', target + '/module-after-typed.json', config,
		target + '/vm/boot.img', target + '/vm/efivars.fd', compiler, source, os.executable(),
		driver, settings['aapt2']!.str(), settings['apksigner']!.str(), settings['java']!.str(),
		settings['firmware']!.str(), settings['qemu']!.str(), settings['input_tool']!.str(),
		base + 'attempt244/companion-packages.json'] {
		pins[path] = hash(path)!
	}
	for name in ['cp', 'tar', 'mcopy', 'mtype', 'zsh', 'unzip', 'cc'] {
		path := os.find_abs_path_of_executable(name)!
		pins[path] = hash(path)!
	}
	for label in ['native296', 'framework296b'] {
		for suffix in ['-build/sha256.json', '-build-readback.json'] {
			path := retained + '/' + label + suffix
			pins[path] = hash(path)!
		}
	}
	for name in ['prelaunch-sha256.json', 'runtime-after.json', 'module-after-typed.json'] {
		path := retained + '/comparison295/' + name
		pins[path] = hash(path)!
	}
	for app in settings['applications']!.as_array() {
		entry := app.as_map()
		pins[entry['apk']!.str()] = hash(entry['apk']!.str())!
		for companion in entry['companion_apks']!.as_array() {
			path := companion.as_map()['apk']!.str()
			pins[path] = hash(path)!
		}
	}
	for label in ['suite', 'runner'] {
		for path, pin in read_map(retained + '/' + label + '-v-files.json')! {
			require_pin(path, pin)!
			require_pin(retained + '/' + label + '-closure/' + path.trim_left('/'), pin)!
		}
	}
	write_json(target + '/launch-pins.json', pins)!
	clone(target, retained + '/prelaunch/maps298')!
	for path in pins.keys() {
		if !path.starts_with(target + '/') {
			clone_bytes(path, retained + '/prelaunch/inputs/' + path.trim_left('/'))!
		}
	}
	write_json(retained + '/references.json', {
		'maps285_prelaunch_root':            previous
		'maps285_prelaunch_manifest_sha256': previous_pin
		'native_input':                      native_path
		'native_sha256':                     native_pin
		'native296_build_root':              native_root
		'native296_build_manifest_sha256':   native_manifest
		'framework_input':                   jar_path
		'framework_sha256':                  jar_pin
		'framework296b_build_root':           framework_root
		'framework296b_build_manifest_sha256': framework_manifest
		'maps295_prelaunch_root':            comparison295
		'maps295_prelaunch_manifest_sha256': comparison295_pin
		'source_revision':                   checked(['git', 'rev-parse', 'HEAD'])!.trim_space()
		'classifier_sha256':                 sha256.sum(classifier(original)!.bytes()).hex()
	})!
	clone(outer_build, retained + '/runner-build')!
	write_json(retained + '/prelaunch-sha256.json', tree(retained + '/prelaunch', true)!)!
	println('MAPS298 PREPARED launch-pins=' + hash(target + '/launch-pins.json')! + ' prelaunch=' + hash(retained + '/prelaunch-sha256.json')!)
}

fn gate(pin string, prelaunch_pin string) ! {
	require_pin(target + '/launch-pins.json', pin)!
	require_pin(retained + '/prelaunch-sha256.json', prelaunch_pin)!
	equal(tree(retained + '/prelaunch', true)!, read_map(retained + '/prelaunch-sha256.json')!)!
	for path, expected in read_map(target + '/launch-pins.json')! { require_pin(path, expected)! }
	equal(tree(target + '/module', true)!, read_map(target + '/module-after-typed.json')!)!
	qualify_builds()!
	qualify_comparison295()!
}

fn results(from string, to string, key string, mut sockets []string) ! {
	os.mkdir_all(to)!
	for name in os.ls(from)! {
		path := from + '/' + name
		relative := if key == '' { name } else { key + '/' + name }
		match os.lstat(path)!.get_filetype() {
			.regular { clone(path, to + '/' + name)! }
			.directory { results(path, to + '/' + name, relative, mut sockets)! }
			.symbolic_link { os.symlink(os.readlink(path)!, to + '/' + name)! }
			.socket {
				if name != 'qmp.sock' { return error('unexpected socket') }
				sockets << relative
			}
			else { return error('unexpected result: ' + relative) }
		}
	}
}

fn run(pin string, prelaunch_pin string) !int {
	gate(pin, prelaunch_pin)!
	if os.exists(output) || os.exists(retained + '/launch-before.json') {
		return error('fresh launch required')
	}
	status := receipt('launch', [target + '/suite298', config])!
	mut sockets := []string{}
	if os.exists(output) { results(output, retained + '/results/attempt298', '', mut sockets)! }
	write_json(retained + '/omitted-sockets.json', sockets)!
	clone(target + '/vm', retained + '/postrun-vm')!
	mut postrun := map[string]string{}
	for path, expected in read_map(target + '/launch-pins.json')! {
		postrun[path] = hash(path)!
		if !path.starts_with(target + '/vm/') && postrun[path]! != expected {
			return error('non-media input changed: ' + path)
		}
	}
	write_json(retained + '/postrun-pins.json', postrun)!
	equal(tree(target + '/module', true)!, read_map(target + '/module-after-typed.json')!)!
	qualify_builds()!
	qualify_comparison295()!
	write_json(retained + '/sha256.json', tree(retained, true)!)!
	println('MAPS298 RECORDED exit=' + status.str() + ' manifest=' + hash(retained + '/sha256.json')!)
	return status
}

fn rebuild() ! {
	if os.exists(outer_build) { return error('fresh runner build directory required') }
	require_pin(compiler, compiler_pin)!
	os.mkdir_all(outer_build)!
	clone_bytes(source, outer_build + '/maps298-run.v')!
	clone_bytes(compiler, outer_build + '/v_old276')!
	closure_argv := [compiler, '-print-v-files', source]
	closure_started := time.utc().str()
	listing := os.exec(closure_argv)
	os.write_file(outer_build + '/closure-v-files.txt', listing.output)!
	write_json(outer_build + '/closure-receipt.json', {
		'argv': json2.Any(closure_argv)
		'started_utc': json2.Any(closure_started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(listing.exit_code)
		'compiler_sha256': json2.Any(hash(compiler)!)
		'VROOT': json2.Any(os.getenv('VROOT'))
	})!
	if listing.exit_code != 0 { return error('runner build closure discovery failed') }
	mut before := map[string]string{}
	for path in listing.output.split_into_lines().filter(it.ends_with('.v')) {
		before[path] = hash(path)!
		clone_bytes(path, outer_build + '/closure/' + path.trim_left('/'))!
	}
	if before.len < 10 { return error('incomplete runner build closure') }
	write_json(outer_build + '/closure-before.json', before)!
	argv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', base + 'maps298-run-recorded',
		source]
	mut record := {
		'argv':              json2.Any(argv)
		'started_utc':       json2.Any(time.utc().str())
		'working_directory': json2.Any(os.getwd())
		'VROOT':             json2.Any(os.getenv('VROOT'))
		'compiler_sha256':   json2.Any(hash(compiler)!)
		'source_sha256':     json2.Any(hash(source)!)
		'cc_path':           json2.Any(os.find_abs_path_of_executable('cc')!)
		'cc_sha256':         json2.Any(hash(os.find_abs_path_of_executable('cc')!)!)
		'closure_before_sha256': json2.Any(hash(outer_build + '/closure-before.json')!)
		'closure_listing_sha256': json2.Any(hash(outer_build + '/closure-v-files.txt')!)
	}
	write_json(outer_build + '/build-before.json', record)!
	r := os.exec(argv)
	os.write_file(outer_build + '/build.log', r.output)!
	record['completed_utc'] = time.utc().str()
	record['exit_code'] = r.exit_code
	if r.exit_code == 0 { record['binary_sha256'] = hash(base + 'maps298-run-recorded')! }
	mut after := map[string]string{}
	for path, pin in before {
		after[path] = hash(path)!
		require_pin(outer_build + '/closure/' + path.trim_left('/'), pin)!
	}
	equal(after, before)!
	require_pin(compiler, compiler_pin)!
	require_pin(record['cc_path']!.str(), record['cc_sha256']!.str())!
	write_json(outer_build + '/closure-after.json', after)!
	record['closure_after_sha256'] = hash(outer_build + '/closure-after.json')!
	write_json(outer_build + '/build-receipt.json', record)!
	if r.exit_code != 0 { return error('recorded runner build failed') }
	clone_bytes(base + 'maps298-run-recorded', outer_build + '/maps298-run')!
	require_pin(source, record['source_sha256']!.str())!
	println('MAPS298-RUNNER-BUILD-PASS')
}

fn verify(pin string) ! {
	require_pin(retained + '/sha256.json', pin)!
	mut actual := tree(retained, true)!
	actual.delete('sha256.json')
	actual.delete('@mode:sha256.json')
	equal(actual, read_map(retained + '/sha256.json')!)!
	println('MAPS298-COMPLETED-READBACK-PASS entries=' + actual.len.str())
}

fn main() {
	$if prod {
		eprintln('requires assertions')
		exit(2)
	}
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('COPYFILE_DISABLE', '1', true)
	if os.args.len == 2 && os.args[1] == '--hash-stdin' {
		println(stdin_hash()!)
		return
	}
	if os.args.len == 2 && os.args[1] == 'rebuild' {
		rebuild()!
		return
	}
	if os.args.len == 3 && os.args[1] == 'verify' {
		verify(os.args[2])!
		return
	}
	if os.args.len == 8 && os.args[1] == 'prepare' {
		prepare(os.abs_path(os.args[2]), os.args[3], os.args[4],
			os.abs_path(os.args[5]), os.args[6], os.args[7])!
		return
	}
	if os.args.len == 4 && os.args[1] == 'check' {
		gate(os.args[2], os.args[3])!
		println('MAPS298-GATE-PASS')
		return
	}
	if os.args.len == 4 && os.args[1] == 'run' { exit(run(os.args[2], os.args[3])!) }
	panic('usage: maps298-run rebuild | prepare NATIVE_ROOT MANIFEST_SHA NATIVE_SHA FRAMEWORK_ROOT MANIFEST_SHA FRAMEWORK_SHA | check|run LAUNCH_PINS_SHA256 PRELAUNCH_SHA256 | verify MANIFEST_SHA256')
}
