// SPDX-License-Identifier: GPL-2.0-or-later
// Independently replay the original complete bootstrap auditor and input checks.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/intent-uri369-run-bootstrap-build-b-2026-10-26'
const output = state + '/intent-uri369-run-bootstrap-peer-readback-2026-10-26'
const checker = repo + '/build/android-maps/build-bundle-check290'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'
const manifest_pin = '0de15d5f6e3f96dabba630779e3b17e34c8c50fff33ddd8a705d8a14191b591a'
const source_pin = '09b717df537cb6d320224b53e74405c5ba62b994114443bdfe64d93d4218fd1b'
const binary_pin = '6244cdb6e9a61cf0ddc438b90b833e3a991049d2031793f3ac2424362b1f9f5e'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const source_name = 'tests/native-android-ws/intent-uri369-run.v'
const revision = '0722b8485772e7325c96a3d90f331bea597180f1'
const original_bootstrap = state + '/intent-uri369-run-bootstrap-build-2026-10-26'
const original_manifest = 'f3aeac7aa1ff66543a1afd520c1cd2363982fe9250c6dfb475e5c3e1e1c8873a'
const framework_manifest = '933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b'

fn hash(path string) !string {
	assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn qualify() ! {
	assert hash(checker)! == checker_pin && hash(root + '/sha256.json')! == manifest_pin
	assert hash(root + '/intent-uri369-run')! == binary_pin
	assert hash(root + '/frozen/vroot/v')! == compiler_pin
	assert hash(repo + '/' + source_name)! == source_pin
	assert hash(root + '/frozen/vroot/source/intent-uri369-run-corrected.v')! == source_pin
	build := object(root + '/build.json')!
	assert build['source_commit']!.str() == revision && build['source_sha256']!.str() == source_pin
	assert build['binary_sha256']!.str() == binary_pin && build['compiler_sha256']!.str() == compiler_pin
	assert build['baseline_manifest_sha256']!.str() == original_manifest
	assert build['framework_baseline_manifest_sha256']!.str() == framework_manifest
	bootstrap_receipt := object(root + '/baseline-receipt.json')!
	assert bootstrap_receipt['root']!.str() == original_bootstrap
	assert bootstrap_receipt['manifest_sha256']!.str() == original_manifest
	assert bootstrap_receipt['exit_code']!.int() == 0 && bootstrap_receipt['files_checked']!.int() == 649
	assert bootstrap_receipt['every_file_hash_matches']!.bool() && bootstrap_receipt['exact_file_set']!.bool()
	assert bootstrap_receipt['checker_sha256']!.str() == checker_pin
	framework_receipt := object(root + '/framework367-receipt.json')!
	assert framework_receipt['root']!.str() == state + '/timing-logger367-framework-build-2026-10-26'
	assert framework_receipt['manifest_sha256']!.str() == framework_manifest
	assert framework_receipt['exit_code']!.int() == 0 && framework_receipt['files_checked']!.int() == 41884
	assert framework_receipt['every_file_hash_matches']!.bool() && framework_receipt['exact_file_set']!.bool()
	assert framework_receipt['checker_sha256']!.str() == checker_pin
	assert build['v_input_count']!.int() == 270
	before := object(root + '/closure-before.json')!
	assert before.len == 270 && before == object(root + '/closure-after.json')!
	for path, pin in before {
		assert os.real_path(path) == path && path.starts_with(root + '/frozen/vroot/')
		assert hash(path)! == pin.str(), path
	}
	for path, pin in build['host_tools']!.as_map() { assert hash(path)! == pin.str(), path }
	for name in ['closure-before', 'closure-after', 'compile', 'self-test', 'committed-source',
		'committed-recorder', 'verify-baseline', 'clone-vroot', 'retain-source', 'retain-recorder',
		'retain-framework-receipt', 'find-clang', 'find-ld'] {
		command := object(root + '/commands/' + name + '.json')!
		assert command['exit_code']!.int() == 0, name
		argv := command['argv']!.as_array().map(it.str())
		assert argv.len > 0 && hash(argv[0])! == command['executable_sha256']!.str(), name
	}
	compile := object(root + '/commands/compile.json')!['argv']!.as_array().map(it.str())
	assert compile == [root + '/frozen/vroot/v', '-path', root + '/frozen/vroot/vlib',
		'-nocache', '-keepc', '-showcc', '-cc', '/usr/bin/cc', '-o', root + '/intent-uri369-run',
		root + '/frozen/vroot/source/intent-uri369-run-corrected.v']
	assert !os.read_file(root + '/commands/compile.log')!.contains('/Users/alex/code/')
	assert os.read_file(root + '/commands/self-test.log')!.trim_space() == 'INTENT-URI-SEMANTIC-SELF-TEST-PASS'
	assert sha256.sum(os.read_bytes(root + '/commands/committed-source.log')!).hex() == source_pin
	assert hash(root + '/commands/committed-recorder.log')! == hash(root + '/recorder.v')!
	assert object(root + '/commands/verify-baseline.json')!['argv']!.as_array().map(it.str()) ==
		[checker, original_bootstrap, original_manifest, root + '/baseline-receipt.json']
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
	println('INTENT369-BOOTSTRAP-PEER-PASS closure=270')
}
