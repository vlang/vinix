// SPDX-License-Identifier: GPL-2.0-or-later
// Independently replay the original complete bootstrap auditor and input checks.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/intent-uri369-framework-builder-build-2026-10-26'
const output = state + '/intent-uri369-builder-bootstrap-peer-readback-2026-10-26'
const checker = repo + '/build/android-maps/build-bundle-check290'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'
const manifest_pin = 'f8efd6af2c765d356b33f0869990eb7531ba486162bf97433520f8e57d34e31f'
const source_pin = '4121330ca79c379918faa1a977021c13f28c529b4f70c97409e447fe0361cc4b'
const binary_pin = '16d2579abf9b52b1f3a7e4a1682ede757ac00864d5db4d795893395a0a3918e3'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const source_name = 'tests/native-android-ws/intent-uri-framework-build.v'
const revision = 'be605eeb981d340fc53cd1fb3346e0614080d085'

fn hash(path string) !string {
	assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn qualify() ! {
	assert hash(checker)! == checker_pin && hash(root + '/sha256.json')! == manifest_pin
	assert hash(root + '/intent-uri-framework-build')! == binary_pin
	assert hash(root + '/frozen/vroot/v')! == compiler_pin
	assert hash(repo + '/' + source_name)! == source_pin
	assert hash(root + '/frozen/vroot/source/intent-uri-framework-build.v')! == source_pin
	build := object(root + '/build.json')!
	assert build['source_commit']!.str() == revision && build['source_sha256']!.str() == source_pin
	assert build['binary_sha256']!.str() == binary_pin && build['compiler_sha256']!.str() == compiler_pin
	assert build['v_input_count']!.int() == 270
	before := object(root + '/closure-before.json')!
	assert before.len == 270 && before == object(root + '/closure-after.json')!
	for path, pin in before {
		assert os.real_path(path) == path && path.starts_with(root + '/frozen/vroot/')
		assert hash(path)! == pin.str(), path
	}
	for path, pin in build['host_tools']!.as_map() { assert hash(path)! == pin.str(), path }
	for name in ['closure-before', 'closure-after', 'compile', 'self-test', 'committed-source', 'committed-recorder',
		'verify-baseline', 'clone-vroot', 'retain-source', 'retain-recorder', 'find-clang', 'find-ld'] {
		command := object(root + '/commands/' + name + '.json')!
		assert command['exit_code']!.int() == 0, name
		argv := command['argv']!.as_array().map(it.str())
		assert argv.len > 0 && hash(argv[0])! == command['executable_sha256']!.str(), name
	}
	compile := object(root + '/commands/compile.json')!['argv']!.as_array().map(it.str())
	assert compile == [root + '/frozen/vroot/v', '-path', root + '/frozen/vroot/vlib',
		'-nocache', '-keepc', '-showcc', '-cc', '/usr/bin/cc', '-o', root + '/intent-uri-framework-build',
		root + '/frozen/vroot/source/intent-uri-framework-build.v']
	assert !os.read_file(root + '/commands/compile.log')!.contains('/Users/alex/code/')
	assert os.read_file(root + '/commands/self-test.log')!.trim_space() == 'INTENT369-BUILDER-SELF-TEST-PASS rejected=6'
	assert sha256.sum(os.read_bytes(root + '/commands/committed-source.log')!).hex() == source_pin
	for name in ['recorder.v', 'commands/committed-recorder.log'] {
		assert hash(root + '/' + name)! == 'edb870a4d52230211384eb04d78ebaee5125282c776d80a9d8ea78b7d4dde4f4'
	}
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 1 && os.getwd() == repo && os.real_path(root) == root
	assert !os.exists(output) && !os.is_link(output), 'fresh adjacent peer receipt required'
	qualify()!
	os.mkdir(output)!
	os.cp(@FILE, output + '/reader.v')!
	os.cp(os.executable(), output + '/reader')!
	argv := [checker, root, manifest_pin, output + '/complete-receipt.json']
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(output + '/stdout.log', r.output)!
	os.write_file(output + '/command.json', json2.encode({
		'argv': json2.Any(argv), 'working_directory': json2.Any(repo),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
		'exit_code': json2.Any(r.exit_code), 'checker_sha256': json2.Any(checker_pin),
		'manifest_sha256_before': json2.Any(manifest_pin),
		'manifest_sha256_after': json2.Any(hash(root + '/sha256.json')!),
		'reader_source_sha256': json2.Any(hash(@FILE)!),
		'reader_binary_sha256': json2.Any(hash(os.executable())!),
		'stdout_sha256': json2.Any(hash(output + '/stdout.log')!)
	}, prettify: true) + '\n')!
	assert r.exit_code == 0, 'original auditor failed; actual status retained'
	qualify()!
	print(r.output)
	println('INTENT369-BUILDER-BOOTSTRAP-PEER-PASS closure=270')
}
