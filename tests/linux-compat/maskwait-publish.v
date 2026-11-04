// SPDX-License-Identifier: GPL-2.0-or-later
// Publish immutable execution artifacts without duplicating their data blocks.
// The original area and all selected runs must have stopped before publication.
module main

import crypto.sha256
import json2
import os

fn copy_tree(source string, destination string) ! {
	if os.is_link(source) { return error('Restore regular artifact first: ' + source) }
	if os.is_dir(source) {
		os.mkdir_all(destination)!
		for name in os.ls(source)! { copy_tree(source + '/' + name, destination + '/' + name)! }
	} else if os.is_file(source) {
		os.mkdir_all(os.dir(destination))!
		os.link(source, destination)!
	}
}
fn main() {
	if os.args.len != 4 { panic('Usage: maskwait-publish AREA REPOSITORY FRESH-OUTPUT') }
	area, repo, output := os.real_path(os.args[1]), os.real_path(os.args[2]), os.args[3]
	if os.exists(output) || output.starts_with(area + '/') { panic('Fresh external output required') }
	os.mkdir_all(output)!
	selected := {
		'compile-arm-r2': 'compile-arm-r1', 'compile-x86-r2': 'compile-x86-r1',
		'reference-arm-r2': 'reference-arm', 'reference-x86-r2': 'reference-x86',
		'native-arm-r2': 'native-arm', 'native-x86-r2': 'native-x86', 'baseline-x86-r2': 'baseline-x86',
		'maintained-arm-r2': 'maintained-arm', 'maintained-x86-r2': 'maintained-x86',
		'build-arm': 'build-arm', 'build-base-x86': 'build-base-x86', 'build-fixed-x86': 'build-fixed-x86'
	}
	for name in os.ls(area)! {
		if name in ['kernel-arm', 'kernel-x86'] { continue }
		copy_tree(area + '/' + name, output + '/' + if name in selected { selected[name] } else { 'attempts/' + name })!
	}
	for name in ['kernel/userland/linux_signal_amd64.v', 'tests/linux-compat/maskwaitfixture/core.v',
		'tests/linux-compat/maskwaitreferenceinit/core.v', 'tests/linux-compat/maskwait-host.v',
		'tests/linux-compat/maskwait-reference.v', 'tests/linux-compat/maskwait-cc.v',
		'tests/linux-compat/maskwait-evidence.v', 'tests/linux-compat/maskwait-publish.v', 'tests/linux-compat/run.v'] {
		os.mkdir_all(os.dir(output + '/source/' + name))!
		// Working source may still be edited: freeze bytes instead of linking it.
		os.cp(repo + '/' + name, output + '/source/' + name)!
	}
	mut manifest := map[string]string{}
	mut paths := os.walk_ext(output, ''); paths.sort()
	for path in paths { if os.is_file(path) { manifest[path[output.len + 1..]] = sha256.sum(os.read_bytes(path)!).hex() } }
	os.write_file(output + '/manifest.json', json2.encode(manifest, prettify: true) + '\n')!
	println('Published ' + manifest.len.str() + ' files')
	println('manifest SHA-256: ' + sha256.sum(os.read_bytes(output + '/manifest.json')!).hex())
}
