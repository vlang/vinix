// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the exact consumed cleanup tool before adding its production guard.
module main

import crypto.sha256
import json2
import os
import time

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn inventory(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		info := os.lstat(path)!
		match info.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory {
				entries[key] = 'directory'
				inventory(root, key, mut entries)!
			}
			.symbolic_link { entries[key] = 'symlink:' + os.readlink(path)! }
			else { return error('unexpected supplemental artifact: ' + path) }
		}
		entries['@mode:' + key] = (info.mode & 0o7777).str()
	}
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	assert os.args.len == 1
	root := '/Users/alex/.local/state/vinix/android/maps300-304-working-cleanup-2026-10-25'
	consumed := root + '/consumed-tooling'
	manifest := root + '/preservation-sha256.json'
	result := root + '/preservation-readback.json'
	for fresh in [consumed, manifest, result] {
		assert !os.exists(fresh) && !os.is_link(fresh), 'fresh supplemental preservation required'
	}
	receipt := json2.decode[map[string]json2.Any](os.read_file(root + '/receipt.json')!)!
	source := 'tests/native-android-ws/maps-working-cleanup.v'
	binary := 'build/android-maps/maps-working-cleanup'
	assert receipt['source_sha256']!.str() == 'b3414412a7665af45c1ae8eaf736ec5c05303ac428ee14f3f427ff3e5c085ba4'
	assert receipt['binary_sha256']!.str() == '23f1415777355bf6faf83e740a1632276c36916823b0ff0a8990e74c1e50864e'
	assert hash(source)! == receipt['source_sha256']!.str()
	assert hash(binary)! == receipt['binary_sha256']!.str()
	os.mkdir(consumed)!
	for input in [source, binary] {
		output := consumed + '/' + os.base(input)
		os.cp(input, output)!
		assert hash(output)! == hash(input)!
	}
	os.cp('tests/native-android-ws/maps-working-cleanup-preserve.v', consumed + '/preserve.v')!
	os.cp(os.executable(), consumed + '/preserve')!
	mut expected := map[string]string{}
	inventory(root, '', mut expected)!
	os.write_file(manifest, json2.encode(expected, prettify: true) + '\n')!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	actual.delete('preservation-sha256.json')
	actual.delete('@mode:preservation-sha256.json')
	assert actual.len == expected.len
	for key, value in expected {
		assert actual[key]! == value
	}
	os.write_file(result, json2.encode({
		'completed_utc':           json2.Any(time.utc().str())
		'manifest_sha256':         json2.Any(hash(manifest)!)
		'typed_entries':           json2.Any(actual.len)
		'original_receipt_sha256': json2.Any(hash(root + '/receipt.json')!)
		'original_source_sha256':  receipt['source_sha256']!
		'original_binary_sha256':  receipt['binary_sha256']!
	}, prettify: true) + '\n')!
	println('MAPS-CLEANUP-PRESERVATION-PASS manifest=' + hash(manifest)! + ' typed=' + actual.len.str())
}
