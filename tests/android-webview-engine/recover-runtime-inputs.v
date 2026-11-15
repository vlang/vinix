// SPDX-License-Identifier: GPL-2.0-or-later
// Recover only the API auditor's actual deployed libraries from stopped media.
module main

import json2
import mapsaccountstage
import modulestream
import os

fn main() {
	if os.args.len != 3 { panic('usage: recover-runtime-inputs STOPPED_PARENT_VM FRESH_EXTERNAL_ROOT') }
	parent, root := os.real_path(os.args[1]), os.abs_path(os.args[2])
	if os.exists(root) || os.is_link(root) || root.starts_with(os.real_path(os.getwd()) + '/') {
		panic('fresh external output required')
	}
	metadata := parent + '/payload/opt/vinix-maps-account/build.json'
	before := mapsaccountstage.hash(metadata)!
	deployment := json2.decode[map[string]json2.Any](os.read_file(metadata)!)!
	inputs := deployment['inputs_sha256']!.as_map()
	libraries := ['libwebkitgtk-6.0.so.4', 'libgtk-4.so.1', 'libgobject-2.0.so.0',
		'libglib-2.0.so.0', 'libsoup-3.0.so.0', 'libX11.so.6', 'libXtst.so.6', 'libsqlite3.so.0']
	mut paths := libraries.map('opt/vinix-google-browser/usr/lib/' + it)
	paths << ['opt/vinix-google-browser/lib/ld-musl-aarch64.so.1',
		'opt/vinix-google-browser/lib/libc.musl-aarch64.so.1', 'opt/vinix-google-browser/lib/libc.so']
	os.mkdir_all(root)!
	os.mkdir_all(root + '/empty')!
	status := modulestream.extract_members(parent + '/boot.img', 'maps-account.tar', root, paths)!
	if status.producer != 0 || status.consumer != 0 { panic('deployed runtime extraction failed') }
	mut hashes := map[string]json2.Any{}
	for path in paths {
		actual := root + '/' + path
		if os.lstat(actual)!.get_filetype() != .regular { panic('regular deployed library required') }
		sum := mapsaccountstage.hash(actual)!
		if sum != inputs['/' + path]!.str() { panic('deployed runtime library digest differs: ' + path) }
		hashes[path] = json2.Any(sum)
	}
	if mapsaccountstage.hash(metadata)! != before { panic('deployment metadata changed during recovery') }
	os.write_file(root + '/recovery.json', json2.encode({
		'parent': json2.Any(parent), 'deployment_sha256': json2.Any(before),
		'libraries': json2.Any(hashes)
	}, prettify: true))!
	println('WEBVIEW-RUNTIME-INPUTS-PASS libraries=8 musl-files=3 root=' + root + '/opt/vinix-google-browser')
}
