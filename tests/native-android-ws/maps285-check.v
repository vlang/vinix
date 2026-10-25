// SPDX-License-Identifier: GPL-2.0-or-later
// Independent readback of new Maps285 evidence; historical bundles stay references.
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

const prelaunch_pin = 'e69637746f704240c9c9e19ecd85aa421df786c55931cf1ca361c51dbb07e895'
const runner_build_pin = '54f62d97952c7417d6c9c1ce61be0a540bbf946852125c7ddefd935cdf1db7ee'
const prepare_build_pin = '4cdde83512e06b97a0d0e529cf09a3dd870d0d9304936d8892df30f633b49677'
const native_pin = '2687a6df361f3173499fcae7ffeeb9318d2c83363cee1fce0deedf17f9ee0585'
const jar_pin = '92b069b1dbb31b08960d00d4f33f84b068a3adf53af9339f2ef3c1a6478f0618'
const native = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const jar = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const retained = 'prelaunch/prelaunch/'
const module_prefix = retained + 'maps285/module/'
const app_prefix = 'results/attempt285/google-maps/'

fn require(ok bool, message string) ! { if !ok { return error(message) } }

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn string_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

// Reviewed CommonCrypto file backend with bounded portable V fallback.
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
		mut state := sha256.new()
		defer { unsafe { state.free() } }
		for {
			n := file.read(mut buffer) or {
				if err is os.Eof { break }
				return err
			}
			if n == 0 { break }
			if state.write(buffer[..n])! != n { return error('SHA256 short write') }
		}
		mut result := []u8{len: 32}
		defer { unsafe { result.free() } }
		state.checksum_into(mut result)
		return result.hex()
	}
}

fn inventory(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.directory {
				entries[key] = 'directory'
				inventory(root, key, mut entries)!
			}
			.regular { entries[key] = hash(path)! }
			.symbolic_link { entries[key] = 'symlink:' + os.readlink(path)! }
			else { return error('special retained entry: ' + key) }
		}
	}
}

fn equal_maps(actual map[string]string, expected map[string]string) ! {
	require(actual.len == expected.len, 'inventory length differs')!
	for key, value in expected {
		require(actual[key] or { '' } == value, 'inventory differs: ' + key)!
	}
}

fn verify(root string, pin string) !map[string]string {
	require(pin.len == 64 && hash(root + '/sha256.json')! == pin, 'wrong completed manifest pin')!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	actual.delete('sha256.json')
	equal_maps(actual, string_map(root + '/sha256.json')!)!
	return actual
}

// Reuse the independently read inventory, avoiding a second media read.
fn nested(root string, actual map[string]string, prefix string, manifest string, pin string) ! {
	require(actual[manifest]! == pin, 'nested manifest pin: ' + manifest)!
	mut selected := map[string]string{}
	for path, value in actual {
		if path.starts_with(prefix) && path != manifest { selected[path.all_after(prefix)] = value }
	}
	equal_maps(selected, string_map(root + '/' + manifest)!)!
}

fn receipt_pair(root string, label string) !map[string]json2.Any {
	before := object(root + '/' + label + '-before.json')!
	after := object(root + '/' + label + '-receipt.json')!
	done_keys := ['completed_utc', 'exit_code', 'combined_output_sha256', 'combined_output_bytes']
	require(after.len == before.len + done_keys.len, 'receipt before/done field count')!
	for key in done_keys {
		require(key !in before && key in after, 'receipt completed-only field: ' + key)!
	}
	for key in after.keys() {
		require(key in before || key in done_keys, 'missing before field: ' + key)!
	}
	for key, value in before {
		require(json2.encode(after[key]!) == json2.encode(value), 'receipt mismatch: ' + label + '/' + key)!
	}
	require(time.parse(after['completed_utc']!.str())!.unix() - time.parse(before['started_utc']!.str())!.unix() >= 600, 'receipt shorter than observation: ' + label)!
	return after
}

fn classifier(source string) !string {
	require(source.count('fn observation(') == 1 && source.count('// Real companion packages') == 1, 'classifier bounds')!
	return source.all_after('fn observation(').all_before('// Real companion packages')
}

fn validate_row(row map[string]json2.Any) ! {
	for key in ['backend_ready', 'native_maps_observed', 'launcher_entered', 'qemu_alive_before_capture'] {
		require(row[key]!.bool(), 'raw flag: ' + key)!
	}
	require(!row['process_exited']!.bool() && row['outcome']!.str() == 'window_observed', 'raw outcome differs')!
	require(row['functional_passed']! is json2.Null && row['failure_markers']!.as_array().len == 0, 'raw classifier changed or failed')!
	for key in ['startup_seconds', 'startup_timeout_seconds', 'observation_elapsed_seconds'] {
		require(row[key]!.int() == 600, 'incomplete observation: ' + key)!
	}
}

fn observation(log string) map[string]json2.Any {
	mut failures := []string{}
	for line in log.split_into_lines() {
		for marker in ['ANDROID-WS-FAIL', 'APK-SUITE-DEPENDENCY-FAIL', 'ANDROID-WS-DEPENDENCY-FAIL',
			'ANDROID-WS-PROCESS-FAIL', 'JNI DETECTED ERROR', 'NoClassDefFoundError', 'NoSuchMethodError',
			'UnsatisfiedLinkError', 'ClassNotFoundException', 'NoSuchFieldError', 'APK-SUITE-EXIT id='] {
			if line.contains(marker) {
				failures << line.trim_space()
				break
			}
		}
	}
	begin := log.contains('APK-SUITE-BEGIN id=google-maps ')
	ready := log.contains('ANDROID-WS-READY backend=vinix-native')
	exited := log.contains('APK-SUITE-EXIT id=google-maps ')
	outcome := if !begin {
		'harness_failure'
	} else if exited || failures.len > 0 {
		'startup_failed'
	} else if ready {
		'window_observed'
	} else {
		'startup_timeout'
	}
	return {
		'launcher_entered':     json2.Any(begin)
		'backend_ready':        json2.Any(ready)
		'process_exited':       json2.Any(exited)
		'native_maps_observed': json2.Any(log.contains('APK-SUITE-MAPS id=google-maps '))
		'functional_passed':    json2.Any(json2.Null{})
		'outcome':              json2.Any(outcome)
		'failure_markers':      json2.Any(failures)
	}
}

fn check(root string, pin string) ! {
	actual := verify(root, pin)!
	nested(root, actual, 'runner-build/', 'runner-build/sha256.json', runner_build_pin)!
	nested(root, actual, 'preparation-build/', 'preparation-build/sha256.json', prepare_build_pin)!
	nested(root, actual, retained, 'prelaunch/prelaunch-sha256.json', prelaunch_pin)!
	references := object(root + '/references.json')!
	require(references['maps283_manifest_sha256']!.str() == actual[retained + 'reference283/sha256.json']!, 'Maps283 reference pin')!
	require(references['queue284_prelaunch_sha256']!.str() == actual[retained + 'reference284/prelaunch-sha256.json']!, 'queue284 reference pin')!
	equal_maps(string_map(root + '/references.json')!, string_map(root + '/' + retained + 'maps285/references.json')!)!
	receipt := receipt_pair(root, 'execution/launch')!
	require(receipt['exit_code']!.int() == 0 && receipt['observation_seconds']!.int() == 600, 'launch failed or wrong budget')!
	require(receipt['argv']!.as_array().map(it.str()) == [
		'build/android-maps/maps285/suite285',
		'build/android-maps/attempt285.json',
	], 'wrong launch argv')!
	require(receipt['prelaunch_manifest_sha256']!.str() == prelaunch_pin && receipt['runner_build_manifest_sha256']!.str() == runner_build_pin, 'launch trust roots')!
	for field, path in {
		'runner_source_sha256':   'runner-build/maps285-run.v'
		'runner_binary_sha256':   'runner-build/maps285-run'
		'suite_source_sha256':    retained + 'maps285/suite285.v'
		'suite_binary_sha256':    retained + 'maps285/suite285'
		'config_sha256':          retained + 'attempt285.json'
		'launch_pins_sha256':     retained + 'maps285/prelaunch-sha256.json'
		'combined_output_sha256': 'execution/launch.log'
	} {
		require(receipt[field]!.str() == actual[path]!, 'launch input/output binding: ' + field)!
	}
	require(receipt['combined_output_bytes']!.int() == os.file_size(root + '/execution/launch.log'), 'incomplete launch output')!
	require(receipt['output_capture']!.str() == 'entire combined stdout/stderr from os.exec; no truncation', 'capture scope')!
	require(json2.decode[[]string](os.read_file(root + '/execution/omitted-sockets.json')!)!.len == 0, 'unexpected omissions')!
	equal_maps(object_strings(root + '/postrun-config.json')!, object_strings(root + '/' + retained + 'attempt285.json')!)!
	before := string_map(root + '/' + retained + 'maps285/runtime-before.json')!
	after := string_map(root + '/' + retained + 'maps285/runtime-after.json')!
	require(before.len == 109 && after.len == 109 && before[native]! != native_pin && after[native]! == native_pin && after[jar]! == jar_pin, 'runtime count or overlay pins')!
	mut expected_after := before.clone()
	expected_after[native] = native_pin
	equal_maps(after, expected_after)!
	mut typed := map[string]string{}
	inventory(root + '/' + module_prefix, '', mut typed)!
	mut regular := map[string]string{}
	for key in typed.keys() {
		if typed[key]!.len == 64 { regular[key] = typed[key]! }
		typed['@mode:' + key] = (os.lstat(root + '/' + module_prefix + key)!.mode & 0o7777).str()
	}
	equal_maps(regular, after)!
	equal_maps(typed, string_map(root + '/' + retained + 'maps285/module-after-typed.json')!)!
	mut typed_before := string_map(root + '/' + retained + 'maps285/module-before-typed.json')!
	require(typed_before[native]! == before[native]!, 'typed baseline native')!
	typed_before[native] = native_pin
	equal_maps(typed, typed_before)!
	launch_pins := string_map(root + '/' + retained + 'maps285/prelaunch-sha256.json')!
	postrun := string_map(root + '/execution/postrun-inputs.json')!
	require(postrun.len == launch_pins.len + 5, 'postrun input count')!
	mut expected_post := launch_pins.clone()
	for name in ['staging-tools.json', 'module-after-typed.json', 'references.json',
		'build-receipt.json', 'preparation-receipt.json'] {
		expected_post['build/android-maps/maps285/' + name] = actual[retained + 'maps285/' + name]!
	}
	for path in expected_post.keys() {
		if path.starts_with('build/android-maps/maps285/vm/') {
			expected_post[path] = actual['postrun-vm/' + path.all_after('/vm/')]!
		}
	}
	equal_maps(postrun, expected_post)!
	source := os.read_file(root + '/' + retained + 'maps285/suite285.v')!
	old_source := os.read_file(root + '/' + retained + 'consumed283/suite283.v')!
	require(classifier(source)! == classifier(old_source)!, 'original classifier changed')!
	build := object(root + '/' + retained + 'maps285/build-receipt.json')!
	require(build['exit_code']!.int() == 0 && '-prod' !in build['argv']!.as_array().map(it.str()), 'suite assertions or build')!
	require(build['binary_sha256']!.str() == actual[retained + 'maps285/suite285']!, 'suite build output')!
	rows := json2.decode[[]map[string]json2.Any](os.read_file(root + '/results/attempt285/results.json')!)!
	require(rows.len == 1, 'expected one Maps row')!
	row := rows[0]
	validate_row(row)!
	require(row['id']!.str() == 'google-maps' && row['package']!.str() == 'com.google.android.apps.maps', 'wrong app')!
	require(row['serial_sha256']!.str() == actual[app_prefix + 'serial.log']! && row['screenshot_sha256']!.str() == actual[app_prefix + 'application.png']!, 'row evidence pins')!
	serial := gzip.decompress(os.read_bytes(root + '/' + app_prefix + 'serial.log.gz')!)!.bytestr()
	require(serial == os.read_file(root + '/' + app_prefix + 'serial.log')!, 'raw/gzip serial mismatch')!
	recomputed := observation(serial)
	captured := object(root + '/' + app_prefix + 'observation-before-capture.json')!
	for key in ['observation_elapsed_seconds', 'startup_timeout_seconds'] {
		require(captured[key]!.int() == 600, 'before-capture budget: ' + key)!
	}
	require(captured['qemu_alive_before_capture']!.bool(), 'before-capture QEMU not alive')!
	for key, value in recomputed {
		require(json2.encode(row[key]!) == json2.encode(value) && json2.encode(captured[key]!) == json2.encode(value), 'classifier result: ' + key)!
	}
	// Bind the screenshots reviewed by people; pixels alone do not establish UI semantics.
	for name, image_pin in {
		'preview-open.png':     '45f537ad6635517dbf00b6d6c5d882db98601d7bbb3e8f2bb9f844e5091304aa'
		'preview-next.png':     'be3cf4f66c171ad86b9f6de2090302fecfbf8b4001c1bfad36f49cffe9819230'
		'preview-previous.png': '1212730de7938767423d1d4536e92187041b358a6211a0872ff96b73914cf13a'
	} {
		require(actual[app_prefix + name]! == image_pin, 'reviewed screenshot binding: ' + name)!
	}
	require(actual[app_prefix + 'interaction.log']!.len == 64, 'missing interaction log')!
	println('MAPS285 COMPLETED READBACK PASS entries=' + actual.len.str() + '; 109 runtime files/native-only; observation=600; raw=window_observed; functional_passed=null; screenshots bound for separate visual review')
}

fn object_strings(path string) !map[string]string {
	mut result := map[string]string{}
	for key, value in object(path)! { result[key] = json2.encode(value) }
	return result
}

fn self_test() ! {
	root := os.join_path(os.temp_dir(), 'maps285-completed-test-' + os.getpid().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/dir')!
	os.write_file(root + '/dir/input', 'complete evidence')!
	os.symlink('dir/input', root + '/link')!
	mut expected := map[string]string{}
	inventory(root, '', mut expected)!
	os.write_file(root + '/sha256.json', json2.encode(expected))!
	pin := hash(root + '/sha256.json')!
	verify(root, pin)!
	mut rejects := 0
	verify(root, '0'.repeat(64)) or {
		rejects++
		map[string]string{}
	}
	os.rm(root + '/dir/input')!
	verify(root, pin) or {
		rejects++
		map[string]string{}
	}
	os.write_file(root + '/dir/input', 'changed')!
	verify(root, pin) or {
		rejects++
		map[string]string{}
	}
	os.write_file(root + '/dir/input', 'complete evidence')!
	os.write_file(root + '/extra', 'extra')!
	verify(root, pin) or {
		rejects++
		map[string]string{}
	}
	os.rm(root + '/extra')!
	os.rm(root + '/link')!
	os.symlink('dir', root + '/link')!
	verify(root, pin) or {
		rejects++
		map[string]string{}
	}
	mut row := observation('APK-SUITE-BEGIN id=google-maps x\nANDROID-WS-READY backend=vinix-native\nAPK-SUITE-MAPS id=google-maps x\n')
	for key in ['startup_seconds', 'startup_timeout_seconds', 'observation_elapsed_seconds'] {
		row[key] = 600
	}
	row['qemu_alive_before_capture'] = true
	validate_row(row)!
	row['observation_elapsed_seconds'] = 599
	validate_row(row) or { rejects++ }
	row['observation_elapsed_seconds'] = 600
	row['functional_passed'] = true
	validate_row(row) or { rejects++ }
	row['functional_passed'] = json2.Null{}
	row['process_exited'] = true
	validate_row(row) or { rejects++ }

	for log in [
		'APK-SUITE-BEGIN id=google-maps x\nANDROID-WS-READY backend=vinix-native\n',
		'ANDROID-WS-READY backend=vinix-native\nAPK-SUITE-MAPS id=google-maps x\n',
		'APK-SUITE-BEGIN id=google-maps x\nAPK-SUITE-MAPS id=google-maps x\n',
	] {
		mut invalid := observation(log)
		for key in ['startup_seconds', 'startup_timeout_seconds', 'observation_elapsed_seconds'] {
			invalid[key] = 600
		}
		invalid['qemu_alive_before_capture'] = true
		validate_row(invalid) or { rejects++ }
	}
	require(observation('')['outcome']!.str() == 'harness_failure', 'missing-BEGIN branch')!
	require(observation('APK-SUITE-BEGIN id=google-maps x ')['outcome']!.str() == 'startup_timeout', 'missing-READY branch')!
	require(rejects == 11, 'negative case accepted')!
	println('MAPS285 COMPLETED CHECK SELF-TEST PASS valid typed inventory + 11 negatives')
}

fn main() {
	$if prod {
		eprintln('assertions must remain enabled')
		exit(2)
	}
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len != 4 || os.args[1] != 'check' {
		eprintln('usage: maps285-check --self-test | check ROOT MANIFEST_SHA256')
		exit(2)
	}
	check(os.args[2], os.args[3]) or {
		eprintln(err)
		exit(1)
	}
}
