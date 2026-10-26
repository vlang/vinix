// SPDX-License-Identifier: GPL-2.0-or-later
// Record the unchanged Maps366 runner's complete typed canonical readback.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/maps366-2026-10-26'
const output = state + '/maps366-report-peer-readback-2026-10-26'
const runner = repo + '/build/android-maps/maps366-run-recorded'
const source = state + '/maps366-generation-2026-10-26/maps366-run.v'
const manifest_pin = '06275b99ad6cb5581800de65ed9604ac7677f7890f872cb41c7bce70a24552c0'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn inputs() map[string]string {
	return {
		runner: 'fdcc5aef72202c1cb62b394ab1db73167c771e08f2ed06445ad6b2a0f5b504cf'
		source: 'fa542ebfe4dd8cf644a5c57dd2349fb9775a3c299830f1aed1813cd4fcf3ee65'
		root + '/sha256.json': manifest_pin
	}
}
fn qualify() ! {
	for path, pin in inputs() {
		assert os.real_path(path) == path && !os.is_link(path)
		assert os.lstat(path)!.get_filetype() == .regular && hash(path)! == pin
	}
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 1 && os.getwd() == repo
	assert os.real_path(state) == state && os.real_path(root) == root
	assert !os.exists(output) && !os.is_link(output), 'fresh receipt directory required'
	qualify()!
	reader_source := hash(@FILE)!
	reader_binary := hash(os.executable())!
	os.mkdir(output)!
	os.cp(@FILE, output + '/reader.v')!
	os.cp(os.executable(), output + '/reader')!
	argv := [runner, 'verify', manifest_pin]
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(output + '/stdout.log', r.output)!
	qualify()!
	assert hash(@FILE)! == reader_source && hash(os.executable())! == reader_binary
	assert hash(output + '/reader.v')! == reader_source && hash(output + '/reader')! == reader_binary
	status := r.exit_code == 0 && r.output.starts_with('MAPS366-COMPLETED-READBACK-PASS entries=')
	mut input_record := map[string]json2.Any{}
	for path, pin in inputs() { input_record[path] = json2.Any(pin) }
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
