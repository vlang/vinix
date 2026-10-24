// SPDX-License-Identifier: GPL-2.0-or-later
// Strict semantic check of the retained baseline270/fixed272 Path JNI pair.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const apk_pin = '6bf5727f53f9d14d2bb67d7f282598890437a79b2ef71d874fde13117d078f4b'
const jar_pin = '305f04316f617fa26ca84d74d8a1693f90a0a3ffdada0936f9bb18d3cc5a5f75'
const native_pin = '6e92d8d95ae6b0cddf082f34ed33209bf6d49e04463b3af8354b12bb1bf80989'
const old_jar_pin = 'b1364aa6d21f3293bef534a939cafa93bb4194e13deb9c0864bec7e9b18f9413'
const old_native_pin = 'ce78582105a8e2e29e29d0fa843769549d5fa4deba02067b41749643bb4b0c32'
const jar_target = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native_target = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const baseline_assertion = 'java.lang.AssertionError: Path fill: nested1 pixel=85 actual=-13408615 expected=0'
const optional_diagnostics = [
	'java.lang.NoSuchFieldError: no type "Lnge;" found and so no field "bB" could be found in class "Lorg/vinix/bootstrap/Main;" or its superclasses',
	'Caused by: java.lang.ClassNotFoundException: nge',
]
const pass_markers = [
	'BOOTSTRAP-PATH-FILL-RULES-PASS', 'BOOTSTRAP-PATH-CONTOURS-PASS',
	'BOOTSTRAP-PATH-FILL-STATE-PASS', 'BOOTSTRAP-PATH-FILL-PASS', 'BOOTSTRAP-READY',
]

fn require(value bool, message string) ! {
	if !value { return error(message) }
}

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

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn inventory(root string, relative string, mut result map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative.len == 0 { name } else { relative + '/' + name }
		if key in [jar_target, native_target] { continue }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.directory { result[key] = 'directory'; inventory(root, key, mut result)! }
			.regular { result[key] = hash(path)! }
			else { return error('unexpected staged entry: ' + key) }
		}
	}
}

fn validate_fixed(serial string, row map[string]json2.Any) ! {
	lines := serial.replace('\r', '').split_into_lines()
	for marker in pass_markers { require(lines.count(it == marker) == 1, 'missing/duplicate ' + marker)! }
	require(!serial.contains('AssertionError') && !serial.contains('ANDROID-WS-FAIL '), 'fixed guest failure')!
	for line in lines {
		if line.starts_with('java.lang.') || line.starts_with('Caused by:') {
			require(line in optional_diagnostics, 'unexpected fixed diagnostic: ' + line)!
		}
	}
	require(row['backend_ready']!.bool() && row['native_maps_observed']!.bool(), 'fixed backend absent')!
	require(row['launcher_entered']!.bool() && row['qemu_alive_before_capture']!.bool(), 'fixed launcher/VM absent')!
	require(!row['process_exited']!.bool() && row['observation_elapsed_seconds']!.int() == 30, 'fixed observation incomplete')!
	require(row['functional_passed']! is json2.Null, 'raw functional result changed')!
	failures := row['failure_markers']!.as_array().map(it.str())
	require(failures.all(it in optional_diagnostics), 'unexpected fixed classifier failure')!
	actual_optional := optional_diagnostics.filter(it in lines)
	require(failures == actual_optional, 'fixed classifier/serial diagnostics differ')!
	expected_outcome := if failures.len == 0 { 'window_observed' } else { 'startup_failed' }
	require(row['outcome']!.str() == expected_outcome, 'fixed raw classification changed')!
}

fn validate_baseline(serial string, row map[string]json2.Any) ! {
	lines := serial.replace('\r', '').split_into_lines()
	require(lines.count(it == baseline_assertion) == 1, 'baseline assertion differs')!
	for line in lines {
		if line.starts_with('java.lang.') || line.starts_with('Caused by:') {
			require(line == baseline_assertion, 'unexpected baseline diagnostic: ' + line)!
		}
	}
	require(!serial.contains('BOOTSTRAP-PATH-') && row['process_exited']!.bool(), 'baseline unexpectedly passed')!
	require(row['native_maps_observed']!.bool() && row['launcher_entered']!.bool(), 'baseline did not reach JNI')!
	require(row['outcome']!.str() == 'startup_failed' && row['functional_passed']! is json2.Null, 'baseline raw classification changed')!
	require(row['failure_markers']!.as_array().map(it.str()) == ['ANDROID-WS-FAIL start activity', 'APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true'], 'unexpected baseline classifier failures')!
}

fn verify_build(original string, mut pins map[string]string) ! {
	for label, output in {
		'build-framework-compiler': 'build-framework'
		'build-framework': 'framework/api-impl.jar'
		'generate-native': 'native/android-native.c'
		'build-native': 'native/libvinix-android-native.so'
		'fixture-compiler': 'fixture-generator'
		'fixture': 'apk/probe.apk'
	} {
		before := object(original + '/' + label + '-before.json')!
		after := object(original + '/' + label + '-receipt.json')!
		require(after['exit_code']!.int() == 0 && after['completed_utc']!.str().len > 0, 'failed build ' + label)!
		require(json2.encode(before['argv']!) == json2.encode(after['argv']!), 'build argv changed ' + label)!
		require(before['started_utc']!.str() == after['started_utc']!.str(), 'build start changed ' + label)!
		require(after['output_sha256']!.str() == hash(original + '/' + output)!, 'build output changed ' + label)!
		pins['build/' + label] = hash(original + '/' + label + '-receipt.json')!
	}
	for name, digest in {'framework/api-impl.jar': jar_pin, 'native/libvinix-android-native.so': native_pin, 'apk/probe.apk': apk_pin} {
		require(hash(original + '/' + name)! == digest, 'artifact pin ' + name)!
		pins[name] = digest
	}
}

fn check(pair string, original string, metadata string, output string) ! {
	mut pins := map[string]string{}
	verify_build(original, mut pins)!
	compile := object(metadata + '/compile-receipt.json')!
	require(compile['exit_code']!.int() == 0 && compile['completed_utc']!.str().len > 0, 'retry suite compile failed')!
	require(compile['source_sha256']!.str() == hash(pair + '/suite.v')!, 'retry suite source changed')!
	require(compile['output_sha256']!.str() == hash(pair + '/suite')!, 'retry suite changed')!
	require(compile['original_suite_sha256']!.str() == hash(original + '/source/suite.v')!, 'original suite changed')!
	old_suite := os.read_file(original + '/source/suite.v')!
	old := "suite_clone_tree(native + '/' + provider, runtime + '/usr/lib/art/native-ws/' + provider)!"
	new := "suite_clone_tree(native + '/' + provider, runtime + '/usr/lib/art/native-ws')!"
	require(old_suite.count(old) == 1 && os.read_file(pair + '/suite.v')! == old_suite.replace(old, new), 'retry suite scope differs')!
	mut common := map[string]string{}
	mut summaries := map[string]json2.Any{}
	for mode in ['baseline', 'fixed'] {
		config := object(pair + '/' + mode + '.json')!
		receipt := object(metadata + '/run-' + mode + '-receipt.json')!
		before := object(metadata + '/run-' + mode + '-before.json')!
		require(receipt['exit_code']!.int() == 0 && receipt['completed_utc']!.str().len > 0, 'suite did not complete ' + mode)!
		for field in ['argv', 'started_utc', 'suite_sha256', 'config_sha256'] {
			require(json2.encode(before[field]!) == json2.encode(receipt[field]!), 'run receipt changed ' + field)!
		}
		require(receipt['suite_sha256']!.str() == hash(pair + '/suite')!, 'suite receipt pin')!
		require(receipt['config_sha256']!.str() == hash(pair + '/' + mode + '.json')!, 'config receipt pin')!
		require(config['output']!.str().ends_with('/compound272-staging2/run-' + mode), 'unexpected output identity')!
		app := config['applications']!.as_array()[0].as_map()
		require(config['applications']!.as_array().len == 1 && app['startup_seconds']!.int() == 30, 'unexpected application settings')!
		require(app['apk']!.str().ends_with('/compound272/apk/probe.apk'), 'unexpected APK source')!
		rows := json2.decode[[]map[string]json2.Any](os.read_file(pair + '/run-' + mode + '/results.json')!)!
		require(rows.len == 1, 'unexpected row count')!
		row := rows[0]
		require(row['container_sha256']!.str() == apk_pin, 'pair uses different APK')!
		metadata_row := row['metadata']!.as_map()
		require(metadata_row['apk_sha256']!.str() == apk_pin && metadata_row['signature_verification']!.str().contains('\nVerifies\n'), 'APK signature/pin absent')!
		case_dir := pair + '/run-' + mode + '/bootstrap-fixture'
		require(row['screenshot_sha256']!.str() == hash(case_dir + '/application.png')!, 'screenshot hash differs')!
		serial := gzip.decompress(os.read_bytes(case_dir + '/serial.log.gz')!)!.bytestr()
		require(row['serial_sha256']!.str() == sha256.sum(serial.bytes()).hex(), 'serial hash differs')!
		require(serial == os.read_file(case_dir + '/serial.log')!, 'compressed serial differs')!
		if mode == 'fixed' { validate_fixed(serial, row)! } else { validate_baseline(serial, row)! }
		module := pair + '/run-' + mode + '/module'
		require(hash(module + '/' + jar_target)! == if mode == 'fixed' { jar_pin } else { old_jar_pin }, 'staged JAR mismatch')!
		require(hash(module + '/' + native_target)! == if mode == 'fixed' { native_pin } else { old_native_pin }, 'staged native mismatch')!
		mut staged := map[string]string{}
		inventory(module, '', mut staged)!
		if mode == 'baseline' { common = staged.clone() } else { require(common == staged, 'staged common inventory/bytes differ')! }
		pins[mode + '/serial.log.gz'] = hash(case_dir + '/serial.log.gz')!
		pins[mode + '/results.json'] = hash(pair + '/run-' + mode + '/results.json')!
		pins[mode + '/config.json'] = hash(pair + '/' + mode + '.json')!
		pins[mode + '/run-receipt.json'] = hash(metadata + '/run-' + mode + '-receipt.json')!
		summaries[mode] = json2.Any({'raw_outcome': row['outcome']!, 'functional_passed': row['functional_passed']!, 'process_exited': row['process_exited']!, 'observation_seconds': row['observation_elapsed_seconds']!, 'failure_markers': row['failure_markers']!})
	}
	pins['checker_source'] = hash(@FILE)!
	pins['checker_binary'] = hash(os.executable())!
	pins['suite-compile-receipt.json'] = hash(metadata + '/compile-receipt.json')!
	os.write_file(output, json2.encode({'checked_utc': json2.Any(time.utc().str()), 'semantic_passed': json2.Any(true), 'pair_root': json2.Any(pair), 'original_build_root': json2.Any(original), 'metadata_root': json2.Any(metadata), 'common_staged_entry_count': json2.Any(common.len), 'rows': json2.Any(summaries), 'pins': json2.decode[json2.Any](json2.encode(pins))!, 'scope': json2.Any('Path JNI assertions, original raw classifications, build/run output pins, exact common staged inventory. No claim of a full retained-bundle or firmware-media audit.')}, prettify: true) + '\n')!
	println('PATH272-JNI-CHECK-PASS')
}

fn self_test() ! {
	serial := pass_markers.join('\n') + '\n'
	row := {'backend_ready': json2.Any(true), 'native_maps_observed': json2.Any(true), 'launcher_entered': json2.Any(true), 'qemu_alive_before_capture': json2.Any(true), 'process_exited': json2.Any(false), 'observation_elapsed_seconds': json2.Any(30), 'functional_passed': json2.Any(json2.Null{}), 'failure_markers': json2.Any([]json2.Any{}), 'outcome': json2.Any('window_observed')}
	validate_fixed(serial, row)!
	for bad_serial in [serial.replace(pass_markers[0], ''), serial + pass_markers[0] + '\n', serial + 'java.lang.LinkageError: changed JNI\n', serial + 'ANDROID-WS-FAIL start activity\n'] {
		mut rejected := false
		validate_fixed(bad_serial, row) or { rejected = true }
		require(rejected, 'negative serial accepted')!
	}
	for field in ['backend_ready', 'process_exited', 'observation_elapsed_seconds'] {
		mut bad := row.clone()
		bad[field] = if field == 'observation_elapsed_seconds' { json2.Any(29) } else { json2.Any(field == 'process_exited') }
		mut rejected := false
		validate_fixed(serial, bad) or { rejected = true }
		require(rejected, 'negative row accepted: ' + field)!
	}
	println('PATH272-JNI-CHECK-SELFTEST-PASS seven negatives')
}

fn main() {
	$if prod { panic('assertions required') }
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test()!; return }
	assert os.args.len == 5, 'path-fill-check <retained-pair-root> <original272-root> <retry-receipts-root> <output.json>'
	check(os.args[1], os.args[2], os.args[3], os.args[4])!
}
