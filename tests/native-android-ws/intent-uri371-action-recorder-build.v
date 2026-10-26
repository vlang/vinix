// SPDX-License-Identifier: GPL-2.0-or-later
// Retain the exact compiler closure and actual build of the ART action recorder.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/intent-uri371-action-recorder-build-2026-10-26'
const baseline = state + '/intent-uri371-run-bootstrap-build-2026-10-26'
const source = '/Users/alex/code/vinix/tests/native-android-ws/intent-uri371-action-recorder.v'
const vroot = root + '/frozen/vroot'

fn hash(path string) !string {
	assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn record(label string, argv []string) !string {
	assert !os.exists(root + '/commands/' + label + '.json')
	pin := hash(argv[0])!
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', r.output)!
	os.write_file(root + '/commands/' + label + '.json', json2.encode({
		'argv': json2.Any(argv), 'executable_sha256': json2.Any(pin),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
		'exit_code': json2.Any(r.exit_code),
	}, prettify: true) + '\n')!
	assert r.exit_code == 0 && hash(argv[0])! == pin, r.output
	return r.output
}

fn closure(label string) !map[string]string {
	listing := record(label, [vroot + '/v', '-path', vroot + '/vlib', '-print-v-files',
		vroot + '/source/intent-uri371-action-recorder.v'])!
	mut pins := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		assert os.real_path(path) == path && path.starts_with(vroot + '/')
		pins[path] = hash(path)!
	}
	assert pins.len == 270
	os.write_file(root + '/' + label + '.json', json2.encode(pins, prettify: true) + '\n')!
	return pins
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2 && !os.exists(root) && !os.is_link(root)
	manifest_pin := os.args[1]
	assert manifest_pin.len == 64 && manifest_pin.bytes().all(it in '0123456789abcdef'.bytes())
	assert hash(baseline + '/sha256.json')! == manifest_pin
	compiler_pin := '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
	assert hash(baseline + '/frozen/vroot/v')! == compiler_pin
	os.mkdir_all(root + '/commands')!
	os.mkdir_all(root + '/frozen')!
	record('clone-vroot', ['/bin/cp', '-c', '-R', baseline + '/frozen/vroot', vroot])!
	os.cp(source, vroot + '/source/intent-uri371-action-recorder.v')!
	os.cp(@FILE, root + '/builder.v')!
	os.cp(os.executable(), root + '/builder')!
	os.mkdir_all(root + '/generated-c')!
	os.mkdir_all(root + '/vmodules')!
	os.setenv('VTMP', root + '/generated-c', true)
	os.setenv('VMODULES', root + '/vmodules', true)
	os.setenv('VROOT', vroot, true)
	os.setenv('VEXE', vroot + '/v', true)
	before := closure('closure-before')!
	record('compile', [vroot + '/v', '-path', vroot + '/vlib', '-nocache', '-keepc',
		'-showcc', '-cc', '/usr/bin/cc', '-o', root + '/action-recorder',
		vroot + '/source/intent-uri371-action-recorder.v'])!
	assert !os.read_file(root + '/commands/compile.log')!.contains('/Users/alex/code/')
	assert before == closure('closure-after')!
	assert hash(source)! == hash(vroot + '/source/intent-uri371-action-recorder.v')!
	assert hash(vroot + '/v')! == compiler_pin
	os.write_file(root + '/build.json', json2.encode({
		'source_sha256': json2.Any(hash(source)!),
		'binary_sha256': json2.Any(hash(root + '/action-recorder')!),
		'compiler_sha256': json2.Any(compiler_pin), 'v_input_count': json2.Any(before.len),
		'baseline_manifest_sha256': json2.Any(hash(baseline + '/sha256.json')!),
	}, prettify: true) + '\n')!
	println('INTENT371-ACTION-RECORDER-BUILD-PASS closure=270')
}
