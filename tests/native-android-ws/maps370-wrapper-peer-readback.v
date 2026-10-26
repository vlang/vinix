// SPDX-License-Identifier: GPL-2.0-or-later
// Retain independent original290 readbacks of the Maps370 wrapper receipts.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const checker = repo + '/build/android-maps/build-bundle-check290'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'

fn hash(path string) !string {
	assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn run() ! {
	assert os.args.len == 3 && os.args[1] in ['prepare', 'check'],
		'usage: maps370-wrapper-peer-readback prepare|check MANIFEST_SHA'
	assert os.getwd() == repo && os.real_path(state) == state
	stage, pin := os.args[1], os.args[2]
	assert pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
	root := state + '/maps370-' + stage + '-receipt-2026-10-26'
	prefix := state + '/maps370-' + stage + '-receipt-peer-readback-2026-10-26'
	assert os.real_path(root) == root && !os.is_link(root)
	for suffix in ['.json', '-command.json', '.log', '-recorder.v', '-recorder'] {
		assert !os.exists(prefix + suffix) && !os.is_link(prefix + suffix), 'fresh adjacent receipt required'
	}
	assert hash(checker)! == checker_pin && hash(root + '/sha256.json')! == pin
	source_pin, binary_pin := hash(@FILE)!, hash(os.executable())!
	os.cp(@FILE, prefix + '-recorder.v')!
	os.cp(os.executable(), prefix + '-recorder')!
	argv := [checker, root, pin, prefix + '.json']
	started := time.utc().str()
	result := os.exec(argv)
	os.write_file(prefix + '.log', result.output)!
	checker_after := hash(checker) or { 'unreadable: ' + err.msg() }
	manifest_after := hash(root + '/sha256.json') or { 'unreadable: ' + err.msg() }
	os.write_file(prefix + '-command.json', json2.encode({
		'argv': json2.Any(argv)
		'working_directory': json2.Any(repo)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(result.exit_code)
		'checker_sha256_before': json2.Any(checker_pin)
		'checker_sha256_after': json2.Any(checker_after)
		'manifest_sha256_before': json2.Any(pin)
		'manifest_sha256_after': json2.Any(manifest_after)
		'stdout_stderr_sha256': json2.Any(hash(prefix + '.log')!)
		'recorder_source_sha256': json2.Any(source_pin)
		'recorder_binary_sha256': json2.Any(binary_pin)
		'retained_recorder_source_sha256': json2.Any(hash(prefix + '-recorder.v')!)
		'retained_recorder_binary_sha256': json2.Any(hash(prefix + '-recorder')!)
	}, prettify: true) + '\n')!
	assert result.exit_code == 0, result.output
	assert checker_after == checker_pin && manifest_after == pin
	assert hash(@FILE)! == source_pin && hash(os.executable())! == binary_pin
	assert hash(prefix + '-recorder.v')! == source_pin && hash(prefix + '-recorder')! == binary_pin
	receipt := object(prefix + '.json')!
	assert receipt['argv']!.as_array().map(it.str()) == argv
	assert receipt['root']!.str() == root && receipt['manifest_sha256']!.str() == pin
	assert receipt['checker_sha256']!.str() == checker_pin && receipt['exit_code']!.int() == 0
	assert receipt['exact_file_set']!.bool() && receipt['every_file_hash_matches']!.bool()
	assert receipt['files_checked']!.int() == 9
	println('MAPS370-WRAPPER-PEER-PASS stage=' + stage + ' files=9 receipt_sha256=' + hash(prefix + '.json')!
		+ ' command_sha256=' + hash(prefix + '-command.json')!)
	print(result.output)
}

fn main() {
	$if prod { panic('assertions required') }
	run() or { eprintln(err); exit(1) }
}
