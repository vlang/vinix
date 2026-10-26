// SPDX-License-Identifier: GPL-2.0-or-later
// Record the unchanged Maps370 runner's complete typed canonical readback.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/maps370-2026-10-26'
const output = state + '/maps370-report-peer-readback-2026-10-26'
const runner = repo + '/build/android-maps/maps370-run-recorded'
const source = state + '/maps370-generation-2026-10-26/maps370-run.v'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn inputs(manifest string) map[string]string {
	return {
		runner: 'd8fb503f68deb073e351d3a292b08e03b80aa181395647dc18bb20d231526330'
		source: '11ab2cd3ac79ec8c24810f127c4a163d267d998fc1ea03f60258ef9e33e84ac1'
		root + '/sha256.json': manifest
	}
}
fn qualify(manifest string) ! {
	for path, pin in inputs(manifest) {
		assert os.real_path(path) == path && !os.is_link(path)
		assert os.lstat(path)!.get_filetype() == .regular && hash(path)! == pin
	}
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2 && os.getwd() == repo, 'usage: maps370-completed-readback MANIFEST_SHA'
	manifest := os.args[1]
	assert manifest.len == 64 && manifest.bytes().all(it in '0123456789abcdef'.bytes())
	assert os.real_path(state) == state && os.real_path(root) == root
	assert !os.exists(output) && !os.is_link(output), 'fresh receipt directory required'
	qualify(manifest)!
	reader_source := hash(@FILE)!
	reader_binary := hash(os.executable())!
	os.mkdir(output)!
	os.cp(@FILE, output + '/reader.v')!
	os.cp(os.executable(), output + '/reader')!
	argv := [runner, 'verify', manifest]
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(output + '/stdout.log', r.output)!
	qualify(manifest)!
	assert hash(@FILE)! == reader_source && hash(os.executable())! == reader_binary
	assert hash(output + '/reader.v')! == reader_source && hash(output + '/reader')! == reader_binary
	status := r.exit_code == 0 && r.output.starts_with('MAPS370-COMPLETED-READBACK-PASS entries=')
	mut input_record := map[string]json2.Any{}
	for path, pin in inputs(manifest) { input_record[path] = json2.Any(pin) }
	os.write_file(output + '/receipt.json', json2.encode({
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'root': json2.Any(root)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(r.exit_code)
		'complete_readback_passed': json2.Any(status)
		'input_pins_before_and_after': json2.Any(input_record)
		'reader_source_sha256': json2.Any(reader_source)
		'reader_binary_sha256': json2.Any(reader_binary)
		'stdout_sha256': json2.Any(hash(output + '/stdout.log')!)
	}, prettify: true) + '\n')!
	print(r.output)
	assert status, 'original complete readback failed; actual status retained'
}
