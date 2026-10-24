// SPDX-License-Identifier: GPL-2.0-or-later
// An authentic pinned inventory must not make an incomplete bundle acceptable.
module main

import crypto.sha256
import json2
import os

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	$if prod {
		eprintln('Refusing -prod: this compiler removes assertions; use -cflags -O2.')
		exit(2)
	}
	if os.args.len != 5 { panic('usage: maps-runtime-negative BUNDLE CHECKER EXTERNAL_OUTPUT MANIFEST_SHA256') }
	bundle, checker, output, pinned := os.args[1], os.args[2], os.args[3], os.args[4]
	assert os.is_abs_path(output) && !output.starts_with(os.getwd() + '/')
	assert !os.exists(output), 'fresh external output required'
	assert hash(bundle + '/sha256.json')! == pinned
	os.mkdir_all(output + '/partial')!
	os.cp(bundle + '/sha256.json', output + '/partial/sha256.json')!
	result := os.exec([checker, 'check', output + '/partial', pinned])
	os.write_file(output + '/negative.log', result.output)!
	assert result.exit_code != 0, 'incomplete bundle unexpectedly accepted'
	assert result.output.contains('actual.len == expected.len'), 'rejected for an unexpected reason: ' + result.output
	os.cp(@FILE, output + '/maps-runtime-negative.v')!
	os.write_file(output + '/receipt.json', json2.encode({
		'bundle_manifest_sha256': pinned
		'checker_sha256': hash(checker)!
		'checker_source_sha256': hash(bundle + '/audit/maps-runtime-evidence.v')!
		'test_source_sha256': hash(@FILE)!
		'negative_log_sha256': hash(output + '/negative.log')!
		'exit_code': result.exit_code.str()
		'expected_failure': 'authentic pinned manifest, all execution evidence omitted'
	}, prettify: true) + '\n')!
	println('MAPS-RUNTIME-NEGATIVE PASS: authentic inventory alone rejected as incomplete evidence; exit=' + result.exit_code.str())
}
