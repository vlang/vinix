// SPDX-License-Identifier: GPL-2.0-or-later
// Bound the next JNI producer's live-source delta against the deployed snapshot.
module main

import crypto.sha256
import json2
import os

const baseline = '/Users/alex/.local/state/vinix/android/current-native-build-2026-10-27-startup-r1'
const baseline_seal = 'a62bf4a8a4ef8d1c000f82395ec64b145c9c4d6df25f12077f75d96d341e0a20'
const repository = '/Users/alex/code/vinix'

fn digest(path string) !string {
	if os.real_path(path) != path || os.lstat(path)!.get_filetype() != .regular
		|| os.lstat(path)!.size > 8 * 1024 * 1024 { return error('canonical bounded regular source required: ' + path) }
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn run(destination string) ! {
	if digest(baseline + '/sha256.json')! != baseline_seal { return error('deployed native manifest differs') }
	files := json2.decode[map[string]string](os.read_file(baseline + '/sha256.json')!)!
	origins_path := 'native/source-origins.json'
	if digest(baseline + '/' + origins_path)! != files[origins_path]! { return error('sealed source origins differ') }
	origins := json2.decode[map[string]string](os.read_file(baseline + '/' + origins_path)!)!
	mut observed := map[string]bool{}
	mut changes := map[string]map[string]string{}
	for name, live in origins {
		if os.file_name(live) != name || os.dir(live) !in [repository + '/build-support/android/atlframework', repository + '/build-support/android/nativews'] {
			return error('unexpected deployed source origin: ' + live)
		}
		old := files['native/atlframework/' + name]!
		if digest(baseline + '/native/atlframework/' + name)! != old { return error('deployed source differs: ' + name) }
		current := digest(live)!
		observed[live] = true
		if current != old {
			if live !in [repository + '/build-support/android/nativews/diagnostics.v', repository + '/build-support/android/nativews/ws_views.v'] {
				return error('unreviewed native source delta: ' + live)
			}
			changes[live] = {'deployed_sha256': old, 'current_sha256': current}
		}
	}
	for directory in ['atlframework', 'nativews'] {
		for name in os.ls(repository + '/build-support/android/' + directory)!.filter(it.ends_with('.v')) {
			if repository + '/build-support/android/' + directory + '/' + name !in observed { return error('new unreviewed native source: ' + name) }
		}
	}
	spec := 'native/bindings.txt'
	if digest(baseline + '/' + spec)! != files[spec]!
		|| digest(repository + '/build-support/android/nativews/bindings.txt')! != files[spec]! { return error('JNI binding specification changed') }
	if os.exists(destination) || os.is_link(destination) || !destination.starts_with('/Users/alex/.local/state/vinix/android/') {
		return error('fresh external report required')
	}
	os.write_file(destination, json2.encode({
		'kind': json2.Any('vinix-maps-native-source-delta-v1'),
		'baseline': json2.Any(baseline), 'baseline_sha256': json2.Any(baseline_seal),
		'checked_source_count': json2.Any(observed.len),
		'changes': json2.decode[json2.Any](json2.encode(changes))!,
		'bindings_sha256': json2.Any(files[spec]!),
	}, prettify: true) + '\n')!
	println('MAPS-NATIVE-SOURCE-DELTA PASS sources=' + observed.len.str() + ' changes=' + changes.len.str() + ' report=' + destination)
}

fn main() {
	if os.args.len != 2 { eprintln('usage: maps-native-source-delta FRESH_EXTERNAL_REPORT'); exit(2) }
	run(os.args[1]) or { eprintln(err); exit(1) }
}
