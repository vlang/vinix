// SPDX-License-Identifier: GPL-2.0-or-later
module venusbuild

import androidhost as ah

fn native_sources() !string {
	sources := call('builtins.list')!
	for relative in ['build-support/dota2/venus_query.v', 'build-support/dota2/venusbuild',
		'build-support/dota2/mesa-build.py', 'build-support/dota2/mesa_query.v',
		'build-support/dota2/mesabuild', 'build-support/dota2/androidhost',
		'build-support/dota2/boothost', 'build-support/dota2/packagestore', 'tools/packagestore',
		'tools/_package_store_native.py', 'build-support/native_host.py',
		'build-support/android/_boot_native.py', 'build-support/run-v-tool.sh',
		'build-support/find-v.sh'] {
		path := join(constant('REPO')!, relative)!
		append(sources, o(path))!
		if truth(method(path, 'is_dir', [], {})!)! {
			entries := iterator(call('sorted', o(method(path, 'rglob', [v(ah.Value('*'))], {})!))!)!
			for {
				entry := next(entries)!
				if entry.done { break }
				if truth(method(entry.value, 'is_file', [], {})!)! {
					append(sources, o(entry.value))!
				}
			}
		}
	}
	return sources
}

fn source_key(lavapipe string) !string {
	hashes := dictionary()!
	paths := iterator(native_sources()!)!
	for {
		path := next(paths)!
		if path.done { break }
		relative := call('str', o(method(path.value, 'relative_to', [o(constant('REPO')!)], {})!))!
		if truth(method(path.value, 'is_symlink', [], {})!)! {
			set_item(hashes, o(relative), o(call('os.readlink', o(path.value))!))!
		} else if truth(method(path.value, 'is_file', [], {})!)! {
			set_item(hashes, o(relative), o(method(lavapipe, 'digest', [o(path.value)], {})!))!
		}
	}
	return hashes
}
