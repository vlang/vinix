// SPDX-License-Identifier: GPL-2.0-or-later
// Compare literal diagnostics in two sealed Maps runs without changing verdicts.
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn inspect(root string, pin string, attempt string) !map[string]json2.Any {
	assert digest(root + '/sha256.json')! == pin
	manifest := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	serial_key := 'results/attempt' + attempt + '/google-maps/serial.log'
	results_key := 'results/attempt' + attempt + '/results.json'
	for key in [serial_key, results_key] {
		assert digest(root + '/' + key)! == manifest[key]!
	}
	lines := os.read_file(root + '/' + serial_key)!.split_into_lines()
	patterns := {
		'stub_op': 'STUB: op'
		'path_native_op': 'android.graphics.Path.native_op'
		'unsatisfied_link': 'UnsatisfiedLinkError'
		'fatal_exception': 'FATAL EXCEPTION'
		'runtime_aborting': 'Runtime aborting'
		'jni_detected_error': 'JNI DETECTED ERROR'
		'out_of_memory': 'OutOfMemoryError'
		'sigsegv': 'SIGSEGV'
		'process_exit': 'APK-SUITE-EXIT id='
		'android_ws_fail': 'ANDROID-WS-FAIL'
		'suite_dependency_fail': 'APK-SUITE-DEPENDENCY-FAIL'
		'ws_dependency_fail': 'ANDROID-WS-DEPENDENCY-FAIL'
		'ws_process_fail': 'ANDROID-WS-PROCESS-FAIL'
		'no_class_def': 'NoClassDefFoundError'
		'no_such_method': 'NoSuchMethodError'
		'class_not_found': 'ClassNotFoundException'
		'no_such_field': 'NoSuchFieldError'
	}
	mut counts := map[string]int{}
	for name, pattern in patterns { counts[name] = lines.filter(it.contains(pattern)).len }
	mut pairs := 0
	for i, line in lines {
		if i > 0 && line.trim_space() == 'STUB: op' && lines[i - 1].trim_space() == 'Path' {
			pairs++
		}
	}
	counts['path_op_warning_pairs'] = pairs
	return {
		'root': json2.Any(os.abs_path(root))
		'manifest_sha256': json2.Any(pin)
		'serial_sha256': json2.Any(manifest[serial_key]!)
		'results_sha256': json2.Any(manifest[results_key]!)
		'counts': json2.decode[json2.Any](json2.encode(counts))!
		'patterns': json2.decode[json2.Any](json2.encode(patterns))!
		'raw_results': json2.decode[json2.Any](os.read_file(root + '/' + results_key)!)!
	}
}

fn main() {
	if os.args.len != 8 {
		panic('usage: audit BEFORE_ROOT BEFORE_MANIFEST BEFORE_ATTEMPT AFTER_ROOT AFTER_MANIFEST AFTER_ATTEMPT FRESH_OUTPUT')
	}
	output := os.abs_path(os.args[7])
	if os.exists(output) || os.is_link(output) { panic('fresh output required') }
	before := inspect(os.args[1], os.args[2], os.args[3])!
	after := inspect(os.args[4], os.args[5], os.args[6])!
	os.mkdir_all(output)!
	os.cp(@FILE, output + '/audit.v.txt')!
	os.cp(os.executable(), output + '/audit')!
	os.write_file(output + '/argv.txt', os.args.join('\n') + '\n')!
	os.write_file(output + '/definition.txt', 'Counts are final sealed raw serial lines containing each case-sensitive literal. path_op_warning_pairs counts adjacent trimmed lines Path then STUB: op. Raw classifiers are retained unchanged. This audit authenticates serial/results only; the run bundle requires its separate complete readback.\n')!
	os.write_file(output + '/before.json', json2.encode(before, prettify: true) + '\n')!
	os.write_file(output + '/after.json', json2.encode(after, prettify: true) + '\n')!
	mut manifest := map[string]string{}
	for name in os.ls(output)! { manifest[name] = digest(output + '/' + name)! }
	os.write_file(output + '/sha256.json', json2.encode(manifest, prettify: true) + '\n')!
	println('MAPS-PATH-OP-AUDIT-PASS sha256=' + digest(output + '/sha256.json')!)
}
