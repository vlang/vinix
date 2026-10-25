// SPDX-License-Identifier: GPL-2.0-or-later
// Independently check Maps299 derivation and its complete recorded V build closure.
// Run from the repository root with assertions enabled; writes no evidence.
module main

import crypto.sha256
import json2
import os

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 1, 'usage: maps299-build-check'
	build := '/Users/alex/.local/state/vinix/android/maps299-run-build-c-2026-10-25'
	work := '/Users/alex/.local/state/vinix/android/maps299-generation-2026-10-25'
	record := json2.decode[map[string]json2.Any](os.read_file(build + '/build-receipt.json')!)!
	assert record['exit_code']!.int() == 0
	assert record['VROOT']!.str() == '/Users/alex/code/v'
	assert hash(build + '/closure-before.json')! == record['closure_before_sha256']!.str()
	assert hash(build + '/closure-after.json')! == record['closure_after_sha256']!.str()
	assert hash(build + '/closure-v-files.txt')! == record['closure_listing_sha256']!.str()
	before := json2.decode[map[string]string](os.read_file(build + '/closure-before.json')!)!
	after := json2.decode[map[string]string](os.read_file(build + '/closure-after.json')!)!
	assert before == after
	mut listed := map[string]bool{}
	for path in os.read_lines(build + '/closure-v-files.txt')!.filter(it.ends_with('.v')) {
		assert path !in listed
		listed[path] = true
	}
	assert listed.len == before.len
	for path, pin in before {
		assert path in listed
		assert hash(path)! == pin, path
		assert hash(build + '/closure/' + path.trim_left('/'))! == pin, path
	}
	assert before.len == 272
	compiler := 'build/android-maps/queue284-tools/v_old276'
	assert hash(compiler)! == '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
	assert hash(build + '/v_old276')! == hash(compiler)!
	assert record['compiler_sha256']!.str() == hash(compiler)!
	assert hash(record['cc_path']!.str())! == record['cc_sha256']!.str()
	assert hash(build + '/maps299-run')! == record['binary_sha256']!.str()
	assert hash('build/android-maps/maps299-run-recorded')! == record['binary_sha256']!.str()
	assert hash(work + '/maps299-run.v')! == record['source_sha256']!.str()
	assert hash(build + '/maps299-run.v')! == record['source_sha256']!.str()
	original := os.read_file('tests/native-android-ws/maps298-run.v')!
	assert sha256.sum(original.bytes()).hex() == '5d220b06590bc0823f12c6d5071dc60af51a9dc284a383afb77cb907c1f17ed1'
	mut derived := original
	for prefix in ['maps', 'attempt', 'suite', 'MAPS', 'validate_styled', 'fresh'] {
		derived = derived.replace(prefix + '298', prefix + '299')
	}
	derived = derived.replace("const source = 'tests/native-android-ws/maps299-run.v'", "const source = '" + work + "/maps299-run.v'")
	assert derived == os.read_file(work + '/maps299-run.v')!
	assert derived == os.read_file(build + '/generation/maps299-run.v')!
	assert original == os.read_file(build + '/generation/maps298-input.v')!
	assert os.read_file('tests/native-android-ws/maps299-generate.v')! == os.read_file(build + '/generation/generator.v')!
	derivation := json2.decode[map[string]json2.Any](os.read_file(build + '/generation/derivation.json')!)!
	assert derivation['original_sha256']!.str() == sha256.sum(original.bytes()).hex()
	assert derivation['generator_sha256']!.str() == hash('tests/native-android-ws/maps299-generate.v')!
	assert derivation['generated_sha256']!.str() == record['source_sha256']!.str()
	argv := record['argv']!.as_array().map(it.str())
	assert argv == [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', 'build/android-maps/maps299-run-recorded', work + '/maps299-run.v']
	println('MAPS299-INDEPENDENT-REVIEW-PASS dependencies=${before.len} source=' + record['source_sha256']!.str() + ' binary=' + record['binary_sha256']!.str())
}
