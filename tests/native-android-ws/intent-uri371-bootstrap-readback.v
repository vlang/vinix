// SPDX-License-Identifier: GPL-2.0-or-later
// Independently replay the original complete run-bootstrap auditor and input checks.
module main

import json2
import os
import time

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/intent-uri371-run-bootstrap-build-2026-10-26'
const output = state + '/intent-uri371-run-bootstrap-peer-readback-2026-10-26'
const checker = repo + '/build/android-maps/build-bundle-check290'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'
const manifest_pin = '0056ca7608c43d61612f24caeb251c502e41c1f6b28db22ba249710084691421'
const source_pin = 'e6de49d024b706ffc34f6169b3a1a31f725708d3bbfd7425657513d9c6d2e707'
const binary_pin = '4c192b967eb30a27caa5fa08d5d5c0ff15e4136e89134390d91c7704ef4488b6'
const recorder_source_pin = '863004aa49d84602d4a83e20c81f6ff46f7c2dec298d11565ddb77efd22aa0a0'
const recorder_binary_pin = '6eaaf95fdd1d724b82714b37cc5ceceb475899e17d4c21482f3a60a9a8494b72'
const file_count = 655
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const source_name = 'tests/native-android-ws/intent-uri371-run.v'
const recorder_name = 'tests/native-android-ws/intent-uri371-run-recorder.v'
const revision = '6668c29e9e07d6ab89cc04fe58e8ab8a89ac4afa'
const baseline = state + '/intent-uri369-run-bootstrap-build-b-2026-10-26'
const baseline_manifest = '0de15d5f6e3f96dabba630779e3b17e34c8c50fff33ddd8a705d8a14191b591a'
const framework_manifest = '933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b'

fn hash(path string) !string {
	assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut digest := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &digest }) == 1
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
	}
	mut sum := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &sum[0] }, unsafe { &digest }) == 1
	return sum[..].hex()
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn expected_argv(name string) []string {
	vroot := root + '/frozen/vroot'
	source := vroot + '/source/intent-uri371-run.v'
	return match name {
		'closure-before', 'closure-after' { [vroot + '/v', '-path', vroot + '/vlib', '-print-v-files', source] }
		'compile' { [vroot + '/v', '-path', vroot + '/vlib', '-nocache', '-keepc', '-showcc', '-cc', '/usr/bin/cc', '-o', root + '/intent-uri371-run', source] }
		'self-test' { [root + '/intent-uri371-run', 'self-test'] }
		'committed-source' { ['/usr/bin/git', 'show', revision + ':' + source_name] }
		'committed-recorder' { ['/usr/bin/git', 'show', revision + ':' + recorder_name] }
		'verify-baseline' { [checker, baseline, baseline_manifest, root + '/baseline-receipt.json'] }
		'clone-vroot' { ['/bin/cp', '-c', '-R', baseline + '/frozen/vroot', vroot] }
		'retain-source' { ['/bin/cp', '-c', repo + '/' + source_name, source] }
		'retain-recorder' { ['/bin/cp', '-c', repo + '/' + recorder_name, root + '/recorder.v'] }
		'retain-framework-receipt' { ['/bin/cp', '-c', baseline + '/framework367-receipt.json', root + '/framework367-receipt.json'] }
		'find-clang' { ['/usr/bin/xcrun', '--find', 'clang'] }
		'find-ld' { ['/usr/bin/xcrun', '--find', 'ld'] }
		else { panic('unexpected command: ' + name) }
	}
}

fn qualify() ! {
	assert hash(checker)! == checker_pin && hash(root + '/sha256.json')! == manifest_pin
	assert hash(root + '/intent-uri371-run')! == binary_pin
	assert hash(root + '/frozen/vroot/v')! == compiler_pin
	assert hash(repo + '/' + source_name)! == source_pin
	assert hash(root + '/frozen/vroot/source/intent-uri371-run.v')! == source_pin
	assert hash(repo + '/' + recorder_name)! == recorder_source_pin
	assert hash(root + '/recorder.v')! == recorder_source_pin
	assert hash(root + '/recorder')! == recorder_binary_pin
	build := object(root + '/build.json')!
	assert build['source_commit']!.str() == revision && build['source_sha256']!.str() == source_pin
	assert build['binary_sha256']!.str() == binary_pin && build['compiler_sha256']!.str() == compiler_pin
	assert build['recorder_source_sha256']!.str() == recorder_source_pin
	assert build['recorder_binary_sha256']!.str() == recorder_binary_pin
	assert build['baseline_manifest_sha256']!.str() == baseline_manifest
	assert build['framework_baseline_manifest_sha256']!.str() == framework_manifest
	bootstrap_receipt := object(root + '/baseline-receipt.json')!
	assert bootstrap_receipt['root']!.str() == baseline
	assert bootstrap_receipt['manifest_sha256']!.str() == baseline_manifest
	assert bootstrap_receipt['exit_code']!.int() == 0 && bootstrap_receipt['files_checked']!.int() == 653
	assert bootstrap_receipt['every_file_hash_matches']!.bool() && bootstrap_receipt['exact_file_set']!.bool()
	assert bootstrap_receipt['checker_sha256']!.str() == checker_pin
	assert bootstrap_receipt['argv']!.as_array().map(it.str()) == expected_argv('verify-baseline')
	framework_receipt := object(root + '/framework367-receipt.json')!
	assert framework_receipt['root']!.str() == state + '/timing-logger367-framework-build-2026-10-26'
	assert framework_receipt['manifest_sha256']!.str() == framework_manifest
	assert framework_receipt['exit_code']!.int() == 0 && framework_receipt['files_checked']!.int() == 41884
	assert framework_receipt['every_file_hash_matches']!.bool() && framework_receipt['exact_file_set']!.bool()
	assert framework_receipt['checker_sha256']!.str() == checker_pin
	assert hash(root + '/framework367-receipt.json')! == hash(baseline + '/framework367-receipt.json')!
	assert build['v_input_count']!.int() == 270
	before := object(root + '/closure-before.json')!
	assert before.len == 270 && before == object(root + '/closure-after.json')!
	for path, pin in before {
		assert os.real_path(path) == path && path.starts_with(root + '/frozen/vroot/')
		assert hash(path)! == pin.str(), path
	}
	for path, pin in build['host_tools']!.as_map() { assert hash(path)! == pin.str(), path }
	vroot := root + '/frozen/vroot'
	expected_environment := {'VROOT': json2.Any(vroot), 'VEXE': json2.Any(vroot + '/v'),
		'VTMP': json2.Any(root + '/generated-c'), 'VMODULES': json2.Any(root + '/vmodules')}
	assert object(root + '/compile-environment.json')! == expected_environment
	for name in ['closure-before', 'closure-after', 'compile', 'self-test', 'committed-source',
		'committed-recorder', 'verify-baseline', 'clone-vroot', 'retain-source', 'retain-recorder',
		'retain-framework-receipt', 'find-clang', 'find-ld'] {
		command := object(root + '/commands/' + name + '.json')!
		assert command['exit_code']!.int() == 0, name
		argv := command['argv']!.as_array().map(it.str())
		assert argv == expected_argv(name), name
		assert hash(argv[0])! == command['executable_sha256']!.str(), name
	}
	assert !os.read_file(root + '/commands/compile.log')!.contains('/Users/alex/code/')
	assert os.read_file(root + '/commands/self-test.log')!.trim_space() == 'INTENT-URI-SEMANTIC-SELF-TEST-PASS'
	assert hash(root + '/commands/committed-source.log')! == source_pin
	assert hash(root + '/commands/committed-recorder.log')! == recorder_source_pin
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 1 && os.getwd() == repo && os.real_path(root) == root
	assert !os.exists(output) && !os.is_link(output), 'fresh adjacent peer receipt required'
	qualify()!
	os.mkdir(output)!
	os.cp(@FILE, output + '/reader.v')!
	os.cp(os.executable(), output + '/reader')!
	reader_source_pin := hash(@FILE)!
	reader_binary_pin := hash(os.executable())!
	assert hash(output + '/reader.v')! == reader_source_pin && hash(output + '/reader')! == reader_binary_pin
	argv := [checker, root, manifest_pin, output + '/complete-receipt.json']
	mut command := {'argv': json2.Any(argv), 'working_directory': json2.Any(repo),
		'started_utc': json2.Any(time.utc().str()), 'checker_sha256': json2.Any(checker_pin),
		'manifest_sha256_before': json2.Any(manifest_pin),
		'reader_source_sha256': json2.Any(reader_source_pin),
		'reader_binary_sha256': json2.Any(reader_binary_pin)}
	os.write_file(output + '/before.json', json2.encode(command, prettify: true) + '\n')!
	r := os.exec(argv)
	os.write_file(output + '/stdout.log', r.output)!
	command['completed_utc'] = time.utc().str()
	command['exit_code'] = r.exit_code
	command['manifest_sha256_after'] = hash(root + '/sha256.json')!
	command['stdout_sha256'] = hash(output + '/stdout.log')!
	os.write_file(output + '/command.json', json2.encode(command, prettify: true) + '\n')!
	assert r.exit_code == 0, 'original auditor failed; actual status retained'
	receipt := object(output + '/complete-receipt.json')!
	assert receipt['argv']!.as_array().map(it.str()) == argv
	assert receipt['root']!.str() == root && receipt['manifest_sha256']!.str() == manifest_pin
	assert receipt['checker_sha256']!.str() == checker_pin && receipt['exit_code']!.int() == 0
	assert receipt['files_checked']!.int() == file_count
	assert receipt['every_file_hash_matches']!.bool() && receipt['exact_file_set']!.bool()
	qualify()!
	assert hash(@FILE)! == reader_source_pin && hash(os.executable())! == reader_binary_pin
	assert hash(output + '/reader.v')! == reader_source_pin && hash(output + '/reader')! == reader_binary_pin
	print(r.output)
	println('INTENT371-BOOTSTRAP-PEER-PASS files=' + file_count.str() + ' closure=270')
}
