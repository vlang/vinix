// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only complete bundle check. Receipt must be outside the sealed root.
module main

import crypto.sha256
import json2
import os
import time

fn hash(path string) !string {
	before_size := os.file_size(path)
	before_mtime := os.file_last_mod_unix(path)
	mut input := os.open(path)!
	defer { input.close() }
	mut state := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		state.write(buffer[..n])!
	}
	if before_size != os.file_size(path) || before_mtime != os.file_last_mod_unix(path) {
		return error('file metadata changed while hashing: ' + path)
	}
	return state.sum([]u8{}).hex()
}

fn inventory(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		if os.is_link(path) { return error('unexpected symlink: ' + key) }
		if os.is_dir(path) { inventory(root, key, mut entries)! }
		else if os.is_file(path) { entries[key] = hash(path)! }
		else { return error('unexpected non-regular entry: ' + key) }
	}
}

fn check() ! {
	if os.args.len != 4 { return error('usage: build-bundle-check ROOT MANIFEST_SHA256 RECEIPT') }
	root := os.real_path(os.args[1])
	pin := os.args[2]
	out := os.abs_path(os.args[3])
	if out == root || out.starts_with(root + '/') { return error('receipt must be outside sealed root') }
	if os.exists(out) { return error('receipt already exists') }
	if pin.len != 64 || !pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
		return error('invalid manifest pin')
	}
	started := time.utc().str()
	manifest := root + '/sha256.json'
	if hash(manifest)! != pin { return error('manifest pin mismatch') }
	expected := json2.decode[map[string]string](os.read_file(manifest)!)!
	if expected.len == 0 || 'sha256.json' in expected { return error('invalid bundle inventory') }
	for path, _ in expected {
		if path == '' || path.starts_with('/') || path.split('/').any(it in ['', '.', '..']) {
			return error('invalid relative inventory path: ' + path)
		}
	}
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	actual.delete('sha256.json')
	if expected.len != actual.len { return error('complete file count mismatch') }
	for path, expected_hash in expected {
		if path !in actual || actual[path]! != expected_hash { return error('missing or changed file: ' + path) }
	}
	if hash(manifest)! != pin { return error('manifest changed during check') }
	os.mkdir_all(os.dir(out))!
	os.write_file(out, json2.encode({
		'root': json2.Any(root)
		'manifest_sha256': json2.Any(pin)
		'files_checked': json2.Any(actual.len)
		'exact_file_set': json2.Any(true)
		'every_file_hash_matches': json2.Any(true)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'argv': json2.Any(os.args)
		'checker_sha256': json2.Any(hash(os.executable())!)
		'exit_code': json2.Any(0)
	}, prettify: true) + '\n')!
	println('BUILD-BUNDLE-COMPLETE-PASS files=${actual.len} manifest=${pin}')
}

fn main() {
	$if prod { eprintln('requires assertions; compile without -prod'); exit(2) }
	check() or { eprintln(err); exit(1) }
}
