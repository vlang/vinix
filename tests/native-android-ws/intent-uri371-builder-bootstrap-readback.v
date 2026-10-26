// SPDX-License-Identifier: GPL-2.0-or-later
// Independently replay the original complete bootstrap auditor and input checks.
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
const root = state + '/intent-uri371-framework-builder-build-2026-10-26'
const output = state + '/intent-uri371-builder-bootstrap-peer-readback-2026-10-26'
const baseline = state + '/timing-logger367-framework-build-2026-10-26'
const baseline_pin = '933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b'
const checker = repo + '/build/android-maps/build-bundle-check290'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'
const manifest_pin = '9f062095b54c8c52e6797750529d0a241e592b21611db5c53e082d4c317b70cd'
const source_pin = 'e329f69505d1e6fb1be869ce42c4e00f86c896b509e0425e93ebb1473cddce68'
const binary_pin = '081765f4e6a3ea94e20cd5fca3c25b535e71ba3ba90dd183e91fa3c231df2cc6'
const recorder_pin = '018b27a5b1a40200bfe6dd2eadb3f328038a360c46395113d55cc87207e0eca1'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const source_name = 'tests/native-android-ws/intent-uri371-framework-build.v'
const recorder_name = 'tests/native-android-ws/intent-uri371-builder-recorder.v'
const revision = '11a1b17bfbce3153d161b414e99c9d49fb862e7b'

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
	source := vroot + '/source/intent-uri371-framework-build.v'
	return match name {
		'closure-before', 'closure-after' { [vroot + '/v', '-path', vroot + '/vlib', '-print-v-files', source] }
		'compile' { [vroot + '/v', '-path', vroot + '/vlib', '-nocache', '-keepc', '-showcc', '-cc', '/usr/bin/cc', '-o', root + '/intent-uri371-framework-build', source] }
		'self-test' { [root + '/intent-uri371-framework-build', '--self-test'] }
		'committed-source' { ['/usr/bin/git', 'show', revision + ':' + source_name] }
		'committed-recorder' { ['/usr/bin/git', 'show', revision + ':' + recorder_name] }
		'verify-baseline' { [checker, baseline, baseline_pin, root + '/baseline-receipt.json'] }
		'clone-vroot' { ['/bin/cp', '-c', '-R', baseline + '/baseline365/baseline361/baseline359/baseline353/frozen/vroot', vroot] }
		'retain-source' { ['/bin/cp', '-c', repo + '/' + source_name, source] }
		'retain-recorder' { ['/bin/cp', '-c', repo + '/' + recorder_name, root + '/recorder.v'] }
		'find-clang' { ['/usr/bin/xcrun', '--find', 'clang'] }
		'find-ld' { ['/usr/bin/xcrun', '--find', 'ld'] }
		else { panic('unexpected command: ' + name) }
	}
}

fn qualify() ! {
	assert hash(checker)! == checker_pin && hash(root + '/sha256.json')! == manifest_pin
	assert hash(root + '/intent-uri371-framework-build')! == binary_pin
	assert hash(root + '/frozen/vroot/v')! == compiler_pin
	assert hash(repo + '/' + source_name)! == source_pin
	assert hash(root + '/frozen/vroot/source/intent-uri371-framework-build.v')! == source_pin
	assert hash(repo + '/' + recorder_name)! == recorder_pin
	build := object(root + '/build.json')!
	assert build['source_commit']!.str() == revision && build['source_sha256']!.str() == source_pin
	assert build['binary_sha256']!.str() == binary_pin && build['compiler_sha256']!.str() == compiler_pin
	assert build['baseline_manifest_sha256']!.str() == baseline_pin
	assert build['v_input_count']!.int() == 270
	before := object(root + '/closure-before.json')!
	assert before.len == 270 && before == object(root + '/closure-after.json')!
	for path, pin in before {
		assert os.real_path(path) == path && path.starts_with(root + '/frozen/vroot/')
		assert hash(path)! == pin.str(), path
	}
	host_tools := build['host_tools']!.as_map()
	assert host_tools.len == 3
	for path, pin in host_tools { assert hash(path)! == pin.str(), path }
	assert host_tools['/usr/bin/cc']!.str() == '179301dcb41ea78accc3fa0048a7e6f6710d891945a751a34addd622020c1818'
	for name in ['clang', 'ld'] {
		path := os.read_file(root + '/commands/find-' + name + '.log')!.trim_space()
		assert path == '/Library/Developer/CommandLineTools/usr/bin/' + name
		assert path in host_tools
	}
	for name in ['closure-before', 'closure-after', 'compile', 'self-test', 'committed-source', 'committed-recorder',
		'verify-baseline', 'clone-vroot', 'retain-source', 'retain-recorder', 'find-clang', 'find-ld'] {
		command := object(root + '/commands/' + name + '.json')!
		assert command['exit_code']!.int() == 0, name
		argv := command['argv']!.as_array().map(it.str())
		assert argv == expected_argv(name), name
		assert hash(argv[0])! == command['executable_sha256']!.str(), name
	}
	assert !os.read_file(root + '/commands/compile.log')!.contains('/Users/alex/code/')
	assert os.read_file(root + '/commands/self-test.log')!.trim_space() == 'INTENT371-BUILDER-SELF-TEST-PASS rejected=6'
	assert hash(root + '/commands/committed-source.log')! == source_pin
	for name in ['recorder.v', 'commands/committed-recorder.log'] {
		assert hash(root + '/' + name)! == recorder_pin
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
	reader_source_pin := hash(@FILE)!
	reader_binary_pin := hash(os.executable())!
	assert hash(output + '/reader.v')! == reader_source_pin
	assert hash(output + '/reader')! == reader_binary_pin
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
	assert receipt['files_checked']!.int() == 648
	assert receipt['every_file_hash_matches']!.bool() && receipt['exact_file_set']!.bool()
	qualify()!
	assert hash(@FILE)! == reader_source_pin && hash(os.executable())! == reader_binary_pin
	assert hash(output + '/reader.v')! == reader_source_pin && hash(output + '/reader')! == reader_binary_pin
	print(r.output)
	println('INTENT371-BUILDER-BOOTSTRAP-PEER-PASS files=648 closure=270')
}
