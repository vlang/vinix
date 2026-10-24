// SPDX-License-Identifier: GPL-2.0-or-later
// Bind the already-built276 native snapshot to the immutable274 reference.
module main
import crypto.sha256
import json2
import os
import time

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	old := 'build/android-maps/compound274'
	base := 'build/android-maps/compound276'
	archive := '/Users/alex/.local/state/vinix/android/compound274-2026-10-24'
	pin := '78d8d38f8e855e42cceed3054944641a622d5ceecda1cb5e826953d6bf5b9e22'
	assert hash(archive + '/failed-attempt-sha256.json')! == pin
	mut pairs := map[string]string{}
	for kind in ['framework', 'native'] {
		for name in ['sources.json', 'exact-sources.json.gz'] {
			path := kind + '/' + name
			pairs[path] = hash(old + '/' + path)!
			assert pairs[path]! == hash(archive + '/prelaunch/' + path)!, path
		}
	}
	pairs['native/bindings.txt'] = hash(old + '/native/bindings.txt')!
	assert pairs['native/bindings.txt']! == hash(archive + '/prelaunch/native/bindings.txt')!
	assert hash(base + '/native/bindings.txt')! == pairs['native/bindings.txt']!
	assert hash(base + '/native/atlframework/graphics.v')! == 'cb05db13887d7a019cee731b0994ce1b54b2f0619f67c2eae0fa09aeabec9739'
	receipt := {'archived274_manifest_sha256': json2.Any(pin), 'verified_utc': json2.Any(time.utc().str()), 'source_sha256': json2.Any(hash(@FILE)!), 'local274_equal_archived274': json2.decode[json2.Any](json2.encode(pairs))!}
	assert !os.exists(base + '/baseline-provenance.json')
	os.cp(@FILE, base + '/baseline-provenance.v')!
	os.write_file(base + '/baseline-provenance.json', json2.encode(receipt, prettify: true) + '\n')!
	println('CANVAS-CENTER276 BASELINE SOURCE PROVENANCE PASS; no rebuild needed')
}
