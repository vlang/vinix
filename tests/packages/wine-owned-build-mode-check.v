// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import json2
import os
import tests.packages.wineoverlay

fn refusal(argv []string, log string, wanted string) ! {
	os.write_file(log + '.argv.json', json2.encode(argv))!
	hwhost.run_tool(argv, map[string]string{}, log, 60) or {
		if !os.read_file(log)!.contains(wanted) { return error('ownership mode refused at wrong gate: ' + log) }
		return
	}
	return error('ownership mode unexpectedly accepted: ' + log)
}
fn run() ! {
	if os.args.len != 5 { return error('usage: CHECK FRESH_OUTPUT BUILDER NATIVE_CONTROLLER OWNED_PREPARED') }
	work := os.abs_path(os.args[1]); builder := os.real_path(os.args[2]); native := os.real_path(os.args[3]); prepared := os.real_path(os.args[4])
	if os.exists(work) || os.is_link(work) { return error('fresh mode check output required') }
	os.mkdir_all(work)!
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), builder, native, prepared + '/owned-manager.json', prepared + '/outputs.json'] { inputs[path] = wineoverlay.digest(path)! }
	refusal([builder, 'aarch64', '/missing', work + '/producer', '/missing', '/missing', '/missing', '/missing', '/missing', '--local-qualification-only', '/missing', '--owned-manager'], work + '/arm-producer.log', 'owned Wine producer is qualified only for x86_64')!
	refusal([native, 'aarch64', work + '/arm', prepared, '/missing', '/missing', '/missing', '/missing', '/missing', '--owned-manager'], work + '/arm-native.log', 'owned native Wine qualification requires x86_64')!
	refusal([native, 'aarch64', work + '/arm-collection', prepared, '/missing', '/missing', '/missing', '/missing', '/missing', '--owned-manager', '--collection-probe'], work + '/arm-collection.log', 'owned native Wine qualification requires x86_64')!
	refusal([native, 'x86_64', work + '/unowned-collection', prepared, '/missing', '/missing', '/missing', '/missing', '/missing', '--collection-probe'], work + '/unowned-collection.log', 'usage: wine-native-check')!
	refusal([native, 'x86_64', work + '/mixed', prepared, '/missing', '/missing', '/missing', '/missing', '/missing'], work + '/mixed.log', 'ownership modes differ')!
	os.mkdir(work + '/unmarked')!
	refusal([native, 'x86_64', work + '/unmarked-run', work + '/unmarked', '/missing', '/missing', '/missing', '/missing', '/missing', '--owned-manager'], work + '/unmarked.log', 'ownership modes differ')!
	for directory in ['producer', 'arm', 'arm-collection', 'unowned-collection'] {
		if os.exists(work + '/' + directory) { return error('mode/architecture refusal created workload output') }
	}
	for directory in [work + '/mixed', work + '/unmarked-run'] {
		if os.exists(directory) && os.ls(directory)!.len != 0 { return error('mode refusal created signing/build output') }
	}
	for path, hash in inputs { if wineoverlay.digest(path)! != hash { return error('mode check input changed') } }
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	println('WINE OWNED BUILD MODE PASS architecture and mixed-mode refusals before workload/signing')
}
fn main() { run() or { eprintln(err); exit(1) } }
